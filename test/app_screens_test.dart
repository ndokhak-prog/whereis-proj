import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whereis/db/database_helper.dart';
import 'package:whereis/main.dart';
import 'package:whereis/models/inventory_item.dart';
import 'package:whereis/services/excel_service.dart';
import 'package:whereis/services/photo_backup_service.dart';
import 'package:whereis/services/photo_service.dart';

const _materialFonts = r'C:\tools\flutter\bin\cache\artifacts\material_fonts';

/// 테스트에서 쓰는 앱 문서 폴더(사진 폴더의 부모). setUp에서 매번 새로 만든다.
late Directory _docsDir;

Future<void> _loadFamily(String family, String filePath) async {
  final bytes = await File(filePath).readAsBytes();
  final loader = FontLoader(family);
  loader.addFont(
    Future<ByteData>.value(
      ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes),
    ),
  );
  await loader.load();
}

void _unfocus(WidgetTester tester) {
  tester.binding.focusManager.primaryFocus?.unfocus();
}

Finder _btn(String label) => find.ancestor(
      of: find.text(label),
      matching: find.byWidgetPredicate((w) {
        final n = w.runtimeType.toString();
        return n == 'FilledButton' || n == '_FilledButtonWithIcon';
      }),
    );

Finder _btnLike(String typePart, String label) => find.ancestor(
      of: find.text(label),
      matching: find.byWidgetPredicate((w) {
        final n = w.runtimeType.toString();
        return n.contains(typePart) && !n.endsWith('Child');
      }),
    );

Finder _dialogField() => find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );

Future<void> _back(WidgetTester tester) async {
  await tester.tap(find
      .descendant(
          of: find.byType(AppBar), matching: find.byIcon(Icons.arrow_back))
      .first);
  await tester.pumpAndSettle();
}

Future<void> _pumpApp(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(412, 915));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(const WhereIsApp());
  await tester.pumpAndSettle();
}

Future<void> _golden(WidgetTester tester, String name,
    {bool keepFocus = false}) async {
  if (keepFocus) {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
  } else {
    _unfocus(tester);
    await tester.pumpAndSettle();
  }
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('goldens/$name.png'),
  );
}

Future<void> _seedItems() async {
  final db = DatabaseHelper.instance;
  final now = DateTime.now().millisecondsSinceEpoch;
  Future<void> add(
    String name,
    String floor,
    String large,
    String medium,
    String small, {
    int qty = 1,
    String? expiry,
    String note = '',
    String category = '',
  }) async {
    await db.insertItem(InventoryItem(
      itemName: name,
      category: category,
      floor: floor,
      placeLarge: large,
      placeMedium: medium,
      placeSmall: small,
      quantity: qty,
      expiryDate: expiry,
      note: note,
      createdAt: now,
      updatedAt: now,
    ));
    await db.ensureMaster('item', name);
    await db.ensureMaster('place_medium', medium);
    if (category.isNotEmpty) await db.ensureMaster('category', category);
  }

  await add('에어컨 필터', '2층', '큰방', '옷장', '상단',
      qty: 2, expiry: '2026-12-31', note: '거실 선반 위', category: '공구');
  await add('김치', '1층', '주방', '냉장고', '안쪽', category: '기타');
  await add('세탁세제', '1층', '욕실', '세탁기', '하단', qty: 3, category: '수도');
}

/// 테스트용 엑셀 파일 바이트를 만든다.
List<int> _buildXlsx(List<List<String>> rows) {
  final excel = Excel.createExcel();
  final sheet = excel['Sheet1'];
  for (var r = 0; r < rows.length; r++) {
    for (var c = 0; c < rows[r].length; c++) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r))
          .value = TextCellValue(rows[r][c]);
    }
  }
  return excel.encode() ?? [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    await _loadFamily('Roboto', p.join(_materialFonts, 'roboto-regular.ttf'));
    await _loadFamily(
        'MaterialIcons', p.join(_materialFonts, 'materialicons-regular.otf'));
    await _loadFamily('Malgun Gothic', r'C:\Windows\Fonts\malgun.ttf');
  });

  setUp(() async {
    await DatabaseHelper.instance.close();
    final path = p.join(await getDatabasesPath(), 'whereis.db');
    if (await File(path).exists()) {
      await databaseFactory.deleteDatabase(path);
    }
    await DatabaseHelper.instance.countItems();

    // path_provider(앱 문서 폴더)를 임시 폴더로 바꾼다. 사진 폴더가 이 안에 생긴다.
    _docsDir = await Directory.systemTemp.createTemp('udiso_docs');
    const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(pathProviderChannel, (call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return _docsDir.path;
      }
      return null;
    });
    addTearDown(() async {
      messenger.setMockMethodCallHandler(pathProviderChannel, null);
      if (await _docsDir.exists()) {
        await _docsDir.delete(recursive: true);
      }
    });
  });

  testWidgets('01 홈 초기 화면', (tester) async {
    await _pumpApp(tester);

    expect(find.text('어디소 (udiso)'), findsOneWidget);
    expect(find.text('조건을 선택해 물건을 찾아보세요'), findsOneWidget);

    final floors = await DatabaseHelper.instance.masterNames('floor');
    expect(floors, ['지하', '1층', '2층', '3층', '옥상']);
    expect(await DatabaseHelper.instance.masterNames('category'),
        ['인테리어', '공구', '수도', '전기', '기타']);
    expect(await DatabaseHelper.instance.countItems(), 0);

    await _golden(tester, '01_home_initial');
  });

  testWidgets('02 건별 등록 및 전체 조회', (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.widgetWithText(FloatingActionButton, '등록'));
    await tester.pumpAndSettle();
    expect(find.text('등록'), findsOneWidget);
    // 사진이 없어도 저장경로·파일명 항목은 항상 표시된다
    expect(find.text('사진 저장경로 및 파일명'), findsOneWidget);
    expect(find.text('등록된 사진 없음'), findsOneWidget);
    await _golden(tester, '02_item_edit_new');

    await tester.enterText(find.byType(TextFormField).at(0), '에어컨 필터');
    _unfocus(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>).at(0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2층').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('큰방').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('+ 분류 추가'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('공구').last);
    await tester.pumpAndSettle();
    await tester.tap(_btn('확인'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(TextFormField).at(2));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // 달력을 항상 고정된 달(2020년 1월)로 이동해 15일을 선택한 뒤 골든을
    // 찍는다. 달력 그리드뿐 아니라 대화상자 헤더(처음 선택된 날짜)까지
    // 실행 시점의 날짜에 영향받지 않아야 골든이 안정적으로 유지된다.
    final now = DateTime.now();
    final monthsBack = (now.year - 2020) * 12 + (now.month - 1);
    final prevMonth = find.byIcon(Icons.chevron_left);
    for (var i = 0; i < monthsBack; i++) {
      await tester.tap(prevMonth);
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('15').last);
    await tester.pumpAndSettle();
    await _golden(tester, '03_date_picker', keepFocus: true);
    await tester.tap(find.text('확인'));
    await tester.pump();
    _unfocus(tester);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(3), '거실 선반 위');
    _unfocus(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '저장'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FloatingActionButton, '등록'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), '에어컨');
    await _golden(tester, '04_item_suggestions', keepFocus: true);
    await tester.tap(find.text('에어컨 필터').last);
    await tester.pump();
    _unfocus(tester);
    await tester.pumpAndSettle();
    await _back(tester);

    await tester.tap(find.widgetWithText(FloatingActionButton, '등록'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), '김치');
    _unfocus(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>).at(0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1층').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('주방').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(1), '2');
    _unfocus(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '저장'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FloatingActionButton, '등록'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), '세탁세제');
    _unfocus(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>).at(0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1층').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('욕실').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>).at(2));
    await tester.pumpAndSettle();
    await tester.tap(find.text('➕ 추가...').last);
    await tester.pumpAndSettle();
    await tester.enterText(_dialogField(), '세탁기');
    _unfocus(tester);
    await tester.pumpAndSettle();
    await tester.tap(_btn('추가'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(1), '3');
    _unfocus(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '저장'));
    await tester.pumpAndSettle();

    expect(find.text('에어컨 필터'), findsWidgets);
    expect(find.text('김치'), findsOneWidget);
    expect(find.text('세탁세제'), findsOneWidget);
    expect(find.text('2020.01.15'), findsOneWidget);

    final db = DatabaseHelper.instance;
    expect(await db.countItems(), 3);
    final medium = await db.masterNames('place_medium');
    expect(medium, contains('세탁기'));

    await _golden(tester, '05_home_results');
  });

  testWidgets('03 세부 검색', (tester) async {
    await _seedItems();
    await _pumpApp(tester);

    await tester.tap(find.text('세부'));
    await tester.pumpAndSettle();
    expect(find.text('품목'), findsOneWidget);
    await _golden(tester, '06_detail_mode');

    await tester.tap(find.byType(DropdownButtonFormField<String>).at(0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('에어컨 필터').last);
    await tester.pumpAndSettle();
    await tester.tap(_btn('찾기'));
    await tester.pumpAndSettle();

    expect(find.text('에어컨 필터'), findsWidgets);
    expect(find.text('김치'), findsNothing);
    expect(
        (await DatabaseHelper.instance.searchItems(itemName: '에어컨 필터'))
            .length,
        1);
    expect(
        (await DatabaseHelper.instance.searchItems(category: '공구')).length,
        1);
    expect(
        (await DatabaseHelper.instance.searchItems(category: '김치')).isEmpty,
        isTrue);
    expect(
        (await DatabaseHelper.instance.searchItems(placeLarge: '거실')).isEmpty,
        isTrue);

    await _golden(tester, '07_detail_results');
  });

  testWidgets('04 키워드 검색 및 결과 없음', (tester) async {
    await _seedItems();
    await _pumpApp(tester);

    await tester.tap(find.text('키워드'));
    await tester.pumpAndSettle();
    await _golden(tester, '08_keyword_mode');

    await tester.enterText(find.byType(TextField), '김치');
    _unfocus(tester);
    await tester.pumpAndSettle();
    await tester.tap(_btn('찾기'));
    await tester.pumpAndSettle();
    expect(find.text('김치'), findsWidgets);
    expect(
        (await DatabaseHelper.instance.searchItems(keyword: '김치')).length, 1);
    await _golden(tester, '09_keyword_results');

    await tester.enterText(find.byType(TextField), '없는검색어');
    _unfocus(tester);
    await tester.pumpAndSettle();
    await tester.tap(_btn('찾기'));
    await tester.pumpAndSettle();
    expect(find.text('검색 결과가 없습니다'), findsOneWidget);
    expect(
        (await DatabaseHelper.instance.searchItems(keyword: '없는검색어'))
            .isEmpty,
        isTrue);
    await _golden(tester, '10_no_results');
  });

  testWidgets('05 기존 항목 수정 화면', (tester) async {
    await _seedItems();
    await _pumpApp(tester);

    await tester.tap(_btn('전체 조회'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('김치'));
    await tester.pumpAndSettle();

    expect(find.text('김치'), findsOneWidget);
    expect(find.text('1층'), findsOneWidget);
    await _golden(tester, '11_item_edit_existing');

    await tester.tap(_btnLike('OutlinedButton', '삭제'));
    await tester.pumpAndSettle();
    expect(find.text('삭제 확인'), findsOneWidget);
    await tester.tap(_btn('삭제'));
    await tester.pumpAndSettle();

    expect(find.text('어디소 (udiso)'), findsOneWidget);
    expect(find.text('김치'), findsNothing);
    expect(find.text('에어컨 필터'), findsOneWidget);
    expect(find.text('세탁세제'), findsOneWidget);
    expect(await DatabaseHelper.instance.countItems(), 2);
    expect(
        (await DatabaseHelper.instance.searchItems(itemName: '김치')).isEmpty,
        isTrue);
  });

  testWidgets('06 일괄등록(엑셀) 바텀시트', (tester) async {
    await _seedItems();
    await _pumpApp(tester);

    await tester.tap(find.byTooltip('일괄등록'));
    await tester.pumpAndSettle();
    expect(find.text('엑셀 양식 파일 받기'), findsOneWidget);
    expect(find.text('엑셀 파일 가져오기'), findsOneWidget);
    expect(find.text('사진 파일 내보내기 (백업)'), findsOneWidget);
    expect(find.text('사진 파일 가져오기 (복원)'), findsOneWidget);
    await _golden(tester, '12_import_sheet');

    // 교체 모드: 주의 대화상자에서 취소하면 기존 정보가 유지된다
    await tester.tap(find.text('엑셀 파일 가져오기'));
    await tester.pumpAndSettle();
    expect(find.text('가져오기 확인'), findsOneWidget);
    expect(find.textContaining('모두 삭제되고'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '취소'));
    await tester.pumpAndSettle();
    expect(find.text('가져오기 확인'), findsNothing);
    expect(await DatabaseHelper.instance.countItems(), 3);

    await tester.tapAt(const Offset(206, 150));
    await tester.pumpAndSettle();
    expect(find.text('엑셀 파일 가져오기'), findsNothing);
  });

  testWidgets('07 설정 및 목록관리', (tester) async {
    await _seedItems();
    await _pumpApp(tester);

    await tester.tap(find.byTooltip('설정'));
    await tester.pumpAndSettle();
    expect(find.text('설정'), findsOneWidget);
    await _golden(tester, '13_settings');

    await tester.tap(find.text('층'));
    await tester.pumpAndSettle();
    expect(find.text('지하'), findsOneWidget);
    await _golden(tester, '14_manage_floor');

    await tester.tap(find.descendant(
        of: find.byType(AppBar), matching: find.byIcon(Icons.add)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '4층');
    await tester.tap(_btn('저장'));
    await tester.pumpAndSettle();
    expect(find.text('4층'), findsOneWidget);
    expect(await DatabaseHelper.instance.masterNames('floor'),
        contains('4층'));

    await _back(tester);
    await tester.tap(find.text('품목'));
    await tester.pumpAndSettle();
    expect(find.text('에어컨 필터'), findsOneWidget);
    expect(find.text('김치'), findsOneWidget);
    expect(find.text('세탁세제'), findsOneWidget);
    await _golden(tester, '15_manage_items');
  });

  testWidgets('08 선택모드 및 일괄수정', (tester) async {
    await _seedItems();
    await _pumpApp(tester);

    await tester.tap(_btn('전체 조회'));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('김치'));
    await tester.pumpAndSettle();
    expect(find.byType(Checkbox), findsNWidgets(3));
    expect(find.text('선택 1건'), findsOneWidget);

    await tester.tap(find.byType(Checkbox).at(1));
    await tester.pumpAndSettle();
    expect(find.text('선택 2건'), findsOneWidget);
    await _golden(tester, '16_select_mode');

    await tester.tap(_btn('일괄수정'));
    await tester.pumpAndSettle();
    expect(find.text('일괄수정 (2건)'), findsOneWidget);
    await _golden(tester, '17_batch_edit');

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('3층').last);
    await tester.pumpAndSettle();
    await tester.tap(_btn('2건 적용'));
    await tester.pumpAndSettle();
    expect(find.text('일괄수정 확인'), findsOneWidget);
    await tester.tap(_btn('변경'));
    await tester.pumpAndSettle();

    expect(find.text('2건이 변경되었습니다'), findsOneWidget);
    final moved = await DatabaseHelper.instance.searchItems(floor: '3층');
    expect(moved.length, 2);

    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
  });

  testWidgets('09 일괄삭제', (tester) async {
    await _seedItems();
    await _pumpApp(tester);

    await tester.tap(_btn('전체 조회'));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('김치'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox).at(1));
    await tester.pumpAndSettle();
    expect(find.text('선택 2건'), findsOneWidget);

    await tester.tap(_btn('삭제'));
    await tester.pumpAndSettle();
    expect(find.text('삭제 확인'), findsOneWidget);
    await tester.tap(find
        .descendant(of: find.byType(AlertDialog), matching: _btn('삭제')));
    await tester.pumpAndSettle();

    expect(find.text('삭제 확인'), findsNothing);
    expect(find.text('김치'), findsNothing);
    expect(find.text('세탁세제'), findsNothing);
    expect(find.text('에어컨 필터'), findsOneWidget);
    final left = await DatabaseHelper.instance.searchItems();
    expect(left.length, 1);
    expect(left.first.itemName, '에어컨 필터');
  });

  test('10 물품 전체 교체(교체 모드)', () async {
    await _seedItems();
    final db = DatabaseHelper.instance;
    expect(await db.countItems(), 3);

    final now = DateTime.now().millisecondsSinceEpoch;
    final deleted = await db.replaceAllItems([
      InventoryItem(
        itemName: '새 품목 A',
        floor: '1층',
        placeLarge: '주방',
        quantity: 2,
        createdAt: now,
        updatedAt: now,
      ),
      InventoryItem(
        itemName: '새 품목 B',
        floor: '2층',
        placeLarge: '큰방',
        quantity: 1,
        createdAt: now,
        updatedAt: now,
      ),
    ]);

    expect(deleted, 3);
    expect(await db.countItems(), 2);
    expect(await db.searchItems(itemName: '김치'), isEmpty);

    final names = (await db.searchItems()).map((e) => e.itemName).toSet();
    expect(names, {'새 품목 A', '새 품목 B'});

    // 마스터(드롭다운) 목록은 교체 후에도 유지된다
    expect(await db.masterNames('floor'), contains('2층'));
    expect(await db.masterNames('item'), contains('에어컨 필터'));
  });

  test('11 엑셀 가져오기: 품목과 장소1이 있는 행만 등록', () async {
    final bytes = _buildXlsx([
      kExcelHeaders,
      ['생수', '기타', '2', '2027-12-31', '리필용', '1층', '주방', '팬트리', '바닥'],
      ['', '기타', '1', '', '', '1층', '주방', '', ''], // 품목 없음 → 제외
      ['휴지', '생활', '3', '', '', '2층', '', '', ''], // 장소1 없음 → 제외
      ['세제', '생활', '1', '', '', '', '욕실', '', ''], // 정상 등록
    ]);

    final result = await ExcelService.importFromBytes(
      bytes,
      sourceName: 'ndokhak_udiso_test.xlsx',
      sourcePath: '/tmp/ndokhak_udiso_test.xlsx',
    );

    expect(result.inserted, 2);
    expect(result.errors.any((e) => e.contains('품목이 비어')), isTrue);
    expect(result.errors.any((e) => e.contains('장소1이 비어')), isTrue);
    expect(result.sourceName, 'ndokhak_udiso_test.xlsx');
    expect(result.sourcePath, '/tmp/ndokhak_udiso_test.xlsx');

    final items = await DatabaseHelper.instance.searchItems();
    expect(items.map((e) => e.itemName).toSet(), {'생수', '세제'});
    expect(items.every((e) => e.placeLarge.isNotEmpty), isTrue);
  });

  test('12 엑셀 가져오기: 유효한 행이 없으면 기존 정보 유지', () async {
    await _seedItems();
    expect(await DatabaseHelper.instance.countItems(), 3);

    final bytes = _buildXlsx([
      kExcelHeaders,
      ['', '', '', '', '', '', '', '', ''],
      ['품목만있음', '', '1', '', '', '', '', '', ''],
    ]);

    final result = await ExcelService.importFromBytes(bytes);

    expect(result.inserted, 0);
    expect(result.errors.first, contains('기존 정보를 유지'));
    expect(await DatabaseHelper.instance.countItems(), 3);
  });

  test('13 엑셀 가져오기: 사진 경로·파일명 반영', () async {
    final dir = await Directory.systemTemp.createTemp('udiso_photo_test');
    final photo = File(p.join(dir.path, 'photo_test.jpg'));
    await photo.writeAsBytes([1, 2, 3]);

    final bytes = _buildXlsx([
      kExcelHeaders,
      ['사진있음', '기타', '1', '', '', '1층', '주방', '', '', photo.path, 'photo_test.jpg'],
      ['사진없음', '기타', '1', '', '', '1층', '주방', '', '', '/no/such/photo.jpg', 'photo.jpg'],
    ]);

    final result = await ExcelService.importFromBytes(bytes);

    expect(result.inserted, 2);
    expect(result.photoMissing, 1); // 없는 경로는 사진 없이 등록

    final items = await DatabaseHelper.instance.searchItems();
    expect(items.firstWhere((e) => e.itemName == '사진있음').photoPath,
        photo.path);
    expect(
        items.firstWhere((e) => e.itemName == '사진없음').photoPath, isNull);

    await dir.delete(recursive: true);
  });

  test('14 사진 백업(zip) 내보내기·복원', () async {
    final photos = Directory(p.join(_docsDir.path, 'photos'))
      ..createSync(recursive: true);
    File(p.join(photos.path, 'photo_a.jpg')).writeAsBytesSync([1, 2, 3]);
    File(p.join(photos.path, 'photo_b.jpg')).writeAsBytesSync([4, 5, 6]);

    final zip = await PhotoBackupService.buildPhotoZip();
    expect(zip, isNotEmpty);

    // 사진을 모두 지운 뒤(앱 재설치 상황) 백업 파일에서 복원한다
    photos.deleteSync(recursive: true);
    expect(await PhotoService.allPhotos(), isEmpty);

    final restored = await PhotoBackupService.restorePhotoZip(zip);
    expect(restored, 2);
    expect(File(p.join(photos.path, 'photo_a.jpg')).readAsBytesSync(),
        [1, 2, 3]);
    expect(File(p.join(photos.path, 'photo_b.jpg')).readAsBytesSync(),
        [4, 5, 6]);

    // zip이 아니면 사용자에게 알릴 수 있는 예외를 던진다
    await expectLater(
      PhotoBackupService.restorePhotoZip([1, 2, 3, 4]),
      throwsA(isA<PhotoBackupException>()),
    );
  });

  test('15 엑셀 가져오기: 사진 파일명으로 사진 연결', () async {
    final photos = Directory(p.join(_docsDir.path, 'photos'))
      ..createSync(recursive: true);
    File(p.join(photos.path, 'photo_c.jpg')).writeAsBytesSync([7, 8, 9]);

    // 경로는 다른 기기에서 만든 값이라 없지만, 파일명은 앱 사진 폴더에 있다
    final bytes = _buildXlsx([
      kExcelHeaders,
      [
        '파일명연결',
        '기타',
        '1',
        '',
        '',
        '1층',
        '주방',
        '',
        '',
        '/old/device/photo_c.jpg',
        'photo_c.jpg',
      ],
    ]);

    final result = await ExcelService.importFromBytes(bytes);

    expect(result.inserted, 1);
    expect(result.photoMissing, 0); // 파일명으로 찾았으므로 사진 없음이 아니다

    final items = await DatabaseHelper.instance.searchItems();
    expect(items.single.photoPath, p.join(photos.path, 'photo_c.jpg'));
  });

  testWidgets('16 키워드 찾기 후 포커스 이동·키보드 숨김', (tester) async {
    await _seedItems();
    await _pumpApp(tester);

    await tester.tap(find.text('키워드'));
    await tester.pumpAndSettle();

    final field = find.byType(TextField);
    final editable = tester.widget<EditableText>(
      find.descendant(of: field, matching: find.byType(EditableText)),
    );
    expect(editable.focusNode.hasFocus, isFalse);

    // 키워드 칸을 누르면 포커스(키보드 표시)
    await tester.tap(field);
    await tester.pumpAndSettle();
    expect(editable.focusNode.hasFocus, isTrue);

    await tester.enterText(field, '김치');
    await tester.pumpAndSettle();

    // 찾기 버튼을 누르면 커서가 버튼으로 옮겨가고 키보드가 내려간다
    await tester.tap(_btn('찾기'));
    await tester.pumpAndSettle();
    expect(editable.focusNode.hasFocus, isFalse);
    expect(
      find.ancestor(
        of: find.text('찾기'),
        matching: find.byWidgetPredicate(
          (w) => w is Focus && w.focusNode == FocusManager.instance.primaryFocus,
        ),
      ),
      findsOneWidget,
    );
    expect(find.text('김치'), findsWidgets);

    // 키워드 칸을 다시 누르면 포커스(키보드 표시)가 돌아온다
    await tester.tap(field);
    await tester.pumpAndSettle();
    expect(editable.focusNode.hasFocus, isTrue);
  });
}
