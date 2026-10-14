import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gieokhaejwo/data/alert_repository.dart';
import 'package:gieokhaejwo/models/missing_alert.dart';
import 'package:gieokhaejwo/screens/alert_detail_screen.dart';
import 'package:gieokhaejwo/screens/alert_list_screen.dart';
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
      final ai = detailAi[calls.clamp(0, detailAi.length - 1)];
      calls++;
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

  group('05 상세', () {
    Future<void> open(WidgetTester tester, List<Object?> detailAi) async {
      final repository = _server(_listAi, detailAi);
      final a = (await tester.runAsync(() => repository.loadOne(9990001)))!;
      await tester.pumpWidget(
        _app(AlertDetailScreen(alert: a, repository: repository)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    testWidgets('done: 이것만 기억하세요에 요약, 인상착의에 상의·하의·신발·소지품', (tester) async {
      await open(tester, [_detailAi]);
      expect(find.text('지팡이 사용'), findsOneWidget); // 요약 칸
      for (final label in ['상의', '하의', '신발', '소지품']) {
        expect(find.text(label), findsOneWidget);
      }
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

    testWidgets('done인데 결과가 비면 "옷차림 정보 없음"', (tester) async {
      await open(tester, [_empty('done')]);
      expect(find.text('옷차림 정보 없음'), findsOneWidget);
      expect(find.text('신발'), findsNothing);
      expect(find.text('새로고침'), findsNothing);
    });

    testWidgets('unavailable: "AI 정보를 제공할 수 없음"', (tester) async {
      await open(tester, [_empty('unavailable')]);
      expect(find.text('AI 정보를 제공할 수 없음'), findsWidgets);
      expect(find.text('새로고침'), findsNothing);
    });

    testWidgets('pending: "분석 중" → 새로고침 버튼으로 결과 보기', (tester) async {
      await open(tester, [_empty('pending'), _detailAi]);
      expect(find.text('분석 중'), findsWidgets);
      await tester.ensureVisible(find.text('새로고침'));
      await tester.runAsync(() async {
        await tester.tap(find.text('새로고침'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(find.text('분석 중'), findsNothing);
      expect(find.text('지팡이'), findsOneWidget);
    });

    testWidgets('pending: 아래로 당겨도 다시 읽어요', (tester) async {
      await open(tester, [_empty('pending'), _detailAi]);
      await tester.fling(
        find.byType(SingleChildScrollView),
        const Offset(0, 400),
        1000,
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1)); // 당김 표시가 돌기 시작
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(find.text('지팡이'), findsOneWidget);
    });

    testWidgets('다시 읽기에 실패하면 안내만 하고 화면은 그대로', (tester) async {
      await open(tester, [_empty('pending'), null]);
      await tester.ensureVisible(find.text('새로고침'));
      await tester.runAsync(() async {
        await tester.tap(find.text('새로고침'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(find.text('다시 불러오지 못했어요. 잠시 후 다시 시도해 주세요.'), findsOneWidget);
      expect(find.text('분석 중'), findsWidgets);
    });

    testWidgets('ai가 없으면 기존 화면 (상의, 하의·신발 2칸)', (tester) async {
      final a = MissingAlert.fromJson({
        ..._raw(1),
        'clothingTop': '녹색 체크무늬 셔츠',
        'clothingBottom': '베이지색 바지',
      });
      await tester.pumpWidget(_app(AlertDetailScreen(alert: a)));
      await tester.pumpAndSettle();
      expect(find.text('하의·신발'), findsOneWidget); // 인상착의 라벨
      expect(find.text('신발'), findsNothing);
      expect(find.text('소지품'), findsNothing);
      expect(find.text('녹색 체크무늬 셔츠'), findsNWidgets(2));
    });
  });
}
