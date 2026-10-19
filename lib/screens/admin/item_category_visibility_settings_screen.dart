import 'package:flutter/material.dart';
import 'package:Orderx/core/theme/app_theme.dart';
import 'package:Orderx/services/admin_settings_service.dart';
import 'package:Orderx/services/product_service.dart';
import 'package:Orderx/utils/item_category_visibility.dart';

class ItemCategoryVisibilitySettingsScreen extends StatefulWidget {
  final String companyId;

  const ItemCategoryVisibilitySettingsScreen({
    super.key,
    required this.companyId,
  });

  @override
  State<ItemCategoryVisibilitySettingsScreen> createState() =>
      _ItemCategoryVisibilitySettingsScreenState();
}

class _ItemCategoryVisibilitySettingsScreenState
    extends State<ItemCategoryVisibilitySettingsScreen> {
  final AdminSettingsService _settingsService = AdminSettingsService();
  final ProductService _productService = ProductService();
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  String? _error;
  List<String> _allCategories = [];
  final Set<String> _hiddenNames = {};
  String _query = '';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final catalog = await _productService.getItemCategoryCatalog(
        companyId: widget.companyId,
      );
      final hidden =
          await _settingsService.getHiddenItemCategoryNames(widget.companyId);
      if (!mounted) return;
      setState(() {
        _allCategories = [
          ...catalog.names,
          if (catalog.hasUngrouped) ungroupedItemCategoryKey,
        ];
        _hiddenNames
          ..clear()
          ..addAll(hidden);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  List<String> get _visibleCategories {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _allCategories;
    return _allCategories.where((name) {
      return _labelFor(name).toLowerCase().contains(q);
    }).toList();
  }

  String _labelFor(String name) {
    if (name == ungroupedItemCategoryKey) return ungroupedItemCategoryLabel;
    return name;
  }

  int get _enabledCount =>
      _allCategories.where((name) => !_hiddenNames.contains(name)).length;

  Future<void> _setCategoryEnabled(String name, bool enabled) async {
    final previous = Set<String>.from(_hiddenNames);
    setState(() {
      if (enabled) {
        _hiddenNames.remove(name);
      } else {
        _hiddenNames.add(name);
      }
    });
    await _persist(previous);
  }

  Future<void> _setAllEnabled(bool enabled) async {
    final previous = Set<String>.from(_hiddenNames);
    setState(() {
      _hiddenNames.clear();
      if (!enabled) {
        _hiddenNames.addAll(_allCategories);
      }
    });
    await _persist(previous);
  }

  Future<void> _persist(Set<String> previous) async {
    setState(() => _saving = true);
    try {
      await _settingsService.saveHiddenItemCategoryNames(
        widget.companyId,
        _hiddenNames.toList(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Item category visibility saved'),
          backgroundColor: AppTheme.success,
          duration: Duration(seconds: 1),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _hiddenNames
          ..clear()
          ..addAll(previous);
      });
      final err = e.toString();
      final missingColumn = err.contains('PGRST204') &&
          err.contains('hidden_stock_group_names');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            missingColumn
                ? 'Failed to save: add hidden_stock_group_names to company_settings in Supabase, then try again.'
                : 'Failed to save item category visibility: $e',
          ),
          backgroundColor: AppTheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Item Category Visibility'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : Column(
                  children: [
                    _buildHeader(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Search item categories',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _query.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _query = '');
                                  },
                                ),
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (value) => setState(() => _query = value),
                      ),
                    ),
                    if (_saving) const LinearProgressIndicator(minHeight: 2),
                    Expanded(
                      child: _visibleCategories.isEmpty
                          ? const Center(
                              child: Text('No item categories found'),
                            )
                          : ListView.separated(
                              itemCount: _visibleCategories.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final name = _visibleCategories[index];
                                final enabled = !_hiddenNames.contains(name);
                                return SwitchListTile(
                                  title: Text(_labelFor(name)),
                                  subtitle: Text(
                                    enabled
                                        ? 'Visible in order item selection'
                                        : 'Hidden from order item selection',
                                  ),
                                  value: enabled,
                                  activeThumbColor: AppTheme.primaryBlue,
                                  onChanged: (value) =>
                                      _setCategoryEnabled(name, value),
                                );
                              },
                            ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$_enabledCount of ${_allCategories.length} item categories enabled',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          const Text(
            'Disabled item categories are not shown on order creation item select pages.',
            style: TextStyle(fontSize: 13, color: AppTheme.grey),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                onPressed: _allCategories.isEmpty
                    ? null
                    : () => _setAllEnabled(true),
                child: const Text('Enable all'),
              ),
              OutlinedButton(
                onPressed: _allCategories.isEmpty
                    ? null
                    : () => _setAllEnabled(false),
                child: const Text('Disable all'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error ?? 'Failed to load item categories'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _load,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
