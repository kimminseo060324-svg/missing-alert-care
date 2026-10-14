import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import 'push_open.dart';
import 'push_payload.dart';

/// Firebase 푸시 연결: 알림 권한 요청, 토픽 구독, 알림을 눌렀을 때 화면 이동.
/// Firebase 설정은 android/app/google-services.json에서 읽어요. (git에 올리지 않아요)
class PushService {
  PushService._();

  /// 알림을 눌렀을 때 화면을 열려고 앱 전체 Navigator를 잡아 둬요.
  static final navigatorKey = GlobalKey<NavigatorState>();

  /// 앱이 뜬 뒤에 불러요. 푸시 연결이 실패해도 앱은 그대로 쓸 수 있어요.
  static Future<void> start() async {
    try {
      await Firebase.initializeApp();
    } catch (e) {
      debugPrint('푸시 연결 실패: $e');
      return;
    }
    final messaging = FirebaseMessaging.instance;

    // 앱이 백그라운드에 있을 때 알림을 누르면
    FirebaseMessaging.onMessageOpenedApp.listen(_open);

    // 앱이 꺼져 있을 때 알림을 눌러서 켜졌으면
    final initial = await messaging.getInitialMessage();
    if (initial != null) await _open(initial);

    try {
      await messaging.requestPermission();
      await messaging.subscribeToTopic(PushPayload.topic);
    } catch (e) {
      debugPrint('푸시 구독 실패: $e');
    }
  }

  static Future<void> _open(RemoteMessage message) async {
    // 첫 화면이 그려진 뒤에 Navigator가 생겨요.
    await WidgetsBinding.instance.endOfFrame;
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;
    await openFromPush(navigator, PushPayload.fromData(message.data));
  }
}
