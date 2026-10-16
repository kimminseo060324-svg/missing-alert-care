import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 경보를 어디서 읽을지: 우리 서버 주소, 또는 앱 안 가짜 데이터.
/// 시연 메뉴의 "서버 주소" 화면에서 바꾸고, 휴대폰에 저장해요.
@immutable
class ApiSettings {
  const ApiSettings({required this.baseUrl, this.useBuiltIn = false});

  /// 기본 주소. 에뮬레이터에서 10.0.2.2는 이 컴퓨터(맥)를 뜻해요.
  /// 빌드할 때 바꾸려면: fvm flutter run --dart-define=API_BASE_URL=http://192.168.0.5:8000
  static const defaultBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  static const _keyUrl = 'api_base_url';
  static const _keyBuiltIn = 'api_use_built_in';

  /// 지금 쓰는 설정. 앱이 시작할 때 [load]로 저장된 값을 읽어요.
  static var current = const ApiSettings(baseUrl: defaultBaseUrl);

  /// 서버 주소 (끝에 / 없음). 예: http://10.0.2.2:8000
  final String baseUrl;

  /// true면 서버 대신 앱 안 가짜 데이터(assets/data)를 읽어요. 서버 없이 시연할 때 써요.
  final bool useBuiltIn;

  /// "192.168.0.5:8000/" → "http://192.168.0.5:8000"
  static String normalize(String input) {
    var url = input.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    if (url.isEmpty) return '';
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'http://$url';
    }
    return url;
  }

  /// 주소 형식이 맞는지 (http://호스트[:포트])
  static bool isValid(String url) {
    final uri = Uri.tryParse(url);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      current = ApiSettings(
        baseUrl: prefs.getString(_keyUrl) ?? defaultBaseUrl,
        useBuiltIn: prefs.getBool(_keyBuiltIn) ?? kIsWeb, // 웹은 기본으로 앱 안 가짜 데이터
      );
    } catch (e) {
      debugPrint('서버 설정을 읽지 못했어요: $e');
    }
  }

  static Future<void> save(ApiSettings settings) async {
    current = settings;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUrl, settings.baseUrl);
    await prefs.setBool(_keyBuiltIn, settings.useBuiltIn);
  }

  @override
  bool operator ==(Object other) =>
      other is ApiSettings &&
      other.baseUrl == baseUrl &&
      other.useBuiltIn == useBuiltIn;

  @override
  int get hashCode => Object.hash(baseUrl, useBuiltIn);
}
