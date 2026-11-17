import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 안드로이드 네이티브 기능을 쓰기 위한 통로.
///
/// - '다운로드' 폴더에 엑셀 파일 저장 (MediaStore)
/// - '다운로드' 폴더에서 시작하는 파일 선택 창
///
/// 네이티브 구현이 없는 환경(데스크톱/테스트)에서는 MissingPluginException이
/// 발생하므로 호출한 쪽에서 다른 방법을 사용한다.
class FileGateway {
  FileGateway._();

  static const MethodChannel _channel = MethodChannel('udiso/files');

  /// 안드로이드 파일 선택 창이 처음 열리는 폴더(다운로드)의 문서 URI.
  static const String downloadsDocumentsUri =
      'content://com.android.providers.downloads.documents/root/downloads';

  /// '다운로드' 폴더에 저장하고 실제 파일 경로를 돌려준다.
  /// 지원하지 않는 환경이거나 실패하면 null을 돌려준다.
  static Future<String?> saveToDownloads(String name, List<int> bytes) async {
    try {
      return await _channel.invokeMethod<String>('saveToDownloads', {
        'name': name,
        'bytes': Uint8List.fromList(bytes),
      });
    } catch (e) {
      debugPrint('다운로드 폴더 저장 실패(다른 방법 사용): $e');
      return null;
    }
  }

  /// '다운로드' 폴더에서 시작하는 엑셀 파일 선택 창을 연다.
  /// 사용자가 취소하면 null을 돌려준다.
  static Future<PickedFile?> pickExcelFile() async {
    final map = await _channel.invokeMapMethod<String, dynamic>('pickExcelFile');
    if (map == null) return null;
    final raw = map['bytes'];
    return PickedFile(
      name: (map['name'] as String?) ?? 'import.xlsx',
      bytes: raw is Uint8List
          ? raw
          : Uint8List.fromList((raw as List<dynamic>).cast<int>()),
      location: readableLocation(map['location'] as String?),
    );
  }
}

/// 파일 선택 창에서 고른 파일.
class PickedFile {
  final String name;
  final Uint8List bytes;
  final String? location;

  const PickedFile({required this.name, required this.bytes, this.location});
}

/// 안드로이드 문서 URI를 사람이 읽기 쉬운 위치 문자열로 바꾼다.
///
/// 예) content://com.android.externalstorage.documents/document/primary%3ADownload%2Fa.xlsx
///     → /storage/emulated/0/Download/a.xlsx
/// 바꿀 수 없으면 원래 값을 그대로 돌려준다.
String readableLocation(String? location) {
  if (location == null || location.isEmpty) return '';
  const marker = '/document/';
  final index = location.indexOf(marker);
  if (index < 0) return location;
  var raw = location.substring(index + marker.length);
  try {
    raw = Uri.decodeComponent(raw);
  } catch (_) {
    return location;
  }
  const primary = 'primary:';
  if (raw.startsWith(primary)) {
    return '/storage/emulated/0/${raw.substring(primary.length)}';
  }
  return location;
}
