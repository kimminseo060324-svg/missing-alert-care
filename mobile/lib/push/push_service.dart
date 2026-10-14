import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../theme/app_colors.dart';
import 'foreground_notice.dart';
import 'push_open.dart';
import 'push_payload.dart';

/// Firebase 푸시 연결: 알림 권한 요청, 토픽 구독, 알림을 눌렀을 때 화면 이동.
/// Firebase 설정은 android/app/google-services.json에서 읽어요. (git에 올리지 않아요)
///
/// - 앱이 백그라운드이거나 꺼져 있을 때: Android가 알림을 띄워요. 앱은 띄우지 않아요.
/// - 앱을 보고 있을 때: Android가 띄우지 않아서 앱이 같은 채널로 직접 띄워요.
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
        onDidReceiveNotificationResponse: (r) => _openPayload(r.payload),
      );
      final launch = await _local.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        await _openPayload(launch!.notificationResponse?.payload);
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
    if (notice == null) return;
    try {
      await _local.show(
        id: ForegroundNotice.androidId,
        title: notice.title,
        body: notice.body,
        payload: notice.payload,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            '실종경보',
            channelDescription: '우리 동네 실종경보 알림',
            importance: Importance.high,
            priority: Priority.high,
            icon: 'ic_stat_notify',
            color: AppColors.navy,
            tag: notice.tag,
          ),
        ),
      );
    } catch (e) {
      debugPrint('앱 알림 띄우기 실패: $e');
    }
  }

  static Future<void> _openPayload(String? payload) async {
    final p = ForegroundNotice.decode(payload);
    if (p != null) await _open(p);
  }

  static Future<void> _open(PushPayload payload) async {
    // 첫 화면이 그려진 뒤에 Navigator가 생겨요.
    await WidgetsBinding.instance.endOfFrame;
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;
    // 서버에서 이 경보의 최신 상태를 새로 읽어서 화면을 정해요.
    await openFromPush(navigator, payload);
  }
}
