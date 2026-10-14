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
/// 아래로 당기면 서버에서 다시 읽어요 (AI 옷차림 분석이 끝났는지 볼 때).
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

  Future<void> _reload() async {
    final repository = widget.repository ?? AlertRepository.instance;
    MissingAlert? fresh;
    try {
      fresh = await repository.loadOne(alert.id);
    } catch (_) {
      fresh = null;
    }
    if (!mounted) return;
    if (fresh == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('다시 불러오지 못했어요. 잠시 후 다시 시도해 주세요.')),
      );
      return;
    }
    setState(() => alert = fresh!);
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
                          _OutfitTiles(alert: alert, onRefresh: _reload),
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
        : [
            ('상의', alert.topText),
            (alert.hasAi ? '하의' : '하의·신발', alert.bottomText),
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
}

/// 인상착의의 옷차림 칸.
/// 서버 ai가 있으면 상의·하의·신발·소지품을 따로 보여 줘요.
/// 옷차림이 하나도 없으면 "분석 중" 같은 한 줄 안내, 분석 중이면 새로고침 버튼도 같이.
/// ai가 없으면(앱 안 가짜 데이터) 지금처럼 상의, 하의·신발 2칸이에요.
class _OutfitTiles extends StatelessWidget {
  const _OutfitTiles({required this.alert, required this.onRefresh});

  final MissingAlert alert;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    if (!alert.hasAi) {
      return _pair(('상의', alert.topText), ('하의·신발', alert.bottomText));
    }
    if (!alert.hasOutfit) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InfoTile(label: '옷차림', value: alert.outfitNote),
          if (alert.aiPending) ...[
            const SizedBox(height: 8),
            AppButton(
              label: '새로고침',
              primary: false,
              onPressed: () => onRefresh(),
            ),
          ],
        ],
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
