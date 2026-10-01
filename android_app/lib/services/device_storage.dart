import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Đại diện cho thiết bị máy giặt đã được đồng bộ từ SmartThings
class SyncedDevice {
  final String id;
  final String name;
  final bool isEnabled;

  const SyncedDevice({
    required this.id,
    required this.name,
    this.isEnabled = true,
  });

  factory SyncedDevice.fromJson(Map<String, dynamic> json) {
    return SyncedDevice(
      id: json['id']?.toString() ?? json['deviceId']?.toString() ?? '',
      name: json['name']?.toString() ?? json['deviceName']?.toString() ?? 'Máy giặt Samsung',
      isEnabled: json['isEnabled'] == null ? true : (json['isEnabled'] == true || json['isEnabled'] == 'true'),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'isEnabled': isEnabled,
  };

  SyncedDevice copyWith({
    String? id,
    String? name,
    bool? isEnabled,
  }) {
    return SyncedDevice(
      id: id ?? this.id,
      name: name ?? this.name,
      isEnabled: isEnabled ?? this.isEnabled,
    );
  }
}

/// Dịch vụ quản lý Local Storage cho danh sách thiết bị máy giặt đã đồng bộ
class DeviceStorage {
  static const String _keyDevices = 'synced_devices';
  static const String _keyLastSync = 'last_sync_timestamp';

  // Event stream để UI cập nhật realtime khi có SYNC_DEVICES mới đến
  static final StreamController<List<SyncedDevice>> _syncController =
      StreamController<List<SyncedDevice>>.broadcast();

  static Stream<List<SyncedDevice>> get onDevicesSynced => _syncController.stream;

  /// Parse danh sách thiết bị từ payload FCM:
  /// Hỗ trợ cả JSON string: '[{"id":"...","name":"..."}]' và dynamic List
  static List<SyncedDevice> parseDevices(dynamic raw) {
    if (raw == null) return [];
    if (raw is List) {
      return raw
          .map((item) => SyncedDevice.fromJson(Map<String, dynamic>.from(item)))
          .where((d) => d.id.isNotEmpty)
          .toList();
    }
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw.trim());
        if (decoded is List) {
          return decoded
              .map((item) => SyncedDevice.fromJson(Map<String, dynamic>.from(item)))
              .where((d) => d.id.isNotEmpty)
              .toList();
        }
      } catch (e) {
        debugPrint('[DeviceStorage ⚠️] Lỗi parse devices JSON: $e');
      }
    }
    return [];
  }

  /// Lưu danh sách thiết bị vào Local Storage (SharedPreferences)
  static Future<void> saveDevices(List<SyncedDevice> devices) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = devices.map((d) => d.toJson()).toList();
    await prefs.setString(_keyDevices, jsonEncode(jsonList));
    await prefs.setInt(_keyLastSync, DateTime.now().millisecondsSinceEpoch);
    _syncController.add(devices);
  }

  /// Lấy danh sách thiết bị đã lưu từ Local Storage
  static Future<List<SyncedDevice>> getDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyDevices);
    if (raw == null || raw.isEmpty) return [];
    return parseDevices(raw);
  }

  /// Lấy thời điểm đồng bộ gần nhất
  static Future<int?> getLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyLastSync);
  }

  /// Cập nhật trạng thái bật/tắt nhận chuông thông báo của thiết bị
  static Future<void> updateDeviceEnabled(String deviceId, bool isEnabled) async {
    final devices = await getDevices();
    final updated = devices.map((d) {
      if (d.id == deviceId) {
        return d.copyWith(isEnabled: isEnabled);
      }
      return d;
    }).toList();
    await saveDevices(updated);
  }

  /// Kiểm tra xem thiết bị có đang được bật chuông thông báo hay không
  static Future<bool> isDeviceEnabled(String deviceId) async {
    try {
      final devices = await getDevices();
      if (devices.isEmpty) return true;
      for (final d in devices) {
        if (d.id == deviceId) {
          return d.isEnabled;
        }
      }
      return true;
    } catch (e) {
      debugPrint('[DeviceStorage ⚠️] Lỗi kiểm tra isDeviceEnabled: $e');
      return true;
    }
  }

  /// Xử lý Data Message có type: 'SYNC_DEVICES' hoặc 'SYNC_DEVICE'
  static Future<List<SyncedDevice>> handleSyncMessage(Map<String, dynamic> data) async {
    final type = data['type']?.toString();
    List<SyncedDevice> devices = [];

    if (type == 'SYNC_DEVICES') {
      devices = parseDevices(data['devices']);
    } else if (type == 'SYNC_DEVICE') {
      final deviceId = data['deviceId']?.toString() ?? '';
      final deviceName = data['deviceName']?.toString() ?? 'Máy giặt Samsung';
      if (deviceId.isNotEmpty) {
        devices = [SyncedDevice(id: deviceId, name: deviceName)];
      }
    }

    if (devices.isNotEmpty) {
      // Giữ lại trạng thái isEnabled đã lưu trước đó nếu có
      final existing = await getDevices();
      final existingMap = {for (var d in existing) d.id: d.isEnabled};
      final merged = devices.map((d) {
        if (existingMap.containsKey(d.id)) {
          return d.copyWith(isEnabled: existingMap[d.id]);
        }
        return d;
      }).toList();

      debugPrint('[DeviceStorage 💾] Đã parse và lưu ${merged.length} thiết bị vào Local Storage');
      await saveDevices(merged);
      return merged;
    }
    return devices;
  }

  /// Xóa danh sách thiết bị (nếu cần reset)
  static Future<void> clearDevices() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyDevices);
    await prefs.remove(_keyLastSync);
    _syncController.add([]);
  }
}

