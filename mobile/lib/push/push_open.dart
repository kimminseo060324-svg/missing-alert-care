import 'dart:async';

import 'package:flutter/material.dart';

import '../app_routes.dart';
import '../data/alert_repository.dart';
import '../screens/alert_list_screen.dart';
import 'push_payload.dart';

/// 푸시 알림을 눌렀을 때 열 화면을 정해요.
/// alert_id로 경보를 찾으면 상세(수색 중·경보 종료 05, 발견 완료 07),
/// 못 찾거나 읽기에 실패하면 04 경보 목록을 열어요.
Future<void> openFromPush(
  NavigatorState navigator,
  PushPayload payload, {
  AlertRepository? repository,
}) async {
  if (!payload.isMissingAlert) return;
  final repo = repository ?? AlertRepository.instance;

  Widget screen = AlertListScreen(repository: repo);
  final id = payload.alertId;
  if (id != null) {
    try {
      // 서버에서 읽을 때는 이 경보의 최신 상태를 새로 받아 와요.
      final alert = await repo.loadOne(id);
      if (alert != null) screen = AppRoutes.detailScreen(alert);
    } catch (_) {
      // 읽기에 실패하면 목록 화면이 다시 시도 안내를 보여 줘요.
    }
  }
  if (!navigator.mounted) return;
  // push는 화면이 닫힐 때 끝나서 기다리지 않아요.
  unawaited(navigator.push(MaterialPageRoute(builder: (_) => screen)));
}
