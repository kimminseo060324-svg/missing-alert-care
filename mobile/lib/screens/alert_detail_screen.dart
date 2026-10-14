import 'package:flutter/material.dart';

import '../app_routes.dart';
import '../data/alert_repository.dart';
import '../models/missing_alert.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../widgets/app_button.dart';
import '../widgets/hero_header.dart';
import '../widgets/outfit_figure.dart';
import '../widgets/section_card.dart';
import '../widgets/status_chip.dart';
import '../widgets/swatch_tile.dart';
import '../widgets/timeline.dart';

/// 05 실종 정보 상세 (수색 중)
/// 서버 모드면 열 때 상세(/alerts/{id})를 바로 다시 읽어요.
/// 목록에서 받은 경보에는 옷차림 칸(ai.clothing)이 없고, 상태도 바뀌었을 수 있어서요.
/// 아래로 당겨도 다시 읽어요 (AI 옷차림 분석이 끝났는지 볼 때).
class AlertDetailScreen extends StatefulWidget {
  const AlertDetailScreen({super.key, required this.alert, this.repository});

  final MissingAlert alert;

  /// 다시 읽을 곳. 없으면 지금 설정(서버 / 앱 안 가짜 데이터)을 써요.
  final AlertRepository? repository;

  @override
  State<AlertDetailScreen> createState() => _AlertDetailScreenState();
}

class _AlertDetailScreenState extends State<AlertDetailScreen> {
  late MissingAlert alert = widget.alert;
  late final AlertRepository _repo =
      widget.repository ?? AlertRepository.instance;

  /// 상세를 읽는 중이에요.
  bool _loading = false;

  /// 마지막으로 읽기에 실패했어요.
  bool _failed = false;

  /// 요청 번호. 여러 번 당겨도 마지막 요청의 응답만 화면에 넣어요.
  int _request = 0;

  @override
  void initState() {
    super.initState();
    // 앱 안 가짜 데이터는 목록에 다 들어 있어서 다시 읽지 않아요.
    if (_repo.isServer) {
      _loading = true;
      _fetch();
    }
  }

  Future<void> _reload() {
    setState(() {
      _loading = true;
      _failed = false;
    });
    return _fetch();
  }

  Future<void> _fetch() async {
    final request = ++_request;
    MissingAlert? fresh;
    try {
      fresh = await _repo.loadOne(alert.id);
    } catch (_) {
      fresh = null;
    }
    if (!mounted || request != _request) return; // 더 새 요청이 있어요
    if (fresh == null) {
      setState(() {
        _loading = false;
        _failed = true;
      });
      // 옷차림 칸이 이미 있으면 화면은 그대로 두고 안내만 해요.
      if (alert.hasClothingDetail) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('다시 불러오지 못했어요. 잠시 후 다시 시도해 주세요.')),
        );
      }
      return;
    }
    setState(() {
      alert = fresh!;
      _loading = false;
      _failed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          ScreenHeader(
            title: '실종경보 상세',
            child: HeroInfo(
              chip: StatusChip.of(alert, onColor: true),
              title: '${alert.maskedName} 씨',
              sub: '${alert.sexLong} · ${alert.age}세',
              meta: '${alert.region}  ·  ${alert.occrDateText} 발령',
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _reload,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (alert.isEnded) ...[
                      const _EndedNotice(),
                      const SizedBox(height: 12),
                    ],
                    // 이것만 기억하세요: 핵심 3가지를 색 칸으로
                    SectionCard(
                      title: '이것만 기억하세요',
                      child: _RememberTiles(alert: alert),
                    ),
                    const SizedBox(height: 12),

                    // 인상착의: 옷차림 그림 + 2칸 정보
                    SectionCard(
                      title: '인상착의',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          OutfitPanel(alert: alert),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: InfoTile(
                                  label: '키',
                                  value: alert.heightText,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: InfoTile(
                                  label: '체형',
                                  value: alert.bodyText,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          _OutfitTiles(
                            alert: alert,
                            loading: _loading,
                            failed: _failed,
                            onRefresh: _reload,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            '그림은 AI가 문자 내용으로 그린 옷차림이에요. 얼굴은 그리지 않아요.',
                            style: appText(
                              11,
                              color: AppColors.gray400,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // 마지막 목격 + 진행 기록 (지도는 나중에)
                    SectionCard(
                      title: '마지막 목격',
                      trailing: Text(
                        alert.occrDateText,
                        style: appText(
                          13,
                          weight: FontWeight.w500,
                          color: AppColors.gray600,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            height: 160,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: AppColors.bg,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '지도 연동 예정',
                              style: appText(12, color: AppColors.gray400),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            alert.occrAdres,
                            style: appText(15, weight: FontWeight.w700),
                          ),
                          const SizedBox(height: 22),
                          const SectionTitle('진행 기록'),
                          Timeline(
                            entries: [
                              TimelineEntry(alert.occrDateShort, '실종경보 발령'),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    const SourceText(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomActionBar(
        child: Row(
          children: [
            Expanded(
              child: AppButton(
                label: '182 전화',
                primary: false,
                large: true,
                onPressed: () => AppRoutes.call182(context),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: AppButton(
                label: '목격 제보',
                large: true,
                onPressed: () => AppRoutes.report(context, alert),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "이것만 기억하세요" 3칸.
/// 서버 요약(ai.summary)이 있으면 요약을 넣고, 3개보다 적으면 남은 칸에 키를 넣어요.
/// 요약이 없으면 상의·하의·키를 보여 줘요.
class _RememberTiles extends StatelessWidget {
  const _RememberTiles({required this.alert});

  final MissingAlert alert;

  @override
  Widget build(BuildContext context) {
    final summary = alert.aiSummary.take(3).toList();
    final tiles = summary.isNotEmpty
        ? [
            for (final s in summary) (s, s),
            if (summary.length < 3) ('키', alert.heightText),
          ]
        : alert.hasAi
        ? [
            ('상의', _short(alert.clothingTop)),
            ('하의', _short(alert.clothingBottom)),
            ('키', alert.heightText),
          ]
        : [
            ('상의', alert.topText),
            ('하의·신발', alert.bottomText),
            ('키', alert.heightText),
          ];
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, (label, text)) in tiles.indexed) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: SwatchTile(label: label, text: text),
            ),
          ],
        ],
      ),
    );
  }

  /// 좁은 칸이라 긴 안내 대신 "분석 중" / "제공 불가" / "정보 없음"
  String _short(String text) => text.isNotEmpty ? text : alert.outfitShortNote;
}

/// 인상착의의 옷차림 칸.
/// 서버 ai가 있으면 상의·하의·신발·소지품을 따로 보여 줘요.
/// 옷차림이 하나도 없으면 "분석 중" 같은 한 줄 안내, 분석 중이면 새로고침 버튼도 같이.
/// 목록에서 받은 경보(옷차림 칸 없음)는 상세를 읽는 동안 "불러오는 중",
/// 실패하면 "다시 시도" 버튼을 보여 줘요.
/// ai가 없으면(앱 안 가짜 데이터) 지금처럼 상의, 하의·신발 2칸이에요.
class _OutfitTiles extends StatelessWidget {
  const _OutfitTiles({
    required this.alert,
    required this.loading,
    required this.failed,
    required this.onRefresh,
  });

  static const loadingText = '불러오는 중';
  static const failedText = '옷차림을 불러오지 못했어요';

  final MissingAlert alert;
  final bool loading;
  final bool failed;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    if (!alert.hasAi) {
      return _pair(('상의', alert.topText), ('하의·신발', alert.bottomText));
    }
    if (!alert.hasClothingDetail) {
      // 목록에서 받은 경보: 상세를 읽기 전에는 옷차림을 알 수 없어요.
      return _note(
        failed ? failedText : loadingText,
        button: loading ? null : '다시 시도',
        loading: loading,
      );
    }
    if (!alert.hasOutfit) {
      return _note(
        alert.outfitNote,
        button: alert.aiPending ? '새로고침' : null,
        loading: loading && alert.aiPending,
      );
    }
    return Column(
      children: [
        _pair(('상의', alert.topText), ('하의', alert.bottomText)),
        const SizedBox(height: 8),
        _pair(('신발', alert.shoesText), ('소지품', alert.accessoriesText)),
      ],
    );
  }

  Widget _note(String text, {String? button, bool loading = false}) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      InfoTile(label: '옷차림', value: text),
      if (loading) ...[
        const SizedBox(height: 8),
        const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ] else if (button != null) ...[
        const SizedBox(height: 8),
        AppButton(label: button, primary: false, onPressed: () => onRefresh()),
      ],
    ],
  );

  static Widget _pair((String, String) left, (String, String) right) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: InfoTile(label: left.$1, value: left.$2),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: InfoTile(label: right.$1, value: right.$2),
      ),
    ],
  );
}

/// 경보 종료 안내. 경찰청 목록에서 내려간 경보예요 (발견 여부는 알 수 없어요).
class _EndedNotice extends StatelessWidget {
  const _EndedNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.generalGray,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: appText(15, weight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            '경찰청 실종경보 목록에서 내려간 경보예요. 그래도 이 분을 본 적이 있으면 182로 알려 주세요.',
            style: appText(13, color: AppColors.gray600, height: 1.5),
          ),
        ],
      ),
    );
  }

  static const title = '경보가 종료됐어요';
}
