import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../models/missing_alert.dart';
import 'api_settings.dart';

/// 경보 목록·상세를 읽어요.
/// 기본은 우리 서버(GET /alerts, GET /alerts/{id})를 읽고,
/// 시연 메뉴 "서버 주소"에서 앱 안 가짜 데이터(assets/data/missing-alerts.json)로 바꿀 수 있어요.
/// 앱은 경찰청·행안부 API를 직접 부르지 않아요.
class AlertRepository {
  AlertRepository._(
    this._loadRaw, {
    Future<MissingAlert?> Function(int id)? loadOne,
    this.isServer = false,
  }) : _loadOne = loadOne;

  /// 지금 설정(서버 주소 / 앱 안 가짜 데이터)에 맞는 저장소
  static AlertRepository get instance {
    final settings = ApiSettings.current;
    if (_instance == null || _instanceFor != settings) {
      _instance = settings.useBuiltIn
          ? _builtIn
          : AlertRepository.server(settings.baseUrl);
      _instanceFor = settings;
    }
    return _instance!;
  }

  static AlertRepository? _instance;
  static ApiSettings? _instanceFor;
  static final _builtIn = AlertRepository._(_loadAsset);

  /// 시연·확인용: 실행할 때 늦게 읽거나 실패하게 만들 수 있어요. (앱 안 가짜 데이터일 때)
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

  /// 우리 서버에서 읽어요. 목록 응답 모양은 앱 안 가짜 데이터와 같아요 ({"list": [...]}).
  factory AlertRepository.server(String baseUrl, {http.Client? client}) {
    final c = client ?? http.Client();
    Future<String> get(String path) async {
      final res = await c.get(Uri.parse('$baseUrl$path'));
      if (res.statusCode != 200) {
        throw ServerException(res.statusCode);
      }
      return utf8.decode(res.bodyBytes);
    }

    return AlertRepository._(
      () => get('/alerts'),
      loadOne: (id) async {
        try {
          final raw = await get('/alerts/$id').timeout(timeout);
          return MissingAlert.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        } on ServerException catch (e) {
          if (e.statusCode == 404) return null; // 없는 경보, 또는 발견 후 내려간 경보
          rethrow;
        }
      },
      isServer: true,
    );
  }

  /// 테스트용: 원하는 JSON 문자열(빈 목록, 깨진 JSON 등)로 바꿔 끼워요.
  factory AlertRepository.fromRaw(
    Future<String> Function() loadRaw, {
    bool isServer = false,
  }) => AlertRepository._(loadRaw, isServer: isServer);

  final Future<String> Function() _loadRaw;
  final Future<MissingAlert?> Function(int id)? _loadOne;

  /// 서버에서 읽는지 (실패 안내 문구가 달라져요)
  final bool isServer;

  List<MissingAlert>? _cache;

  /// 이 시간 안에 못 읽으면 실패로 보고 "다시 시도" 화면을 보여 줘요.
  static const timeout = Duration(seconds: 10);

  /// 읽기에 실패하면 에러를 그대로 넘겨요. 실패한 결과는 저장하지 않아서
  /// "다시 시도"를 누르면 처음부터 다시 읽어요.
  /// 서버에서 읽을 때는 화면을 열 때마다 새로 읽어요 (상태가 바뀔 수 있어서).
  Future<List<MissingAlert>> loadAll() async {
    if (_cache != null) return _cache!;
    final raw = await _loadRaw().timeout(timeout);
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final list = (json['list'] as List? ?? [])
        .map((e) => MissingAlert.fromJson(e as Map<String, dynamic>))
        .toList();
    if (!isServer) _cache = list;
    return list;
  }

  /// 경보 한 건 (푸시 알림을 눌렀을 때). 없으면 null.
  Future<MissingAlert?> loadOne(int id) async {
    final one = _loadOne;
    if (one != null) return one(id);
    final all = await loadAll();
    return all.where((a) => a.id == id).firstOrNull;
  }
}

/// 서버가 200이 아닌 응답을 줬어요.
class ServerException implements Exception {
  const ServerException(this.statusCode);

  final int statusCode;

  @override
  String toString() => '서버 응답 $statusCode';
}
