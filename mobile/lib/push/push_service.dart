import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../theme/app_colors.dart';
import 'foreground_notice.dart';
import 'notice_figure.dart';
import 'push_open.dart';
import 'push_payload.dart';

/// Firebase 푸시 연결: 알림 권한 요청, 토픽 구독, 알림을 눌렀을 때 화면 이동.
/// Firebase 설정은 android/app/google-services.json에서 읽어요. (git에 올리지 않아요)
///
/// - 서버가 알림 문구(notification)를 같이 보낸 푸시
///   - 앱이 백그라운드이거나 꺼져 있을 때: Android가 알림을 띄워요. 앱은 띄우지 않아요.
///   - 앱을 보고 있을 때: Android가 띄우지 않아서 앱이 같은 채널로 직접 띄워요.
/// - 서버가 data만 보낸 푸시: 언제나 앱이 띄워요. ([pushBackgroundHandler])
/// 앱이 띄우는 알림은 펼치면 여러 줄이고, 찾는 중인 경보에는 옷 그림과
/// "상세 보기"·"목격 제보" 버튼이 붙어요.
/// 같은 경보의 알림은 tag `alert_{alert_id}`가 같아서 종료·발견 알림이 앞 알림을 바꿔치기해요.
class PushService {
  PushService._();

  /// 알림을 눌렀을 때 화면을 열려고 앱 전체 Navigator를 잡아 둬요.
  static final navigatorKey = GlobalKey<NavigatorState>();

  /// MainActivity가 만드는 알림 채널과 같은 id
  static const channelId = 'missing_alerts';

  static final _local = FlutterLocalNotificationsPlugin();

  /// 앱이 뜬 뒤에 불러요. 푸시 연결이 실패해도 앱은 그대로 쓸 수 있어요.
  static Future<void> start() async {
    try {
      await Firebase.initializeApp();
    } catch (e) {
      debugPrint('푸시 연결 실패: $e');
      return;
    }
    final messaging = FirebaseMessaging.instance;

    // 앱이 백그라운드이거나 꺼져 있을 때 온 data만 있는 푸시
    FirebaseMessaging.onBackgroundMessage(pushBackgroundHandler);

    await _startLocal();

    // 앱을 보고 있을 때 온 푸시
    FirebaseMessaging.onMessage.listen(_showForeground);

    // 앱이 백그라운드에 있을 때 알림을 누르면
    FirebaseMessaging.onMessageOpenedApp.listen(
      (m) => _open(PushPayload.fromData(m.data)),
    );

    // 앱이 꺼져 있을 때 알림을 눌러서 켜졌으면
    final initial = await messaging.getInitialMessage();
    if (initial != null) await _open(PushPayload.fromData(initial.data));

    try {
      await messaging.requestPermission();
      await messaging.subscribeToTopic(PushPayload.topic);
    } catch (e) {
      debugPrint('푸시 구독 실패: $e');
    }
  }

  /// 앱이 직접 띄우는 알림 준비. 앱이 띄운 알림을 눌러서 켜졌으면 그 화면을 열어요.
  static Future<void> _startLocal() async {
    try {
      await _local.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_stat_notify'),
        ),
        onDidReceiveNotificationResponse: _openResponse,
      );
      final launch = await _local.getNotificationAppLaunchDetails();
      final response = launch?.notificationResponse;
      if ((launch?.didNotificationLaunchApp ?? false) && response != null) {
        await _openResponse(response);
      }
    } catch (e) {
      debugPrint('앱 알림 준비 실패: $e');
    }
  }

  static Future<void> _showForeground(RemoteMessage message) async {
    final notice = ForegroundNotice.from(
      message.data,
      title: message.notification?.title,
      body: message.notification?.body,
    );
    if (notice != null) await show(_local, notice);
  }

  /// [notice]를 알림으로 띄워요. 앱이 꺼져 있을 때도 써요.
  static Future<void> show(
    FlutterLocalNotificationsPlugin local,
    ForegroundNotice notice,
  ) async {
    try {
      await local.show(
        id: ForegroundNotice.androidId,
        title: notice.title,
        body: notice.body,
        payload: notice.payload,
        notificationDetails: NotificationDetails(android: details(notice)),
      );
    } catch (e) {
      debugPrint('앱 알림 띄우기 실패: $e');
    }
  }

  /// 알림 모양: 펼치면 여러 줄, 찾는 중이면 옷 그림과 버튼 두 개.
  @visibleForTesting
  static AndroidNotificationDetails details(ForegroundNotice notice) {
    final figure = NoticeFigure.fromSummary(notice.summary);
    return AndroidNotificationDetails(
      channelId,
      '실종경보',
      channelDescription: '우리 동네 실종경보 알림',
      importance: Importance.high,
      priority: Priority.high,
      icon: 'ic_stat_notify',
      color: AppColors.navy,
      tag: notice.tag,
      styleInformation: BigTextStyleInformation(
        notice.bigText,
        contentTitle: notice.title,
      ),
      largeIcon: notice.active && figure.hasColor
          ? ByteArrayAndroidBitmap(figure.toBmp())
          : null,
      actions: notice.active
          ? const [
              AndroidNotificationAction(
                ForegroundNotice.detailAction,
                '상세 보기',
                showsUserInterface: true,
              ),
              AndroidNotificationAction(
                ForegroundNotice.reportAction,
                '목격 제보',
                showsUserInterface: true,
              ),
            ]
          : null,
    );
  }

  /// 알림 본문을 누르거나 "상세 보기"면 상세, "목격 제보"면 06 목격 제보를 열어요.
  static Future<void> _openResponse(NotificationResponse response) async {
    final p = ForegroundNotice.decode(response.payload);
    if (p == null) return;
    await _open(p, report: response.actionId == ForegroundNotice.reportAction);
  }

  static Future<void> _open(PushPayload payload, {bool report = false}) async {
    // 첫 화면이 그려진 뒤에 Navigator가 생겨요.
    await WidgetsBinding.instance.endOfFrame;
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;
    // 서버에서 이 경보의 최신 상태를 새로 읽어서 화면을 정해요.
    await openFromPush(navigator, payload, report: report);
  }
}

/// 앱이 백그라운드이거나 꺼져 있을 때 온 푸시. Android가 앱과 따로 깨워서 불러요.
/// 알림 문구(notification)가 있는 푸시는 Android가 이미 띄웠으니 그냥 둬요.
/// data만 있는 푸시는 앱이 직접 띄워요.
@pragma('vm:entry-point')
Future<void> pushBackgroundHandler(RemoteMessage message) async {
  if (message.notification != null) return;
  final notice = ForegroundNotice.from(message.data);
  if (notice == null) return;
  final local = FlutterLocalNotificationsPlugin();
  try {
    await local.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_notify'),
      ),
    );
  } catch (e) {
    debugPrint('앱 알림 준비 실패: $e');
    return;
  }
  await PushService.show(local, notice);
}
