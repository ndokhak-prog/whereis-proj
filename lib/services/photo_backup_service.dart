import 'package:archive/archive.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import 'file_io.dart';
import 'photo_service.dart';

/// 사진 백업 파일(.zip)의 형식 문제를 사용자에게 알리기 위한 예외
class PhotoBackupException implements Exception {
  final String message;
  const PhotoBackupException(this.message);
  @override
  String toString() => message;
}

class PhotoImportResult {
  final int restored; // 복원한 사진 수
  final String? sourceName; // 가져온 백업 파일명
  const PhotoImportResult({required this.restored, this.sourceName});
}

/// 사진 전체를 zip 하나로 백업하고, 그 zip으로 사진을 복원한다.
///
/// 사진은 앱 내부 저장소에만 있어서 앱을 지우면 함께 사라진다. 백업 파일을
/// 폰에서 볼 수 있는 '다운로드' 폴더에 두면 PC 등으로 옮겨 보관할 수 있고,
/// 복원하면 엑셀의 `사진경로` 값과 다시 연결된다.
class PhotoBackupService {
  PhotoBackupService._();

  /// (파일명 → 내용)을 zip 바이트로 묶는다.
  static List<int> buildZip(Map<String, List<int>> files) {
    final archive = Archive();
    files.forEach((name, bytes) {
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    });
    return ZipEncoder().encode(archive) ?? const <int>[];
  }

  /// zip 바이트에서 (파일명 → 내용)을 꺼낸다. zip이 아니면 예외.
  static Map<String, List<int>> readZip(List<int> bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final files = <String, List<int>>{};
    for (final file in archive) {
      if (!file.isFile) continue;
      final content = file.content;
      files[p.basename(file.name)] = content is List<int>
          ? content
          : List<int>.from(content as Iterable);
    }
    return files;
  }

  /// 앱에 저장된 모든 사진을 zip 바이트로 만든다.
  static Future<List<int>> buildPhotoZip() async {
    final photos = await PhotoService.allPhotos();
    if (photos.isEmpty) {
      throw const PhotoBackupException('내보낼 사진이 없습니다');
    }
    final files = <String, List<int>>{};
    for (final file in photos) {
      files[p.basename(file.path)] = await file.readAsBytes();
    }
    return buildZip(files);
  }

  /// zip 바이트의 사진들을 앱 사진 폴더에 복원하고 개수를 돌려준다.
  static Future<int> restorePhotoZip(List<int> bytes) async {
    final Map<String, List<int>> entries;
    try {
      entries = readZip(bytes);
    } catch (e) {
      throw const PhotoBackupException('사진 백업 파일(.zip)이 아니거나 손상되었습니다');
    }
    var restored = 0;
    for (final entry in entries.entries) {
      await PhotoService.savePhotoBytes(entry.key, entry.value);
      restored++;
    }
    if (restored == 0) {
      throw const PhotoBackupException('사진 백업 파일 안에 사진이 없습니다');
    }
    return restored;
  }

  /// 사진 전체를 zip으로 내보낸다(백업). 사용자가 취소하면 null.
  static Future<SavedFile?> exportPhotos({bool chooseFolder = false}) async {
    final bytes = await buildPhotoZip();
    final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    return FileIo.saveBytes(
      bytes,
      'ndokhak_udiso_photos_$stamp.zip',
      chooseFolder: chooseFolder,
    );
  }

  /// 사진 백업 파일(.zip)을 골라 복원한다. 사용자가 취소하면 restored 0.
  static Future<PhotoImportResult> importPhotos() async {
    final picked = await FileIo.pickFile(
      mimeTypes: const ['application/zip', 'application/x-zip-compressed'],
      extensions: const ['zip'],
      dialogTitle: '사진 백업 파일(.zip) 선택',
    );
    if (picked == null) {
      return const PhotoImportResult(restored: 0); // 사용자가 취소
    }
    final restored = await restorePhotoZip(picked.bytes);
    return PhotoImportResult(restored: restored, sourceName: picked.name);
  }
}
