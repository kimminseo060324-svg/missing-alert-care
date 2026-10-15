import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gieokhaejwo/data/alert_repository.dart';
import 'package:gieokhaejwo/data/api_settings.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:gieokhaejwo/push/foreground_notice.dart';
import 'package:gieokhaejwo/push/notice_figure.dart';
import 'package:gieokhaejwo/push/push_open.dart';
import 'package:gieokhaejwo/push/push_service.dart';
import 'package:gieokhaejwo/screens/alert_detail_screen.dart';
import 'package:gieokhaejwo/screens/found_detail_screen.dart';
import 'package:gieokhaejwo/screens/report_screen.dart';
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

/// 서버가 data만 보내는 푸시 (version 2). 알림 문구도 data에 들어 있어요.
Map<String, dynamic> _dataOnly({String? body}) => {
  ..._data('issued', '수색중'),
  'version': '2',
  'title': '실종경보',
  'body': body ?? '오산시에서 82세 남성을 찾고 있어요',
  'ai_summary': '회색 점퍼 · 검정 바지 · 흰 운동화',
  'age': '82',
  'sex': '남자',
  'height': '170',
  'address': '경기 오산시 양산동',
};

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

  group('펼친 알림 (여러 줄 · 버튼 · 옷 그림)', () {
    test('서버가 여러 줄로 보내면 첫 줄은 접힌 알림, 전부는 펼친 알림', () {
      final n = ForegroundNotice.from(
        _data('issued', '수색중'),
        title: '실종경보',
        body: '오산시에서 82세 남성을 찾고 있어요\n옷차림: 회색 점퍼\n장소: 경기 오산시 양산동',
      )!;
      expect(n.body, '오산시에서 82세 남성을 찾고 있어요');
      expect(n.bigText, '오산시에서 82세 남성을 찾고 있어요\n옷차림: 회색 점퍼\n장소: 경기 오산시 양산동');
    });

    test('서버 version 2 실제 발송 모양 (data-only)', () {
      const body =
          '오산시에서 82세 남성을 찾고 있어요\n'
          '옷차림: 회색 점퍼 · 검정 바지 · 지팡이 사용\n'
          '인상: 82세 남성 · 168cm\n'
          '장소: 경기 오산시 양산동';
      final n = ForegroundNotice.from({
        ..._data('issued', '수색중'),
        'version': '2',
        'title': '실종경보',
        'body': body,
        'ai_summary': '회색 점퍼 · 검정 바지 · 지팡이 사용',
        'height': '168',
        'address': '경기 오산시 양산동',
        'age': '82',
        'sex': '남자',
      })!;
      expect(n.title, '실종경보');
      expect(n.body, '오산시에서 82세 남성을 찾고 있어요');
      expect(n.bigText, body);
      final d = PushService.details(n);
      expect(d.actions, hasLength(2));
      expect(d.largeIcon, isNotNull);
      final f = NoticeFigure.fromSummary(n.summary);
      expect(f.top, const Color(0xFF8E8C96));
      expect(f.bottom, const Color(0xFF2B2B30));
    });

    test('서버가 한 줄만 보내면 data로 옷차림·인상·장소 줄을 만들어요', () {
      final n = ForegroundNotice.from(_dataOnly())!;
      expect(n.title, '실종경보');
      expect(n.lines, [
        '오산시에서 82세 남성을 찾고 있어요',
        '옷차림: 회색 점퍼 · 검정 바지 · 흰 운동화',
        '인상: 82세 남성 · 170cm',
        '장소: 경기 오산시 양산동',
      ]);
    });

    test('data에 없는 값은 줄을 빼요 (version 1 푸시는 예전처럼 한 줄)', () {
      final n = ForegroundNotice.from({
        ..._data('issued', '수색중'),
        'height': '165.5',
        'ai_summary': '',
      })!;
      expect(n.lines, ['오산시에서 실종자를 찾고 있어요', '인상: 166cm']);
      final old = ForegroundNotice.from(_data('issued', '수색중'))!;
      expect(old.lines, ['오산시에서 실종자를 찾고 있어요']);
    });

    test('찾는 중이면 버튼 두 개와 옷 그림, 펼치면 여러 줄', () {
      final d = PushService.details(ForegroundNotice.from(_dataOnly())!);
      expect(d.tag, 'alert_9990001');
      expect(d.actions!.map((a) => a.title), ['상세 보기', '목격 제보']);
      expect(d.actions!.every((a) => a.showsUserInterface), isTrue);
      final style = d.styleInformation! as BigTextStyleInformation;
      expect(style.bigText.split('\n'), hasLength(4));
      expect(d.largeIcon, isA<ByteArrayAndroidBitmap>());
    });

    test('종료·발견 알림은 버튼·옷 그림·추가 줄이 없어요', () {
      for (final status in ['경보종료', '발견완료']) {
        final n = ForegroundNotice.from({
          ..._dataOnly(),
          'event': 'closed',
          'status': status,
          'title': '',
          'body': '',
        })!;
        expect(n.active, isFalse);
        expect(n.lines, hasLength(1));
        final d = PushService.details(n);
        expect(d.actions, isNull);
        expect(d.largeIcon, isNull);
      }
    });

    test('옷차림 색을 모르면 그림을 붙이지 않아요', () {
      final n = ForegroundNotice.from({
        ..._dataOnly(),
        'ai_summary': '지팡이 사용',
      })!;
      expect(PushService.details(n).largeIcon, isNull);
      expect(PushService.details(n).actions, hasLength(2));
    });

    test('요약 문장으로 상의·하의·신발 색을 골라요', () {
      final f = NoticeFigure.fromSummary(['지팡이 사용', '흰 운동화', '검정 바지', '회색 점퍼']);
      expect(f.top, const Color(0xFF8E8C96));
      expect(f.bottom, const Color(0xFF2B2B30));
      expect(f.shoe, const Color(0xFFFFFFFF));
    });

    test('옷 그림은 Android가 읽는 BMP 파일 모양', () {
      final bmp = NoticeFigure.fromSummary(['회색 점퍼', '검정 바지']).toBmp();
      expect(String.fromCharCodes(bmp.sublist(0, 2)), 'BM');
      expect(bmp.length, 54 + 128 * 128 * 3);
      final header = ByteData.sublistView(bmp);
      expect(header.getUint32(2, Endian.little), bmp.length);
      expect(header.getInt32(18, Endian.little), 128);
      // 가운데 몸통(위에서 40% 높이)은 상의 회색이에요. BMP는 아래 줄부터 써요.
      final row = 127 - (128 * 0.4).round();
      final i = 54 + row * 128 * 3 + 64 * 3;
      expect(bmp.sublist(i, i + 3), [0x96, 0x8C, 0x8E]);
      // 구석은 바탕색
      expect(bmp.sublist(54, 57), [0xF9, 0xF7, 0xF1]);
    });
  });

  group('"목격 제보" 버튼을 누르면', () {
    Future<void> tapReport(WidgetTester tester, String serverStatus) async {
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: _navKey,
          theme: buildAppTheme(),
          home: const Scaffold(body: Text('시작 화면')),
        ),
      );
      final n = ForegroundNotice.from(_dataOnly())!;
      await tester.runAsync(
        () => openFromPush(
          _navKey.currentState!,
          ForegroundNotice.decode(n.payload)!,
          repository: _serverWith(serverStatus),
          report: true,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('06 목격 제보, 뒤로 가면 05 상세', (tester) async {
      await tapReport(tester, '수색중');
      expect(find.byType(ReportScreen), findsOneWidget);
      _navKey.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(AlertDetailScreen), findsOneWidget);
    });

    testWidgets('그사이 발견 완료가 됐으면 목격 제보 없이 07', (tester) async {
      await tapReport(tester, '발견완료');
      expect(find.byType(ReportScreen), findsNothing);
      expect(find.byType(FoundDetailScreen), findsOneWidget);
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
