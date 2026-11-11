import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/inventory_item.dart';

class DatabaseHelper {
  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();

  Database? _db;

  Future<Database> get database async {
    return _db ??= await _openDb();
  }

  Future<void> close() async {
    final db = _db;
    _db = null;
    await db?.close();
  }

  Future<Database> _openDb() async {
    final path = join(await getDatabasesPath(), 'whereis.db');
    return openDatabase(
      path,
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE masters (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            list_type TEXT NOT NULL,
            name TEXT NOT NULL,
            sort_order INTEGER NOT NULL DEFAULT 0,
            UNIQUE(list_type, name)
          )
        ''');
        await db.execute('''
          CREATE TABLE items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            item_name TEXT NOT NULL,
            category TEXT NOT NULL DEFAULT '',
            floor TEXT NOT NULL DEFAULT '',
            place_large TEXT NOT NULL DEFAULT '',
            place_medium TEXT NOT NULL DEFAULT '',
            place_small TEXT NOT NULL DEFAULT '',
            quantity INTEGER NOT NULL DEFAULT 1,
            expiry_date TEXT,
            note TEXT NOT NULL DEFAULT '',
            photo_path TEXT,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
        await _seedDefaults(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE items ADD COLUMN photo_path TEXT');
        }
        if (oldVersion < 3) {
          await db.execute(
              "ALTER TABLE items ADD COLUMN category TEXT NOT NULL DEFAULT ''");
          await _seedCategory(db);
        }
      },
    );
  }

  Future<void> _seedDefaults(Database db) async {
    Future<void> seed(String type, List<String> names) async {
      for (var i = 0; i < names.length; i++) {
        await db.insert('masters', {
          'list_type': type,
          'name': names[i],
          'sort_order': i,
        });
      }
    }

    await seed('floor', ['지하', '1층', '2층', '3층', '옥상']);
    await seed('place_large', [
      '현관',
      '거실',
      '주방',
      '큰방',
      '작은방',
      '욕실',
      '발코니',
      '창고',
    ]);
    await _seedCategory(db);
  }

  Future<void> _seedCategory(Database db) async {
    const names = ['인테리어', '공구', '수도', '전기', '기타'];
    for (var i = 0; i < names.length; i++) {
      await db.insert(
        'masters',
        {'list_type': 'category', 'name': names[i], 'sort_order': i},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  Future<List<String>> masterNames(String listType) async {
    final db = await database;
    final rows = await db.query(
      'masters',
      where: 'list_type = ?',
      whereArgs: [listType],
      orderBy: 'sort_order, id',
    );
    return rows.map((r) => r['name'] as String).toList();
  }

  Future<void> addMaster(String listType, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final db = await database;
    final maxRow = await db.rawQuery(
      'SELECT MAX(sort_order) AS m FROM masters WHERE list_type = ?',
      [listType],
    );
    final next = ((maxRow.first['m'] as int?) ?? -1) + 1;
    await db.insert(
      'masters',
      {'list_type': listType, 'name': trimmed, 'sort_order': next},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> ensureMaster(String listType, String name) async {
    if (name.trim().isEmpty) return;
    await addMaster(listType, name);
  }

  Future<void> updateMasterName(int id, String newName) async {
    final db = await database;
    await db.update(
      'masters',
      {'name': newName.trim()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteMaster(int id) async {
    final db = await database;
    await db.delete('masters', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> moveMaster(int id, int delta) async {
    final db = await database;
    final rows = await db.query('masters', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return;
    final row = rows.first;
    final type = row['list_type'] as String;
    final order = row['sort_order'] as int;
    final targetOrder = order + delta;
    final other = (await db.rawQuery(
      'SELECT id FROM masters WHERE list_type = ? AND sort_order = ? AND id != ?',
      [type, targetOrder, id],
    )).firstOrNull;
    await db.transaction((txn) async {
      if (other != null) {
        await txn.update(
          'masters',
          {'sort_order': order},
          where: 'id = ?',
          whereArgs: [other['id']],
        );
      }
      await txn.update(
        'masters',
        {'sort_order': targetOrder},
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  Future<int> insertItem(InventoryItem item) async {
    final db = await database;
    final map = item.toMap()..remove('id');
    return db.insert('items', map);
  }

  Future<void> updateItem(InventoryItem item) async {
    final db = await database;
    await db.update('items', item.toMap(), where: 'id = ?', whereArgs: [item.id]);
  }

  Future<void> deleteItem(int id) async {
    final db = await database;
    await db.delete('items', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteItems(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await database;
    await db.delete(
      'items',
      where: 'id IN (${ids.map((_) => '?').join(',')})',
      whereArgs: ids,
    );
  }

  Future<void> deleteAllItems() async {
    final db = await database;
    await db.delete('items');
  }

  Future<List<InventoryItem>> searchItems({
    String itemName = '',
    String category = '',
    String floor = '',
    String placeLarge = '',
    String placeMedium = '',
    String placeSmall = '',
    String keyword = '',
  }) async {
    final db = await database;
    final where = <String>[];
    final args = <Object?>[];
    void eq(String column, String value) {
      if (value.isNotEmpty) {
        where.add('$column = ?');
        args.add(value);
      }
    }

    eq('item_name', itemName);
    eq('category', category);
    eq('floor', floor);
    eq('place_large', placeLarge);
    eq('place_medium', placeMedium);
    eq('place_small', placeSmall);
    if (keyword.isNotEmpty) {
      where.add(
        "(item_name LIKE ? OR category LIKE ? OR floor LIKE ? "
        "OR place_large LIKE ? OR place_medium LIKE ? OR place_small LIKE ? "
        "OR note LIKE ? OR IFNULL(expiry_date, '') LIKE ? "
        "OR CAST(quantity AS TEXT) LIKE ?)",
      );
      final like = '%$keyword%';
      args.addAll(List.filled(9, like));
    }
    final rows = await db.query(
      'items',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: where.isEmpty ? null : args,
      orderBy: 'item_name COLLATE NOCASE, floor, place_large',
    );
    return rows.map(InventoryItem.fromMap).toList();
  }

  Future<List<String>> distinctItemNames() async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT DISTINCT item_name FROM items ORDER BY item_name COLLATE NOCASE',
    );
    return rows.map((r) => r['item_name'] as String).toList();
  }

  Future<int> batchUpdateFields(List<int> ids, Map<String, String> updates) async {
    if (ids.isEmpty || updates.isEmpty) return 0;
    const allowed = {
      'item_name',
      'category',
      'floor',
      'place_large',
      'place_medium',
      'place_small',
    };
    final data = <String, Object>{
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    };
    for (final e in updates.entries) {
      if (allowed.contains(e.key)) data[e.key] = e.value;
    }
    final db = await database;
    return db.update(
      'items',
      data,
      where: 'id IN (${ids.map((_) => '?').join(',')})',
      whereArgs: ids,
    );
  }

  Future<int> countItems() async {
    final db = await database;
    final r = await db.rawQuery('SELECT COUNT(*) AS c FROM items');
    return Sqflite.firstIntValue(r) ?? 0;
  }

  Future<List<InventoryItem>> allItems() async {
    final db = await database;
    final rows = await db.query('items', orderBy: 'item_name COLLATE NOCASE');
    return rows.map(InventoryItem.fromMap).toList();
  }
}
