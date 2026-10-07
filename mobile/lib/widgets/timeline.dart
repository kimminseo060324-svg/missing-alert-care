import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';

class TimelineEntry {
  const TimelineEntry(this.time, this.text, {this.done = false});

  final String time;
  final String text;
  final bool done; // 발견 완료 줄은 초록 글씨
}

/// "진행 기록" 목록. 줄 사이에 얇은 선.
class Timeline extends StatelessWidget {
  const Timeline({super.key, required this.entries});

  final List<TimelineEntry> entries;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final (i, e) in entries.indexed)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              border: i == entries.length - 1
                  ? null
                  : const Border(bottom: BorderSide(color: AppColors.line)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 52,
                  child: Text(
                    e.time,
                    style: appText(
                      14,
                      weight: FontWeight.w700,
                      color: e.done ? AppColors.green : AppColors.ink,
                    ).copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    e.text,
                    style: appText(
                      14,
                      color: e.done ? AppColors.green : AppColors.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
