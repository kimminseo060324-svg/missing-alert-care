import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_routes.dart';
import '../models/missing_alert.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../widgets/app_button.dart';
import '../widgets/hero_header.dart';
import '../widgets/outfit_figure.dart';
import '../widgets/section_card.dart';
import '../widgets/status_chip.dart';
import '../widgets/swatch_tile.dart';

/// 06 목격 제보
/// 시간·장소·특징을 고르면 182에 전화해서 말할 문장을 만들어 줘요.
/// 앱이 자동으로 신고하지는 않아요.
class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key, required this.alert});

  final MissingAlert alert;

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  static const _whenOptions = ['방금', '30분 전', '1시간 전'];

  String _when = _whenOptions.first;
  final _place = TextEditingController();
  late final List<String> _features = [
    widget.alert.clothingTop,
    widget.alert.clothingBottom,
  ].where((s) => s.isNotEmpty).toList();
  final Set<String> _picked = {};

  @override
  void initState() {
    super.initState();
    _place.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _place.dispose();
    super.dispose();
  }

  String get _summary {
    final a = widget.alert;
    final place = _place.text.trim().isEmpty ? '○○' : _place.text.trim();
    final look = _picked.isEmpty ? '' : '${_picked.join(', ')} 차림의 ';
    final ageGroup = a.age >= 20 ? '${a.age ~/ 10 * 10}대 ' : '${a.age}세 ';
    return '"$_when $place에서 $look$ageGroup${a.sexLong}을 봤습니다. '
        '${a.region} 실종경보의 ${a.maskedName} 씨와 비슷합니다."';
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.alert;
    return Scaffold(
      body: Column(
        children: [
          ScreenHeader(
            title: '목격 제보',
            child: HeroInfo(
              chip: const StatusChip.searching(tone: ChipTone.onColor),
              title: '${a.maskedName} 씨',
              sub: '${a.sexLong} · ${a.age}세',
              meta: '본 내용을 고르면 전화로 말할 문장을 만들어 드려요',
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SectionCard(
                    title: '언제 보셨나요?',
                    child: Row(
                      children: [
                        for (final w in _whenOptions) ...[
                          if (w != _whenOptions.first) const SizedBox(width: 8),
                          Expanded(
                            child: _Option(
                              label: w,
                              on: _when == w,
                              onTap: () => setState(() => _when = w),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SectionCard(
                    title: '어디서 보셨나요?',
                    child: TextField(
                      controller: _place,
                      cursorColor: AppColors.navy,
                      style: appText(15, weight: FontWeight.w500),
                      decoration: InputDecoration(
                        hintText: '예: ○○공원 정문 앞',
                        hintStyle: appText(15, color: AppColors.gray400),
                        filled: true,
                        fillColor: AppColors.bg,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                        enabledBorder: _border(Colors.transparent),
                        focusedBorder: _border(AppColors.navy),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SectionCard(
                    title: '일치하는 특징',
                    trailing: Text(
                      '여러 개 선택',
                      style: appText(12, color: AppColors.gray400),
                    ),
                    child: _features.isEmpty
                        ? Text(
                            '옷차림 ${MissingAlert.noInfo}',
                            style: appText(13, color: AppColors.gray600),
                          )
                        : IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (final f in _features) ...[
                                  if (f != _features.first)
                                    const SizedBox(width: 8),
                                  Expanded(
                                    child: _FeatureTile(
                                      label: f == a.clothingTop ? '상의' : '하의',
                                      text: f,
                                      on: _picked.contains(f),
                                      onTap: () => setState(
                                        () => _picked.contains(f)
                                            ? _picked.remove(f)
                                            : _picked.add(f),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                  ),
                  const SizedBox(height: 12),
                  SectionCard(
                    color: AppColors.navySoft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '정리된 제보 내용',
                          style: appText(
                            13,
                            weight: FontWeight.w800,
                            color: AppColors.navy,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _summary,
                          style: appText(
                            15,
                            weight: FontWeight.w700,
                            height: 1.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '앱이 자동으로 신고하지 않아요.\n위험해 보이면 112로 바로 연락하세요.',
                    textAlign: TextAlign.center,
                    style: appText(12, color: AppColors.gray600, height: 1.5),
                  ),
                ],
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
                label: '내용 복사',
                primary: false,
                large: true,
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  await Clipboard.setData(ClipboardData(text: _summary));
                  messenger.showSnackBar(
                    const SnackBar(content: Text('제보 내용을 복사했어요.')),
                  );
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: AppButton(
                label: '182 전화하기',
                large: true,
                onPressed: () => AppRoutes.call182(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  OutlineInputBorder _border(Color c) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: c, width: 1.5),
      );
}

/// '언제' 고르는 칸 (선택되면 남색)
class _Option extends StatelessWidget {
  const _Option({required this.label, required this.on, required this.onTap});

  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? AppColors.navy : AppColors.bg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: appText(
            14,
            weight: on ? FontWeight.w700 : FontWeight.w500,
            color: on ? Colors.white : AppColors.ink,
          ),
        ),
      ),
    );
  }
}

/// 옷차림 특징 칸: "이것만 기억하세요"와 같은 모양, 고르면 남색 테두리 + 체크.
class _FeatureTile extends StatelessWidget {
  const _FeatureTile({
    required this.label,
    required this.text,
    required this.on,
    required this.onTap,
  });

  final String label;
  final String text;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(6, 16, 6, 14),
            decoration: BoxDecoration(
              color: on ? AppColors.white : AppColors.bg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: on ? AppColors.navy : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Column(
              children: [
                ColorSquare(
                  color: colorFromText(text),
                  size: 40,
                  fallback: label,
                ),
                const SizedBox(height: 10),
                Text(
                  text,
                  textAlign: TextAlign.center,
                  style: appText(15, weight: FontWeight.w800, height: 1.35),
                ),
              ],
            ),
          ),
          if (on)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                width: 20,
                height: 20,
                decoration: const BoxDecoration(
                  color: AppColors.navy,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check, size: 14, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}
