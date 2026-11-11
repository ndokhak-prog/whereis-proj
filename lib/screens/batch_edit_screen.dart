import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../models/inventory_item.dart';
import '../widgets/master_dropdown.dart';

class BatchEditScreen extends StatefulWidget {
  const BatchEditScreen({super.key, required this.items});

  final List<InventoryItem> items;

  @override
  State<BatchEditScreen> createState() => _BatchEditScreenState();
}

class _BatchEditScreenState extends State<BatchEditScreen> {
  static const _fields = <String, String>{
    'floor': '층',
    'place_large': '장소1',
    'place_medium': '장소2',
    'place_small': '장소3',
    'category': '분류',
    'item_name': '품목',
  };

  String _field = 'floor';
  String _value = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('일괄수정 (${widget.items.length}건)')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '대상',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.items
                        .map((e) => '${e.itemName} (${e.locationText})')
                        .join(', '),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('변경 항목', style: Theme.of(context).textTheme.titleMedium),
          ..._fields.entries.map(
            (e) => RadioListTile<String>(
              value: e.key,
              groupValue: _field,
              title: Text(e.value),
              onChanged: (v) {
                if (v == null) return;
                setState(() {
                  _field = v;
                  _value = '';
                });
              },
            ),
          ),
          const Divider(),
          const SizedBox(height: 8),
          if (_field == 'item_name')
            TextFormField(
              initialValue: _value,
              decoration: const InputDecoration(labelText: '새 품목'),
              onChanged: (v) => _value = v,
            )
          else
            MasterDropdown(
              listType: _field,
              label: '새 ${_fields[_field]}',
              value: _value,
              hint: '변경값 선택 또는 추가',
              onChanged: (v) => _value = v,
            ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _apply,
            icon: const Icon(Icons.done_all),
            label: Text('${widget.items.length}건 적용'),
          ),
        ],
      ),
    );
  }

  Future<void> _apply() async {
    final newValue = _value.trim();
    if (newValue.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('변경값을 입력하세요')),
      );
      return;
    }
    final fieldName = _fields[_field]!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('일괄수정 확인'),
        content: Text(
          '${widget.items.length}건의 $fieldName(을)를 "$newValue"(으)로 변경할까요?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('변경'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final ids = widget.items
        .map((e) => e.id)
        .whereType<int>()
        .toList();
    final count = await DatabaseHelper.instance
        .batchUpdateFields(ids, {_field: newValue});
    if (_field == 'item_name') {
      await DatabaseHelper.instance.ensureMaster('item', newValue);
    } else {
      await DatabaseHelper.instance.ensureMaster(_field, newValue);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$count건이 변경되었습니다')),
    );
    Navigator.of(context).pop(true);
  }
}
