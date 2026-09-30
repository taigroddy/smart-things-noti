import 'dart:convert';

/// Model đại diện cho một thiết bị máy giặt / sấy trong nhà
/// Hỗ trợ cả 2 chuẩn đặt tên: (id / deviceId), (name / deviceName), (isNotificationEnabled / isEnabled)
class DeviceItem {
  final String id;
  String name;
  String modelCode;
  String serialNumber;
  bool isNotificationEnabled;
  String status;
  DateTime lastUpdated;

  // Aliases theo đúng yêu cầu spec: { deviceId, deviceName, isEnabled }
  String get deviceId => id;
  String get deviceName => name;
  bool get isEnabled => isNotificationEnabled;
  set isEnabled(bool val) => isNotificationEnabled = val;

  DeviceItem({
    required this.id,
    required this.name,
    this.modelCode = '',
    this.serialNumber = '',
    this.isNotificationEnabled = true,
    this.status = 'Đã đồng bộ',
    DateTime? lastUpdated,
  }) : lastUpdated = lastUpdated ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'deviceId': id,
      'name': name,
      'deviceName': name,
      'modelCode': modelCode,
      'serialNumber': serialNumber,
      'isNotificationEnabled': isNotificationEnabled,
      'isEnabled': isNotificationEnabled,
      'status': status,
      'lastUpdated': lastUpdated.toIso8601String(),
    };
  }

  factory DeviceItem.fromMap(Map<String, dynamic> map) {
    final dId = map['deviceId']?.toString() ?? map['id']?.toString() ?? '';
    final dName = map['deviceName']?.toString() ?? map['name']?.toString() ?? 'Máy giặt';
    final dEnabled = map['isEnabled'] ?? map['isNotificationEnabled'] ?? true;

    return DeviceItem(
      id: dId,
      name: dName,
      modelCode: map['modelCode']?.toString() ?? '',
      serialNumber: map['serialNumber']?.toString() ?? '',
      isNotificationEnabled: dEnabled is bool ? dEnabled : (dEnabled.toString().toLowerCase() == 'true'),
      status: map['status']?.toString() ?? 'Đã đồng bộ',
      lastUpdated: map['lastUpdated'] != null
          ? DateTime.tryParse(map['lastUpdated'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  String toJson() => jsonEncode(toMap());

  factory DeviceItem.fromJson(String source) =>
      DeviceItem.fromMap(jsonDecode(source));
}
