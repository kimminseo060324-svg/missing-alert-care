import 'dart:convert';

import 'push_payload.dart';

/// 앱이 직접 띄울 알림 내용.
///
/// - 서버가 알림 문구(notification)를 같이 보낸 푸시: 앱이 백그라운드이거나 꺼져 있으면
///   Android가 띄우고, 앱을 보고 있을 때만 앱이 이 내용으로 띄워요.
/// - 서버가 data만 보낸 푸시: 언제나 앱이 이 내용으로 띄워요. (버튼·옷 그림)
/// 그래서 같은 푸시가 두 번 뜨지 않아요.
class ForegroundNotice {
  const ForegroundNotice({
    required this.tag,
    required this.title,
    required this.lines,
    required this.summary,
    required this.active,
    required this.payload,
  });

  /// Android 알림 번호. 서버(FCM)가 tag를 달아 띄운 알림은 번호가 0이라
  /// 앱도 0을 써야 같은 경보의 알림을 바꿔치기할 수 있어요.
  static const androidId = 0;

  /// 알림 버튼 id. 누르면 돌려받아서 열 화면을 정해요.
  static const detailAction = 'detail';
  static const reportAction = 'report';

  /// 같은 경보의 알림끼리 같은 이름표를 달아요. 서버와 맞춘 규칙이에요.
  /// 종료·발견 알림이 오면 앞의 "찾고 있어요" 알림을 바꿔치기해요.
  static String tagFor(int alertId) => 'alert_$alertId';

  /// 실종경보 푸시가 아니거나 alert_id가 없으면 null (띄우지 않아요).
  /// [title], [body]는 푸시의 알림 문구예요. 없으면 data의 title·body,
  /// 그것도 없으면 상태에 맞는 문구를 만들어요.
  static ForegroundNotice? from(
    Map<String, dynamic> data, {
    String? title,
    String? body,
  }) {
    final payload = PushPayload.fromData(data);
    final id = payload.alertId;
    if (!payload.isMissingAlert || id == null) return null;
    String text(String key) => data[key]?.toString().trim() ?? '';
    final active = !_isClosed(payload);
    final fallback = _fallbackText(payload);
    final summary = text(
      'ai_summary',
    ).split('·').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

    final fullBody = _orElse(body, _orElse(text('body'), fallback.$2));
    var lines = fullBody
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    // 서버가 한 줄만 보냈으면 data로 옷차림·인상·장소 줄을 만들어요.
    if (lines.length == 1 && active) {
      lines = [lines.first, ..._detailLines(data, summary)];
    }

    return ForegroundNotice(
      tag: tagFor(id),
      title: _orElse(title, _orElse(text('title'), fallback.$1)),
      lines: lines,
      summary: active ? summary : const [],
      active: active,
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

  /// 알림 글 줄들. 첫 줄은 접힌 알림에, 전부는 펼친 알림에 보여요.
  final List<String> lines;

  /// 서버 AI 옷차림 요약 (옷 그림 색). 종료·발견이면 비어 있어요.
  final List<String> summary;

  /// 아직 찾는 중인 경보. 이때만 "상세 보기"·"목격 제보" 버튼과 옷 그림을 붙여요.
  final bool active;

  /// 알림을 눌렀을 때 돌려받을 푸시 data (JSON 글자)
  final String payload;

  /// 접힌 알림 한 줄
  String get body => lines.first;

  /// 펼친 알림 전체 글
  String get bigText => lines.join('\n');

  static String _orElse(String? text, String fallback) =>
      (text == null || text.trim().isEmpty) ? fallback : text.trim();

  static bool _isClosed(PushPayload p) =>
      p.event == 'closed' || p.status == '경보종료' || p.status == '발견완료';

  /// "옷차림: …", "인상: 82세 남성 · 170cm", "장소: …". 값이 없는 줄은 빼요.
  static List<String> _detailLines(
    Map<String, dynamic> data,
    List<String> summary,
  ) {
    String text(String key) => data[key]?.toString().trim() ?? '';
    final age = int.tryParse(text('age'));
    final sex = switch (text('sex')) {
      '남자' || '남' => '남성',
      '여자' || '여' => '여성',
      final s => s,
    };
    final height = double.tryParse(text('height'));
    final looks = [
      [if (age != null && age > 0) '$age세', if (sex.isNotEmpty) sex].join(' '),
      if (height != null && height > 0) '${height.round()}cm',
    ].where((s) => s.isNotEmpty).join(' · ');
    final place = _orElse(text('address'), text('place'));
    return [
      if (summary.isNotEmpty) '옷차림: ${summary.join(' · ')}',
      if (looks.isNotEmpty) '인상: $looks',
      if (place.isNotEmpty) '장소: $place',
    ];
  }

  /// 서버가 알림 문구를 안 보냈을 때 쓰는 문구. 서버 문구와 같은 말투예요.
  static (String, String) _fallbackText(PushPayload p) {
    final region = p.region.isEmpty ? '우리 동네' : p.region;
    if (_isClosed(p)) {
      if (p.status == '발견완료') return ('실종자 발견', '$region 실종자를 찾았어요');
      return ('실종경보 종료', '$region 실종경보가 종료됐어요');
    }
    return ('실종경보', '$region에서 실종자를 찾고 있어요');
  }
}
