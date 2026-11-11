import 'package:flutter/material.dart';

import '../db/database_helper.dart';

class ManageListScreen extends StatefulWidget {
  const ManageListScreen({
    super.key,
    required this.listType,
    required this.title,
  });

  final String listType;
  final String title;

  @override
  State<ManageListScreen> createState() => _ManageListScreenState();
}

class _ManageListScreenState extends State<ManageListScreen> {
  List<String> _names = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = DatabaseHelper.instance;
    final names = await db.masterNames(widget.listType);
    if (!mounted) return;
    setState(() => _names = names);
  }

  Future<int?> _idOf(String name) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'masters',
      columns: ['id'],
      where: 'list_type = ? AND name = ?',
      whereArgs: [widget.listType, name],
    );
    return rows.firstOrNull?['id'] as int?;
  }

  Future<void> _add() async {
    final name = await _promptName('추가');
    if (name == null || name.isEmpty) return;
    await DatabaseHelper.instance.addMaster(widget.listType, name);
    await _load();
  }

  Future<void> _rename(String oldName) async {
    final name = await _promptName('수정', initial: oldName);
    if (name == null || name.isEmpty || name == oldName) return;
    final id = await _idOf(oldName);
    if (id == null) return;
    await DatabaseHelper.instance.updateMasterName(id, name);
    await _load();
  }

  Future<void> _delete(String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('삭제 확인'),
        content: Text('"$name" 항목을 목록에서 삭제할까요?\n(이미 입력된 자료는 그대로 남습니다)'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final id = await _idOf(name);
    if (id == null) return;
    await DatabaseHelper.instance.deleteMaster(id);
    await _load();
  }

  Future<void> _move(String name, int delta) async {
    final id = await _idOf(name);
    if (id == null) return;
    await DatabaseHelper.instance.moveMaster(id, delta);
    await _load();
  }

  Future<String?> _promptName(String title, {String initial = ''}) async {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${widget.title} $title'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '이름'),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('저장'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(icon: const Icon(Icons.add), onPressed: _add),
        ],
      ),
      body: _names.isEmpty
          ? const Center(child: Text('항목이 없습니다. 우측 상단 + 로 추가하세요.'))
          : ListView.builder(
              itemCount: _names.length,
              itemBuilder: (context, index) {
                final name = _names[index];
                return ListTile(
                  leading: CircleAvatar(
                    child: Text('${index + 1}',
                        style: const TextStyle(fontSize: 13)),
                  ),
                  title: Text(name),
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) {
                      switch (v) {
                        case 'rename':
                          _rename(name);
                        case 'up':
                          _move(name, -1);
                        case 'down':
                          _move(name, 1);
                        case 'delete':
                          _delete(name);
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'rename', child: Text('수정')),
                      PopupMenuItem(value: 'up', child: Text('위로')),
                      PopupMenuItem(value: 'down', child: Text('아래로')),
                      PopupMenuItem(value: 'delete', child: Text('삭제')),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
