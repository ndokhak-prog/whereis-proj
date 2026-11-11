import 'package:flutter/material.dart';

import '../db/database_helper.dart';

const kAddMasterSentinel = '➕ 추가...';

class MasterDropdown extends StatefulWidget {
  const MasterDropdown({
    super.key,
    required this.listType,
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint,
    this.required = false,
  });

  final String listType;
  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final String? hint;
  final bool required;

  @override
  State<MasterDropdown> createState() => _MasterDropdownState();
}

class _MasterDropdownState extends State<MasterDropdown> {
  List<String> _names = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final names = await DatabaseHelper.instance.masterNames(widget.listType);
    if (!mounted) return;
    setState(() => _names = names);
  }

  Future<void> _addNew() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${widget.label} 추가'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: widget.label),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('추가'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || name == kAddMasterSentinel) return;
    await DatabaseHelper.instance.addMaster(widget.listType, name);
    await _load();
    if (!mounted) return;
    widget.onChanged(name);
  }

  @override
  Widget build(BuildContext context) {
    final items = <String>[
      ..._names,
      if (widget.value.isNotEmpty && !_names.contains(widget.value))
        widget.value,
      kAddMasterSentinel,
    ];
    final current = items.contains(widget.value) ? widget.value : null;
    return DropdownButtonFormField<String>(
      value: current,
      isExpanded: true,
      isDense: true,
      decoration: InputDecoration(
        labelText: widget.required ? '${widget.label} *' : widget.label,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        isDense: true,
      ),
      hint: Text(widget.hint ?? '${widget.label} 선택', overflow: TextOverflow.ellipsis),
      items: items
          .map((n) => DropdownMenuItem(
                value: n,
                child: Text(n, overflow: TextOverflow.ellipsis, maxLines: 1),
              ))
          .toList(),
      onChanged: (v) {
        if (v == null) return;
        if (v == kAddMasterSentinel) {
          _addNew();
        } else {
          widget.onChanged(v);
        }
      },
    );
  }
}
