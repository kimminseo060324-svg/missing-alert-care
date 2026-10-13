import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/missing_alert.dart';

/// 지금은 앱 안의 가짜 데이터(assets/data/missing-alerts.json)만 읽어요.
/// 앱은 외부 API를 직접 부르지 않고, 나중에 우리 서버 하나만 부를 거예요.
class AlertRepository {
  AlertRepository._(this._loadRaw);
  static final instance = AlertRepository._(_loadAsset);

  /// 시연·확인용: 실행할 때 늦게 읽거나 실패하게 만들 수 있어요.
  ///   fvm flutter run --dart-define=DEMO_LOAD_DELAY=4   (4초 늦게 읽기 → 로딩 화면)
  ///   fvm flutter run --dart-define=DEMO_LOAD_FAIL=true  (처음 한 번 실패 → 다시 시도 화면)
  static const _demoDelay = int.fromEnvironment('DEMO_LOAD_DELAY');
  static const _demoFail = bool.fromEnvironment('DEMO_LOAD_FAIL');
  static var _demoFailed = false;

  static Future<String> _loadAsset() async {
    if (_demoDelay > 0) await Future.delayed(Duration(seconds: _demoDelay));
    if (_demoFail && !_demoFailed) {
      _demoFailed = true;
      throw Exception('시연용 실패');
    }
    return rootBundle.loadString('assets/data/missing-alerts.json');
  }

  /// 테스트용: 원하는 JSON 문자열(빈 목록, 깨진 JSON 등)로 바꿔 끼워요.
  factory AlertRepository.fromRaw(Future<String> Function() loadRaw) =>
      AlertRepository._(loadRaw);

  final Future<String> Function() _loadRaw;
  List<MissingAlert>? _cache;

  /// 이 시간 안에 못 읽으면 실패로 보고 "다시 시도" 화면을 보여 줘요.
  static const timeout = Duration(seconds: 10);

  /// 읽기에 실패하면 에러를 그대로 넘겨요. 실패한 결과는 저장하지 않아서
  /// "다시 시도"를 누르면 처음부터 다시 읽어요.
  Future<List<MissingAlert>> loadAll() async {
    if (_cache != null) return _cache!;
    final raw = await _loadRaw().timeout(timeout);
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final list = (json['list'] as List? ?? [])
        .map((e) => MissingAlert.fromJson(e as Map<String, dynamic>))
        .toList();
    _cache = list;
    return list;
  }
}
