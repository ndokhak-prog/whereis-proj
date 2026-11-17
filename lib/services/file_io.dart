import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'file_gateway.dart';

/// 저장된 파일 정보 (실제 파일 경로 + 파일명)
typedef SavedFile = ({String path, String name});

/// 파일 선택·저장 중에 사용자에게 그대로 보여 줄 수 있는 문제
class FileIoException implements Exception {
  final String message;
  const FileIoException(this.message);
  @override
  String toString() => message;
}

/// 파일 저장/선택을 공통으로 처리한다.
///
/// - 저장: 기본은 스마트폰에서 바로 볼 수 있는 '다운로드' 폴더에 저장하고,
///   [chooseFolder]가 true면 사용자가 위치를 고르는 시스템 대화상자를 띄운다
///   (대화상자의 기본 위치도 '다운로드').
/// - 선택: 안드로이드에서는 '다운로드' 폴더에서 시작하는 네이티브 파일 선택
///   창을 쓰고, 그 외 환경에서는 file_picker를 쓴다.
class FileIo {
  FileIo._();

  /// 바이트를 파일로 저장한다. 사용자가 취소하면 null을 돌려준다.
  static Future<SavedFile?> saveBytes(
    List<int> bytes,
    String fileName, {
    bool chooseFolder = false,
    String dialogTitle = '저장 위치 선택 (기본: 다운로드)',
  }) async {
    if (!chooseFolder) {
      // 안드로이드: MediaStore로 '다운로드' 폴더에 바로 저장 (저장소 권한 불필요)
      final path = await FileGateway.saveToDownloads(fileName, bytes);
      if (path != null) return (path: path, name: p.basename(path));
    }

    // 그 외 환경이거나 저장에 실패한 경우: 시스템 저장 대화상자(SAF)를 띄운다.
    final extension = p.extension(fileName).replaceFirst('.', '');
    final saved = await FilePicker.saveFile(
      dialogTitle: dialogTitle,
      fileName: fileName,
      initialDirectory:
          Platform.isAndroid ? FileGateway.downloadsDocumentsUri : null,
      type: FileType.custom,
      allowedExtensions: extension.isEmpty ? null : [extension],
      bytes: Uint8List.fromList(bytes),
    );
    if (saved == null) return null; // 사용자가 저장을 취소
    return (path: readableLocation(saved), name: fileName);
  }

  /// 파일을 하나 고른다. 사용자가 취소하면 null을 돌려준다.
  ///
  /// 안드로이드에서는 [mimeTypes] 형식만 고를 수 있는 네이티브 파일 선택 창을
  /// '다운로드' 폴더에서 시작하고, 그 외 환경에서는 file_picker를 쓴다.
  static Future<PickedFile?> pickFile({
    required List<String> mimeTypes,
    required List<String> extensions,
    String? dialogTitle,
  }) async {
    try {
      final picked = await FileGateway.pickFile(mimeTypes: mimeTypes);
      if (picked != null) return picked;
      return null; // 사용자가 취소
    } on MissingPluginException {
      // 네이티브 채널이 없는 환경(데스크톱/테스트)에서는 file_picker 사용
    } on PlatformException catch (e) {
      debugPrint('파일 선택 실패: $e');
      throw FileIoException(e.message ?? '파일을 선택할 수 없습니다');
    }

    final result = await FilePicker.pickFiles(
      dialogTitle: dialogTitle,
      type: FileType.custom,
      allowedExtensions: extensions,
    );
    final picked = result?.files.single;
    final path = picked?.path;
    if (path == null) {
      return null; // 사용자가 취소
    }

    final List<int> bytes;
    try {
      bytes = await File(path).readAsBytes();
    } catch (e) {
      debugPrint('파일 읽기 실패: $e');
      throw const FileIoException('선택한 파일을 읽을 수 없습니다');
    }
    return PickedFile(
      name: picked?.name ?? p.basename(path),
      bytes: bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
      location: path,
    );
  }
}
