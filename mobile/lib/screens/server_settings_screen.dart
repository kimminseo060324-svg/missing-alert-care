import 'dart:async';

import 'package:flutter/material.dart';

import '../data/alert_repository.dart';
import '../data/api_settings.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../widgets/app_button.dart';

/// 시연 메뉴 > 서버 주소.
/// 휴대폰에서 컴퓨터에 켠 서버에 접속할 주소를 넣거나, 앱 안 가짜 데이터로 바꿔요.
class ServerSettingsScreen extends StatefulWidget {
  const ServerSettingsScreen({super.key});

  @override
  State<ServerSettingsScreen> createState() => _ServerSettingsScreenState();
}

/// 연결 확인에 실패했을 때 보여 줄 짧은 안내. 긴 오류 문장은 보여 주지 않아요.
String connectFailText(Object error) {
  if (error is ServerException) {
    return '연결하지 못했어요. 서버가 오류를 보냈어요. (${error.statusCode})';
  }
  if (error is TimeoutException) {
    return '연결하지 못했어요. 서버 응답이 너무 늦어요.';
  }
  return '연결하지 못했어요. 서버가 켜져 있는지, 주소가 맞는지 확인해 주세요.';
}

class _ServerSettingsScreenState extends State<ServerSettingsScreen> {
  late final _url = TextEditingController(text: ApiSettings.current.baseUrl);
  late bool _useBuiltIn = ApiSettings.current.useBuiltIn;
  String? _error;
  String? _check; // 연결 확인 결과
  bool _checking = false;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  /// 입력한 주소를 정리해요. 형식이 틀리면 안내를 띄우고 null.
  String? _validUrl() {
    final url = ApiSettings.normalize(_url.text);
    if (!ApiSettings.isValid(url)) {
      setState(() => _error = '주소 형식이 맞지 않아요. 예: http://192.168.0.5:8000');
      return null;
    }
    setState(() => _error = null);
    return url;
  }

  Future<void> _checkConnection() async {
    final url = _validUrl();
    if (url == null) return;
    setState(() {
      _checking = true;
      _check = null;
    });
    String result;
    try {
      final alerts = await AlertRepository.server(url).loadAll();
      result = '연결됐어요. 경보 ${alerts.length}건을 받았어요.';
    } catch (e) {
      result = connectFailText(e);
    }
    if (!mounted) return;
    setState(() {
      _checking = false;
      _check = result;
    });
  }

  Future<void> _save() async {
    final url = _useBuiltIn ? ApiSettings.normalize(_url.text) : _validUrl();
    if (url == null) return;
    await ApiSettings.save(ApiSettings(baseUrl: url, useBuiltIn: _useBuiltIn));
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(titleSpacing: 16, title: const Text('서버 주소')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          TextField(
            controller: _url,
            enabled: !_useBuiltIn,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: '서버 주소',
              hintText: 'http://192.168.0.5:8000',
              errorText: _error,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '에뮬레이터: http://10.0.2.2:8000\n'
            '휴대폰: 같은 와이파이에 연결한 컴퓨터의 IP (예: http://192.168.0.5:8000)\n'
            '서버는 backend 폴더에서 uvicorn main:app --host 0.0.0.0 --port 8000 으로 켜요.',
            style: appText(12, color: AppColors.gray600, height: 1.6),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _useBuiltIn || _checking ? null : _checkConnection,
              child: Text(_checking ? '확인하는 중…' : '연결 확인'),
            ),
          ),
          if (_check != null) ...[
            const SizedBox(height: 8),
            Text(_check!, style: appText(13, weight: FontWeight.w700)),
          ],
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _useBuiltIn,
            onChanged: (v) => setState(() => _useBuiltIn = v),
            title: Text(
              '앱 안 가짜 데이터로 보기',
              style: appText(15, weight: FontWeight.w700),
            ),
            subtitle: Text(
              '서버 없이 시연할 때 켜요. 경보 종료 예시도 들어 있어요.',
              style: appText(12, color: AppColors.gray600),
            ),
          ),
          const SizedBox(height: 20),
          AppButton(label: '저장', onPressed: _save),
        ],
      ),
    );
  }
}
