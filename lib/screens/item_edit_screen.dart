import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../db/database_helper.dart';
import '../models/inventory_item.dart';
import '../services/photo_service.dart';
import '../utils/format.dart';
import '../widgets/master_dropdown.dart';
import 'manage_list_screen.dart';

class ItemEditScreen extends StatefulWidget {
  const ItemEditScreen({super.key, this.item});

  final InventoryItem? item;

  @override
  State<ItemEditScreen> createState() => _ItemEditScreenState();
}

class _ItemEditScreenState extends State<ItemEditScreen> {
  final _formKey = GlobalKey<FormState>();
  TextEditingController? _autoNameController;
  late final TextEditingController _quantityController;
  late final TextEditingController _noteController;
  late final TextEditingController _expiryController;

  List<String> _itemMasterNames = [];
  List<String> _categoryList = [];
  String _category = '';
  String _floor = '';
  String _placeLarge = '';
  String _placeMedium = '';
  String _placeSmall = '';
  String? _expiryDate;

  String? _photoPath;
  String? _originalPhotoPath;
  bool _photoChanged = false;
  bool _nameInitialized = false;

  bool get _isEdit => widget.item != null;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _quantityController =
        TextEditingController(text: (item?.quantity ?? 1).toString());
    _noteController = TextEditingController(text: item?.note ?? '');
    _expiryController =
        TextEditingController(text: formatExpiryLabel(item?.expiryDate));
    _category = item?.category ?? '';
    _categoryList = _category
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    _floor = item?.floor ?? '';
    _placeLarge = item?.placeLarge ?? '';
    _placeMedium = item?.placeMedium ?? '';
    _placeSmall = item?.placeSmall ?? '';
    _expiryDate = item?.expiryDate;
    _photoPath = item?.photoPath;
    _originalPhotoPath = item?.photoPath;
    _loadItemMasters();
  }

  Future<void> _loadItemMasters() async {
    final names = await DatabaseHelper.instance.masterNames('item');
    if (!mounted) return;
    setState(() => _itemMasterNames = names);
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _noteController.dispose();
    _expiryController.dispose();
    if (_photoChanged &&
        _photoPath != null &&
        _photoPath != _originalPhotoPath) {
      PhotoService.deleteFile(_photoPath);
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final initial = tryParseYmd(_expiryDate ?? '') ??
        DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _expiryDate = ymd(picked);
        _expiryController.text = formatExpiryLabel(_expiryDate);
      });
    }
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 95,
      );
      if (picked == null) return;
      final newPath = await PhotoService.compressAndSave(picked);
      if (newPath == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('사진 처리에 실패했습니다')),
          );
        }
        return;
      }
      final old = _photoPath;
      setState(() {
        _photoPath = newPath;
        _photoChanged = true;
      });
      if (old != null && old != _originalPhotoPath) {
        PhotoService.deleteFile(old);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('사진 등록 실패: $e')));
      }
    }
  }

  void _syncCategory() {
    _category = _categoryList.join(',');
  }

  Future<void> _pickCategories() async {
    final db = DatabaseHelper.instance;
    final all = await db.masterNames('category');
    if (!mounted) return;
    final selected = List<String>.from(_categoryList);
    final result = await showDialog<List<String>>(
      context: context,
      builder: (ctx) {
        var tmp = List<String>.from(selected);
        return StatefulBuilder(
          builder: (ctx, setDlg) => AlertDialog(
            title: const Text('분류 선택'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView(
                shrinkWrap: true,
                children: [
                  ...all.map((c) => CheckboxListTile(
                        value: tmp.contains(c),
                        title: Text(c),
                        onChanged: (v) {
                          setDlg(() {
                            if (v == true) {
                              if (!tmp.contains(c)) tmp.add(c);
                            } else {
                              tmp.remove(c);
                            }
                          });
                        },
                      )),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  Navigator.of(ctx).pop();
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ManageListScreen(
                        listType: 'category',
                        title: '분류',
                      ),
                    ),
                  );
                  await _loadItemMasters();
                  if (!mounted) return;
                  setState(() {});
                },
                child: const Text('목록관리'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(tmp),
                child: const Text('확인'),
              ),
            ],
          ),
        );
      },
    );
    if (result == null) return;
    setState(() {
      _categoryList = result
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      _syncCategory();
    });
  }

  void _removePhoto() {
    final old = _photoPath;
    setState(() {
      _photoPath = null;
      _photoChanged = true;
    });
    if (old != null && old != _originalPhotoPath) {
      PhotoService.deleteFile(old);
    }
  }

  void _viewPhoto() {
    final path = _photoPath;
    if (path == null) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: InteractiveViewer(
          child: Image.file(File(path)),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final name = (_autoNameController?.text ?? '').trim();
    if (name.isEmpty) return;
    final quantity = int.tryParse(_quantityController.text.trim()) ?? 1;
    final db = DatabaseHelper.instance;
    final now = DateTime.now().millisecondsSinceEpoch;

    final item = InventoryItem(
      id: widget.item?.id,
      itemName: name,
      category: _category,
      floor: _floor,
      placeLarge: _placeLarge,
      placeMedium: _placeMedium,
      placeSmall: _placeSmall,
      quantity: quantity,
      expiryDate: _expiryDate,
      note: _noteController.text.trim(),
      photoPath: _photoPath,
      createdAt: widget.item?.createdAt ?? now,
      updatedAt: now,
    );

    if (_isEdit) {
      await db.updateItem(item);
    } else {
      await db.insertItem(item);
    }
    await db.ensureMaster('item', item.itemName);
    await db.ensureMaster('category', item.category);
    await db.ensureMaster('floor', item.floor);
    await db.ensureMaster('place_large', item.placeLarge);
    await db.ensureMaster('place_medium', item.placeMedium);
    await db.ensureMaster('place_small', item.placeSmall);

    if (_originalPhotoPath != null &&
        _originalPhotoPath != _photoPath) {
      PhotoService.deleteFile(_originalPhotoPath);
    }
    _originalPhotoPath = _photoPath;
    _photoChanged = false;

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _delete() async {
    final item = widget.item;
    if (item?.id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('삭제 확인'),
        content: Text('"${item!.itemName}" 항목을 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final db = DatabaseHelper.instance;
    await db.deleteItem(item!.id!);
    await PhotoService.deleteFile(item.photoPath);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? '수정' : '등록'),
        actions: [
          TextButton(onPressed: _save, child: const Text('저장')),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Autocomplete<String>(
              optionsBuilder: (textEditingValue) {
                final q = textEditingValue.text.toLowerCase();
                return _itemMasterNames
                    .where((n) => n.toLowerCase().contains(q));
              },
              fieldViewBuilder:
                  (context, controller, focusNode, onFieldSubmitted) {
                _autoNameController = controller;
                if (!_nameInitialized) {
                  _nameInitialized = true;
                  controller.text = widget.item?.itemName ?? '';
                }
                return TextFormField(
                  controller: controller,
                  focusNode: focusNode,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: '품목 *',
                    prefixIcon: Icon(Icons.inventory_2_outlined),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? '품목을 입력하세요' : null,
                );
              },
              optionsMaxHeight: 200,
            ),
            const SizedBox(height: 12),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: MasterDropdown(
                    listType: 'floor',
                    label: '층',
                    value: _floor,
                    onChanged: (v) => setState(() => _floor = v),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: MasterDropdown(
                    listType: 'place_large',
                    label: '장소1',
                    value: _placeLarge,
                    hint: '예: 큰방, 발코니, 창고',
                    onChanged: (v) => setState(() => _placeLarge = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: MasterDropdown(
                    listType: 'place_medium',
                    label: '장소2',
                    value: _placeMedium,
                    hint: '예: 옷장, 선반',
                    onChanged: (v) => setState(() => _placeMedium = v),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: MasterDropdown(
                    listType: 'place_small',
                    label: '장소3',
                    value: _placeSmall,
                    hint: '예: 상단 칸, 서랍 3',
                    onChanged: (v) => setState(() => _placeSmall = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: '분류',
                      border: OutlineInputBorder(),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            ..._categoryList.map((c) => InputChip(
                                  label: Text(c, overflow: TextOverflow.ellipsis),
                                  onDeleted: () {
                                    setState(() {
                                      _categoryList.remove(c);
                                      _syncCategory();
                                    });
                                  },
                                )),
                            ActionChip(
                              label: const Text('+ 분류 추가'),
                              onPressed: _pickCategories,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _quantityController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    maxLength: 3,
                    decoration: const InputDecoration(
                      labelText: '수량',
                      prefixIcon: Icon(Icons.numbers),
                      counterText: '',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              readOnly: true,
              controller: _expiryController,
              onTap: _pickDate,
              decoration: InputDecoration(
                labelText: '유효기한',
                prefixIcon: const Icon(Icons.calendar_today_outlined),
                suffixIcon: _expiryDate == null
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() {
                          _expiryDate = null;
                          _expiryController.clear();
                        }),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _noteController,
              maxLines: null,
              minLines: 1,
              keyboardType: TextInputType.multiline,
              maxLength: 100,
              decoration: const InputDecoration(
                labelText: '비고',
                alignLabelWithHint: true,
                counterText: '',
              ),
            ),
            const SizedBox(height: 16),
            Text('사진', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_photoPath != null)
                  InkWell(
                    onTap: _viewPhoto,
                    borderRadius: BorderRadius.circular(8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        File(_photoPath!),
                        width: 96,
                        height: 96,
                        fit: BoxFit.cover,
                      ),
                    ),
                  )
                else
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.photo_outlined,
                      color: Colors.grey,
                    ),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _pickPhoto(ImageSource.camera),
                        icon: const Icon(Icons.camera_alt_outlined, size: 18),
                        label: const Text('촬영'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _pickPhoto(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library_outlined, size: 18),
                        label: const Text('앨범'),
                      ),
                      if (_photoPath != null)
                        OutlinedButton.icon(
                          onPressed: _removePhoto,
                          icon: const Icon(Icons.delete_outline, size: 18),
                          label: const Text('삭제'),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                if (_isEdit) ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _delete,
                      icon: Icon(
                        Icons.delete_outline,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      label: Text(
                        '삭제',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('저장'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
