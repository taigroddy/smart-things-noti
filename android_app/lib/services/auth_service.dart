import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:app_links/app_links.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../models/device_model.dart';
import 'device_storage.dart';
import 'api_service.dart';

/// Service quản lý đăng nhập OAuth2 Samsung SmartThings và Deep Link
class AuthService {
  static const String _keyConnected = 'samsung_oauth_connected';
  static const String _keyAccessToken = 'samsung_oauth_access_token';
  static const String _keyRefreshToken = 'samsung_oauth_refresh_token';
  static const String _keyLastSynced = 'samsung_oauth_last_synced';

  static final AppLinks _appLinks = AppLinks();
  static StreamSubscription<Uri>? _sub;

  /// Kiểm tra trạng thái đã liên kết tài khoản Samsung hay chưa
  static Future<bool> isConnected() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyConnected) ?? false;
  }

  /// Lấy access token đã lưu
  static Future<String?> getAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyAccessToken);
  }

  /// Lấy thời điểm đồng bộ gần nhất
  static Future<String?> getLastSynced() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyLastSynced);
  }

  /// Mở trình duyệt web để người dùng đăng nhập tài khoản Samsung
  static Future<bool> startSamsungOAuthLogin() async {
    try {
      // 1. Lấy trực tiếp authUrl từ backend để tránh lỗi double-encoding khi qua 302 redirect trên trình duyệt Android
      final apiUrl = Uri.parse('${ApiService.baseUrl}/api/auth/login?json=true');
      final response = await http.get(apiUrl).timeout(const Duration(seconds: 10));

      Uri targetUrl;
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final authUrl = data['authUrl'] as String?;
        if (authUrl != null && authUrl.isNotEmpty) {
          targetUrl = Uri.parse(authUrl);
        } else {
          targetUrl = Uri.parse('${ApiService.baseUrl}/api/auth/login');
        }
      } else {
        targetUrl = Uri.parse('${ApiService.baseUrl}/api/auth/login');
      }

      debugPrint('[AuthService] Mở trực tiếp SmartThings Authorize URL: $targetUrl');
      final launched = await launchUrl(
        targetUrl,
        mode: LaunchMode.externalApplication,
      );
      return launched;
    } catch (e) {
      debugPrint('[AuthService] Lỗi khi mở URL đăng nhập: $e');
      return false;
    }
  }

  /// Khởi tạo lắng nghe Deep Link (washerapp://auth)
  static void initDeepLinkListener({
    required Function(List<DeviceItem> newDevices) onSuccess,
    required Function(String error) onError,
  }) {
    _sub?.cancel();

    // 1. Lắng nghe link khi app đang mở hoặc chạy nền
    _sub = _appLinks.uriLinkStream.listen(
      (uri) {
        debugPrint('[AuthService] Nhận Deep Link (stream): $uri');
        _handleDeepLink(uri, onSuccess: onSuccess, onError: onError);
      },
      onError: (err) {
        debugPrint('[AuthService] Lỗi stream Deep Link: $err');
      },
    );

    // 2. Kiểm tra link khởi động (nếu app được mở từ deep link)
    _appLinks.getInitialLink().then((uri) {
      if (uri != null) {
        debugPrint('[AuthService] Nhận Deep Link (initial): $uri');
        _handleDeepLink(uri, onSuccess: onSuccess, onError: onError);
      }
    }).catchError((e) {
      debugPrint('[AuthService] Lỗi getInitialLink: $e');
    });
  }

  /// Hủy lắng nghe
  static void dispose() {
    _sub?.cancel();
    _sub = null;
  }

  /// Xử lý phân tích URI từ Deep Link
  static Future<void> _handleDeepLink(
    Uri uri, {
    required Function(List<DeviceItem> newDevices) onSuccess,
    required Function(String error) onError,
  }) async {
    if (uri.scheme != 'washerapp' || uri.host != 'auth') {
      return;
    }

    final queryParams = uri.queryParameters;
    final isSuccess = queryParams['success'] == 'true';

    if (!isSuccess) {
      final errorMsg = queryParams['error'] ?? 'Xác thực tài khoản Samsung thất bại';
      onError(errorMsg);
      return;
    }

    final token = queryParams['token'];
    final refreshToken = queryParams['refreshToken'];
    final devicesRaw = queryParams['devices'];

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyConnected, true);
    if (token != null && token.isNotEmpty) {
      await prefs.setString(_keyAccessToken, token);
    }
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await prefs.setString(_keyRefreshToken, refreshToken);
    }
    await prefs.setString(_keyLastSynced, DateTime.now().toIso8601String());

    List<DeviceItem> resolvedDevices = [];

    if (devicesRaw != null && devicesRaw.isNotEmpty) {
      try {
        final List<dynamic> parsed = jsonDecode(devicesRaw);
        for (final item in parsed) {
          final deviceId = item['deviceId']?.toString() ?? '';
          final name = item['name']?.toString() ?? 'Máy giặt Samsung';
          final label = item['label']?.toString() ?? name;
          final modelNumber = item['modelNumber']?.toString() ?? 'Samsung Smart Washer';
          final serialNumber = item['serialNumber']?.toString() ?? 'SN-${deviceId.length > 8 ? deviceId.substring(0, 8) : deviceId}';

          final devItem = DeviceItem(
            id: deviceId,
            name: label,
            modelCode: modelNumber,
            serialNumber: serialNumber,
            isNotificationEnabled: true,
            status: 'Đã kết nối OAuth',
          );
          resolvedDevices.add(devItem);
        }
      } catch (e) {
        debugPrint('[AuthService] Lỗi parse devices từ deep link: $e');
      }
    }

    // Nếu parse được thiết bị, cập nhật/lưu vào DeviceStorage
    if (resolvedDevices.isNotEmpty) {
      final currentList = await DeviceStorage.getDevices();
      for (final newDev in resolvedDevices) {
        final existingIndex = currentList.indexWhere((d) => d.id == newDev.id);
        if (existingIndex != -1) {
          currentList[existingIndex] = newDev;
        } else {
          currentList.add(newDev);
        }
      }
      await DeviceStorage.saveDevices(currentList);
    }

    onSuccess(resolvedDevices);
  }

  /// Đồng bộ thiết bị lại từ SmartThings (qua token OAuth hoặc PAT)
  static Future<List<DeviceItem>> syncDevices() async {
    final token = await getAccessToken();
    final deviceMaps = await ApiService.fetchSmartThingsDevices(token: token);

    final List<DeviceItem> synced = [];
    for (final item in deviceMaps) {
      final deviceId = item['deviceId']?.toString() ?? '';
      final name = item['name']?.toString() ?? 'Máy giặt Samsung';
      final label = item['label']?.toString() ?? name;
      final modelNumber = item['modelNumber']?.toString() ?? 'Samsung Smart Washer';
      final serialNumber = item['serialNumber']?.toString() ?? 'SN-${deviceId.length > 8 ? deviceId.substring(0, 8) : deviceId}';

      synced.add(DeviceItem(
        id: deviceId,
        name: label,
        modelCode: modelNumber,
        serialNumber: serialNumber,
        isNotificationEnabled: true,
        status: 'Đã kết nối OAuth',
      ));
    }

    if (synced.isNotEmpty) {
      final currentList = await DeviceStorage.getDevices();
      for (final newDev in synced) {
        final existingIndex = currentList.indexWhere((d) => d.id == newDev.id);
        if (existingIndex != -1) {
          currentList[existingIndex] = newDev;
        } else {
          currentList.add(newDev);
        }
      }
      await DeviceStorage.saveDevices(currentList);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyLastSynced, DateTime.now().toIso8601String());
    }

    return synced;
  }

  /// Ngắt kết nối tài khoản Samsung SmartThings
  static Future<void> disconnect() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyConnected);
    await prefs.remove(_keyAccessToken);
    await prefs.remove(_keyRefreshToken);
    await prefs.remove(_keyLastSynced);
  }
}
