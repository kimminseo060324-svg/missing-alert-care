import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gieokhaejwo/data/alert_repository.dart';
import 'package:gieokhaejwo/models/missing_alert.dart';
import 'package:gieokhaejwo/screens/alert_detail_screen.dart';
import 'package:gieokhaejwo/screens/alert_list_screen.dart';
import 'package:gieokhaejwo/screens/demo_menu_screen.dart';
import 'package:gieokhaejwo/screens/lock_screen.dart';
import 'package:gieokhaejwo/screens/report_screen.dart';
import 'package:gieokhaejwo/theme/app_theme.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 서버 응답의 원본 필드 (경찰청 모양)
Map<String, dynamic> _raw(int id) => {
  'msspsnIdntfccd': id,
  'nm': '김가상',
  'age': 82,
  'sexdstnDscd': '남자',
  'occrAdres': '경기 오산시 양산동',
  'occrde': '20261006',
  'height': 168,
  'frmDscd': '마름',
  'alldressingDscd': '회색 점퍼, 검정 바지',
  'status': '수색중',
};

/// 상세(/alerts/{sid})의 ai. 수빈 님이 보낸 예시 그대로예요.
const _detailAi = {
  'status': 'done',
  'clothing': {
    'upper': ['회색 점퍼'],
    'lower': ['검정 바지'],
    'shoes': [],
    'accessories': ['지팡이'],
  },
  'summary': ['회색 점퍼', '검정 바지', '지팡이 사용'],
  'extracted_at': '2026-10-15T02:41:25+09:00',
};

/// 목록(/alerts)의 ai는 status와 summary만 와요.
const _listAi = {
  'status': 'done',
  'summary': ['회색 점퍼', '검정 바지', '지팡이 사용'],
};

Map<String, dynamic> _empty(String status) => {
  'status': status,
  'clothing': {'upper': [], 'lower': [], 'shoes': [], 'accessories': []},
  'summary': [],
  'extracted_at': null,
};

MissingAlert _alert(Map<String, dynamic> ai) =>
    MissingAlert.fromJson({..._raw(9990001), 'ai': ai});

/// 가짜 서버: 목록은 목록용 ai, 상세는 [detailAi] 차례대로 (마지막 것을 계속)
/// 상세 응답이 null이면 서버 오류(500)를 줘요.
/// Completer를 넣으면 그 응답은 complete할 때까지 기다려요 (늦게 오는 응답).
AlertRepository _server(Object listAi, List<Object?> detailAi) {
  var calls = 0;
  return AlertRepository.server(
    'http://10.0.2.2:8000',
    client: MockClient((req) async {
      if (req.url.path == '/alerts') {
        return _json({
          'list': [
            {..._raw(9990001), 'ai': listAi},
          ],
        });
      }
      var ai = detailAi[calls.clamp(0, detailAi.length - 1)];
      calls++;
      if (ai is Completer<Object?>) ai = await ai.future;
      if (ai == null) return http.Response('error', 500);
      return _json({..._raw(9990001), 'ai': ai});
    }),
  );
}

http.Response _json(Object body) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Widget _app(Widget home) => MaterialApp(theme: buildAppTheme(), home: home);

void main() {
  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(360, 800);
    view.devicePixelRatio = 1;
  });

  group('서버 ai 읽기', () {
    test('상세 done: 상의·하의·신발·소지품을 따로 읽어요', () {
      final a = _alert(_detailAi);
      expect(a.aiStatus, AiStatus.done);
      expect(a.topText, '회색 점퍼');
      expect(a.bottomText, '검정 바지');
      expect(a.shoesText, MissingAlert.noInfo); // 신발만 비었어요
      expect(a.accessoriesText, '지팡이');
      expect(a.aiSummary, ['회색 점퍼', '검정 바지', '지팡이 사용']);
      expect(a.outfitSummary, '회색 점퍼 · 검정 바지 · 지팡이 사용');
    });

    test('여러 개면 쉼표로, 신발은 하의와 섞지 않아요', () {
      final a = _alert({
        ..._detailAi,
        'clothing': {
          'upper': ['검은색 패딩', '흰 티셔츠'],
          'lower': ['청바지'],
          'shoes': ['흰색 운동화'],
          'accessories': [],
        },
      });
      expect(a.clothingTop, '검은색 패딩, 흰 티셔츠');
      expect(a.clothingBottom, '청바지');
      expect(a.shoes, '흰색 운동화');
      expect(a.accessories, '');
    });

    test('목록: 옷 그림 색은 요약 문장에서 (상의·하의·신발 구분)', () {
      final f = _alert({
        'status': 'done',
        'summary': ['흰색 운동화', '회색 점퍼', '검정 바지', '지팡이 사용'],
      }).figureText;
      expect(f.top, '회색 점퍼');
      expect(f.bottom, '검정 바지');
      expect(f.shoes, '흰색 운동화');
    });

    test('상세: 옷 그림 색은 ai.clothing에서, 요약이 없으면 빈 그림', () {
      final f = _alert(_detailAi).figureText;
      expect(f.top, '회색 점퍼');
      expect(f.bottom, '검정 바지');
      final none = _alert(_empty('pending')).figureText;
      expect(none.top, '');
      expect(none.bottom, '');
    });

    test('목록: status와 summary만 와도 한 줄 요약이 나와요', () {
      expect(_alert(_listAi).outfitSummary, '회색 점퍼 · 검정 바지 · 지팡이 사용');
    });

    test('pending이면 "분석 중"', () {
      final a = _alert(_empty('pending'));
      expect(a.aiPending, isTrue);
      expect(a.topText, '분석 중');
      expect(a.shoesText, '분석 중');
      expect(a.outfitNote, '분석 중');
      expect(a.outfitSummary, '옷차림 분석 중');
    });

    test('done인데 결과가 비면 "옷차림 정보 없음"', () {
      final a = _alert(_empty('done'));
      expect(a.hasOutfit, isFalse);
      expect(a.outfitNote, '옷차림 정보 없음');
      expect(a.outfitSummary, '옷차림 정보 없음');
    });

    test('unavailable(또는 모르는 status)이면 "AI 정보를 제공할 수 없음"', () {
      for (final status in ['unavailable', 'error']) {
        final a = _alert(_empty(status));
        expect(a.aiStatus, AiStatus.unavailable);
        expect(a.topText, 'AI 정보를 제공할 수 없음');
        expect(a.outfitNote, 'AI 정보를 제공할 수 없음');
        expect(a.outfitSummary, 'AI 정보를 제공할 수 없음');
      }
    });

    test('ai가 없거나 null이면 기존 필드를 그대로 써요', () {
      final own = {
        ..._raw(1),
        'clothingTop': '녹색 체크무늬 셔츠',
        'clothingBottom': '베이지색 바지, 검정 구두',
      };
      for (final a in [
        MissingAlert.fromJson(own),
        MissingAlert.fromJson({...own, 'ai': null}),
      ]) {
        expect(a.aiStatus, AiStatus.none);
        expect(a.hasAi, isFalse);
        expect(a.topText, '녹색 체크무늬 셔츠');
        expect(a.bottomText, '베이지색 바지, 검정 구두');
        expect(a.outfitSummary, '녹색 체크무늬 셔츠 · 베이지색 바지, 검정 구두');
      }
      final bare = MissingAlert.fromJson({..._raw(1), 'ai': null});
      expect(bare.topText, MissingAlert.noInfo);
      expect(bare.outfitSummary, '옷차림 정보 없음');
    });
  });

  group('04 목록', () {
    Future<void> open(WidgetTester tester, Object listAi) async {
      await tester.pumpWidget(
        _app(AlertListScreen(repository: _server(listAi, [_detailAi]))),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('done: AI 요약 한 줄', (tester) async {
      await open(tester, _listAi);
      expect(find.text('회색 점퍼 · 검정 바지 · 지팡이 사용'), findsOneWidget);
    });

    testWidgets('pending: "옷차림 분석 중"', (tester) async {
      await open(tester, {'status': 'pending', 'summary': []});
      expect(find.text('옷차림 분석 중'), findsOneWidget);
    });

    testWidgets('unavailable: "AI 정보를 제공할 수 없음"', (tester) async {
      await open(tester, {'status': 'unavailable', 'summary': []});
      expect(find.text('AI 정보를 제공할 수 없음'), findsOneWidget);
    });
  });

  group('05 상세 (서버 모드: 열 때 상세를 다시 읽어요)', () {
    /// 목록에서 받은 경보(ai.clothing 없음)로 상세를 열어요. 실제 앱의 04 → 05 흐름이에요.
    /// [wait]가 false면 응답을 기다리지 않아요 (불러오는 중 화면을 볼 때).
    Future<void> open(
      WidgetTester tester,
      List<Object?> detailAi, {
      bool wait = true,
    }) async {
      await tester.pumpWidget(
        _app(
          AlertDetailScreen(
            alert: _alert(_listAi),
            repository: _server(_listAi, detailAi),
          ),
        ),
      );
      // 로딩 표시가 계속 돌아서 pumpAndSettle 대신 한 번만 그려요.
      wait ? await settle(tester) : await tester.pump();
    }

    testWidgets('목록 → 상세: 옷차림 네 칸이 나와요 (회귀)', (tester) async {
      await tester.pumpWidget(
        _app(AlertListScreen(repository: _server(_listAi, [_detailAi]))),
      );
      await settle(tester);
      await tester.tap(find.text('회색 점퍼 · 검정 바지 · 지팡이 사용'));
      await settle(tester);
      expect(find.byType(AlertDetailScreen), findsOneWidget);
      for (final label in ['상의', '하의', '신발', '소지품']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('지팡이'), findsOneWidget);
      expect(find.text('옷차림 정보 없음'), findsNothing);
    });

    testWidgets('done: 이것만 기억하세요에 요약, 인상착의에 네 칸', (tester) async {
      await open(tester, [_detailAi]);
      expect(find.text('지팡이 사용'), findsOneWidget); // 요약 칸
      expect(find.text('지팡이'), findsOneWidget);
      expect(find.text('하의·신발'), findsNothing);
      expect(find.text('새로고침'), findsNothing);
    });

    testWidgets('요약이 3개보다 적으면 남은 칸에 키', (tester) async {
      await open(tester, [
        {
          ..._detailAi,
          'summary': ['회색 점퍼'],
        },
      ]);
      expect(find.text('168cm'), findsNWidgets(2)); // 요약 칸 + 인상착의 키
    });

    testWidgets('불러오는 중 → 응답이 오면 네 칸', (tester) async {
      final slow = Completer<Object?>();
      await open(tester, [slow], wait: false);
      expect(find.text('불러오는 중'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('옷차림 정보 없음'), findsNothing);
      slow.complete(_detailAi);
      await settle(tester);
      expect(find.text('불러오는 중'), findsNothing);
      expect(find.text('지팡이'), findsOneWidget);
    });

    testWidgets('실패 → "다시 시도"로 다시 읽어요', (tester) async {
      await open(tester, [null, _detailAi]);
      expect(find.text('옷차림을 불러오지 못했어요'), findsOneWidget);
      expect(find.text('옷차림 정보 없음'), findsNothing);
      await tap(tester, '다시 시도');
      expect(find.text('옷차림을 불러오지 못했어요'), findsNothing);
      expect(find.text('지팡이'), findsOneWidget);
    });

    testWidgets('done인데 결과가 비면 "옷차림 정보 없음"', (tester) async {
      await open(tester, [_empty('done')]);
      expect(find.text('옷차림 정보 없음'), findsOneWidget);
      expect(find.text('정보 없음'), findsNWidgets(2)); // 기억 칸 상의·하의
      expect(find.text('신발'), findsNothing);
      expect(find.text('새로고침'), findsNothing);
    });

    testWidgets('unavailable: 기억 칸은 "제공 불가", 옷차림 칸은 긴 문장', (tester) async {
      await open(tester, [_empty('unavailable')]);
      expect(find.text('제공 불가'), findsNWidgets(2));
      expect(find.text('AI 정보를 제공할 수 없음'), findsOneWidget);
      expect(find.text('새로고침'), findsNothing);
    });

    testWidgets('pending: "분석 중" → 새로고침 버튼으로 결과 보기', (tester) async {
      await open(tester, [_empty('pending'), _detailAi]);
      expect(find.text('분석 중'), findsWidgets);
      await tap(tester, '새로고침');
      expect(find.text('분석 중'), findsNothing);
      expect(find.text('지팡이'), findsOneWidget);
    });

    testWidgets('pending: 아래로 당겨도 다시 읽어요', (tester) async {
      await open(tester, [_empty('pending'), _detailAi]);
      await pullDown(tester);
      await settle(tester);
      expect(find.text('지팡이'), findsOneWidget);
    });

    testWidgets('이미 옷차림이 있을 때 다시 읽기에 실패하면 안내만, 화면은 그대로', (tester) async {
      await open(tester, [_detailAi, null]);
      await pullDown(tester);
      await settle(tester);
      expect(find.text('다시 불러오지 못했어요. 잠시 후 다시 시도해 주세요.'), findsOneWidget);
      expect(find.text('지팡이'), findsOneWidget);
    });

    testWidgets('늦게 온 이전 응답은 최신 화면을 덮지 않아요', (tester) async {
      final first = Completer<Object?>(); // 열 때 보낸 요청
      final second = Completer<Object?>(); // 당겨서 보낸 요청
      await open(tester, [first, second], wait: false);
      await pullDown(tester);
      second.complete(_detailAi);
      await settle(tester);
      expect(find.text('지팡이'), findsOneWidget);
      first.complete(_empty('pending')); // 이전 요청이 나중에 도착
      await settle(tester);
      expect(find.text('지팡이'), findsOneWidget);
      expect(find.text('분석 중'), findsNothing);
    });

    testWidgets('앱 안 가짜 데이터 모드는 다시 읽지 않고 기존 화면', (tester) async {
      var reads = 0;
      final builtIn = AlertRepository.fromRaw(() async {
        reads++;
        return '{"list": []}';
      });
      final a = MissingAlert.fromJson({
        ..._raw(1),
        'clothingTop': '녹색 체크무늬 셔츠',
        'clothingBottom': '베이지색 바지',
      });
      await tester.pumpWidget(
        _app(AlertDetailScreen(alert: a, repository: builtIn)),
      );
      await settle(tester);
      expect(reads, 0);
      expect(find.text('하의·신발'), findsOneWidget); // 인상착의 라벨
      expect(find.text('신발'), findsNothing);
      expect(find.text('소지품'), findsNothing);
      expect(find.text('녹색 체크무늬 셔츠'), findsNWidgets(2));
      expect(find.text('불러오는 중'), findsNothing);
    });
  });

  group('잠금화면·목격 제보 (목록에는 옷차림 칸이 없어요)', () {
    testWidgets('시연 메뉴 02: 상세를 읽어서 펼친 카드에 상의·하의', (tester) async {
      await tester.pumpWidget(
        _app(DemoMenuScreen(repository: _server(_listAi, [_detailAi]))),
      );
      await settle(tester);
      await tester.tap(find.text('잠금화면 · 펼친 알림'));
      await settle(tester);
      expect(find.byType(LockScreen), findsOneWidget);
      expect(find.text('회색 점퍼'), findsWidgets);
      expect(find.text('검정 바지'), findsWidgets);
    });

    testWidgets('시연 메뉴 02: 상세를 못 읽어도 목록 정보로 열려요', (tester) async {
      await tester.pumpWidget(
        _app(DemoMenuScreen(repository: _server(_listAi, [null]))),
      );
      await settle(tester);
      await tester.tap(find.text('잠금화면 · 펼친 알림'));
      await settle(tester);
      expect(find.byType(LockScreen), findsOneWidget);
    });

    testWidgets('시연 메뉴 06: 상세를 읽어서 일치하는 특징에 상의·하의', (tester) async {
      await tester.pumpWidget(
        _app(DemoMenuScreen(repository: _server(_listAi, [_detailAi]))),
      );
      await settle(tester);
      await tester.tap(find.text('목격 제보'));
      await settle(tester);
      expect(find.byType(ReportScreen), findsOneWidget);
      expect(find.text('회색 점퍼'), findsOneWidget);
      expect(find.text('검정 바지'), findsOneWidget);
    });

    testWidgets('목격 제보: 옷차림 칸이 없으면 AI 요약을 특징으로', (tester) async {
      await tester.pumpWidget(_app(ReportScreen(alert: _alert(_listAi))));
      await tester.pumpAndSettle();
      expect(find.text('지팡이 사용'), findsOneWidget);
      expect(find.text('옷차림 ${MissingAlert.noInfo}'), findsNothing);
    });
  });
}

/// 가짜 서버 응답(진짜 비동기)을 기다린 뒤 화면을 다 그려요.
Future<void> settle(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.tap(find.text(text));
  await settle(tester);
}

/// 상세 화면을 아래로 당겨요 (RefreshIndicator).
Future<void> pullDown(WidgetTester tester) async {
  await tester.fling(
    find.byType(SingleChildScrollView),
    const Offset(0, 400),
    1000,
  );
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}
