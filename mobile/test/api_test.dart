import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gieokhaejwo/data/alert_repository.dart';
import 'package:gieokhaejwo/data/api_settings.dart';
import 'package:gieokhaejwo/models/missing_alert.dart';
import 'package:gieokhaejwo/push/push_open.dart';
import 'package:gieokhaejwo/push/push_payload.dart';
import 'package:gieokhaejwo/screens/alert_detail_screen.dart';
import 'package:gieokhaejwo/screens/alert_list_screen.dart';
import 'package:gieokhaejwo/screens/found_detail_screen.dart';
import 'package:gieokhaejwo/screens/server_settings_screen.dart';
import 'package:gieokhaejwo/theme/app_theme.dart';
import 'package:gieokhaejwo/widgets/load_state_view.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _base = 'http://10.0.2.2:8000';

/// 서버 응답처럼 만든 경보 (원본 필드 + status, found_at …)
Map<String, dynamic> _serverItem(int id, String status, {String? foundAt}) {
  final json = File('assets/data/missing-alerts.json').readAsStringSync();
  final first =
      (jsonDecode(json)['list'] as List).first as Map<String, dynamic>;
  return {
    ...first
      ..remove('clothingTop')
      ..remove('clothingBottom')
      ..remove('demoFoundTime'),
    'msspsnIdntfccd': id,
    'status': status,
    'issued_at': '2026-10-06T00:00:00+09:00',
    'found_at': foundAt,
    'target_label': '치매환자',
    'photo_url': null,
    'source': '시연용 가상 데이터',
    'is_sample': true,
  };
}

final _serverList = [
  _serverItem(1, '수색중'),
  _serverItem(2, '경보종료'),
  _serverItem(3, '발견완료', foundAt: '2026-10-14T21:30:05+09:00'),
];

/// 가짜 서버: /alerts, /alerts/{id} (없는 번호는 404)
MockClient _mockServer({int listStatus = 200}) => MockClient((req) async {
  http.Response json(Object body, [int status = 200]) => http.Response.bytes(
    utf8.encode(jsonEncode(body)),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
  final path = req.url.path;
  if (path == '/alerts') {
    if (listStatus != 200) return json({'detail': '오류'}, listStatus);
    return json({
      'notice': null,
      'is_sample': true,
      'totalCount': _serverList.length,
      'list': _serverList,
    });
  }
  final id = int.tryParse(path.replaceFirst('/alerts/', ''));
  final item = _serverList.where((e) => e['msspsnIdntfccd'] == id).firstOrNull;
  return item == null ? json({'detail': '없음'}, 404) : json(item);
});

AlertRepository _server({int listStatus = 200}) =>
    AlertRepository.server(_base, client: _mockServer(listStatus: listStatus));

final _navKey = GlobalKey<NavigatorState>();

void main() {
  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(360, 800);
    view.devicePixelRatio = 1;
  });

  group('서버 응답 읽기', () {
    test('status 글자로 수색 중 / 경보 종료 / 발견 완료를 정해요', () async {
      final alerts = await _server().loadAll();
      expect(alerts.map((a) => a.status), [
        AlertStatus.searching,
        AlertStatus.ended,
        AlertStatus.found,
      ]);
      expect(alerts[0].nm, '김가상'); // 한글이 깨지지 않아요
      expect(alerts[2].foundTime, '21:30'); // found_at의 시각
      expect(alerts[1].topText, MissingAlert.noInfo); // AI 옷차림은 아직 없음
    });

    test('status가 없으면(앱 안 데이터) demoFoundTime으로 정해요', () {
      expect(MissingAlert.fromJson({}).status, AlertStatus.searching);
      expect(
        MissingAlert.fromJson({'demoFoundTime': '11:05'}).status,
        AlertStatus.found,
      );
    });

    test('서버가 200이 아니면 실패로 넘겨요', () {
      expect(
        _server(listStatus: 500).loadAll(),
        throwsA(isA<ServerException>()),
      );
    });

    test('경보 한 건: 있으면 최신 정보, 404면 null', () async {
      final repo = _server();
      expect((await repo.loadOne(2))!.isEnded, isTrue);
      expect(await repo.loadOne(999), isNull);
    });
  });

  group('서버 주소 설정', () {
    test('주소를 정리하고 형식을 확인해요', () {
      expect(
        ApiSettings.normalize(' 192.168.0.5:8000/ '),
        'http://192.168.0.5:8000',
      );
      expect(ApiSettings.normalize('https://a.kr'), 'https://a.kr');
      expect(ApiSettings.isValid('http://192.168.0.5:8000'), isTrue);
      expect(ApiSettings.isValid('http://'), isFalse);
      expect(ApiSettings.isValid(''), isFalse);
    });

    test('설정에 따라 서버 / 앱 안 가짜 데이터로 바뀌어요', () {
      ApiSettings.current = const ApiSettings(baseUrl: _base);
      expect(AlertRepository.instance.isServer, isTrue);
      ApiSettings.current = const ApiSettings(baseUrl: _base, useBuiltIn: true);
      expect(AlertRepository.instance.isServer, isFalse);
    });

    testWidgets('주소를 넣고 저장하면 휴대폰에 저장돼요', (tester) async {
      SharedPreferences.setMockInitialValues({});
      ApiSettings.current = const ApiSettings(baseUrl: _base);
      await tester.pumpWidget(
        MaterialApp(theme: buildAppTheme(), home: const ServerSettingsScreen()),
      );
      await tester.enterText(find.byType(TextField), '192.168.0.5:8000');
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();
      expect(ApiSettings.current.baseUrl, 'http://192.168.0.5:8000');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('api_base_url'), 'http://192.168.0.5:8000');
    });

    testWidgets('주소 형식이 틀리면 저장하지 않고 안내해요', (tester) async {
      SharedPreferences.setMockInitialValues({});
      ApiSettings.current = const ApiSettings(baseUrl: _base);
      await tester.pumpWidget(
        MaterialApp(theme: buildAppTheme(), home: const ServerSettingsScreen()),
      );
      await tester.enterText(find.byType(TextField), '');
      await tester.tap(find.text('저장'));
      await tester.pump();
      expect(find.textContaining('주소 형식이 맞지 않아요'), findsOneWidget);
      expect(ApiSettings.current.baseUrl, _base);
    });
  });

  group('화면', () {
    testWidgets('서버에 연결 못 하면 서버 안내와 다시 시도가 보여요', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: AlertListScreen(repository: _server(listStatus: 500)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(LoadErrorView.serverMessage), findsOneWidget);
      expect(find.text('다시 시도'), findsOneWidget);
    });

    testWidgets('목록: 경보 종료는 수색 중 건수에서 빠지고 회색 라벨', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: AlertListScreen(repository: _server()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1'), findsWidgets); // 수색 중 1건
      expect(find.text('경보 종료'), findsOneWidget);
      expect(find.text('발견 완료 (21:30)'), findsOneWidget);
    });

    testWidgets('경보 종료 상세: 회색 라벨과 종료 안내', (tester) async {
      final ended = (await _server().loadOne(2))!;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: AlertDetailScreen(alert: ended),
        ),
      );
      expect(find.text('경보 종료'), findsOneWidget);
      expect(find.text('경보가 종료됐어요'), findsOneWidget);
      expect(find.text('목격 제보'), findsOneWidget);
    });
  });

  group('푸시 알림을 누르면 서버에서 최신 정보를 받아요', () {
    Future<void> tap(WidgetTester tester, String alertId) async {
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: _navKey,
          theme: buildAppTheme(),
          home: const Scaffold(body: Text('시작 화면')),
        ),
      );
      await tester.runAsync(
        () => openFromPush(
          _navKey.currentState!,
          PushPayload.fromData({'type': 'missing_alert', 'alert_id': alertId}),
          repository: _server(),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('경보 종료가 된 경보는 종료 안내가 있는 상세', (tester) async {
      await tap(tester, '2');
      expect(find.byType(AlertDetailScreen), findsOneWidget);
      expect(find.text('경보가 종료됐어요'), findsOneWidget);
    });

    testWidgets('발견 완료가 된 경보는 07', (tester) async {
      await tap(tester, '3');
      expect(find.byType(FoundDetailScreen), findsOneWidget);
    });

    testWidgets('서버에 없는 경보(404)는 04 목록', (tester) async {
      await tap(tester, '999');
      expect(find.byType(AlertListScreen), findsOneWidget);
    });
  });
}
