import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/missing_alert.dart';

/// 지금은 앱 안의 가짜 데이터(assets/data/missing-alerts.json)만 읽어요.
/// 앱은 외부 API를 직접 부르지 않고, 나중에 우리 서버 하나만 부를 거예요.
class AlertRepository {
  AlertRepository._();
  static final instance = AlertRepository._();

  List<MissingAlert>? _cache;

  Future<List<MissingAlert>> loadAll() async {
    if (_cache != null) return _cache!;
    final raw = await rootBundle.loadString('assets/data/missing-alerts.json');
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final list = (json['list'] as List? ?? [])
        .map((e) => MissingAlert.fromJson(e as Map<String, dynamic>))
        .toList();
    _cache = list;
    return list;
  }
}
