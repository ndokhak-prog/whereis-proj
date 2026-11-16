import 'package:flutter/services.dart';

/// 예외를 사용자에게 보여줄 문구로 변환한다.
///
/// toString()이 'null'이나 빈 문자열을 돌려주는 예외도 있어(예: 메시지가 없는
/// 플랫폼/DB 오류) 그대로 보여주면 '실패: null'처럼 알 수 없는 문구가 된다.
/// 그런 경우에는 예외 타입 이름을 대신 보여준다.
String errorText(Object e) {
  if (e is PlatformException) {
    final detail = e.message ?? e.details?.toString();
    if (detail != null && detail.trim().isNotEmpty) return detail.trim();
    return e.code;
  }
  final text = e.toString().trim();
  if (text.isEmpty || text == 'null') return '${e.runtimeType}';
  return text;
}
