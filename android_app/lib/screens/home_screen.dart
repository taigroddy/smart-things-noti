import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/device_storage.dart';

/// Màn hình chính của Passive Listener:
/// - Pre-setup: Kiểm tra xem điện thoại đã cài SmartThings chưa (hiện popup nếu chưa)
/// - Luồng 3 bước tương tác:
///   1. Bấm Sao Chép Mã -> Mở khóa Bước 2
///   2. Bấm Mở SmartThings -> Khởi chạy app SmartThings (hoặc link Play Store)
///   3. Quay lại app (resumed) -> Mở khóa Bước 3 -> Bấm Hoàn tất để load Dashboard
/// - Dashboard danh sách máy giặt kèm nút Bật/Tắt chuông và Đặt lại kết nối
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  String? _fcmToken;
  bool _isLoadingToken = true;
  bool _isCopied = false;

  List<SyncedDevice> _syncedDevices = [];
  StreamSubscription<List<SyncedDevice>>? _syncSubscription;

  // Quản lý tiến trình 3 bước onboarding (1 -> 2 -> 3)
  int _currentStep = 1;
  bool _openedSmartThings = false;
  bool _hasCheckedSmartThings = false;
  bool _hasCompletedOnboarding = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchFCMToken();
    _loadSavedDevices();
    _listenToSyncEvents();

    // Pre-setup check: Kiểm tra SmartThings đã cài đặt chưa ngay khi vào màn hình
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkSmartThingsPreSetup();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _syncSubscription?.cancel();
    super.dispose();
  }

  /// Lắng nghe vòng đời ứng dụng: khi người dùng từ SmartThings quay lại Washer Notifier
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('[HomeScreen] App resumed. Đang kiểm tra trạng thái...');

      // Kiểm tra lại nếu người dùng đã lưu thiết bị
      _loadSavedDevices();

      // Nếu người dùng đã mở SmartThings ở Bước 2 và quay lại app -> tự động kích hoạt Bước 3
      if (_openedSmartThings && _currentStep < 3) {
        setState(() {
          _currentStep = 3;
        });
      }
    }
  }

  /// Pre-setup: Kiểm tra xem ứng dụng Samsung SmartThings đã được cài trên máy chưa
  Future<void> _checkSmartThingsPreSetup() async {
    if (_hasCheckedSmartThings || _syncedDevices.isNotEmpty) return;
    _hasCheckedSmartThings = true;

    final isInstalled = await _isSmartThingsInstalledOnDevice();
    if (!isInstalled && mounted) {
      _showSmartThingsRequiredDialog();
    }
  }

  static const MethodChannel _appLauncherChannel =
      MethodChannel('com.smartthingnoti.app/app_launcher');

  /// Kiểm tra sự tồn tại của ứng dụng SmartThings qua Android PackageManager (MethodChannel)
  Future<bool> _isSmartThingsInstalledOnDevice() async {
    try {
      final bool? isInstalled = await _appLauncherChannel.invokeMethod<bool>(
        'isAppInstalled',
        {'package': 'com.samsung.android.oneconnect'},
      );
      if (isInstalled != null) return isInstalled;
    } catch (e) {
      debugPrint('[HomeScreen] Lỗi kiểm tra cài đặt SmartThings qua MethodChannel: $e');
    }

    // Fallback qua canLaunchUrl
    try {
      final schemeUri = Uri.parse('smartthings://');
      if (await canLaunchUrl(schemeUri)) return true;
    } catch (_) {}

    return false;
  }

  /// Popup Pre-setup cảnh báo nếu chưa cài Samsung SmartThings
  void _showSmartThingsRequiredDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Yêu Cầu SmartThings',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: const Text(
          'Điện thoại của bạn chưa cài đặt ứng dụng Samsung SmartThings.\n\n'
          'Hãy cài đặt Samsung SmartThings và quay lại ứng dụng để tiếp tục thiết lập nhé!',
          style: TextStyle(fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Để sau', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await _openSmartThingsPlayStore();
            },
            icon: const Icon(Icons.download, size: 18),
            label: const Text('Cài Đặt (CH Play)'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1565C0),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  /// Mở ứng dụng Samsung SmartThings qua PackageManager (hoặc popup CH Play nếu chưa cài)
  Future<void> _openSmartThingsApp() async {
    setState(() => _openedSmartThings = true);

    try {
      final bool? opened = await _appLauncherChannel.invokeMethod<bool>(
        'openApp',
        {'package': 'com.samsung.android.oneconnect'},
      );
      if (opened == true) return;
    } catch (e) {
      debugPrint('[HomeScreen] Lỗi khởi chạy SmartThings qua MethodChannel: $e');
    }

    // Fallback qua url_launcher nếu MethodChannel không mở được
    try {
      final schemeUri = Uri.parse('smartthings://');
      if (await canLaunchUrl(schemeUri)) {
        await launchUrl(schemeUri, mode: LaunchMode.externalApplication);
        return;
      }
    } catch (_) {}

    // Nếu không mở được (chưa cài đặt), hiển thị popup cài đặt
    if (mounted) {
      _showSmartThingsRequiredDialog();
    }
  }

  /// Mở trang cài đặt ứng dụng trên Google Play Store
  Future<void> _openSmartThingsPlayStore() async {
    final playStoreUri = Uri.parse('https://play.google.com/store/apps/details?id=com.samsung.android.oneconnect');
    try {
      await launchUrl(playStoreUri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('[HomeScreen] Lỗi mở Google Play Store: $e');
    }
  }

  /// Tải danh sách thiết bị đã lưu từ Local Storage
  Future<void> _loadSavedDevices() async {
    try {
      final devices = await DeviceStorage.getDevices();
      if (mounted && devices.isNotEmpty) {
        setState(() {
          _syncedDevices = devices;
        });
      }
    } catch (e) {
      debugPrint('[HomeScreen] Lỗi đọc danh sách thiết bị từ Local Storage: $e');
    }
  }

  /// Lắng nghe sự kiện đồng bộ thiết bị (SYNC_DEVICES) từ Background/Foreground handler
  void _listenToSyncEvents() {
    _syncSubscription = DeviceStorage.onDevicesSynced.listen((devices) {
      if (!mounted) return;

      setState(() {
        _syncedDevices = devices;
      });

      // Hiển thị thông báo "Kết nối máy giặt thành công!"
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white, size: 22),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Kết nối máy giặt thành công!',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF2E7D32),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    });
  }

  Future<void> _fetchFCMToken() async {
    setState(() => _isLoadingToken = true);
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (mounted) {
        setState(() {
          _fcmToken = token;
          _isLoadingToken = false;
        });
      }

      // Lắng nghe khi token được làm mới
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
        if (mounted) {
          setState(() {
            _fcmToken = newToken;
          });
        }
      });
    } catch (e) {
      debugPrint('[HomeScreen] Lỗi lấy FCM token: $e');
      if (mounted) {
        setState(() => _isLoadingToken = false);
      }
    }
  }

  /// Thao tác Bước 1: Sao chép mã kết nối và mở khóa Bước 2
  Future<void> _copyTokenToClipboard() async {
    if (_fcmToken == null || _fcmToken!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đang khởi tạo mã kết nối, vui lòng đợi giây lát...'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    await Clipboard.setData(ClipboardData(text: _fcmToken!));
    if (mounted) {
      setState(() {
        _isCopied = true;
        if (_currentStep < 2) {
          _currentStep = 2; // Tự động mở khóa Bước 2
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text('Đã sao chép mã kết nối! Hãy chuyển sang Bước 2.'),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF2E7D32),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );

      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _isCopied = false);
      });
    }
  }

  /// Thao tác Bước 3: Chuyển thẳng vào màn hình danh sách thiết bị
  void _handleStep3Complete() {
    setState(() {
      _hasCompletedOnboarding = true;
    });
  }

  /// Hộp thoại xác nhận đặt lại kết nối để lấy lại mã FCM token
  Future<void> _showResetConfirmDialog() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
            SizedBox(width: 8),
            Text('Đặt Lại Kết Nối?'),
          ],
        ),
        content: const Text(
          'Hành động này sẽ xóa danh sách máy giặt đã lưu để bạn có thể sao chép lại mã kết nối và cấu hình lại trên SmartThings.',
          style: TextStyle(fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFC62828),
              foregroundColor: Colors.white,
            ),
            child: const Text('Đặt Lại'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await DeviceStorage.clearDevices();
      if (!mounted) return;
      setState(() {
        _syncedDevices = [];
        _hasCompletedOnboarding = false;
        _currentStep = 1;
        _openedSmartThings = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text('Đã đặt lại kết nối. Bạn có thể sao chép lại mã!'),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF1565C0),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final showDeviceList = _syncedDevices.isNotEmpty || _hasCompletedOnboarding;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F6F9),
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.local_laundry_service, size: 24),
            SizedBox(width: 8),
            Text(
              'Thông Báo Máy Giặt',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
            ),
          ],
        ),
        actions: showDeviceList
            ? [
                IconButton(
                  icon: const Icon(Icons.restart_alt),
                  tooltip: 'Đặt lại kết nối',
                  onPressed: _showResetConfirmDialog,
                ),
              ]
            : null,
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: showDeviceList
            ? _buildConnectedView()
            : _buildOnboardingView(),
      ),
    );
  }

  // ============================================================
  // TRẠNG THÁI A: CHƯA KẾT NỐI — Onboarding 3 bước tương tác
  // ============================================================

  /// Giao diện khi chưa kết nối máy giặt nào — 3 bước tuần tự có tương tác
  Widget _buildOnboardingView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Trạng thái chờ kết nối
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.blue.withValues(alpha: 0.06),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.blue.shade200, width: 1.5),
                ),
                child: Icon(
                  Icons.wifi_tethering,
                  color: Colors.blue.shade700,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Text(
                          '⏳',
                          style: TextStyle(fontSize: 12),
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Chờ Kết Nối Máy Giặt',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1565C0),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Làm theo 3 bước bên dưới để kích hoạt chuông thông báo.',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // ==========================================
        // BƯỚC 1: Sao chép mã kết nối
        // ==========================================
        _buildOnboardingStepCard(
          stepNumber: '1',
          icon: Icons.content_copy,
          title: 'Sao Chép Mã Kết Nối',
          description: 'Sao chép mã kết nối vào bộ nhớ tạm để dán sang SmartThings.',
          isActive: _currentStep == 1,
          isCompleted: _currentStep > 1,
        ),

        const SizedBox(height: 10),

        // Nút Bước 1: Sao chép mã
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isLoadingToken ? null : _copyTokenToClipboard,
              icon: _isLoadingToken
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(
                      (_currentStep > 1 || _isCopied) ? Icons.check_circle : Icons.copy,
                      size: 20,
                    ),
              label: Text(
                _isLoadingToken
                    ? 'Đang khởi tạo mã...'
                    : (_currentStep > 1 ? 'Đã Sao Chép (Bấm Để Chép Lại)' : 'Sao Chép Mã Kết Nối'),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _currentStep > 1
                    ? const Color(0xFF2E7D32)
                    : const Color(0xFF1565C0),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
              ),
            ),
          ),
        ),

        const SizedBox(height: 18),

        // ==========================================
        // BƯỚC 2: Mở Samsung SmartThings
        // ==========================================
        _buildOnboardingStepCard(
          stepNumber: '2',
          icon: Icons.phone_android,
          title: 'Mở Ứng Dụng SmartThings',
          description: 'Mở SmartThings, tìm SmartApp "Washer Notifier" trong mục Tự động hóa.',
          isActive: _currentStep == 2,
          isCompleted: _currentStep > 2,
        ),

        if (_currentStep >= 2) ...[
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _openSmartThingsApp,
                icon: const Icon(Icons.open_in_new, size: 20),
                label: Text(
                  _currentStep > 2 ? 'Mở Lại SmartThings' : 'Mở Ứng Dụng SmartThings',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _currentStep == 2
                      ? const Color(0xFF1565C0)
                      : Colors.blue.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                ),
              ),
            ),
          ),
        ],

        const SizedBox(height: 18),

        // ==========================================
        // BƯỚC 3: Dán mã & Hoàn tất
        // ==========================================
        _buildOnboardingStepCard(
          stepNumber: '3',
          icon: Icons.link,
          title: 'Dán Mã & Hoàn Tất Cài Đặt',
          description: 'Dán mã vừa chép vào SmartApp, chọn máy giặt, nhấn "Done" trên SmartThings rồi bấm hoàn tất.',
          isActive: _currentStep == 3,
          isCompleted: _syncedDevices.isNotEmpty,
        ),

        if (_currentStep >= 3) ...[
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _handleStep3Complete,
                icon: const Icon(Icons.arrow_forward, size: 22),
                label: const Text(
                  'Hoàn Tất & Xem Danh Sách Máy',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 3,
                ),
              ),
            ),
          ),
        ],

        const SizedBox(height: 24),

        // Ghi chú
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF0F4FF),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFBBDEFB)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, color: Colors.blue.shade700, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Khi hoàn tất cài đặt trên SmartThings, ứng dụng sẽ tự động đồng bộ danh sách máy giặt của bạn.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Colors.blue.shade800,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Card hiển thị cho từng bước onboarding với trạng thái: Chưa mở / Đang làm / Đã hoàn thành
  Widget _buildOnboardingStepCard({
    required String stepNumber,
    required IconData icon,
    required String title,
    required String description,
    required bool isActive,
    bool isCompleted = false,
  }) {
    Color borderColor = Colors.grey.shade200;
    Color iconBgColor = Colors.grey.shade100;
    Color iconColor = Colors.grey.shade500;
    Color titleColor = Colors.grey.shade600;
    Color descColor = Colors.grey.shade500;

    if (isCompleted) {
      borderColor = const Color(0xFFC8E6C9);
      iconBgColor = Colors.green.shade50;
      iconColor = const Color(0xFF2E7D32);
      titleColor = const Color(0xFF1B5E20);
      descColor = Colors.grey.shade700;
    } else if (isActive) {
      borderColor = const Color(0xFF1565C0);
      iconBgColor = const Color(0xFF1565C0);
      iconColor = Colors.white;
      titleColor = const Color(0xFF0D47A1);
      descColor = Colors.grey.shade800;
    }

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 250),
      opacity: (isActive || isCompleted) ? 1.0 : 0.55,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: borderColor,
            width: (isActive || isCompleted) ? 1.5 : 1,
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: Colors.blue.withValues(alpha: 0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : [],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconBgColor,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: isCompleted
                    ? const Icon(Icons.check, color: Color(0xFF2E7D32), size: 20)
                    : Text(
                        stepNumber,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isActive ? Colors.white : Colors.grey.shade500,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        icon,
                        size: 18,
                        color: iconColor,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.bold,
                            color: titleColor,
                          ),
                        ),
                      ),
                      if (isCompleted)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.green.shade200),
                          ),
                          child: const Text(
                            'Xong',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF2E7D32),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: descColor,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // TRẠNG THÁI B: ĐÃ KẾT NỐI — Dashboard máy giặt
  // ============================================================

  /// Giao diện khi đã kết nối máy giặt — Dashboard đơn giản
  Widget _buildConnectedView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Trạng thái đã kết nối
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.blue.withValues(alpha: 0.06),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.green.shade200, width: 1.5),
                ),
                child: Icon(
                  Icons.check_circle,
                  color: Colors.green.shade700,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'Đã Kết Nối',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1B5E20),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Đang theo dõi ${_syncedDevices.length} máy giặt. '
                      'Bạn có thể bật/tắt nhận chuông cho từng máy bên dưới.',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 18),

        // Danh sách máy giặt
        _buildDevicesList(),
      ],
    );
  }

  /// Danh sách máy giặt đang được giám sát — bản thân thiện
  Widget _buildDevicesList() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFC8E6C9), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.green.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.local_laundry_service,
                  color: Color(0xFF2E7D32),
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Máy Giặt Của Bạn',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1B5E20),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_syncedDevices.length} máy',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Danh sách các thiết bị hoặc trạng thái chờ
          if (_syncedDevices.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.sync,
                      color: Colors.blue.shade600,
                      size: 24,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Đang chờ SmartThings đồng bộ máy giặt...',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Khi bạn nhấn "Done" trên ứng dụng SmartThings, máy giặt sẽ tự động xuất hiện tại đây.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Colors.grey.shade600,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            )
          else
            ..._syncedDevices.map((device) {
              final isEnabled = device.isEnabled;
              return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: isEnabled ? const Color(0xFFF9FAFB) : const Color(0xFFF1F3F5),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isEnabled ? Colors.grey.shade200 : Colors.grey.shade300,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: isEnabled ? const Color(0xFFE3F2FD) : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.local_laundry_service,
                      color: isEnabled ? const Color(0xFF1565C0) : Colors.grey.shade500,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          device.name,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: isEnabled ? const Color(0xFF1E293B) : Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text(
                              'Mã: ${device.id.length > 8 ? device.id.substring(0, 8) : device.id}',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade500,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              isEnabled ? '• Bật chuông' : '• Đã tắt',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isEnabled ? const Color(0xFF2E7D32) : Colors.red.shade700,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Transform.scale(
                    scale: 0.85,
                    child: Switch.adaptive(
                      value: isEnabled,
                      activeTrackColor: const Color(0xFF81C784),
                      activeThumbColor: const Color(0xFF2E7D32),
                      onChanged: (val) async {
                        await DeviceStorage.updateDeviceEnabled(device.id, val);
                        setState(() {
                          final idx = _syncedDevices.indexWhere((d) => d.id == device.id);
                          if (idx != -1) {
                            _syncedDevices[idx] = _syncedDevices[idx].copyWith(isEnabled: val);
                          }
                        });
                      },
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
