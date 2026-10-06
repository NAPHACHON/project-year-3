import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cybercafe_member_app/main.dart';

class ShopFixture {
  ShopFixture({this.admin = false, this.active = false});
  final bool admin;
  bool active;
  bool booked = false;
  bool ended = false;
  bool refunded = false;
  bool rejectEnd = false;
  int hours = 2;
  int endCalls = 0;
  final now = DateTime.now().toUtc();
  Map<String, dynamic> get session => {
        'id': 1,
        'session_code': 'TEST-SESSION-1',
        'station_id': 1,
        'status': ended
            ? 'completed'
            : active
                ? 'active'
                : 'reserved',
        'station': {'station_code': 'PC-01'},
        'user': {'name': 'Test member'},
        'planned_minutes': hours * 60,
        'quoted_amount': '${hours * 20}.00',
        'prepaid_amount': active || ended ? '${hours * 20}.00' : '0.00',
        'started_at': now.subtract(const Duration(hours: 1)).toIso8601String(),
        'scheduled_end_at': now.add(const Duration(hours: 1)).toIso8601String(),
        'minutes_used': 60,
        'free_minutes_used': 0,
        'total_amount': '20.00',
        'refund_amount': '20.00',
        'refund_status': refunded ? 'paid' : 'pending',
        'balance_due': '0.00',
      };
  Map<String, dynamic> get data => {
        'user': {'name': 'Test member', 'role': admin ? 'admin' : 'user'},
        'server_time': now.toIso8601String(),
        'stations': [
          {
            'id': 1,
            'station_code': 'PC-01',
            'zone_name': 'Normal',
            'status': ended || (!booked && !active)
                ? 'available'
                : active
                    ? 'in_use'
                    : 'reserved',
            'specs_info': 'Core i5 / RAM 16 GB',
            'package': {'hourly_rate': '20.00'},
          },
        ],
        'open_sessions': ended || (!booked && !active) ? [] : [session],
        'members': admin
            ? [
                {'id': 2, 'name': 'Test member', 'email': 'test@example.local'},
              ]
            : [],
        'refunds': ended && !refunded ? [session] : [],
        'history': ended ? [session] : [],
        'rewards': {
          'paid_minutes': 0,
          'free_minutes_available': 0,
          'minutes_to_next_reward': 600,
        },
      };
  late final client = MockClient((request) async {
    final path = request.url.path;
    Map<String, dynamic> result;
    if (path.endsWith('/auth/login')) {
      result = {'token': 'test-token'};
    } else if (path.endsWith('/data')) {
      result = data;
    } else if (path.endsWith('/bookings')) {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['hours'], 2);
      expect(body['station_id'], 1);
      if (admin) expect(body['user_id'], 2);
      hours = body['hours'] as int;
      booked = true;
      result = {'data': session, 'message': 'จองเรียบร้อย'};
    } else if (path.endsWith('/cancel')) {
      booked = false;
      result = {'message': 'ยกเลิกแล้ว'};
    } else if (path.endsWith('/start')) {
      expect(jsonDecode(request.body)['payment_received'], true);
      active = true;
      result = {'data': session, 'message': 'รับเงินและเริ่มเล่นแล้ว'};
    } else if (path.endsWith('/settlement')) {
      result = {
        'data': {
          'prepaid_amount': '40.00',
          'minutes_used': 60,
          'free_minutes_used': 0,
          'total_amount': '20.00',
          'refund_amount': '20.00',
          'balance_due': '0.00',
        },
      };
    } else if (path.endsWith('/end')) {
      endCalls++;
      if (rejectEnd)
        return http.Response.bytes(
            utf8.encode(jsonEncode({'message': 'จบรายการไม่สำเร็จ ลองใหม่'})),
            422,
            headers: {'content-type': 'application/json; charset=utf-8'});
      ended = true;
      active = false;
      booked = false;
      result = {
        'data': session,
        'message': 'กรุณาติดต่อเคาน์เตอร์เพื่อรับเงินส่วนต่าง 20.00 บาท',
      };
    } else if (path.endsWith('/refund')) {
      refunded = true;
      result = {'message': 'คืนเงินแล้ว', 'data': session};
    } else {
      throw StateError('Unexpected request: ${request.method} $path');
    }
    return http.Response.bytes(
      utf8.encode(jsonEncode(result)),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });
}

Future<void> login(WidgetTester tester, ShopFixture shop,
    {double width = 390}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(CafeApp(apiClient: shop.client));
  await tester.ensureVisible(find.text('เข้าสู่ระบบ').last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('เข้าสู่ระบบ').last);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    final scrollable = find
        .descendant(
            of: find.byType(ListView).first, matching: find.byType(Scrollable))
        .first;
    tester.state<ScrollableState>(scrollable).position.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(finder, 200, scrollable: scrollable);
  } else {
    await tester.ensureVisible(finder.first);
  }
  await tester.pumpAndSettle();
  await tester.tap(finder.first);
  await tester.pumpAndSettle();
}

Future<void> chooseHoursAndBook(WidgetTester tester) async {
  await tapVisible(tester, find.byType(DropdownButtonFormField<int>).last);
  await tester.tap(find.text('2 ชั่วโมง').last);
  await tester.pumpAndSettle();
  expect(find.textContaining('40.00 บาท'), findsOneWidget);
  await tester.tap(find.text('ยืนยันจอง'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final fonts = FontLoader('IBMPlexSansThai');
    for (final name in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      fonts.addFont(rootBundle.load('assets/fonts/IBMPlexSansThai-$name.ttf'));
    }
    await fonts.load();
  });
  testWidgets('Member chooses duration and cancels reservation on mobile', (
    tester,
  ) async {
    final shop = ShopFixture();
    await login(tester, shop, width: 320);
    await tapVisible(tester, find.text('จองเครื่อง'));
    await chooseHoursAndBook(tester);
    expect(tester.takeException(), isNull);
    expect(shop.booked, isTrue);
    await tapVisible(
      tester,
      find.text('ยกเลิกการจอง'),
    );
    await tester.tap(find.text('ยืนยัน'));
    await tester.pumpAndSettle();
    expect(shop.booked, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('Member ends active session and sees persistent counter refund', (
    tester,
  ) async {
    final shop = ShopFixture(active: true);
    await login(tester, shop);
    await tapVisible(
      tester,
      find.text('ยกเลิก / จบการใช้งาน'),
    );
    expect(find.text('20.00 บาท'), findsNWidgets(2));
    await tester.tap(find.text('ยืนยันจบ'));
    await tester.pumpAndSettle();
    expect(shop.endCalls, 1);
    expect(shop.ended, isTrue);
    await tapVisible(tester, find.text('ส่วนต่างรอคืน 20.00 บาท'));
    expect(find.text('ส่วนต่างรอคืน 20.00 บาท'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'Admin books for member, receives payment, ends and confirms cash refund',
    (tester) async {
      final shop = ShopFixture(admin: true);
      await login(tester, shop);
      await tapVisible(
        tester,
        find.text('จองให้สมาชิก'),
      );
      await chooseHoursAndBook(tester);
      await tapVisible(
        tester,
        find.text('รับเงิน / เริ่มเล่น'),
      );
      await tester.tap(find.text('ยืนยัน'));
      await tester.pumpAndSettle();
      expect(shop.active, isTrue);
      await tapVisible(
        tester,
        find.text('ยกเลิก / จบการใช้งาน'),
      );
      await tester.tap(find.text('ยืนยันจบ'));
      await tester.pumpAndSettle();
      await tapVisible(
        tester,
        find.text('ยืนยันคืนเงินแล้ว'),
      );
      await tester.tap(find.text('ยืนยัน'));
      await tester.pumpAndSettle();
      expect(shop.refunded, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('Rejected settlement keeps session active and allows retry', (
    tester,
  ) async {
    final shop = ShopFixture(active: true)..rejectEnd = true;
    await login(tester, shop);
    await tapVisible(
      tester,
      find.text('ยกเลิก / จบการใช้งาน'),
    );
    await tester.tap(find.text('ยืนยันจบ'));
    await tester.pumpAndSettle();
    expect(shop.active, isTrue);
    expect(shop.ended, isFalse);
    expect(find.text('จบรายการไม่สำเร็จ ลองใหม่'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
