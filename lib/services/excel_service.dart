import 'dart:io';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../db/database_helper.dart';
import '../models/inventory_item.dart';
import '../utils/format.dart';
import 'file_gateway.dart';
import 'photo_service.dart';

const kExcelHeaders = [
  '품목',
  '분류',
  '수량',
  '유효기한',
  '비고',
  '층',
  '장소1',
  '장소2',
  '장소3',
  '사진경로',
  '사진파일명',
];

/// 저장된 엑셀 파일 정보 (실제 파일 경로 + 파일명)
typedef SavedFile = ({String path, String name});

/// 엑셀 파일 자체의 문제(형식 오류 등)를 사용자에게 알리기 위한 예외
class ExcelImportException implements Exception {
  final String message;
  const ExcelImportException(this.message);
  @override
  String toString() => message;
}

class ImportResult {
  final int inserted;
  final int replaced; // 교체로 삭제된 기존 물품 수
  final List<String> errors;
  final String? sourceName; // 가져온 파일명
  final String? sourcePath; // 가져온 파일 경로
  final int photoMissing; // 사진 파일을 찾지 못해 사진 없이 등록된 건수
  const ImportResult({
    required this.inserted,
    this.replaced = 0,
    required this.errors,
    this.sourceName,
    this.sourcePath,
    this.photoMissing = 0,
  });
}

class ExcelService {
  /// 워크북을 만들어 엑셀 바이트로 돌려준다.
  static List<int> _encodeWorkbook(List<List<dynamic>> rows) {
    final excel = Excel.createExcel();
    final sheet = excel['보유목록'];
    for (var r = 0; r < rows.length; r++) {
      for (var c = 0; c < rows[r].length; c++) {
        final v = rows[r][c];
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r))
            .value = TextCellValue(v?.toString() ?? '');
      }
    }
    excel.delete('Sheet1');
    return excel.encode() ?? [];
  }

  /// 워크북을 저장하고 저장된 파일 정보를 돌려준다.
  ///
  /// [chooseFolder]가 false(기본)면 스마트폰에서 바로 볼 수 있는 '다운로드'
  /// 폴더에 저장한다. true면 사용자가 저장 위치를 고르는 시스템 대화상자를
  /// 띄우며, 기본 위치는 '다운로드'다. 사용자가 취소하면 null을 돌려준다.
  static Future<SavedFile?> _saveWorkbook(
    List<List<dynamic>> rows,
    String fileName, {
    bool chooseFolder = false,
  }) async {
    final bytes = _encodeWorkbook(rows);

    if (!chooseFolder) {
      // 안드로이드: MediaStore로 '다운로드' 폴더에 바로 저장 (저장소 권한 불필요)
      final path = await FileGateway.saveToDownloads(fileName, bytes);
      if (path != null) return (path: path, name: p.basename(path));
    }

    // 그 외 환경이거나 저장에 실패한 경우: 시스템 저장 대화상자(SAF)를 띄운다.
    final saved = await FilePicker.saveFile(
      dialogTitle: '저장 위치 선택 (기본: 다운로드)',
      fileName: fileName,
      initialDirectory:
          Platform.isAndroid ? FileGateway.downloadsDocumentsUri : null,
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      bytes: Uint8List.fromList(bytes),
    );
    if (saved == null) return null; // 사용자가 저장을 취소
    return (path: readableLocation(saved), name: fileName);
  }

  static Future<SavedFile?> exportTemplate({bool chooseFolder = false}) async {
    final rows = [
      kExcelHeaders,
      ['생수', '기타', '2', '2027-12-31', '리필용', '1층', '주방', '팬트리', '바닥', '', ''],
      ['청소기 필터', '인테리어', '1', '', '6개월마다 교체', '발코니', '', '', '수납장', '', ''],
    ];
    return _saveWorkbook(rows, 'ndokhak_udiso_template.xlsx',
        chooseFolder: chooseFolder);
  }

  static Future<SavedFile?> exportAll({bool chooseFolder = false}) async {
    final items = await DatabaseHelper.instance.allItems();
    final rows = [
      kExcelHeaders,
      ...items.map(_toRow),
    ];
    final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    return _saveWorkbook(rows, 'ndokhak_udiso_$stamp.xlsx',
        chooseFolder: chooseFolder);
  }

  static List<dynamic> _toRow(InventoryItem i) => [
        i.itemName,
        i.category,
        i.quantity.toString(),
        i.expiryDate ?? '',
        i.note,
        i.floor,
        i.placeLarge,
        i.placeMedium,
        i.placeSmall,
        i.photoPath ?? '',
        i.photoPath == null ? '' : p.basename(i.photoPath!),
      ];

  /// 엑셀 파일을 골라 가져온다 (교체 모드).
  ///
  /// 안드로이드에서는 '다운로드' 폴더에서 시작하는 파일 선택 창을 띄우고,
  /// 그 외 환경에서는 file_picker를 사용한다.
  /// 사용자가 취소하면 빈 결과(inserted 0, errors 없음)를 돌려준다.
  static Future<ImportResult> importFromPicker() async {
    try {
      final picked = await FileGateway.pickExcelFile();
      if (picked == null) {
        return const ImportResult(inserted: 0, errors: []); // 사용자가 취소
      }
      return importFromBytes(picked.bytes,
          sourceName: picked.name, sourcePath: picked.location);
    } on MissingPluginException {
      // 네이티브 채널이 없는 환경(데스크톱/테스트)에서는 file_picker 사용
    } on PlatformException catch (e) {
      debugPrint('파일 선택 실패: $e');
      throw ExcelImportException(e.message ?? '파일을 선택할 수 없습니다');
    }

    final picked = await FilePicker.pickFiles(
      dialogTitle: '엑셀 파일 선택',
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );
    final pickedFile = picked?.files.single;
    final path = pickedFile?.path;
    if (path == null) {
      return const ImportResult(inserted: 0, errors: []); // 사용자가 취소
    }

    final List<int> bytes;
    try {
      bytes = await File(path).readAsBytes();
    } catch (e) {
      debugPrint('엑셀 파일 읽기 실패: $e');
      throw const ExcelImportException('선택한 파일을 읽을 수 없습니다');
    }
    return importFromBytes(bytes,
        sourceName: pickedFile?.name ?? p.basename(path), sourcePath: path);
  }

  /// 엑셀 내용(바이트)으로 기존 물품을 모두 교체한다.
  /// 품목과 장소1이 비어 있는 행은 제외하며, 유효한 행이 없으면 기존 정보를
  /// 유지한다 (전면 삭제 방지).
  static Future<ImportResult> importFromBytes(
    List<int> bytes, {
    String? sourceName,
    String? sourcePath,
  }) async {
    final Excel excel;
    try {
      excel = Excel.decodeBytes(bytes);
    } catch (e) {
      debugPrint('엑셀 디코드 실패: $e');
      throw const ExcelImportException(
          '엑셀 파일을 읽을 수 없습니다. .xlsx 형식인지 확인하세요');
    }
    final errors = <String>[];
    final items = <InventoryItem>[];
    final db = DatabaseHelper.instance;
    var photoMissing = 0;

    for (final tableName in excel.tables.keys) {
      final table = excel.tables[tableName]!;
      for (var r = 0; r < table.rows.length; r++) {
        final row = table.rows[r];

        String cell(int i) {
          if (i >= row.length) return '';
          final v = row[i]?.value;
          if (v == null) return '';
          if (v is TextCellValue) return v.value.toString().trim();
          if (v is IntCellValue) return v.value.toString();
          if (v is DoubleCellValue) {
            return v.value == v.value.roundToDouble()
                ? v.value.toInt().toString()
                : v.value.toString();
          }
          if (v is DateTimeCellValue) {
            return ymd(DateTime(v.year, v.month, v.day));
          }
          if (v is num) return v.toString();
          return v.toString().trim();
        }

        final isBlank = row.every((c) => c == null || c.value == null);
        if (isBlank) continue;
        if (r == 0 && cell(0) == '품목') continue;

        final name = cell(0);
        if (name.isEmpty) {
          errors.add('${r + 1}행: 품목이 비어 있어 제외됨');
          continue;
        }
        final placeLarge = cell(6);
        if (placeLarge.isEmpty) {
          errors.add('${r + 1}행: 장소1이 비어 있어 제외됨');
          continue;
        }

        final now = DateTime.now().millisecondsSinceEpoch;
        // 사진은 엑셀에 적힌 경로가 이 기기에 실제로 있을 때만 연결한다.
        final photoRaw = cell(9);
        final photoPath = _existingPhoto(photoRaw);
        if (photoRaw.isNotEmpty && photoPath == null) photoMissing++;
        items.add(InventoryItem(
          itemName: name,
          category: cell(1),
          quantity: int.tryParse(cell(2)) ?? 1,
          expiryDate: _normalizeDate(cell(3)),
          note: cell(4),
          floor: cell(5),
          placeLarge: placeLarge,
          placeMedium: cell(7),
          placeSmall: cell(8),
          photoPath: photoPath,
          createdAt: now,
          updatedAt: now,
        ));
      }
    }

    // 유효한 행이 없으면 기존 정보를 유지한다 (전면 삭제 방지)
    if (items.isEmpty) {
      return ImportResult(
        inserted: 0,
        errors: ['가져올 데이터가 없어 기존 정보를 유지했습니다', ...errors],
        sourceName: sourceName,
        sourcePath: sourcePath,
      );
    }

    // 교체 모드: 기존 물품과 첨부된 사진을 삭제하고 엑셀 내용으로 등록한다
    final before = await db.allItems();
    final replaced = await db.replaceAllItems(items);
    // 새로 등록한 물품이 그대로 쓰는 사진은 지우지 않는다
    final keepPhotos =
        items.map((e) => e.photoPath).whereType<String>().toSet();
    for (final old in before) {
      final path = old.photoPath;
      if (path != null && !keepPhotos.contains(path)) {
        await PhotoService.deleteFile(path);
      }
    }
    for (final item in items) {
      await db.ensureMaster('item', item.itemName);
      await db.ensureMaster('category', item.category);
      await db.ensureMaster('floor', item.floor);
      await db.ensureMaster('place_large', item.placeLarge);
      await db.ensureMaster('place_medium', item.placeMedium);
      await db.ensureMaster('place_small', item.placeSmall);
    }
    return ImportResult(
      inserted: items.length,
      replaced: replaced,
      errors: errors,
      sourceName: sourceName,
      sourcePath: sourcePath,
      photoMissing: photoMissing,
    );
  }

  /// 엑셀에 적힌 사진 경로가 이 기기에 실제로 있을 때만 그 경로를 돌려준다.
  static String? _existingPhoto(String path) {
    if (path.isEmpty) return null;
    return File(path).existsSync() ? path : null;
  }

  static String? _normalizeDate(String s) {
    if (s.isEmpty) return null;
    final t = s.trim().replaceAll('.', '-').replaceAll('/', '-');
    final d = DateTime.tryParse(t);
    return d == null ? s.trim() : ymd(d);
  }
}
