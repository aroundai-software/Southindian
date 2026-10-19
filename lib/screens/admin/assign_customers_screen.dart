import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:Orderx/core/theme/app_theme.dart';
import 'package:Orderx/models/customer_model.dart';
import 'package:Orderx/models/user_model.dart';
import 'package:Orderx/providers/auth_provider.dart';
import 'package:Orderx/services/customer_service.dart';
import 'package:Orderx/widgets/app_bar_actions.dart';
import 'package:Orderx/widgets/error_state_widget.dart';

class AssignCustomersScreen extends StatefulWidget {
  final UserModel salesman;

  const AssignCustomersScreen({super.key, required this.salesman});

  @override
  State<AssignCustomersScreen> createState() => _AssignCustomersScreenState();
}

class _AssignCustomersScreenState extends State<AssignCustomersScreen> {
  final GlobalKey<AssignCustomersPanelState> _panelKey =
      GlobalKey<AssignCustomersPanelState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Assign Customers'),
            Text(
              widget.salesman.name,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        actions: [
          AppBarRefreshButton(
            onPressed: () => _panelKey.currentState?.reload(),
          ),
        ],
      ),
      body: AssignCustomersPanel(
        key: _panelKey,
        salesman: widget.salesman,
        popOnSave: true,
      ),
    );
  }
}

class AssignCustomersPanel extends StatefulWidget {
  final UserModel salesman;
  final bool popOnSave;
  final VoidCallback? onSaved;

  const AssignCustomersPanel({
    super.key,
    required this.salesman,
    this.popOnSave = false,
    this.onSaved,
  });

  @override
  State<AssignCustomersPanel> createState() => AssignCustomersPanelState();
}

class AssignCustomersPanelState extends State<AssignCustomersPanel> {
  static const String _allParents = '__all_parents__';
  static const String _allCategories = '__all__';
  static const String _allCustCategories = '__all_cust_categories__';

  final CustomerService _customerService = CustomerService();
  final TextEditingController _searchController = TextEditingController();

  List<CustomerModel> _allCustomers = [];
  List<CustomerModel> _filteredCustomers = [];
  String _selectedParent = _allParents;
  String _selectedCategory = _allCategories;
  String _selectedCustCategory = _allCustCategories;
  Set<String> _selectedCustomerIds = {};
  Set<String> _initiallyAssignedIds = {};
  bool _filtersVisible = false;

  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;
  String? _companyId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  @override
  void didUpdateWidget(AssignCustomersPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.salesman.id != widget.salesman.id) {
      _loadData();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> reload() => _loadData();

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final authProvider = context.read<AuthProvider>();
      _companyId = authProvider.selectedCompanyId;

      if (_companyId == null || _companyId == 'ALL') {
        throw Exception('Please select a specific company to assign customers.');
      }

      final results = await _customerService.getAllCustomers(
        companyId: _companyId,
      );

      final initiallyAssigned = results
          .where((c) => c.assignedSalesmanIds.contains(widget.salesman.id))
          .map((c) => c.id)
          .toSet();

      if (mounted) {
        setState(() {
          _allCustomers = results;
          _selectedParent = _allParents;
          _selectedCategory = _allCategories;
          _selectedCustCategory = _allCustCategories;
          _selectedCustomerIds = Set<String>.from(initiallyAssigned);
          _initiallyAssignedIds = initiallyAssigned;
          _isLoading = false;
        });
        _applyFilters();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  List<String> _sortedNames(Iterable<String> names) {
    final unique = names.toSet();
    final named = unique.where((name) => name != 'Ungrouped').toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    if (unique.contains('Ungrouped')) {
      named.add('Ungrouped');
    }
    return named;
  }

  Iterable<CustomerModel> _matching({
    bool applyParent = true,
    bool applyCategory = true,
    bool applyCustCategory = true,
  }) {
    return _allCustomers.where((customer) {
      if (applyParent &&
          _selectedParent != _allParents &&
          customer.parentGroupName != _selectedParent) {
        return false;
      }
      if (applyCategory &&
          _selectedCategory != _allCategories &&
          customer.groupName != _selectedCategory) {
        return false;
      }
      if (applyCustCategory &&
          _selectedCustCategory != _allCustCategories &&
          customer.custCategoryName != _selectedCustCategory) {
        return false;
      }
      return true;
    });
  }

  List<String> get _parentNames =>
      _sortedNames(_allCustomers.map((c) => c.parentGroupName));

  List<String> get _categoryNames =>
      _sortedNames(_allCustomers.map((c) => c.groupName));

  List<String> get _custCategoryNames =>
      _sortedNames(_allCustomers.map((c) => c.custCategoryName));

  void _applyFilters() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      _filteredCustomers = _matching().where((customer) {
        if (query.isEmpty) return true;
        return customer.customerName.toLowerCase().contains(query) ||
            (customer.mobileNumber?.toLowerCase().contains(query) ?? false) ||
            (customer.city?.toLowerCase().contains(query) ?? false) ||
            customer.groupName.toLowerCase().contains(query) ||
            customer.parentGroupName.toLowerCase().contains(query) ||
            customer.custCategoryName.toLowerCase().contains(query);
      }).toList();
    });
  }

  Future<void> _saveAssignments() async {
    if (_companyId == null) return;

    setState(() {
      _isSaving = true;
    });

    try {
      await _customerService.batchAssignCustomersToSalesman(
        salesmanId: widget.salesman.id,
        companyId: _companyId!,
        assignedCustomerIds: _selectedCustomerIds.toList(),
      );

      if (mounted) {
        setState(() {
          _initiallyAssignedIds = Set<String>.from(_selectedCustomerIds);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Customers successfully assigned!'),
            backgroundColor: AppTheme.success,
          ),
        );
        widget.onSaved?.call();
        if (widget.popOnSave) {
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error assigning customers: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  bool get _allFilteredSelected =>
      _filteredCustomers.isNotEmpty &&
      _filteredCustomers.every((c) => _selectedCustomerIds.contains(c.id));

  int get _activeFilterCount {
    var count = 0;
    if (_selectedParent != _allParents) count++;
    if (_selectedCategory != _allCategories) count++;
    if (_selectedCustCategory != _allCustCategories) count++;
    return count;
  }

  bool get _hasDropdownFilters => _activeFilterCount > 0;

  bool get _hasChanges {
    if (_selectedCustomerIds.length != _initiallyAssignedIds.length) {
      return true;
    }
    return !_selectedCustomerIds.containsAll(_initiallyAssignedIds);
  }

  void _clearDropdownFilters() {
    _selectedParent = _allParents;
    _selectedCategory = _allCategories;
    _selectedCustCategory = _allCustCategories;
    _applyFilters();
  }

  void _toggleFiltersVisible() {
    setState(() => _filtersVisible = !_filtersVisible);
  }

  void _toggleSelectAll() {
    setState(() {
      if (_allFilteredSelected) {
        for (final customer in _filteredCustomers) {
          _selectedCustomerIds.remove(customer.id);
        }
      } else {
        for (final customer in _filteredCustomers) {
          _selectedCustomerIds.add(customer.id);
        }
      }
    });
  }

  void _toggleCustomer(String id, bool? checked) {
    setState(() {
      if (checked == true) {
        _selectedCustomerIds.add(id);
      } else {
        _selectedCustomerIds.remove(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFF7F8FA),
      child: _buildBody(),
    );
  }

  InputDecoration _fieldDecoration({
    String? hint,
    Widget? prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: AppTheme.white,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFE3E6EB)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFE3E6EB)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppTheme.primaryBlue, width: 1.4),
      ),
    );
  }

  Widget _filterField({
    required String caption,
    required String value,
    required String allValue,
    required String allLabel,
    required int allCount,
    required List<String> names,
    required int Function(String name) countFor,
    required ValueChanged<String> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          caption.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
            color: AppTheme.grey,
          ),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: value,
          isExpanded: true,
          isDense: true,
          menuMaxHeight: 360,
          decoration: _fieldDecoration(),
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
          selectedItemBuilder: (context) {
            final labels = [allLabel, ...names];
            return labels
                .map(
                  (label) => Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, color: AppTheme.darkGrey),
                  ),
                )
                .toList();
          },
          items: [
            DropdownMenuItem(
              value: allValue,
              child: Text('$allLabel ($allCount)'),
            ),
            ...names.map(
              (name) => DropdownMenuItem(
                value: name,
                child: Text(
                  '$name (${countFor(name)})',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
          onChanged: (selected) {
            if (selected == null) return;
            onChanged(selected);
          },
        ),
      ],
    );
  }

  String _customerMeta(CustomerModel customer) {
    final parts = <String>[
      if (_selectedParent == _allParents) customer.parentGroupName,
      if (_selectedCategory == _allCategories) customer.groupName,
      if (_selectedCustCategory == _allCustCategories) customer.custCategoryName,
      if (customer.city != null && customer.city!.isNotEmpty) customer.city!,
    ].where((part) => part.isNotEmpty && part != 'Ungrouped').toList();
    if (parts.isEmpty) return 'Ungrouped';
    return parts.toSet().join('  ·  ');
  }

  Widget _buildToolbar() {
    final parentFilter = _filterField(
      caption: 'Parent',
      value: _selectedParent,
      allValue: _allParents,
      allLabel: 'All parents',
      allCount: _matching(applyParent: false).length,
      names: _parentNames,
      countFor: (name) => _matching(applyParent: false)
          .where((c) => c.parentGroupName == name)
          .length,
      onChanged: (value) {
        _selectedParent = value;
        _applyFilters();
      },
    );
    final categoryFilter = _filterField(
      caption: 'Category',
      value: _selectedCategory,
      allValue: _allCategories,
      allLabel: 'All categories',
      allCount: _matching(applyCategory: false).length,
      names: _categoryNames,
      countFor: (name) => _matching(applyCategory: false)
          .where((c) => c.groupName == name)
          .length,
      onChanged: (value) {
        _selectedCategory = value;
        _applyFilters();
      },
    );
    final custFilter = _filterField(
      caption: 'Cust. category',
      value: _selectedCustCategory,
      allValue: _allCustCategories,
      allLabel: 'All cust. categories',
      allCount: _matching(applyCustCategory: false).length,
      names: _custCategoryNames,
      countFor: (name) => _matching(applyCustCategory: false)
          .where((c) => c.custCategoryName == name)
          .length,
      onChanged: (value) {
        _selectedCustCategory = value;
        _applyFilters();
      },
    );

    return Container(
      width: double.infinity,
      color: AppTheme.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: (_) => _applyFilters(),
                  decoration: _fieldDecoration(
                    hint: 'Search by name, city, or group',
                    prefixIcon: const Icon(
                      Icons.search,
                      size: 20,
                      color: AppTheme.grey,
                    ),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            onPressed: () {
                              _searchController.clear();
                              _applyFilters();
                            },
                            icon: const Icon(
                              Icons.close,
                              size: 18,
                              color: AppTheme.grey,
                            ),
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Badge(
                isLabelVisible: _hasDropdownFilters,
                label: Text('$_activeFilterCount'),
                child: IconButton(
                  tooltip: _filtersVisible ? 'Hide filters' : 'Show filters',
                  onPressed: _toggleFiltersVisible,
                  style: IconButton.styleFrom(
                    backgroundColor: _filtersVisible || _hasDropdownFilters
                        ? const Color(0xFFEFF6FF)
                        : const Color(0xFFF3F4F6),
                    foregroundColor: _filtersVisible || _hasDropdownFilters
                        ? AppTheme.primaryBlue
                        : AppTheme.darkGrey,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(
                        color: _filtersVisible || _hasDropdownFilters
                            ? const Color(0xFFBFDBFE)
                            : const Color(0xFFE3E6EB),
                      ),
                    ),
                  ),
                  icon: Icon(
                    _filtersVisible
                        ? Icons.filter_alt
                        : Icons.filter_alt_outlined,
                  ),
                ),
              ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: _filtersVisible
                ? Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Column(
                      children: [
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final wide = constraints.maxWidth >= 820;
                            if (wide) {
                              return Row(
                                children: [
                                  Expanded(child: parentFilter),
                                  const SizedBox(width: 12),
                                  Expanded(child: categoryFilter),
                                  const SizedBox(width: 12),
                                  Expanded(child: custFilter),
                                ],
                              );
                            }
                            return Column(
                              children: [
                                parentFilter,
                                const SizedBox(height: 10),
                                categoryFilter,
                                const SizedBox(height: 10),
                                custFilter,
                              ],
                            );
                          },
                        ),
                        if (_hasDropdownFilters)
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: _clearDropdownFilters,
                              icon: const Icon(
                                Icons.filter_alt_off_outlined,
                                size: 16,
                              ),
                              label: const Text('Clear filters'),
                            ),
                          ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          if (!_filtersVisible && _hasDropdownFilters)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (_selectedParent != _allParents)
                    _filterChip(
                      label: _selectedParent,
                      onDeleted: () {
                        _selectedParent = _allParents;
                        _applyFilters();
                      },
                    ),
                  if (_selectedCategory != _allCategories)
                    _filterChip(
                      label: _selectedCategory,
                      onDeleted: () {
                        _selectedCategory = _allCategories;
                        _applyFilters();
                      },
                    ),
                  if (_selectedCustCategory != _allCustCategories)
                    _filterChip(
                      label: _selectedCustCategory,
                      onDeleted: () {
                        _selectedCustCategory = _allCustCategories;
                        _applyFilters();
                      },
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required VoidCallback onDeleted,
  }) {
    return InputChip(
      label: Text(
        label,
        overflow: TextOverflow.ellipsis,
      ),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      backgroundColor: const Color(0xFFEFF6FF),
      side: const BorderSide(color: Color(0xFFBFDBFE)),
      labelStyle: const TextStyle(
        fontSize: 12,
        color: AppTheme.primaryBlue,
        fontWeight: FontWeight.w600,
      ),
      deleteIcon: const Icon(Icons.close, size: 16),
      onDeleted: onDeleted,
      onPressed: _toggleFiltersVisible,
    );
  }

  Widget _buildListHeader() {
    return Container(
      color: AppTheme.white,
      padding: const EdgeInsets.fromLTRB(8, 4, 20, 4),
      child: Row(
        children: [
          Checkbox(
            value: _filteredCustomers.isEmpty ? false : _allFilteredSelected,
            onChanged: _filteredCustomers.isEmpty ? null : (_) => _toggleSelectAll(),
            activeColor: AppTheme.primaryBlue,
            visualDensity: VisualDensity.compact,
          ),
          Expanded(
            child: GestureDetector(
              onTap: _filteredCustomers.isEmpty ? null : _toggleSelectAll,
              child: Text(
                _allFilteredSelected ? 'Deselect all' : 'Select all',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: AppTheme.darkGrey,
                ),
              ),
            ),
          ),
          Text(
            '${_filteredCustomers.length} listed',
            style: const TextStyle(fontSize: 13, color: AppTheme.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerRow(CustomerModel customer) {
    final selected = _selectedCustomerIds.contains(customer.id);
    final initial = customer.customerName.isNotEmpty
        ? customer.customerName[0].toUpperCase()
        : '?';

    return Material(
      color: selected ? const Color(0xFFEFF6FF) : AppTheme.white,
      child: InkWell(
        onTap: () => _toggleCustomer(customer.id, !selected),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Checkbox(
                value: selected,
                onChanged: (checked) => _toggleCustomer(customer.id, checked),
                activeColor: AppTheme.primaryBlue,
                visualDensity: VisualDensity.compact,
              ),
              CircleAvatar(
                radius: 16,
                backgroundColor: selected
                    ? AppTheme.primaryBlue
                    : const Color(0xFFE8EEF5),
                child: Text(
                  initial,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: selected ? AppTheme.white : AppTheme.darkBlue,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customer.customerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: AppTheme.darkGrey,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _customerMeta(customer),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCountStat({
    required String label,
    required int count,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
            color: AppTheme.grey,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '$count',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            height: 1.1,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildSaveBar() {
    return Material(
      color: AppTheme.white,
      elevation: 8,
      shadowColor: Colors.black26,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    _buildCountStat(
                      label: 'Assigned',
                      count: _initiallyAssignedIds.length,
                      color: AppTheme.darkGrey,
                    ),
                    const SizedBox(width: 20),
                    _buildCountStat(
                      label: 'Selected',
                      count: _selectedCustomerIds.length,
                      color: AppTheme.primaryBlue,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: (_isSaving || !_hasChanges) ? null : _saveAssignments,
                icon: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check, size: 18),
                label: Text(_isSaving ? 'Saving…' : 'Save'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primaryBlue,
                  disabledBackgroundColor: const Color(0xFFD7DCE3),
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return ErrorStateWidget(
        message: _error!,
        onRetry: _loadData,
      );
    }

    if (_allCustomers.isEmpty) {
      return const Center(
        child: Text(
          'No customers found in this company.',
          style: TextStyle(color: AppTheme.grey, fontSize: 16),
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _buildToolbar()),
              const SliverToBoxAdapter(
                child: Divider(height: 1, color: Color(0xFFE3E6EB)),
              ),
              SliverToBoxAdapter(child: _buildListHeader()),
              const SliverToBoxAdapter(
                child: Divider(height: 1, color: Color(0xFFE3E6EB)),
              ),
              if (_filteredCustomers.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Text(
                      'No customers match these filters.',
                      style: TextStyle(color: AppTheme.grey),
                    ),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      if (index.isOdd) {
                        return const Divider(
                          height: 1,
                          color: Color(0xFFF0F2F5),
                        );
                      }
                      return _buildCustomerRow(
                        _filteredCustomers[index ~/ 2],
                      );
                    },
                    childCount: _filteredCustomers.length * 2 - 1,
                  ),
                ),
            ],
          ),
        ),
        _buildSaveBar(),
      ],
    );
  }
}
