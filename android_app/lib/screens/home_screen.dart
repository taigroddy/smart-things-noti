import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../services/call_manager.dart';

/// Màn hình chính của Passive Listener:
/// - Hiển thị chuỗi FCM Device Token kèm nút Sao Chép
/// - Trạng thái sẵn sàng lắng nghe tín hiệu từ SmartThings
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

  @override
  void initState() {
    super.initState();
    _fetchFCMToken();
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
          content: Text('Đang khởi tạo Token, vui lòng đợi giây lát...'),
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
                child: Text('Đã sao chép FCM Token vào bộ nhớ tạm!'),
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

  /// Kích hoạt test cuộc gọi giả lập tức thì
  Future<void> _triggerTestCall() async {
    await CallManager.triggerIncomingCall(
      callerName: 'Máy Giặt Thông Minh',
      handle: 'Quần áo đã giặt xong! (Kiểm tra cuộc gọi)',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F6F9),
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.hearing, size: 24),
            SizedBox(width: 8),
            Text(
              'Washer Notifier',
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Trạng thái lắng nghe (Passive Listener Status)
            _buildStatusHeader(),

            const SizedBox(height: 20),

            // 2. Thẻ hiển thị FCM Device Token và nút Copy
            _buildTokenCard(),

            const SizedBox(height: 20),

            // 3. Thẻ hướng dẫn kết nối với SmartThings
            _buildGuideCard(),

            const SizedBox(height: 24),

            // 4. Nút kích hoạt kiểm thử cuộc gọi giả lập
            ElevatedButton.icon(
              onPressed: _triggerTestCall,
              icon: const Icon(Icons.phone_in_talk, size: 22),
              label: const Text(
                'Thử Nghiệm Cuộc Gọi Giả Lập',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Thẻ trạng thái kết nối
  Widget _buildStatusHeader() {
    return Container(
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
              Icons.sensors,
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
                      'Người Lắng Nghe Thụ Động',
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
                  'Sẵn sàng nhận tín hiệu FCM và đổ chuông khi giặt xong.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Thẻ hiển thị Token và nút sao chép
  Widget _buildTokenCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFBBDEFB), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.vpn_key, color: Color(0xFF1565C0), size: 22),
              SizedBox(width: 10),
              Text(
                'FCM Device Token',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0D47A1),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: _isLoadingToken
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : SelectableText(
                    _fcmToken ?? 'Không thể lấy Token',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: Color(0xFF334155),
                      height: 1.4,
                    ),
                  ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _copyTokenToClipboard,
              icon: Icon(
                _isCopied ? Icons.check : Icons.copy,
                size: 20,
              ),
              label: Text(
                _isCopied ? 'Đã Sao Chép Token' : 'Sao Chép FCM Token',
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
        ],
      ),
    );
  }

  /// Thẻ hướng dẫn nhanh
  Widget _buildGuideCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF9E6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFE082)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: Colors.amber.shade900, size: 20),
              const SizedBox(width: 8),
              Text(
                'Hướng dẫn kết nối SmartThings',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.amber.shade900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '1. Nhấn nút "Sao Chép FCM Token" ở trên.\n'
            '2. Mở SmartThings App > Cài đặt SmartApp Washer Notifier.\n'
            '3. Dán Token vào ô "Lấy mã từ Ứng dụng Washer Notifier" và chọn máy giặt.\n'
            '4. Xong! Bạn sẽ nhận được cuộc gọi tự động ngay khi máy giặt giặt xong.',
            style: TextStyle(
              fontSize: 12.5,
              color: Colors.amber.shade900,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
