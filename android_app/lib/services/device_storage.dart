import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/device_model.dart';

/// Quản lý lưu trữ danh sách thiết bị trên điện thoại qua SharedPreferences
class DeviceStorage {
  static const String _storageKey = 'connected_devices_list';

  /// ValueNotifier để UI tự động cập nhật khi background hoặc foreground đồng bộ thiết bị
  static final ValueNotifier<int> devicesChangedNotifier = ValueNotifier<int>(0);

  /// Lấy danh sách thiết bị đã lưu.
  /// Nếu lần đầu mở app, tự động khởi tạo thiết bị máy giặt mẫu của người dùng.
  static Future<List<DeviceItem>> getDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_storageKey);

    if (jsonString == null || jsonString.isEmpty) {
      // Khởi tạo thiết bị mặc định thực tế của người dùng
      final defaultList = [
        DeviceItem(
          id: 'd5281b1f-97f9-c9f1-23ae-f8d77d8b24d1',
          name: 'Máy giặt Lò siêu',
          modelCode: 'Samsung Ecobubble 10kg (WW10TP44DSH)',
          serialNumber: '0B5Z51NR900123K',
          isNotificationEnabled: true,
          status: 'Đang kết nối',
        ),
      ];
      await saveDevices(defaultList);
      return defaultList;
    }

    try {
      final List<dynamic> decoded = jsonDecode(jsonString);
      return decoded.map((item) => DeviceItem.fromMap(item)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Lưu danh sách thiết bị
  static Future<void> saveDevices(List<DeviceItem> devices) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = devices.map((d) => d.toMap()).toList();
    await prefs.setString(_storageKey, jsonEncode(jsonList));
    devicesChangedNotifier.value++;
  }

  /// Thêm hoặc cập nhật thiết bị khi nhận được SYNC_DEVICE từ SmartThings
  static Future<DeviceItem> upsertDevice({
    required String id,
    required String name,
    String? modelCode,
    String? serialNumber,
  }) async {
    final list = await getDevices();
    final index = list.indexWhere((d) => d.id == id || (d.id.isNotEmpty && id.isNotEmpty && d.id == id));
    DeviceItem device;
    if (index != -1) {
      final existing = list[index];
      device = DeviceItem(
        id: id,
        name: name.isNotEmpty ? name : existing.name,
        modelCode: (modelCode != null && modelCode.isNotEmpty) ? modelCode : existing.modelCode,
        serialNumber: (serialNumber != null && serialNumber.isNotEmpty) ? serialNumber : existing.serialNumber,
        isNotificationEnabled: existing.isNotificationEnabled,
        status: 'Đã đồng bộ SmartApp',
        lastUpdated: DateTime.now(),
      );
      list[index] = device;
    } else {
      device = DeviceItem(
        id: id,
        name: name.isNotEmpty ? name : 'Máy giặt Samsung',
        modelCode: (modelCode != null && modelCode.isNotEmpty) ? modelCode : 'SmartThings Washer',
        serialNumber: (serialNumber != null && serialNumber.isNotEmpty) ? serialNumber : (id.length > 8 ? id.substring(0, 8) : id),
        isNotificationEnabled: true,
        status: 'Đã đồng bộ SmartApp',
        lastUpdated: DateTime.now(),
      );
      list.add(device);
    }
    await saveDevices(list);
    return device;
  }

  /// Bật hoặc tắt cờ thông báo cho thiết bị
  static Future<void> setNotificationEnabled(String id, bool enabled) async {
    final list = await getDevices();
    final index = list.indexWhere((d) => d.id == id);
    if (index != -1) {
      list[index].isNotificationEnabled = enabled;
      await saveDevices(list);
    }
  }

  /// Thêm thiết bị mới
  static Future<void> addDevice(DeviceItem device) async {
    final list = await getDevices();
    list.add(device);
    await saveDevices(list);
  }

  /// Cập nhật thiết bị hiện có
  static Future<void> updateDevice(DeviceItem updated) async {
    final list = await getDevices();
    final index = list.indexWhere((d) => d.id == updated.id);
    if (index != -1) {
      list[index] = updated;
      await saveDevices(list);
    }
  }

  /// Xóa thiết bị theo ID
  static Future<void> deleteDevice(String id) async {
    final list = await getDevices();
    list.removeWhere((d) => d.id == id);
    await saveDevices(list);
  }

  /// Kiểm tra xem có thiết bị nào đang bật thông báo hay không
  static Future<bool> isNotificationEnabledForDevice(String? deviceId) async {
    final list = await getDevices();
    if (list.isEmpty) return true; // Mặc định vẫn báo nếu chưa quản lý
    if (deviceId == null || deviceId.isEmpty) {
      return list.any((d) => d.isNotificationEnabled);
    }
    final match = list.firstWhere(
      (d) => d.id == deviceId || d.modelCode.contains(deviceId),
      orElse: () => list.first,
    );
    return match.isNotificationEnabled;
  }
}
