import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/device_model.dart';
import '../services/device_storage.dart';
import '../services/api_service.dart';

/// Màn hình thêm thiết bị mới (hoặc quét mã QR)
class AddDeviceScreen extends StatefulWidget {
  const AddDeviceScreen({super.key});

  @override
  State<AddDeviceScreen> createState() => _AddDeviceScreenState();
}

class _AddDeviceScreenState extends State<AddDeviceScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _modelController = TextEditingController();
  final _serialController = TextEditingController();
  final _deviceIdController = TextEditingController();
  bool _enableNotification = true;
  bool _isLookingUp = false;
  String? _lookupSuccessMsg;

  @override
  void dispose() {
    _nameController.dispose();
    _modelController.dispose();
    _serialController.dispose();
    _deviceIdController.dispose();
    super.dispose();
  }

  /// Tự động gọi API SmartThings để lấy Device ID khớp với Model/Seri
  Future<void> _lookupDeviceId({String? query}) async {
    String searchParam = query ?? '';
    if (searchParam.isEmpty) {
      searchParam = _serialController.text.trim().isNotEmpty
          ? _serialController.text.trim()
          : _modelController.text.trim();
    }

    setState(() {
      _isLookingUp = true;
      _lookupSuccessMsg = null;
    });

    try {
      final matched = await ApiService.lookupDeviceBySerialOrModel(searchParam);
      if (matched != null) {
        setState(() {
          _deviceIdController.text = matched['deviceId'] ?? '';
          if (_nameController.text.isEmpty) {
            _nameController.text = matched['label'] ?? matched['name'] ?? 'Máy giặt Samsung';
          }
          if (_modelController.text.isEmpty) {
            _modelController.text = matched['modelNumber'] ?? 'Samsung Washer';
          }
          _lookupSuccessMsg = 'Đã tự động lấy Device ID từ SmartThings: ${matched['deviceId']}';
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Đã liên kết thành công với "${matched['label']}"!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Không tìm thấy máy giặt phù hợp trong tài khoản SmartThings. Bạn có thể tự nhập Device ID.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('[Lookup Error]: $e');
    } finally {
      if (mounted) setState(() => _isLookingUp = false);
    }
  }

  /// Mô phỏng quét mã QR trên nhãn máy giặt Samsung
  Future<void> _simulateQRScan() async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          height: 430,
          decoration: const BoxDecoration(
            color: Color(0xFF1E1E2E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.qr_code_scanner, color: Colors.greenAccent, size: 28),
                  SizedBox(width: 10),
                  Text(
                    'Quét mã QR trên thân máy',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Hướng camera về phía mã QR trên tem máy giặt để tự động nhận diện Seri và lấy Device ID.',
                style: TextStyle(color: Colors.white70, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              // Khung quét QR
              Container(
                width: 170,
                height: 170,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.greenAccent, width: 2),
                  borderRadius: BorderRadius.circular(16),
                  color: Colors.black45,
                ),
                child: const Center(
                  child: Icon(
                    Icons.qr_code_2,
                    color: Colors.greenAccent,
                    size: 100,
                  ),
                ),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () async {
                  Navigator.pop(ctx);
                  // Tự động điền dữ liệu quét được từ mã QR
                  setState(() {
                    _nameController.text = 'Máy giặt Lò siêu';
                    _modelController.text = 'Samsung Ecobubble (WW10TP44DSH)';
                    _serialController.text = '0B5Z51NR900123K';
                  });
                  // Tự động tìm deviceId từ SmartThings
                  await _lookupDeviceId(query: 'washer');
                },
                icon: const Icon(Icons.flash_on),
                label: const Text('Mô phỏng Quét & Tự Lấy Device ID'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.greenAccent.shade700,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    final resolvedDeviceId = _deviceIdController.text.trim().isNotEmpty
        ? _deviceIdController.text.trim()
        : const Uuid().v4();

    final newDevice = DeviceItem(
      id: resolvedDeviceId,
      name: _nameController.text.trim(),
      modelCode: _modelController.text.trim(),
      serialNumber: _serialController.text.trim(),
      isNotificationEnabled: _enableNotification,
      status: 'Đang kết nối',
    );

    await DeviceStorage.addDevice(newDevice);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Đã thêm thiết bị "${newDevice.name}" (ID: ${newDevice.id.substring(0, 8)}...) thành công!'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Thêm Thiết Bị Mới'),
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Nút quét QR Code nhanh
              Card(
                elevation: 2,
                color: const Color(0xFFE8F5E9),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Colors.green.shade200),
                ),
                child: InkWell(
                  onTap: _simulateQRScan,
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.green.shade100,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.qr_code_scanner,
                            color: Colors.green.shade800,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Quét mã QR trên thân máy',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green.shade900,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Quét tem để tự nhận diện Seri & lấy Device ID',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.green.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.arrow_forward_ios,
                          size: 16,
                          color: Colors.green.shade800,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              Row(
                children: [
                  Expanded(child: Divider(color: Colors.grey.shade300)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'HOẶC NHẬP THỦ CÔNG & TỰ LẤY ID',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  Expanded(child: Divider(color: Colors.grey.shade300)),
                ],
              ),

              const SizedBox(height: 20),

              // Thông báo nếu đã lấy được Device ID thành công
              if (_lookupSuccessMsg != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.green.shade300),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green.shade700, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _lookupSuccessMsg!,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Card nhập form
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        controller: _nameController,
                        decoration: InputDecoration(
                          labelText: 'Tên thiết bị *',
                          hintText: 'Ví dụ: Máy giặt Lò siêu, Máy giặt ban công',
                          prefixIcon: const Icon(Icons.local_laundry_service),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty ? 'Vui lòng nhập tên thiết bị' : null,
                      ),
                      const SizedBox(height: 16),
                      // Số Seri
                      TextFormField(
                        controller: _serialController,
                        decoration: InputDecoration(
                          labelText: 'Số Seri (Serial Number) *',
                          hintText: 'Ví dụ: 0B5Z51NR900123K',
                          prefixIcon: const Icon(Icons.tag),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty ? 'Vui lòng nhập số Seri' : null,
                      ),
                      const SizedBox(height: 16),
                      // Model
                      TextFormField(
                        controller: _modelController,
                        decoration: InputDecoration(
                          labelText: 'Mã máy / Model *',
                          hintText: 'Ví dụ: Samsung AI Ecobubble (WW10TP44DSH)',
                          prefixIcon: const Icon(Icons.memory),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty ? 'Vui lòng nhập mã máy hoặc Model' : null,
                      ),
                      const SizedBox(height: 14),
                      // Nút Tự lấy Device ID từ SmartThings
                      OutlinedButton.icon(
                        onPressed: _isLookingUp ? null : () => _lookupDeviceId(),
                        icon: _isLookingUp
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.sync),
                        label: Text(_isLookingUp ? 'Đang tìm...' : 'Lấy Device ID từ SmartThings'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF1565C0),
                          minimumSize: const Size(double.infinity, 44),
                        ),
                      ),
                      const SizedBox(height: 14),
                      // Device ID
                      TextFormField(
                        controller: _deviceIdController,
                        decoration: InputDecoration(
                          labelText: 'SmartThings Device ID',
                          hintText: 'Tự động lấy hoặc nhập thủ công (UUID)',
                          prefixIcon: const Icon(Icons.vpn_key),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Cài đặt thông báo
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.ring_volume, color: Color(0xFF1565C0)),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Nhận cuộc gọi khi giặt xong',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Bật giả lập cuộc gọi đến khi máy giặt xong',
                              style: TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _enableNotification,
                        activeThumbColor: const Color(0xFF1565C0),
                        onChanged: (val) {
                          setState(() => _enableNotification = val);
                        },
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              ElevatedButton.icon(
                onPressed: _submitForm,
                icon: const Icon(Icons.save),
                label: const Text(
                  'Lưu Thiết Bị',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1565C0),
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
      ),
    );
  }
}
