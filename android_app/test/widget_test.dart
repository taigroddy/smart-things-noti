import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:washer_notifier/screens/home_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('HomeScreen Passive Listener smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: HomeScreen(),
      ),
    );

    // Kiểm tra UI có tiêu đề và các thành phần chính
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Washer Notifier'), findsOneWidget);
    expect(find.text('Người Lắng Nghe Thụ Động'), findsOneWidget);
    expect(find.text('Thử Nghiệm Cuộc Gọi Giả Lập'), findsOneWidget);
  });
}
