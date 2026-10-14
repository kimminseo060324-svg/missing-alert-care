/// 서버가 보내는 푸시의 data 부분. 서버(백엔드)와 맞춘 모양이에요.
///
/// FCM data 값은 전부 문자열로 와요. 예:
/// {"type": "missing_alert", "event": "issued", "alert_id": "9990001",
///  "status": "수색중", "region": "오산시", "version": "1"}
class PushPayload {
  const PushPayload({
    required this.type,
    required this.event,
    required this.alertId,
    required this.status,
    required this.region,
  });

  /// 앱이 구독하는 토픽
  static const topic = 'missing_alerts_osan';

  /// 실종경보 푸시의 type 값
  static const missingAlertType = 'missing_alert';

  factory PushPayload.fromData(Map<String, dynamic> data) {
    String text(String key) => data[key]?.toString().trim() ?? '';
    return PushPayload(
      type: text('type'),
      event: text('event'),
      alertId: int.tryParse(text('alert_id')),
      status: text('status'),
      region: text('region'),
    );
  }

  final String type;
  final String event; // issued(새 경보) / closed(경보 종료)
  final int? alertId; // 경찰청 식별번호 msspsnIdntfccd. 숫자가 아니면 null
  final String status; // 수색중 / 경보종료 / 발견완료
  final String region;

  bool get isMissingAlert => type == missingAlertType;
}
