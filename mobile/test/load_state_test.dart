import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gieokhaejwo/data/alert_repository.dart';
import 'package:gieokhaejwo/screens/demo_menu_screen.dart';
import 'package:gieokhaejwo/screens/report_screen.dart';
import 'package:gieokhaejwo/theme/app_theme.dart';
import 'package:gieokhaejwo/widgets/load_state_view.dart';
import 'package:gieokhaejwo/widgets/loading_view.dart';
import 'package:gieokhaejwo/widgets/section_card.dart';

/// 시연용 가짜 데이터 원본 (assets/data/missing-alerts.json)
final _goodJson = File('assets/data/missing-alerts.json').readAsStringSync();

/// 모든 경보를 발견 완료로 바꾼 데이터
String _allFoundJson() {
  final json = jsonDecode(_goodJson) as Map<String, dynamic>;
  for (final e in json['list'] as List) {
    (e as Map<String, dynamic>)['demoFoundTime'] = '11:05';
  }
  return jsonEncode(json);
}

AlertRepository _repo(String raw) => AlertRepository.fromRaw(() async => raw);

Widget _menu(AlertRepository repo) => MaterialApp(
  theme: buildAppTheme(),
  home: DemoMenuScreen(repository: repo),
);

void main() {
  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(360, 800);
    view.devicePixelRatio = 1;
  });

  testWidgets('경보 0건: 시연 메뉴가 오류 없이 안내를 보여줘요', (tester) async {
    await tester.pumpWidget(_menu(_repo('{"list": []}')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('지금 표시할 경보가 없어요'), findsOneWidget);
    // 경보가 필요한 01~03, 05~07은 눌리지 않아요.
    expect(find.text('보여줄 경보가 없어요'), findsNWidgets(6));

    // 04 경보 목록은 열리고, 빈 안내가 보여요.
    await tester.tap(find.text('경보 목록'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('수색 중 0건'), findsOneWidget);
    expect(find.text('지금 표시할 경보가 없어요'), findsOneWidget);
  });

  testWidgets('모두 발견 완료: 오류 없이 03·04·07만 열려요', (tester) async {
    await tester.pumpWidget(_menu(_repo(_allFoundJson())));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('지금 수색 중인 경보가 없어요'), findsOneWidget);
    // 01, 02, 05, 06은 수색 중 경보가 있어야 해서 눌리지 않아요.
    expect(find.text('보여줄 경보가 없어요'), findsNWidgets(4));

    await tester.tap(find.text('발견 완료 상세'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('목록으로'), findsOneWidget);
  });

  testWidgets('JSON이 깨지면 안내와 다시 시도 버튼, 누르면 다시 읽어요', (tester) async {
    var calls = 0;
    final repo = AlertRepository.fromRaw(() async {
      calls++;
      return calls == 1 ? '{"list": [ 깨진 데이터' : _goodJson;
    });
    await tester.pumpWidget(_menu(repo));
    await tester.pumpAndSettle();
    expect(find.text(LoadErrorView.message), findsOneWidget);
    expect(find.byType(LoadingView), findsNothing);

    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text(LoadErrorView.message), findsNothing);
    expect(find.text('경보 목록'), findsOneWidget);
  });

  testWidgets('너무 오래 걸리면 로딩 후 실패 안내가 떠요', (tester) async {
    final repo = AlertRepository.fromRaw(() => Completer<String>().future);
    await tester.pumpWidget(_menu(repo));
    await tester.pump();
    expect(find.byType(LoadingView), findsOneWidget);

    await tester.pump(AlertRepository.timeout);
    await tester.pump();
    expect(find.byType(LoadingView), findsNothing);
    expect(find.text(LoadErrorView.message), findsOneWidget);
  });

  testWidgets('다시 시도를 누르면 로딩이 다시 보였다가 목록이 떠요', (tester) async {
    var calls = 0;
    final second = Completer<String>();
    final repo = AlertRepository.fromRaw(() {
      calls++;
      return calls == 1 ? Future.error('연결 실패') : second.future;
    });
    await tester.pumpWidget(_menu(repo));
    await tester.pumpAndSettle();
    expect(find.text(LoadErrorView.message), findsOneWidget);

    await tester.tap(find.text('다시 시도'));
    await tester.pump();
    expect(find.byType(LoadingView), findsOneWidget);
    expect(find.text(LoadErrorView.message), findsNothing);

    second.complete(_goodJson);
    await tester.pumpAndSettle();
    expect(find.byType(LoadingView), findsNothing);
    expect(find.text('경보 목록'), findsOneWidget);
  });

  testWidgets('06 목격 제보에도 시연용 가상 데이터 안내가 있어요', (tester) async {
    final alerts = await _repo(_goodJson).loadAll();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: ReportScreen(alert: alerts.firstWhere((a) => !a.isFound)),
      ),
    );
    await tester.scrollUntilVisible(
      find.byType(SourceText),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('시연용 가상 데이터예요'), findsOneWidget);
  });
}
