import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// 사진 자동 압축(~10KB) 저장 및 구글렌즈 등 외부 앱 공유
class PhotoService {
  static const int _targetBytes = 10 * 1024;
  static const int _maxSide = 480;

  static Future<Directory> _photoDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'photos'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// picked 사진을 압축해 앱 저장소에 저장하고 경로를 반환
  static Future<String?> compressAndSave(XFile source) async {
    try {
      final bytes = await source.readAsBytes();
      var image = img.decodeImage(bytes);
      if (image == null) return null;

      if (image.width > _maxSide || image.height > _maxSide) {
        image = image.width >= image.height
            ? img.copyResize(image, width: _maxSide)
            : img.copyResize(image, height: _maxSide);
      }

      var quality = 70;
      List<int> out = img.encodeJpg(image, quality: quality);
      while (out.length > _targetBytes && quality > 25) {
        quality -= 10;
        out = img.encodeJpg(image, quality: quality);
      }
      if (out.length > 2 * _targetBytes) {
        image = img.copyResize(
          image,
          width: (image.width * 0.7).round(),
          height: (image.height * 0.7).round(),
        );
        quality = 50;
        out = img.encodeJpg(image, quality: quality);
        while (out.length > _targetBytes && quality > 20) {
          quality -= 10;
          out = img.encodeJpg(image, quality: quality);
        }
      }

      final dir = await _photoDir();
      final file = File(
        p.join(dir.path, 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg'),
      );
      await file.writeAsBytes(out, flush: true);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  static Future<void> deleteFile(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  /// 구글렌즈 등 외부 앱으로 사진을 열어 품목을 식별할 수 있게 공유
  static Future<void> shareForIdentification(String path) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path, mimeType: 'image/jpeg')],
        title: '품목 식별',
        text: '구글렌즈 등으로 식별한 품목 이름을 확인하세요',
      ),
    );
  }
}
