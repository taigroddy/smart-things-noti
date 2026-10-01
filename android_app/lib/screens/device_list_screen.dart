import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:uuid/uuid.dart';
import '../models/device_model.dart';
import '../services/device_storage.dart';
import 'add_device_screen.dart';
import 'device_detail_screen.dart';

/// Màn hình danh sách thiết bị thông minh & quản lý FCM SmartApp Sync
class DeviceListScreen extends StatefulWidget {
  const DeviceListScreen({super.key});

  @override
  State<DeviceListScreen> createState() => _DeviceListScreenState();
}

class _DeviceListScreenState extends State<DeviceListScreen>
    with WidgetsBindingObserver {
  List<DeviceItem> _devices = [];
  bool _isLoading = true;
  String? _fcmToken;
  bool _isCopied = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    DeviceStorage.devicesChangedNotifier.addListener(_loadDevices);
    _loadData();
    _fetchFCMToken();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    DeviceStorage.devicesChangedNotifier.removeListener(_loadDevices);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadDevices();
    }
  }

  Future<void> _fetchFCMToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (mounted) {
        setState(() => _fcmToken = token);
      }
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
        if (mounted) {
          setState(() => _fcmToken = newToken);
        }
      });
    } catch (e) {
      debugPrint('[DeviceListScreen] Lỗi lấy FCM token: $e');
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    await _loadDevices();
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadDevices() async {
    final list = await DeviceStorage.getDevices();
    if (mounted) {
      setState(() {
        _devices = list;
      });
    }
  }

  Future<void> _copyTokenToClipboard() async {
    if (_fcmToken == null || _fcmToken!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đang tải FCM Token, vui lòng thử lại sau giây lát...'),
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
              SizedBox(width: 8),
              Expanded(
                child: Text('Đã sao chép FCM Token vào bộ nhớ tạm!'),
              ),
            ],
          ),
          backgroundColor: Colors.green.shade700,
          duration: const Duration(seconds: 3),
        ),
      );
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted) setState(() => _isCopied = false);
      });
    }
  }

  Future<void> _toggleDeviceNotification(DeviceItem device, bool enabled) async {
    await DeviceStorage.setNotificationEnabled(device.id, enabled);
    await _loadDevices();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled
                ? 'Đã BẬT thông báo cuộc gọi cho "${device.name}"'
                : 'Đã TẮT thông báo cuộc gọi cho "${device.name}"',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _openAddDevice() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (context) => const AddDeviceScreen()),
    );
    if (result == true) {
      _loadDevices();
    }
  }

  Future<void> _openDeviceDetail(DeviceItem device) async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => DeviceDetailScreen(device: device),
      ),
    );
    _loadDevices();
  }

  /// Kích hoạt test cuộc gọi giả lập nhanh
  Future<void> _testQuickCall() async {
    final callUuid = const Uuid().v4();
    final firstDevice = _devices.isNotEmpty ? _devices.first : null;
    final callerName = firstDevice?.name ?? 'Máy Giặt Thông Minh';

    final params = CallKitParams(
      id: callUuid,
      nameCaller: callerName,
      appName: 'Washer Notifier',
      avatar: 'https://img.icons8.com/color/96/washing-machine.png',
      handle: 'Quần áo đã giặt xong!',
      type: 0,
      textAccept: 'Xem ngay',
      textDecline: 'Bỏ qua',
      duration: 45000,
      android: const AndroidParams(
        isCustomNotification: true,
        isShowLogo: true,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#1565C0',
        actionColor: '#4CAF50',
        textColor: '#ffffff',
        isShowCallID: false,
      ),
      headers: <String, dynamic>{
        'type': 'TRIGGER_CALL',
        'callUuid': callUuid,
      },
    );

    await FlutterCallkitIncoming.showCallkitIncoming(params);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.local_laundry_service, size: 24),
            SizedBox(width: 8),
            Text(
              'Thiết Bị Của Tôi',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline, size: 26),
            tooltip: 'Thêm thiết bị thủ công',
            onPressed: _openAddDevice,
          ),
          IconButton(
            icon: const Icon(Icons.phone_in_talk, size: 22),
            tooltip: 'Test cuộc gọi giả lập',
            onPressed: _testQuickCall,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadDevices,
              child: _devices.isEmpty
                  ? _buildEmptyState()
                  : _buildDeviceList(),
            ),
    );
  }

  /// Banner hiển thị và sao chép FCM Device Token cho SmartApp Webhook
  Widget _buildFcmTokenBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF90CAF9), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withValues(alpha: 0.08),
            blurRadius: 10,
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
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFF1565C0),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Icon(Icons.vpn_key, color: Colors.white, size: 22),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'FCM Device Token',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0D47A1),
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Dùng để kết nối SmartApp SmartThings',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                  _isCopied ? Icons.check_circle : Icons.copy,
                  color: _isCopied ? Colors.green : const Color(0xFF1565C0),
                ),
                tooltip: 'Sao chép Token',
                onPressed: _copyTokenToClipboard,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Text(
              _fcmToken != null && _fcmToken!.isNotEmpty
                  ? _fcmToken!
                  : 'Đang tải Token thiết bị...',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: Color(0xFF334155),
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _copyTokenToClipboard,
                  icon: Icon(_isCopied ? Icons.check : Icons.content_copy, size: 18),
                  label: Text(_isCopied ? 'Đã Sao Chép Token' : 'Sao Chép FCM Token'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isCopied ? Colors.green.shade700 : const Color(0xFF1565C0),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.info_outline, size: 14, color: Colors.grey.shade600),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Dán Token này vào cài đặt SmartApp trên Samsung SmartThings để tự động đồng bộ.',
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Giao diện khi chưa có thiết bị nào
  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildFcmTokenBanner(),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.blue.shade100, width: 2),
              ),
              child: const Icon(
                Icons.devices_other,
                size: 64,
                color: Color(0xFF1565C0),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Chưa Có Thiết Bị Nào',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A237E),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Hãy sao chép FCM Token ở trên và dán vào SmartApp SmartThings để tự động nhận diện máy giặt, hoặc thêm thủ công bên dưới.',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _openAddDevice,
              icon: const Icon(Icons.add),
              label: const Text(
                'Nhập Thủ Công Mã Máy & Seri',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF1565C0),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                side: const BorderSide(color: Color(0xFF1565C0)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Giao diện danh sách các thiết bị đã kết nối
  Widget _buildDeviceList() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        // Thẻ quản lý FCM Token
        _buildFcmTokenBanner(),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'DANH SÁCH MÁY GIẶT (${_devices.length})',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade700,
                letterSpacing: 0.5,
              ),
            ),
            Text(
              'Chạm để xem chi tiết',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
          ],
        ),

        const SizedBox(height: 10),

        // Danh sách các thẻ thiết bị
        ..._devices.map((device) => _buildDeviceCard(device)),

        const SizedBox(height: 16),

        // Nút thêm thiết bị ở cuối danh sách
        OutlinedButton.icon(
          onPressed: _openAddDevice,
          icon: const Icon(Icons.add),
          label: const Text('Thêm Máy Giặt Khác (Thủ Công)'),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF1565C0),
            padding: const EdgeInsets.symmetric(vertical: 14),
            side: const BorderSide(color: Color(0xFF1565C0)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDeviceCard(DeviceItem device) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: device.isNotificationEnabled
              ? const Color(0xFF90CAF9)
              : Colors.grey.shade300,
        ),
      ),
      child: InkWell(
        onTap: () => _openDeviceDetail(device),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Icon máy giặt
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: device.isNotificationEnabled
                      ? const Color(0xFFE3F2FD)
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.local_laundry_service,
                  color: device.isNotificationEnabled
                      ? const Color(0xFF1565C0)
                      : Colors.grey.shade500,
                  size: 30,
                ),
              ),

              const SizedBox(width: 14),

              // Thông tin máy
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A237E),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Model: ${device.modelCode.isNotEmpty ? device.modelCode : "Samsung Smart Washer"}',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // Công tắc (Switch/Toggle) Bật / Tắt nhận cuộc gọi trực tiếp trên card
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Switch.adaptive(
                    value: device.isNotificationEnabled,
                    activeThumbColor: const Color(0xFF1565C0),
                    onChanged: (val) => _toggleDeviceNotification(device, val),
                  ),
                  Text(
                    device.isNotificationEnabled ? 'Bật chuông' : 'Tắt chuông',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: device.isNotificationEnabled
                          ? Colors.green.shade800
                          : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
