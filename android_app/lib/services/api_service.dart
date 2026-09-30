import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Service giao tiếp với Backend Webhook để lấy thông tin thiết bị SmartThings
class ApiService {
  // URL backend Vercel của dự án
  static const String baseUrl = 'https://smart-things-noti-81ql.vercel.app';

  /// Lấy danh sách máy giặt SmartThings được đồng bộ từ tài khoản (hỗ trợ Bearer Token OAuth)
  static Future<List<Map<String, dynamic>>> fetchSmartThingsDevices({String? token}) async {
    try {
      final url = Uri.parse('$baseUrl/api/devices');
      debugPrint('[ApiService] Đang gọi: $url (token: ${token != null ? "Có" : "Dùng PAT Backend"})');

      final Map<String, String> headers = {
        'Accept': 'application/json',
      };
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }

      final response = await http.get(url, headers: headers).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> items = data['devices'] ?? [];
        return items.map((e) => Map<String, dynamic>.from(e)).toList();
      } else {
        debugPrint('[ApiService] Server trả về mã lỗi: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      debugPrint('[ApiService] Lỗi khi lấy danh sách thiết bị: $e');
    }
    return [];
  }

  /// Tra cứu deviceId tương ứng từ Số Seri / Model đã quét được
  static Future<Map<String, dynamic>?> lookupDeviceBySerialOrModel(String query, {String? token}) async {
    final list = await fetchSmartThingsDevices(token: token);
    if (list.isEmpty) return null;

    final q = query.trim().toLowerCase();

    // 1. Tìm khớp chính xác deviceId
    for (final dev in list) {
      if ((dev['deviceId'] ?? '').toString().toLowerCase() == q) {
        return dev;
      }
    }

    // 2. Tìm khớp theo Model Number hoặc nhãn thiết bị
    for (final dev in list) {
      final model = (dev['modelNumber'] ?? '').toString().toLowerCase();
      final label = (dev['label'] ?? '').toString().toLowerCase();
      if (model.contains(q) || q.contains(model) || label.contains(q) || q.contains(label)) {
        return dev;
      }
    }

    // 3. Nếu chỉ có duy nhất 1 máy giặt trong tài khoản, ưu tiên trả về máy đó
    if (list.length == 1) {
      return list.first;
    }

    return null;
  }
}
