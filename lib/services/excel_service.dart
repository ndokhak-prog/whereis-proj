import 'dart:io';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../db/database_helper.dart';
import '../models/inventory_item.dart';
import '../utils/format.dart';
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
  const ImportResult({
    required this.inserted,
    this.replaced = 0,
    required this.errors,
    this.sourceName,
    this.sourcePath,
  });
}

class ExcelService {
  /// 저장 폴더로 앱 전용 폴더를 사용한다.
  /// 안드로이드에서는 앱 전용 외부 저장소(Android/data/<패키지>/files)라
  /// 저장소 권한 없이 쓸 수 있고 실제 파일 경로를 알 수 있다.
  static Future<Directory> _saveDir() async {
    Directory base;
    try {
      base = (await getExternalStorageDirectory()) ??
          await getApplicationDocumentsDirectory();
    } catch (_) {
      base = await getApplicationDocumentsDirectory();
    }
    final dir = Directory(p.join(base.path, 'udiso'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<SavedFile> _saveWorkbook(
    List<List<dynamic>> rows,
    String fileName,
  ) async {
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
    final bytes = excel.encode() ?? [];
    final dir = await _saveDir();
    final file = File(p.join(dir.path, fileName));
    await file.writeAsBytes(bytes, flush: true);
    return (path: file.path, name: fileName);
  }

  static Future<SavedFile> exportTemplate() async {
    final rows = [
      kExcelHeaders,
      ['생수', '기타', '2', '2027-12-31', '리필용', '1층', '주방', '팬트리', '바닥'],
      ['청소기 필터', '인테리어', '1', '', '6개월마다 교체', '발코니', '', '', '수납장'],
    ];
    return _saveWorkbook(rows, 'ndokhak_udiso_template.xlsx');
  }

  static Future<SavedFile> exportAll() async {
    final items = await DatabaseHelper.instance.allItems();
    final rows = [
      kExcelHeaders,
      ...items.map(_toRow),
    ];
    final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    return _saveWorkbook(rows, 'ndokhak_udiso_$stamp.xlsx');
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
      ];

  /// 엑셀 파일을 가져온다 (교체 모드).
  /// 기존 물품을 모두 삭제하고 엑셀 내용으로 등록하며,
  /// 유효한 행이 없으면 기존 정보를 유지한다.
  static Future<ImportResult> importFromPicker() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );
    final pickedFile = picked?.files.single;
    final path = pickedFile?.path;
    if (path == null) {
      return const ImportResult(inserted: 0, errors: []);
    }

    final List<int> bytes;
    try {
      bytes = await File(path).readAsBytes();
    } catch (e) {
      debugPrint('엑셀 파일 읽기 실패: $e');
      throw const ExcelImportException('선택한 파일을 읽을 수 없습니다');
    }

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
    final sourceName = pickedFile?.name ?? p.basename(path);
    final sourcePath = path;

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
    for (final old in before) {
      await PhotoService.deleteFile(old.photoPath);
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
    );
  }

  static String? _normalizeDate(String s) {
    if (s.isEmpty) return null;
    final t = s.trim().replaceAll('.', '-').replaceAll('/', '-');
    final d = DateTime.tryParse(t);
    return d == null ? s.trim() : ymd(d);
  }
}
