import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../services/device_storage.dart';

/// Màn hình chính của Passive Listener:
/// - Hiển thị chuỗi FCM Device Token kèm nút Sao Chép
/// - Hiển thị danh sách thiết bị máy giặt đã được đồng bộ từ SmartThings
/// - Bắt sự kiện SYNC_DEVICES và hiển thị "Kết nối SmartThings thành công"
/// - Nút kiểm thử cuộc gọi giả lập nhanh
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _fcmToken;
  bool _isLoadingToken = true;
  bool _isCopied = false;

  List<SyncedDevice> _syncedDevices = [];
  StreamSubscription<List<SyncedDevice>>? _syncSubscription;

  @override
  void initState() {
    super.initState();
    _fetchFCMToken();
    _loadSavedDevices();
    _listenToSyncEvents();
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    super.dispose();
  }

  /// Tải danh sách thiết bị đã lưu từ Local Storage
  Future<void> _loadSavedDevices() async {
    try {
      final devices = await DeviceStorage.getDevices();
      if (mounted) {
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

      // Hiển thị thông báo "Kết nối SmartThings thành công"
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
      setState(() => _isCopied = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text('Đã sao chép mã kết nối!'),
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

  @override
  Widget build(BuildContext context) {
    final hasDevices = _syncedDevices.isNotEmpty;

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
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: hasDevices
            ? _buildConnectedView()
            : _buildOnboardingView(),
      ),
    );
  }

  // ============================================================
  // TRẠNG THÁI A: CHƯA KẾT NỐI — Onboarding step-by-step
  // ============================================================

  /// Giao diện khi chưa kết nối máy giặt nào — Onboarding step-by-step
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
                      'Hãy làm theo 3 bước bên dưới để kết nối máy giặt.',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // Bước 1: Sao chép mã kết nối
        _buildOnboardingStep(
          stepNumber: '1',
          icon: Icons.content_copy,
          title: 'Sao Chép Mã Kết Nối',
          description: 'Nhấn nút bên dưới để sao chép mã kết nối vào bộ nhớ tạm.',
          isActive: true,
        ),

        const SizedBox(height: 8),

        // Nút sao chép mã kết nối
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
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
                      _isCopied ? Icons.check : Icons.copy,
                      size: 20,
                    ),
              label: Text(
                _isLoadingToken
                    ? 'Đang khởi tạo...'
                    : (_isCopied ? 'Đã Sao Chép Mã' : 'Sao Chép Mã Kết Nối'),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _isCopied
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

        const SizedBox(height: 16),

        // Bước 2: Mở Samsung SmartThings
        _buildOnboardingStep(
          stepNumber: '2',
          icon: Icons.phone_android,
          title: 'Mở Ứng Dụng SmartThings',
          description: 'Mở ứng dụng Samsung SmartThings trên điện thoại, '
              'tìm và chọn "Washer Notifier" trong danh sách.',
          isActive: false,
        ),

        const SizedBox(height: 16),

        // Bước 3: Dán mã và chọn máy giặt
        _buildOnboardingStep(
          stepNumber: '3',
          icon: Icons.link,
          title: 'Dán Mã & Chọn Máy Giặt',
          description: 'Dán mã vừa sao chép vào ô yêu cầu, chọn máy giặt của bạn, '
              'rồi nhấn "Hoàn tất".',
          isActive: false,
        ),

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
                  'Sau khi hoàn tất, màn hình này sẽ tự động cập nhật '
                  'và hiển thị máy giặt đã kết nối.',
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

  /// Widget cho mỗi bước onboarding
  Widget _buildOnboardingStep({
    required String stepNumber,
    required IconData icon,
    required String title,
    required String description,
    required bool isActive,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive ? const Color(0xFF1565C0) : Colors.grey.shade200,
          width: isActive ? 1.5 : 1,
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
              color: isActive ? const Color(0xFF1565C0) : Colors.grey.shade100,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
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
                      color: isActive ? const Color(0xFF1565C0) : Colors.grey.shade500,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: isActive ? const Color(0xFF0D47A1) : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: isActive ? Colors.grey.shade700 : Colors.grey.shade500,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
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
                      'Bạn sẽ nhận cuộc gọi khi giặt xong.',
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

          // Danh sách các thiết bị
          ..._syncedDevices.map((device) {
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE3F2FD),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.local_laundry_service,
                      color: Color(0xFF1565C0),
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
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Mã: ${device.id.length > 8 ? device.id.substring(0, 8) : device.id}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          'Kết nối',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF2E7D32),
                          ),
                        ),
                      ],
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
