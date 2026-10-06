import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_routes.dart';
import '../models/missing_alert.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../widgets/app_button.dart';
import '../widgets/section_card.dart';

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
      appBar: AppBar(title: const Text('목격 제보')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        children: [
          Text(
            '${a.ageSex} · ${a.outfitSummary}',
            style: appText(12, color: AppColors.gray600),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: '언제 보셨나요?',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final w in _whenOptions)
                  _Option(
                    label: w,
                    on: _when == w,
                    onTap: () => setState(() => _when = w),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: '어디서 보셨나요?',
            child: TextField(
              controller: _place,
              style: appText(14),
              decoration: InputDecoration(
                hintText: '예: ○○공원 정문 앞',
                hintStyle: appText(14, color: AppColors.gray400),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                enabledBorder: _border(AppColors.gray200),
                focusedBorder: _border(AppColors.purple),
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
                : Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final f in _features)
                        _Option(
                          label: f,
                          on: _picked.contains(f),
                          onTap: () => setState(
                            () => _picked.contains(f)
                                ? _picked.remove(f)
                                : _picked.add(f),
                          ),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            color: AppColors.purpleSoft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '정리된 제보 내용',
                  style: appText(
                    13,
                    weight: FontWeight.w700,
                    color: AppColors.purple,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _summary,
                  style: appText(14, weight: FontWeight.w500, height: 1.55),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '앱이 자동으로 신고하지 않아요.\n위험해 보이면 112로 바로 연락하세요.',
            textAlign: TextAlign.center,
            style: appText(11, color: AppColors.gray600, height: 1.5),
          ),
        ],
      ),
      bottomNavigationBar: BottomActionBar(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppButton(
              label: '182 전화하기',
              large: true,
              onPressed: () => AppRoutes.call182(context),
            ),
            const SizedBox(height: 8),
            AppButton(
              label: '제보 내용 복사',
              primary: false,
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                await Clipboard.setData(ClipboardData(text: _summary));
                messenger.showSnackBar(
                  const SnackBar(content: Text('제보 내용을 복사했어요.')),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  OutlineInputBorder _border(Color c) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(10),
    borderSide: BorderSide(color: c),
  );
}

/// 고를 수 있는 네모 버튼 (선택되면 보라 테두리)
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
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: on ? AppColors.purpleSoft : AppColors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: on ? AppColors.purple : AppColors.gray200,
            width: on ? 2 : 1,
          ),
        ),
        child: Center(
          widthFactor: 1,
          child: Text(
            label,
            style: appText(
              14,
              weight: on ? FontWeight.w700 : FontWeight.w400,
              color: on ? AppColors.purpleDeep : AppColors.gray900,
            ),
          ),
        ),
      ),
    );
  }
}
