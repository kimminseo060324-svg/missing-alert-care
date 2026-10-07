/// 실종경보 한 건.
///
/// 필드 이름은 경찰청 안전Dream API(amberList.do) 응답과 같아요.
/// clothingTop / clothingBottom 은 경찰청 API에 없고, 나중에 서버가
/// 행안부 재난문자 본문에서 AI로 뽑아서 붙여 줄 값이에요.
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
  });

  factory MissingAlert.fromJson(Map<String, dynamic> json) {
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
      clothingTop: _str(json['clothingTop']),
      clothingBottom: _str(json['clothingBottom']),
      foundTime: _str(json['demoFoundTime']),
    );
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
  final String clothingBottom; // 하의·신발 (행안부 재난문자)
  final String foundTime; // 시연용: 값이 있으면 발견 완료

  static const noInfo = '정보 없음';

  bool get isFound => foundTime.isNotEmpty;

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

  String get topText => clothingTop.isEmpty ? noInfo : clothingTop;
  String get bottomText => clothingBottom.isEmpty ? noInfo : clothingBottom;
  String get heightText => height > 0 ? '${height}cm' : noInfo;
  String get bodyText =>
      frmDscd.isEmpty || frmDscd == '기타' ? noInfo : '$frmDscd 체형';

  /// 목록·알림에 쓰는 짧은 옷차림 요약
  String get outfitSummary {
    final items = [clothingTop, clothingBottom].where((s) => s.isNotEmpty);
    return items.isEmpty ? '옷차림 $noInfo' : items.join(' · ');
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
  static int _int(Object? v) =>
      v is int ? v : int.tryParse(v?.toString() ?? '') ?? 0;
}
