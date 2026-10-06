import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';

class TimelineEntry {
  const TimelineEntry(this.time, this.text, {this.done = false});

  final String time;
  final String text;
  final bool done; // 발견 완료 줄은 초록 점
}

/// "경보 진행 기록" 목록.
class Timeline extends StatelessWidget {
  const Timeline({super.key, required this.entries});

  final List<TimelineEntry> entries;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final (i, e) in entries.indexed) ...[
          if (i > 0) const SizedBox(height: 10),
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: e.done ? AppColors.green : AppColors.purple,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 48,
                child: Text(
                  e.time,
                  style: appText(13, color: AppColors.gray600).copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              Expanded(child: Text(e.text, style: appText(13))),
            ],
          ),
        ],
      ],
    );
  }
}
