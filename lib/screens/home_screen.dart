import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../db/database_helper.dart';
import '../models/inventory_item.dart';
import '../services/excel_service.dart';
import '../services/photo_service.dart';
import '../utils/format.dart';
import 'batch_edit_screen.dart';
import 'item_edit_screen.dart';
import 'settings_screen.dart';

enum _SearchMode { all, detail, keyword }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _keywordController = TextEditingController();

  _SearchMode _mode = _SearchMode.all;

  List<String> _itemOptions = [];
  List<String> _categoryOptions = [];
  List<String> _floorOptions = [];
  List<String> _largeOptions = [];
  List<String> _mediumOptions = [];
  List<String> _smallOptions = [];

  String _fItem = '';
  String _fCategory = '';
  String _fFloor = '';
  String _fLarge = '';
  String _fMedium = '';
  String _fSmall = '';

  List<InventoryItem> _results = [];
  bool _searched = false;
  bool _selectMode = false;
  final Set<int> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _loadMasters();
  }

  @override
  void dispose() {
    _keywordController.dispose();
    super.dispose();
  }

  Future<void> _loadMasters() async {
    final db = DatabaseHelper.instance;
    final items = await db.masterNames('item');
    final categories = await db.masterNames('category');
    final floors = await db.masterNames('floor');
    final large = await db.masterNames('place_large');
    final medium = await db.masterNames('place_medium');
    final small = await db.masterNames('place_small');
    if (!mounted) return;
    setState(() {
      _itemOptions = items;
      _categoryOptions = categories;
      _floorOptions = floors;
      _largeOptions = large;
      _mediumOptions = medium;
      _smallOptions = small;
    });
  }

  Future<void> _search() async {
    final db = DatabaseHelper.instance;
    final List<InventoryItem> results;
    switch (_mode) {
      case _SearchMode.all:
        results = await db.searchItems();
      case _SearchMode.detail:
        results = await db.searchItems(
          itemName: _fItem,
          category: _fCategory,
          floor: _fFloor,
          placeLarge: _fLarge,
          placeMedium: _fMedium,
          placeSmall: _fSmall,
        );
      case _SearchMode.keyword:
        results = await db.searchItems(
          keyword: _keywordController.text.trim(),
        );
    }
    if (!mounted) return;
    setState(() {
      _results = results;
      _searched = true;
      _selectMode = false;
      _selectedIds.clear();
    });
  }

  Future<void> _openEdit([InventoryItem? item]) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => ItemEditScreen(item: item)),
    );
    if (changed == true) {
      await _loadMasters();
      await _search();
    }
  }

  Future<void> _openBatchEdit() async {
    final items =
        _results.where((e) => _selectedIds.contains(e.id)).toList();
    if (items.isEmpty) return;
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => BatchEditScreen(items: items)),
    );
    if (changed == true) {
      await _loadMasters();
      await _search();
    }
  }

  Future<void> _deleteSelected() async {
    final items =
        _results.where((e) => _selectedIds.contains(e.id)).toList();
    if (items.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('삭제 확인'),
        content: Text('선택한 ${items.length}건을 삭제할까요?'),
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
    final db = DatabaseHelper.instance;
    await db.deleteItems(items.map((e) => e.id!).toList());
    for (final item in items) {
      await PhotoService.deleteFile(item.photoPath);
    }
    await _search();
  }

  void _toggleSelect(InventoryItem item) {
    final id = item.id;
    if (id == null) return;
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  Future<void> _importMenu() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text('일괄등록 (엑셀)'),
              subtitle: Text('양식 파일을 받거나, 작성한 엑셀 파일을 가져옵니다'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('엑셀 양식 파일 받기'),
              onTap: () => Navigator.of(ctx).pop('template'),
            ),
            ListTile(
              leading: const Icon(Icons.file_upload_outlined),
              title: const Text('엑셀 파일 가져오기'),
              onTap: () => Navigator.of(ctx).pop('import'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'template') {
      try {
        final name = await ExcelService.exportTemplate();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  name == null ? '양식 저장이 취소되었습니다' : '양식 저장됨: $name'),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('양식 생성 실패: $e')));
        }
      }
      return;
    }
    await _importExcel();
  }

  /// 교체 모드 가져오기 전 확인 대화상자 (주의 문구 + 취소)
  Future<bool> _confirmReplaceImport() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('가져오기 확인'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '가져오기를 실행하면 기존에 등록된 물품 정보가 모두 삭제되고 '
              '엑셀 파일의 내용으로 교체됩니다.',
            ),
            SizedBox(height: 8),
            Text('물품에 첨부된 사진도 함께 삭제되며 되돌릴 수 없습니다.'),
            SizedBox(height: 8),
            Text(
              '기존 정보가 필요하면 먼저 엑셀 내보내기로 백업하세요.',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('교체'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _importExcel() async {
    final confirmed = await _confirmReplaceImport();
    if (!confirmed || !mounted) return;
    try {
      final result = await ExcelService.importFromPicker();
      if (!mounted || (result.inserted == 0 && result.errors.isEmpty)) {
        return;
      }
      await _loadMasters();
      await _search();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('일괄등록 결과'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(result.replaced > 0
                    ? '기존 ${result.replaced}건을 삭제하고 ${result.inserted}건을 등록했습니다'
                    : '${result.inserted}건이 등록되었습니다'),
                if (result.errors.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    '제외 ${result.errors.length}건',
                    style: Theme.of(ctx).textTheme.titleSmall,
                  ),
                  SizedBox(
                    height: 160,
                    child: ListView.builder(
                      itemCount: result.errors.length,
                      itemBuilder: (_, i) => Text(
                        result.errors[i],
                        style: Theme.of(ctx).textTheme.bodySmall,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('확인'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('가져오기 실패: $e')));
      }
    }
  }

  Future<void> _exportExcel() async {
    try {
      final name = await ExcelService.exportAll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                name == null ? '내보내기가 취소되었습니다' : '내보내기 저장됨: $name'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('내보내기 실패: $e')));
      }
    }
  }

  Future<void> _openYoutube() async {
    final uri = Uri.parse('https://www.youtube.com/@ndokhak');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('어디소 (udiso)'),
        actions: [
          IconButton(
            tooltip: '일괄등록',
            icon: const Icon(Icons.file_upload_outlined),
            onPressed: _importMenu,
          ),
          IconButton(
            tooltip: '엑셀 내보내기',
            icon: const Icon(Icons.file_download_outlined),
            onPressed: _exportExcel,
          ),
          if (_searched && _results.isNotEmpty)
            IconButton(
              tooltip: _selectMode ? '선택 해제' : '선택',
              icon: Icon(_selectMode ? Icons.close : Icons.checklist),
              onPressed: () {
                setState(() {
                  _selectMode = !_selectMode;
                  _selectedIds.clear();
                });
              },
            ),
          IconButton(
            tooltip: '설정',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
              await _loadMasters();
              await _search();
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEdit(),
        icon: const Icon(Icons.add),
        label: const Text('등록'),
      ),
      bottomNavigationBar: _selectMode
          ? BottomAppBar(
              height: 64,
              child: Row(
                children: [
                  Text(
                    '선택 ${_selectedIds.length}건',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const Spacer(),
                  FilledButton.tonal(
                    onPressed: _selectedIds.isEmpty ? null : _openBatchEdit,
                    child: const Text('일괄수정'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _selectedIds.isEmpty ? null : _deleteSelected,
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error,
                    ),
                    child: const Text('삭제'),
                  ),
                ],
              ),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<_SearchMode>(
                  segments: const [
                    ButtonSegment(
                      value: _SearchMode.all,
                      label: Text('전체'),
                      icon: Icon(Icons.apps),
                    ),
                    ButtonSegment(
                      value: _SearchMode.detail,
                      label: Text('세부'),
                      icon: Icon(Icons.tune),
                    ),
                    ButtonSegment(
                      value: _SearchMode.keyword,
                      label: Text('키워드'),
                      icon: Icon(Icons.search),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (s) => setState(() => _mode = s.first),
                ),
                const SizedBox(height: 12),
                if (_mode == _SearchMode.detail) ...[
                  _detailDropdown('품목', _itemOptions, _fItem,
                      (v) => setState(() => _fItem = v)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _detailDropdown(
                            '층', _floorOptions, _fFloor, (v) => setState(() => _fFloor = v)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _detailDropdown('장소1', _largeOptions, _fLarge,
                            (v) => setState(() => _fLarge = v)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _detailDropdown('장소2', _mediumOptions, _fMedium,
                            (v) => setState(() => _fMedium = v)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _detailDropdown('장소3', _smallOptions, _fSmall,
                            (v) => setState(() => _fSmall = v)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _detailDropdown('분류', _categoryOptions, _fCategory,
                      (v) => setState(() => _fCategory = v)),
                ],
                if (_mode == _SearchMode.keyword)
                  TextField(
                    controller: _keywordController,
                    decoration: const InputDecoration(
                      labelText: '키워드',
                      hintText: '모든 항목에서 검색 (예: 1층, 발코니, 필터)',
                      prefixIcon: Icon(Icons.search),
                    ),
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _search(),
                  ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _search,
                  icon: const Icon(Icons.search),
                  label: Text(_mode == _SearchMode.all ? '전체 조회' : '찾기'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _buildResults()),
          if (_mode == _SearchMode.keyword)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(
                        onTap: _openYoutube,
                        borderRadius: BorderRadius.circular(12),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.asset(
                            'assets/ndokhak_optimized.png',
                            width: 200,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => Image.asset(
                              'requirements/ndokhak.png',
                              width: 200,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      InkWell(
                        onTap: _openYoutube,
                        child: Text(
                          '유튜브채널 N독학러',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _detailDropdown(
    String label,
    List<String> options,
    String value,
    ValueChanged<String> onChanged,
  ) {
    return DropdownButtonFormField<String>(
      value: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        isDense: true,
      ),
      items: [
        const DropdownMenuItem(
          value: '',
          child: Text('전체', style: TextStyle(color: Colors.grey)),
        ),
        ...options.map(
          (o) => DropdownMenuItem(value: o, child: Text(o)),
        ),
      ],
      onChanged: (v) => onChanged(v ?? ''),
    );
  }

  Widget _buildResults() {
    if (!_searched) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.travel_explore, size: 64, color: Colors.grey),
            SizedBox(height: 12),
            Text('조건을 선택해 물건을 찾아보세요'),
          ],
        ),
      );
    }
    if (_results.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: Colors.grey),
            SizedBox(height: 12),
            Text('검색 결과가 없습니다'),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final item = _results[index];
        final selected = _selectedIds.contains(item.id);
        final expired = isExpiredYmd(item.expiryDate);
        final expiryLabel = formatExpiryLabel(item.expiryDate);
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          color: selected
              ? Theme.of(context).colorScheme.primaryContainer
              : null,
          child: ListTile(
            leading: _selectMode
                ? Checkbox(
                    value: selected,
                    onChanged: (_) => _toggleSelect(item),
                  )
                : (item.photoPath != null &&
                        File(item.photoPath!).existsSync()
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.file(
                          File(item.photoPath!),
                          width: 44,
                          height: 44,
                          fit: BoxFit.cover,
                        ),
                      )
                    : CircleAvatar(
                        child: Text(
                          item.quantity.toString(),
                          style: const TextStyle(fontSize: 14),
                        ),
                      )),
            title: Text(
              item.itemName,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text([
                  if (item.category.isNotEmpty) item.category,
                  item.locationText,
                ].join(' · ')),
                if (item.note.isNotEmpty)
                  Text(
                    item.note,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
            trailing: expiryLabel.isEmpty
                ? null
                : Chip(
                    label: Text(
                      expiryLabel,
                      style: TextStyle(
                        fontSize: 11,
                        color: expired
                            ? Theme.of(context).colorScheme.error
                            : null,
                      ),
                    ),
                    visualDensity: VisualDensity.compact,
                    side: expired
                        ? BorderSide(color: Theme.of(context).colorScheme.error)
                        : null,
                  ),
            onTap: () {
              if (_selectMode) {
                _toggleSelect(item);
              } else {
                _openEdit(item);
              }
            },
            onLongPress: () {
              if (!_selectMode) {
                setState(() => _selectMode = true);
              }
              _toggleSelect(item);
            },
          ),
        );
      },
    );
  }
}
