import 'dart:convert';

import 'push_payload.dart';

/// 앱을 보고 있을 때 온 푸시를 앱이 직접 띄울 알림 내용.
///
/// 앱이 백그라운드이거나 꺼져 있을 때는 Android가 알림을 띄우고,
/// 앱을 보고 있을 때는 Android가 띄우지 않아서 앱이 이 내용으로 띄워요.
/// 그래서 같은 푸시가 두 번 뜨지 않아요.
class ForegroundNotice {
  const ForegroundNotice({
    required this.tag,
    required this.title,
    required this.body,
    required this.payload,
  });

  /// Android 알림 번호. 서버(FCM)가 tag를 달아 띄운 알림은 번호가 0이라
  /// 앱도 0을 써야 같은 경보의 알림을 바꿔치기할 수 있어요.
  static const androidId = 0;

  /// 같은 경보의 알림끼리 같은 이름표를 달아요. 서버와 맞춘 규칙이에요.
  /// 종료·발견 알림이 오면 앞의 "찾고 있어요" 알림을 바꿔치기해요.
  static String tagFor(int alertId) => 'alert_$alertId';

  /// 실종경보 푸시가 아니거나 alert_id가 없으면 null (띄우지 않아요).
  /// [title], [body]는 푸시의 알림 문구예요. 비어 있으면 data로 만들어요.
  static ForegroundNotice? from(
    Map<String, dynamic> data, {
    String? title,
    String? body,
  }) {
    final payload = PushPayload.fromData(data);
    final id = payload.alertId;
    if (!payload.isMissingAlert || id == null) return null;
    final fallback = _fallbackText(payload);
    return ForegroundNotice(
      tag: tagFor(id),
      title: _orElse(title, fallback.$1),
      body: _orElse(body, fallback.$2),
      payload: jsonEncode(data),
    );
  }

  /// 알림을 눌렀을 때 돌려받은 payload를 푸시 data로 되돌려요.
  static PushPayload? decode(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      final data = jsonDecode(payload);
      if (data is Map<String, dynamic>) return PushPayload.fromData(data);
    } catch (_) {
      // 모양이 틀리면 무시해요.
    }
    return null;
  }

  final String tag;
  final String title;
  final String body;

  /// 알림을 눌렀을 때 돌려받을 푸시 data (JSON 글자)
  final String payload;

  static String _orElse(String? text, String fallback) =>
      (text == null || text.trim().isEmpty) ? fallback : text.trim();

  /// 서버가 알림 문구를 안 보냈을 때 쓰는 문구. 서버 문구와 같은 말투예요.
  static (String, String) _fallbackText(PushPayload p) {
    final region = p.region.isEmpty ? '우리 동네' : p.region;
    if (p.event == 'closed' || p.status == '경보종료' || p.status == '발견완료') {
      if (p.status == '발견완료') return ('실종자 발견', '$region 실종자를 찾았어요');
      return ('실종경보 종료', '$region 실종경보가 종료됐어요');
    }
    return ('실종경보', '$region에서 실종자를 찾고 있어요');
  }
}
