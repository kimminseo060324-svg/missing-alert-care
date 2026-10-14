/// 경보 상태. 서버 응답의 status 글자(수색중 / 경보종료 / 발견완료)와 같아요.
enum AlertStatus { searching, ended, found }

/// 서버 응답 ai.status. none은 ai가 없는 데이터(앱 안 가짜 데이터)예요.
enum AiStatus { none, pending, done, unavailable }

/// 실종경보 한 건.
///
/// 필드 이름은 경찰청 안전Dream API(amberList.do) 응답과 같아요.
/// clothingTop / clothingBottom / shoes / accessories 는 경찰청 API에 없어요.
/// 서버 응답에서는 행안부 재난문자 본문에서 AI로 뽑은 `ai` 필드에서 읽고,
/// 앱 안 가짜 데이터에서는 같은 이름의 필드에서 읽어요.
/// (앱 안 가짜 데이터의 clothingBottom에는 신발까지 들어 있어요.)
class MissingAlert {
  const MissingAlert({
    required this.id,
    required this.occrde,
    required this.nm,
    required this.age,
    required this.ageNow,
    required this.sexdstnDscd,
    required this.writngTrgetDscd,
    required this.occrAdres,
    required this.height,
    required this.bdwgh,
    required this.frmDscd,
    required this.alldressingDscd,
    required this.clothingTop,
    required this.clothingBottom,
    required this.foundTime,
    this.status = AlertStatus.searching,
    this.shoes = '',
    this.accessories = '',
    this.aiStatus = AiStatus.none,
    this.aiSummary = const [],
  });

  factory MissingAlert.fromJson(Map<String, dynamic> json) {
    final demoFoundTime = _str(json['demoFoundTime']);
    final ai = json['ai'] is Map ? json['ai'] as Map : null;
    final aiStatus = ai == null ? AiStatus.none : _aiStatus(_str(ai['status']));
    final clothing = aiStatus == AiStatus.done && ai!['clothing'] is Map
        ? ai['clothing'] as Map
        : const {};
    String fromAi(List<String> slots) =>
        slots.expand((s) => _list(clothing[s])).join(', ');
    String pick(String own, String ai) => own.isNotEmpty ? own : ai;
    return MissingAlert(
      id: _int(json['msspsnIdntfccd']),
      occrde: _str(json['occrde']),
      nm: _str(json['nm']),
      age: _int(json['age']),
      ageNow: _str(json['ageNow']),
      sexdstnDscd: _str(json['sexdstnDscd']),
      writngTrgetDscd: _str(json['writngTrgetDscd']),
      occrAdres: _str(json['occrAdres']),
      height: _int(json['height']),
      bdwgh: _int(json['bdwgh']),
      frmDscd: _str(json['frmDscd']),
      alldressingDscd: _str(json['alldressingDscd']),
      clothingTop: pick(_str(json['clothingTop']), fromAi(['upper'])),
      clothingBottom: pick(_str(json['clothingBottom']), fromAi(['lower'])),
      shoes: pick(_str(json['shoes']), fromAi(['shoes'])),
      accessories: pick(_str(json['accessories']), fromAi(['accessories'])),
      aiStatus: aiStatus,
      aiSummary: aiStatus == AiStatus.done ? _list(ai!['summary']) : const [],
      foundTime: demoFoundTime.isNotEmpty
          ? demoFoundTime
          : _clock(_str(json['found_at'])),
      status: _status(_str(json['status']), demoFoundTime),
    );
  }

  /// 서버가 준 status 글자를 읽어요. 없으면(앱 안 가짜 데이터) demoFoundTime으로 정해요.
  static AlertStatus _status(String status, String demoFoundTime) =>
      switch (status) {
        '수색중' => AlertStatus.searching,
        '경보종료' => AlertStatus.ended,
        '발견완료' => AlertStatus.found,
        _ =>
          demoFoundTime.isNotEmpty ? AlertStatus.found : AlertStatus.searching,
      };

  static AiStatus _aiStatus(String status) => switch (status) {
    'done' => AiStatus.done,
    'pending' => AiStatus.pending,
    _ => AiStatus.unavailable,
  };

  /// "2026-10-14T21:30:05+09:00" → "21:30" (서버가 보낸 한국 시각 그대로)
  static String _clock(String iso) {
    final t = iso.indexOf('T');
    if (t < 0 || iso.length < t + 6) return '';
    return iso.substring(t + 1, t + 6);
  }

  final int id; // msspsnIdntfccd
  final String occrde; // 발생일 yyyyMMdd
  final String nm;
  final int age; // 실종 당시 나이
  final String ageNow;
  final String sexdstnDscd; // 남자 / 여자
  final String writngTrgetDscd; // 010 아동, 060~062 지적장애, 070 치매 ...
  final String occrAdres;
  final int height;
  final int bdwgh;
  final String frmDscd; // 체형
  final String alldressingDscd; // 경찰청 착의 (짧고 비어 있을 때가 많음)
  final String clothingTop; // 상의 (행안부 재난문자)
  final String clothingBottom; // 하의 (앱 안 가짜 데이터는 하의·신발)
  final String shoes; // 신발 (서버 ai.clothing.shoes)
  final String accessories; // 소지품 (지팡이, 배낭 …)
  final AiStatus aiStatus;
  final List<String> aiSummary; // 서버가 정리한 옷차림 문장 (최대 3개)
  final String foundTime; // 발견 시각 "14:35" (모르면 빈 글자)
  final AlertStatus status;

  static const noInfo = '정보 없음';
  static const aiAnalyzing = '분석 중';
  static const noOutfit = '옷차림 정보 없음';
  static const aiUnavailable = 'AI 정보를 제공할 수 없음';

  /// 서버가 옷차림을 아직 뽑는 중이에요. 새로고침하면 채워져요.
  bool get aiPending => aiStatus == AiStatus.pending;

  /// 서버 응답에 ai가 있어요 (상의·하의·신발·소지품을 따로 보여 줘요).
  bool get hasAi => aiStatus != AiStatus.none;

  /// 옷차림 글자가 하나라도 있어요.
  bool get hasOutfit => [
    clothingTop,
    clothingBottom,
    shoes,
    accessories,
  ].any((s) => s.isNotEmpty);

  /// 옷차림이 하나도 없을 때 대신 보여 줄 말
  String get outfitNote => switch (aiStatus) {
    AiStatus.pending => aiAnalyzing,
    AiStatus.unavailable => aiUnavailable,
    _ => noOutfit,
  };

  bool get isSearching => status == AlertStatus.searching;
  bool get isEnded => status == AlertStatus.ended;
  bool get isFound => status == AlertStatus.found;

  /// 김가상 → 김○○
  String get maskedName => nm.isEmpty ? '○○○' : '${nm.substring(0, 1)}○○';

  String get sexShort => sexdstnDscd.startsWith('여') ? '여' : '남';
  String get sexLong => sexdstnDscd.startsWith('여') ? '여성' : '남성';

  /// "82세 남성"
  String get ageSex => '$age세 $sexLong';

  /// 주소에서 시·구 이름만: "서울특별시 가상구 테스트동" → "가상구"
  String get region {
    final parts = occrAdres.split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) return parts[1];
    return parts.isEmpty ? '지역 정보 없음' : parts.first;
  }

  String get topText => _orMissing(clothingTop);
  String get bottomText => _orMissing(clothingBottom);
  String get shoesText => _orMissing(shoes);
  String get accessoriesText => _orMissing(accessories);

  /// 칸 하나가 비었을 때: 분석 중·제공 불가면 그 말을, 아니면 "정보 없음"
  String _orMissing(String text) {
    if (text.isNotEmpty) return text;
    return switch (aiStatus) {
      AiStatus.pending => aiAnalyzing,
      AiStatus.unavailable => aiUnavailable,
      _ => noInfo,
    };
  }

  String get heightText => height > 0 ? '${height}cm' : noInfo;
  String get bodyText =>
      frmDscd.isEmpty || frmDscd == '기타' ? noInfo : '$frmDscd 체형';

  /// 목록·알림에 쓰는 짧은 옷차림 요약
  /// 서버의 ai.summary가 있으면 그대로, 없으면 상의·하의로 만들어요.
  String get outfitSummary {
    if (aiSummary.isNotEmpty) return aiSummary.join(' · ');
    final items = [clothingTop, clothingBottom].where((s) => s.isNotEmpty);
    if (items.isNotEmpty) return items.join(' · ');
    return aiPending ? '옷차림 $aiAnalyzing' : outfitNote;
  }

  /// "10월 6일"
  String get occrDateText {
    if (occrde.length != 8) return occrde;
    final m = int.tryParse(occrde.substring(4, 6)) ?? 0;
    final d = int.tryParse(occrde.substring(6, 8)) ?? 0;
    return '$m월 $d일';
  }

  /// "10/6" (진행 기록처럼 좁은 칸에 써요)
  String get occrDateShort {
    if (occrde.length != 8) return occrde;
    final m = int.tryParse(occrde.substring(4, 6)) ?? 0;
    final d = int.tryParse(occrde.substring(6, 8)) ?? 0;
    return '$m/$d';
  }

  static String _str(Object? v) => v == null ? '' : v.toString().trim();
  static List<String> _list(Object? v) =>
      v is List ? v.map(_str).where((s) => s.isNotEmpty).toList() : const [];
  static int _int(Object? v) =>
      v is int ? v : int.tryParse(v?.toString() ?? '') ?? 0;
}
