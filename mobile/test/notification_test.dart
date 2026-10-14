import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gieokhaejwo/data/alert_repository.dart';
import 'package:gieokhaejwo/data/api_settings.dart';
import 'package:gieokhaejwo/push/foreground_notice.dart';
import 'package:gieokhaejwo/push/push_open.dart';
import 'package:gieokhaejwo/screens/alert_detail_screen.dart';
import 'package:gieokhaejwo/screens/found_detail_screen.dart';
import 'package:gieokhaejwo/screens/server_settings_screen.dart';
import 'package:gieokhaejwo/theme/app_theme.dart';
import 'package:gieokhaejwo/widgets/load_state_view.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 서버가 보내는 푸시 data (모의 메시지)
Map<String, dynamic> _data(
  String event,
  String status, {
  String alertId = '9990001',
}) => {
  'type': 'missing_alert',
  'event': event,
  'alert_id': alertId,
  'status': status,
  'region': '오산시',
  'version': '1',
};

/// 가짜 서버: 경보 한 건의 최신 상태만 돌려줘요.
AlertRepository _serverWith(String status) => AlertRepository.server(
  'http://10.0.2.2:8000',
  client: MockClient(
    (req) async => http.Response.bytes(
      utf8.encode(
        jsonEncode({
          'msspsnIdntfccd': 9990001,
          'nm': null, // 경보 종료면 서버가 이름을 빼요
          'age': 82,
          'sexdstnDscd': '남자',
          'occrAdres': '경기 오산시 양산동',
          'status': status,
          'found_at': status == '발견완료' ? '2026-10-14T21:30:05+09:00' : null,
          'ended_at': status == '경보종료' ? '2026-10-14T21:30:05+09:00' : null,
        }),
      ),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    ),
  ),
);

final _navKey = GlobalKey<NavigatorState>();

void main() {
  group('앱을 보고 있을 때 띄우는 알림', () {
    test('서버가 보낸 문구 그대로, 경보마다 같은 tag', () {
      final n = ForegroundNotice.from(
        _data('issued', '수색중'),
        title: '실종경보',
        body: '오산시에서 82세 남성을 찾고 있어요',
      )!;
      expect(n.tag, 'alert_9990001');
      expect(n.title, '실종경보');
      expect(n.body, '오산시에서 82세 남성을 찾고 있어요');
      // FCM이 tag를 달아 띄운 알림과 같은 번호라야 바꿔치기돼요.
      expect(ForegroundNotice.androidId, 0);
    });

    test('종료·발견 알림은 같은 tag라서 앞의 알림을 바꿔치기해요', () {
      final issued = ForegroundNotice.from(_data('issued', '수색중'))!;
      final ended = ForegroundNotice.from(_data('closed', '경보종료'))!;
      final found = ForegroundNotice.from(_data('closed', '발견완료'))!;
      expect(ended.tag, issued.tag);
      expect(found.tag, issued.tag);
      // 다른 경보는 tag가 달라서 서로 덮지 않아요.
      final other = ForegroundNotice.from(
        _data('issued', '수색중', alertId: '9990002'),
      )!;
      expect(other.tag, isNot(issued.tag));
    });

    test('문구가 없으면 상태에 맞는 문구를 만들어요', () {
      expect(
        ForegroundNotice.from(_data('issued', '수색중'))!.body,
        '오산시에서 실종자를 찾고 있어요',
      );
      final ended = ForegroundNotice.from(_data('closed', '경보종료'))!;
      expect(ended.title, '실종경보 종료');
      expect(ended.body, '오산시 실종경보가 종료됐어요');
      final found = ForegroundNotice.from(_data('closed', '발견완료'))!;
      expect(found.title, '실종자 발견');
      expect(found.body, '오산시 실종자를 찾았어요');
    });

    test('실종경보가 아니거나 alert_id가 없으면 띄우지 않아요', () {
      expect(
        ForegroundNotice.from({..._data('issued', '수색중'), 'type': 'news'}),
        isNull,
      );
      expect(
        ForegroundNotice.from(_data('issued', '수색중', alertId: '')),
        isNull,
      );
    });

    test('알림을 누르면 payload에서 푸시 data를 되찾아요', () {
      final n = ForegroundNotice.from(_data('closed', '경보종료'))!;
      final p = ForegroundNotice.decode(n.payload)!;
      expect(p.alertId, 9990001);
      expect(p.status, '경보종료');
      expect(ForegroundNotice.decode('깨진 글자'), isNull);
      expect(ForegroundNotice.decode(null), isNull);
    });
  });

  group('알림을 누르면 서버의 최신 상태로 화면을 열어요', () {
    Future<void> tap(WidgetTester tester, String serverStatus) async {
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: _navKey,
          theme: buildAppTheme(),
          home: const Scaffold(body: Text('시작 화면')),
        ),
      );
      // 알림은 "찾고 있어요"였지만 그사이 서버 상태가 바뀌었어요.
      final n = ForegroundNotice.from(_data('issued', '수색중'))!;
      await tester.runAsync(
        () => openFromPush(
          _navKey.currentState!,
          ForegroundNotice.decode(n.payload)!,
          repository: _serverWith(serverStatus),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('서버가 경보 종료면 종료 안내가 있는 05 (이름이 없어도 괜찮아요)', (tester) async {
      await tap(tester, '경보종료');
      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDetailScreen), findsOneWidget);
      expect(find.text('경보가 종료됐어요'), findsOneWidget);
    });

    testWidgets('서버가 발견 완료면 07', (tester) async {
      await tap(tester, '발견완료');
      expect(find.byType(FoundDetailScreen), findsOneWidget);
    });
  });

  group('서버 연결 실패 화면', () {
    setUp(() {
      final view =
          TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
      view.physicalSize = const Size(360, 800);
      view.devicePixelRatio = 1;
    });

    testWidgets('짧은 안내와 "서버 주소 바꾸기" → 저장하면 다시 시도', (tester) async {
      SharedPreferences.setMockInitialValues({});
      ApiSettings.current = const ApiSettings(baseUrl: 'http://10.0.2.2:8000');
      var retried = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: LoadErrorView(onRetry: () => retried++, server: true),
          ),
        ),
      );
      expect(find.text(LoadErrorView.serverMessage), findsOneWidget);
      expect(find.text(LoadErrorView.hint), findsOneWidget);

      await tester.tap(find.text(LoadErrorView.changeServerLabel));
      await tester.pumpAndSettle();
      expect(find.byType(ServerSettingsScreen), findsOneWidget);

      await tester.enterText(find.byType(TextField), '192.168.0.5:8000');
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();
      expect(find.byType(ServerSettingsScreen), findsNothing);
      expect(retried, 1);
    });

    testWidgets('뒤로 가기로 닫으면 다시 시도하지 않아요', (tester) async {
      var retried = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: LoadErrorView(onRetry: () => retried++, server: true),
          ),
        ),
      );
      await tester.tap(find.text(LoadErrorView.changeServerLabel));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(retried, 0);
    });

    testWidgets('설정 화면에 있는 동안 원래 화면이 닫혔으면 저장해도 다시 시도하지 않아요', (tester) async {
      SharedPreferences.setMockInitialValues({});
      ApiSettings.current = const ApiSettings(baseUrl: 'http://10.0.2.2:8000');
      var retried = 0;
      final showError = ValueNotifier(true);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: ValueListenableBuilder<bool>(
              valueListenable: showError,
              builder: (_, show, _) => show
                  ? LoadErrorView(onRetry: () => retried++, server: true)
                  : const Text('다른 화면'),
            ),
          ),
        ),
      );
      await tester.tap(find.text(LoadErrorView.changeServerLabel));
      await tester.pumpAndSettle();

      // 설정 화면 아래에서 실패 화면이 사라져요.
      showError.value = false;
      await tester.pump();

      await tester.enterText(find.byType(TextField), '192.168.0.5:8000');
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(retried, 0);
    });

    testWidgets('앱 안 데이터를 못 읽을 때는 서버 버튼이 없어요', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(body: LoadErrorView(onRetry: () {})),
        ),
      );
      expect(find.text(LoadErrorView.changeServerLabel), findsNothing);
    });

    test('연결 확인 실패는 긴 오류 대신 짧은 안내', () {
      expect(
        connectFailText(const ServerException(500)),
        '연결하지 못했어요. 서버가 오류를 보냈어요. (500)',
      );
      expect(
        connectFailText(TimeoutException('x')),
        '연결하지 못했어요. 서버 응답이 너무 늦어요.',
      );
      final other = connectFailText(
        http.ClientException('SocketException: Connection refused'),
      );
      expect(other, '연결하지 못했어요. 서버가 켜져 있는지, 주소가 맞는지 확인해 주세요.');
      expect(other, isNot(contains('Exception')));
    });
  });
}
