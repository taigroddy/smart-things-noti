import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:uuid/uuid.dart';
import '../models/device_model.dart';
import '../services/device_storage.dart';

/// Màn hình chi tiết thiết bị & Cài đặt thông báo
class DeviceDetailScreen extends StatefulWidget {
  final DeviceItem device;

  const DeviceDetailScreen({super.key, required this.device});

  @override
  State<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends State<DeviceDetailScreen> {
  late DeviceItem _device;

  @override
  void initState() {
    super.initState();
    _device = widget.device;
  }

  Future<void> _toggleNotification(bool value) async {
    setState(() {
      _device.isNotificationEnabled = value;
    });
    await DeviceStorage.updateDevice(_device);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            value
                ? 'Đã BẬT thông báo cuộc gọi cho "${_device.name}"'
                : 'Đã TẮT thông báo cuộc gọi cho "${_device.name}"',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  /// Kích hoạt cuộc gọi giả lập với tên của thiết bị này
  Future<void> _testCallForThisDevice() async {
    final callUuid = const Uuid().v4();

    final params = CallKitParams(
      id: callUuid,
      nameCaller: _device.name,
      appName: 'Washer Notifier',
      avatar: 'https://img.icons8.com/color/96/washing-machine.png',
      handle: 'Quần áo đã giặt xong (${_device.modelCode})',
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
        'type': 'WASHING_MACHINE_DONE',
        'deviceId': _device.id,
      },
      extra: <String, dynamic>{
        'deviceId': _device.id,
      },
    );

    await FlutterCallkitIncoming.showCallkitIncoming(params);
  }

  Future<void> _confirmDelete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận xóa'),
        content: Text('Bạn có chắc chắn muốn xóa thiết bị "${_device.name}" khỏi danh sách?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Xóa', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await DeviceStorage.deleteDevice(_device.id);
      if (mounted) {
        Navigator.pop(context, true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text(_device.name),
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Xóa thiết bị',
            onPressed: _confirmDelete,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header Card hình ảnh và trạng thái
            Card(
              elevation: 3,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE3F2FD),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFF90CAF9), width: 2),
                      ),
                      child: const Icon(
                        Icons.local_laundry_service,
                        size: 64,
                        color: Color(0xFF1565C0),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _device.name,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A237E),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.green.shade400),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: Colors.green.shade600,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _device.status,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.green.shade800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Card Cài đặt Thông báo (Feature 2)
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.notifications_active, color: Color(0xFF1565C0), size: 24),
                        SizedBox(width: 10),
                        Text(
                          'Cài Đặt Thông Báo',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1565C0),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Cuộc gọi giả lập khi giặt xong',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                      ),
                      subtitle: const Text(
                        'Tự động hiện màn hình cuộc gọi toàn màn hình khi nhận tín hiệu giặt xong từ máy giặt này.',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      value: _device.isNotificationEnabled,
                      activeThumbColor: const Color(0xFF1565C0),
                      onChanged: _toggleNotification,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Card Thông tin chi tiết kỹ thuật
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Thông Tin Kỹ Thuật',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const Divider(height: 20),
                    _buildInfoRow('Mã máy / Model', _device.modelCode),
                    const Divider(height: 20),
                    _buildInfoRow('Số Seri (Serial)', _device.serialNumber),
                    const Divider(height: 20),
                    _buildInfoRow('Device ID', _device.id),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Nút test cuộc gọi cho riêng thiết bị này
            ElevatedButton.icon(
              onPressed: _testCallForThisDevice,
              icon: const Icon(Icons.phone_in_talk),
              label: Text(
                'Test Cuộc Gọi Cho "${_device.name}"',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
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

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: Colors.grey,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
        ),
      ],
    );
  }
}
