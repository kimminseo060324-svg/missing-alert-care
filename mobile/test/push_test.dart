import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gieokhaejwo/data/alert_repository.dart';
import 'package:gieokhaejwo/push/push_open.dart';
import 'package:gieokhaejwo/push/push_payload.dart';
import 'package:gieokhaejwo/screens/alert_detail_screen.dart';
import 'package:gieokhaejwo/screens/alert_list_screen.dart';
import 'package:gieokhaejwo/screens/found_detail_screen.dart';
import 'package:gieokhaejwo/screens/splash_screen.dart';
import 'package:gieokhaejwo/theme/app_theme.dart';

/// 시연용 가짜 데이터 원본 (assets/data/missing-alerts.json)
/// 9990001 = 수색 중, 9990002 = 발견 완료
final _goodJson = File('assets/data/missing-alerts.json').readAsStringSync();

AlertRepository _repo(String raw) => AlertRepository.fromRaw(() async => raw);

PushPayload _payload(String alertId, {String type = 'missing_alert'}) =>
    PushPayload.fromData({
      'type': type,
      'event': 'issued',
      'alert_id': alertId,
      'status': '수색중',
      'region': '오산시',
      'version': '1',
    });

final _navKey = GlobalKey<NavigatorState>();

Widget _app() => MaterialApp(
  navigatorKey: _navKey,
  theme: buildAppTheme(),
  home: const Scaffold(body: Text('시작 화면')),
);

/// 앱을 띄우고 푸시 알림을 누른 것처럼 화면을 열어요.
Future<void> _tapPush(
  WidgetTester tester,
  PushPayload payload,
  AlertRepository repo,
) async {
  await tester.pumpWidget(_app());
  await tester.runAsync(
    () => openFromPush(_navKey.currentState!, payload, repository: repo),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(360, 800);
    view.devicePixelRatio = 1;
  });

  group('푸시 data 읽기', () {
    test('문자열 값을 읽고 alert_id는 숫자로 바꿔요', () {
      final p = _payload('9990001');
      expect(p.isMissingAlert, isTrue);
      expect(p.event, 'issued');
      expect(p.alertId, 9990001);
      expect(p.status, '수색중');
      expect(p.region, '오산시');
    });

    test('alert_id가 없거나 숫자가 아니면 null', () {
      expect(PushPayload.fromData({'type': 'missing_alert'}).alertId, isNull);
      expect(_payload('abc').alertId, isNull);
    });

    test('구독 토픽은 missing_alerts_osan', () {
      expect(PushPayload.topic, 'missing_alerts_osan');
    });
  });

  group('푸시 알림을 누르면', () {
    testWidgets('수색 중 경보는 05 상세가 열려요', (tester) async {
      await _tapPush(tester, _payload('9990001'), _repo(_goodJson));
      expect(find.byType(AlertDetailScreen), findsOneWidget);
    });

    testWidgets('발견 완료 경보는 07 발견 완료 상세가 열려요', (tester) async {
      await _tapPush(tester, _payload('9990002'), _repo(_goodJson));
      expect(find.byType(FoundDetailScreen), findsOneWidget);
    });

    testWidgets('없는 번호면 04 목록이 열려요', (tester) async {
      await _tapPush(tester, _payload('123'), _repo(_goodJson));
      expect(find.byType(AlertListScreen), findsOneWidget);
    });

    testWidgets('경보를 못 읽으면 04 목록이 열려요', (tester) async {
      await _tapPush(tester, _payload('9990001'), _repo('{깨진 JSON'));
      expect(find.byType(AlertListScreen), findsOneWidget);
    });

    testWidgets('실종경보 푸시가 아니면 아무 화면도 안 열어요', (tester) async {
      await _tapPush(
        tester,
        _payload('9990001', type: 'other'),
        _repo(_goodJson),
      );
      expect(find.text('시작 화면'), findsOneWidget);
    });
  });

  testWidgets('첫 화면 도중 푸시로 연 화면은 첫 화면이 끝나도 남아 있어요', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: _navKey,
        theme: buildAppTheme(),
        home: const SplashScreen(next: Scaffold(body: Text('시연 메뉴'))),
      ),
    );
    await tester.runAsync(
      () => openFromPush(
        _navKey.currentState!,
        _payload('9990001'),
        repository: _repo(_goodJson),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AlertDetailScreen), findsOneWidget);

    await tester.pump(SplashScreen.duration);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDetailScreen), findsOneWidget);

    // 뒤로 가면 첫 화면 대신 시연 메뉴가 나와요.
    _navKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('시연 메뉴'), findsOneWidget);
  });
}
