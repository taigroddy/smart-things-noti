import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:washer_notifier/screens/home_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    const launcherChannel = MethodChannel('com.smartthingnoti.app/app_launcher');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(launcherChannel, (MethodCall methodCall) async {
      if (methodCall.method == 'isAppInstalled') return true;
      return null;
    });
  });

  testWidgets('HomeScreen Passive Listener smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: HomeScreen(),
      ),
    );

    // Kiểm tra UI có tiêu đề và các thành phần chính (đã Việt hóa)
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Thông Báo Máy Giặt'), findsOneWidget);
    expect(find.text('Chờ Kết Nối Máy Giặt'), findsOneWidget);
    expect(find.text('Sao Chép Mã Kết Nối'), findsWidgets);
  });
}
