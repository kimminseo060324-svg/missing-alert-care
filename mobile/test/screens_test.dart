import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gieokhaejwo/data/alert_repository.dart';
import 'package:gieokhaejwo/main.dart';
import 'package:gieokhaejwo/models/missing_alert.dart';
import 'package:gieokhaejwo/screens/alert_detail_screen.dart';
import 'package:gieokhaejwo/screens/alert_list_screen.dart';
import 'package:gieokhaejwo/screens/found_detail_screen.dart';
import 'package:gieokhaejwo/screens/lock_screen.dart';
import 'package:gieokhaejwo/screens/report_screen.dart';
import 'package:gieokhaejwo/theme/app_theme.dart';

Widget _wrap(Widget screen) =>
    MaterialApp(theme: buildAppTheme(), home: screen);

void main() {
  late List<MissingAlert> alerts;
  late MissingAlert searching;
  late MissingAlert found;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    alerts = await AlertRepository.instance.loadAll();
    searching = alerts.firstWhere((a) => !a.isFound);
    found = alerts.firstWhere((a) => a.isFound);
  });

  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(360, 800);
    view.devicePixelRatio = 1;
  });

  test('가짜 데이터 6건을 읽고, 빈 옷차림은 "정보 없음"', () {
    expect(alerts.length, 6);
    final empty = alerts.firstWhere((a) => a.clothingTop.isEmpty);
    expect(empty.topText, '정보 없음');
    expect(searching.maskedName, '김○○');
  });

  testWidgets('시연 메뉴에 화면 7개가 보여요', (tester) async {
    await tester.pumpWidget(const GieokhaejwoApp());
    await tester.pumpAndSettle();
    expect(find.text('경보 목록'), findsOneWidget);
    expect(find.text('발견 완료 상세'), findsOneWidget);
  });

  testWidgets('01 접힌 알림을 누르면 02 펼친 알림이 돼요', (tester) async {
    await tester.pumpWidget(_wrap(LockScreen.folded(alert: searching)));
    expect(find.text('단수 예정 안내'), findsOneWidget);
    await tester.tap(find.text('82세 남성을 찾습니다'));
    await tester.pump();
    expect(find.text('상세보기'), findsOneWidget);
  });

  testWidgets('03 발견 완료 알림', (tester) async {
    await tester.pumpWidget(_wrap(LockScreen.found(alert: found)));
    expect(find.textContaining('안전하게 발견됐어요'), findsOneWidget);
  });

  testWidgets('04 목록 필터', (tester) async {
    await tester.pumpWidget(_wrap(const AlertListScreen()));
    await tester.pumpAndSettle();
    expect(find.text('수색 중 5건'), findsOneWidget);
    await tester.tap(find.text('발견 완료'));
    await tester.pump();
    expect(find.text('안전하게 발견됐어요'), findsOneWidget);
  });

  testWidgets('05 상세에 출처 문구가 있어요', (tester) async {
    await tester.pumpWidget(_wrap(AlertDetailScreen(alert: searching)));
    expect(find.text('자료 출처: 경찰청 · 행안부 재난문자'), findsOneWidget);
    expect(find.text('AI 생성 옷차림 그림 (얼굴 없음)'), findsOneWidget);
  });

  testWidgets('06 특징을 고르면 제보 문장에 들어가요', (tester) async {
    await tester.pumpWidget(_wrap(ReportScreen(alert: searching)));
    await tester.tap(find.text('회색 점퍼').last);
    await tester.pump();
    expect(find.textContaining('회색 점퍼 차림의 80대 남성'), findsOneWidget);
  });

  testWidgets('07 발견 완료 상세', (tester) async {
    await tester.pumpWidget(_wrap(FoundDetailScreen(alert: found)));
    expect(find.text('목록으로'), findsOneWidget);
  });
}
