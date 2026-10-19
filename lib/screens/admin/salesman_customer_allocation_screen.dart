import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:Orderx/core/theme/app_theme.dart';
import 'package:Orderx/models/customer_model.dart';
import 'package:Orderx/models/salesman.dart';
import 'package:Orderx/models/user_model.dart';
import 'package:Orderx/providers/auth_provider.dart';
import 'package:Orderx/screens/admin/assign_customers_screen.dart';
import 'package:Orderx/services/customer_service.dart';
import 'package:Orderx/services/salesman_service.dart';
import 'package:Orderx/widgets/app_bar_actions.dart';
import 'package:Orderx/widgets/error_state_widget.dart';

class SalesmanCustomerAllocationScreen extends StatefulWidget {
  const SalesmanCustomerAllocationScreen({super.key});

  @override
  State<SalesmanCustomerAllocationScreen> createState() =>
      _SalesmanCustomerAllocationScreenState();
}

class _SalesmanCustomerAllocationScreenState
    extends State<SalesmanCustomerAllocationScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final GlobalKey<_AssignCustomersTabState> _assignKey =
      GlobalKey<_AssignCustomersTabState>();
  final GlobalKey<_CustomerAllocationsTabState> _allocationsKey =
      GlobalKey<_CustomerAllocationsTabState>();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging && _tabController.index == 1) {
        _allocationsKey.currentState?.reload();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Salesman Customer Allocation'),
        actions: [
          AppBarRefreshButton(
            onPressed: () {
              _assignKey.currentState?.reload();
              _allocationsKey.currentState?.reload();
            },
          ),
          const GlobalCompanySwitcher(),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'Assign'),
            Tab(text: 'Customers'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _AssignCustomersTab(
            key: _assignKey,
            onSaved: () => _allocationsKey.currentState?.reload(),
          ),
          _CustomerAllocationsTab(key: _allocationsKey),
        ],
      ),
    );
  }
}

class _AssignCustomersTab extends StatefulWidget {
  final VoidCallback onSaved;

  const _AssignCustomersTab({super.key, required this.onSaved});

  @override
  State<_AssignCustomersTab> createState() => _AssignCustomersTabState();
}

class _AssignCustomersTabState extends State<_AssignCustomersTab>
    with AutomaticKeepAliveClientMixin {
  final SalesmanService _salesmanService = SalesmanService();
  final GlobalKey<AssignCustomersPanelState> _panelKey =
      GlobalKey<AssignCustomersPanelState>();

  List<Salesman> _salesmen = [];
  String? _selectedSalesmanId;
  bool _isLoading = true;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSalesmen());
  }

  Future<void> reload() async {
    await _loadSalesmen();
    await _panelKey.currentState?.reload();
  }

  Future<void> _loadSalesmen() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final companyId = context.read<AuthProvider>().selectedCompanyId;
      if (companyId == null || companyId == 'ALL') {
        throw Exception('Please select a specific company.');
      }

      final salesmen = await _salesmanService.getSalesmen(companyId: companyId);
      salesmen.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      if (!mounted) return;
      setState(() {
        _salesmen = salesmen;
        if (_selectedSalesmanId != null &&
            salesmen.every((s) => s.id != _selectedSalesmanId)) {
          _selectedSalesmanId = null;
        }
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

  UserModel _toUserModel(Salesman salesman) {
    return UserModel(
      id: salesman.id,
      mobileNumber: salesman.mobileNumber,
      name: salesman.name,
      userType: salesman.userType,
      isActive: salesman.isActive,
      createdAt: salesman.createdAt,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return ErrorStateWidget(
        message: _error!,
        onRetry: _loadSalesmen,
      );
    }

    if (_salesmen.isEmpty) {
      return const Center(
        child: Text(
          'No salesmen found in this company.',
          style: TextStyle(color: AppTheme.grey, fontSize: 16),
        ),
      );
    }

    final selected = _salesmen
        .where((s) => s.id == _selectedSalesmanId)
        .firstOrNull;

    return Column(
      children: [
        Container(
          width: double.infinity,
          color: AppTheme.white,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'SALESMAN',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6,
                  color: AppTheme.grey,
                ),
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: _selectedSalesmanId,
                isExpanded: true,
                isDense: true,
                decoration: InputDecoration(
                  hintText: 'Choose a salesman',
                  filled: true,
                  fillColor: AppTheme.white,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
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
                    borderSide: const BorderSide(
                      color: AppTheme.primaryBlue,
                      width: 1.4,
                    ),
                  ),
                ),
                icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
                items: _salesmen
                    .map(
                      (salesman) => DropdownMenuItem(
                        value: salesman.id,
                        child: Text(
                          salesman.isActive
                              ? salesman.name
                              : '${salesman.name} (inactive)',
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  setState(() => _selectedSalesmanId = value);
                },
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: Color(0xFFE3E6EB)),
        Expanded(
          child: selected == null
              ? const Center(
                  child: Text(
                    'Select a salesman to assign customers.',
                    style: TextStyle(color: AppTheme.grey),
                  ),
                )
              : AssignCustomersPanel(
                  key: _panelKey,
                  salesman: _toUserModel(selected),
                  onSaved: widget.onSaved,
                ),
        ),
      ],
    );
  }
}

class _CustomerAllocationsTab extends StatefulWidget {
  const _CustomerAllocationsTab({super.key});

  @override
  State<_CustomerAllocationsTab> createState() => _CustomerAllocationsTabState();
}

class _CustomerAllocationsTabState extends State<_CustomerAllocationsTab>
    with AutomaticKeepAliveClientMixin {
  static const String _allSalesmen = '__all__';
  static const String _allParents = '__all_parents__';
  static const String _allCategories = '__all_categories__';

  final CustomerService _customerService = CustomerService();
  final SalesmanService _salesmanService = SalesmanService();
  final TextEditingController _searchController = TextEditingController();

  List<CustomerModel> _allocatedCustomers = [];
  List<CustomerModel> _filteredCustomers = [];
  Map<String, String> _salesmanNames = {};
  List<Salesman> _salesmen = [];
  String _selectedSalesmanFilter = _allSalesmen;
  String _selectedParent = _allParents;
  String _selectedCategory = _allCategories;
  bool _filtersVisible = false;
  Set<String> _selectedCustomerIds = {};
  String? _companyId;

  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => reload());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> reload() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final companyId = context.read<AuthProvider>().selectedCompanyId;
      if (companyId == null || companyId == 'ALL') {
        throw Exception('Please select a specific company.');
      }

      final results = await Future.wait([
        _customerService.getAllCustomers(companyId: companyId),
        _salesmanService.getSalesmen(companyId: companyId),
      ]);

      final customers = (results[0] as List<CustomerModel>)
          .where((c) => c.assignedSalesmanIds.isNotEmpty)
          .toList();
      final salesmen = results[1] as List<Salesman>;
      salesmen.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );

      final names = {
        for (final salesman in salesmen) salesman.id: salesman.name,
      };
      final missingIds = customers
          .expand((c) => c.assignedSalesmanIds)
          .where((id) => !names.containsKey(id))
          .toSet()
          .toList();
      if (missingIds.isNotEmpty) {
        names.addAll(await _salesmanService.getSalesmanNamesByIds(missingIds));
      }

      final allocatedSalesmen = salesmen
          .where((s) => customers.any((c) => c.assignedSalesmanIds.contains(s.id)))
          .toList();
      var salesmanFilter = _selectedSalesmanFilter;
      if (salesmanFilter != _allSalesmen &&
          allocatedSalesmen.every((s) => s.id != salesmanFilter)) {
        salesmanFilter = _allSalesmen;
      }

      if (!mounted) return;
      setState(() {
        _companyId = companyId;
        _allocatedCustomers = customers;
        _salesmen = allocatedSalesmen;
        _salesmanNames = names;
        _selectedSalesmanFilter = salesmanFilter;
        _selectedCustomerIds.clear();
        _isLoading = false;
      });
      _applyFilters();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  String _salesmanLabel(CustomerModel customer) {
    final names = customer.assignedSalesmanIds
        .map((id) => _salesmanNames[id] ?? 'Unknown')
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return names.join(', ');
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

  Iterable<CustomerModel> get _salesmanScoped => _allocatedCustomers.where(
        (customer) =>
            _selectedSalesmanFilter == _allSalesmen ||
            customer.assignedSalesmanIds.contains(_selectedSalesmanFilter),
      );

  Iterable<CustomerModel> _matching({
    bool applyParent = true,
    bool applyCategory = true,
  }) {
    return _salesmanScoped.where((customer) {
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
      return true;
    });
  }

  List<String> get _parentNames =>
      _sortedNames(_salesmanScoped.map((c) => c.parentGroupName));

  List<String> get _categoryNames => _sortedNames(
        _salesmanScoped
            .where((c) =>
                _selectedParent == _allParents ||
                c.parentGroupName == _selectedParent)
            .map((c) => c.groupName),
      );

  bool get _hasGroupFilters =>
      _selectedParent != _allParents || _selectedCategory != _allCategories;

  int get _activeFilterCount =>
      (_selectedParent != _allParents ? 1 : 0) +
      (_selectedCategory != _allCategories ? 1 : 0);

  void _syncGroupFilters() {
    if (_selectedParent != _allParents &&
        !_parentNames.contains(_selectedParent)) {
      _selectedParent = _allParents;
    }
    if (_selectedCategory != _allCategories &&
        !_categoryNames.contains(_selectedCategory)) {
      _selectedCategory = _allCategories;
    }
  }

  void _applyFilters() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      _syncGroupFilters();
      _filteredCustomers = _matching().where((customer) {
        if (query.isEmpty) return true;
        return customer.customerName.toLowerCase().contains(query) ||
            (customer.mobileNumber?.toLowerCase().contains(query) ?? false) ||
            (customer.city?.toLowerCase().contains(query) ?? false) ||
            customer.parentGroupName.toLowerCase().contains(query) ||
            customer.groupName.toLowerCase().contains(query) ||
            customer.custCategoryName.toLowerCase().contains(query) ||
            _salesmanLabel(customer).toLowerCase().contains(query);
      }).toList();
      _selectedCustomerIds.removeWhere(
        (id) => !_filteredCustomers.any((c) => c.id == id),
      );
    });
  }

  bool get _allFilteredSelected =>
      _filteredCustomers.isNotEmpty &&
      _filteredCustomers.every((c) => _selectedCustomerIds.contains(c.id));

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

  Future<void> _deallocateSelected() async {
    if (_companyId == null || _selectedCustomerIds.isEmpty) return;

    final count = _selectedCustomerIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Deallocate customers'),
        content: Text(
          _selectedSalesmanFilter == _allSalesmen
              ? 'Remove salesman assignment from $count selected customer(s)?'
              : 'Remove these $count customer(s) from this salesman?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Deallocate'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isSaving = true);
    try {
      await _customerService.deallocateCustomers(
        companyId: _companyId!,
        customerIds: _selectedCustomerIds.toList(),
        salesmanId: _selectedSalesmanFilter == _allSalesmen
            ? null
            : _selectedSalesmanFilter,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Deallocated $count customer(s).'),
          backgroundColor: AppTheme.success,
        ),
      );
      await reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error deallocating customers: $e'),
          backgroundColor: AppTheme.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  InputDecoration _filterDecoration() {
    return InputDecoration(
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

  Widget _groupFilterField({
    required String caption,
    required String value,
    required String allValue,
    required String allLabel,
    required int allCount,
    required List<String> names,
    required int Function(String name) countFor,
    required ValueChanged<String> onChanged,
  }) {
    final selectedValue =
        value != allValue && !names.contains(value) ? allValue : value;
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
          value: selectedValue,
          isExpanded: true,
          isDense: true,
          menuMaxHeight: 360,
          decoration: _filterDecoration(),
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
          selectedItemBuilder: (context) {
            final labels = [allLabel, ...names];
            return labels
                .map(
                  (label) => Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppTheme.darkGrey,
                    ),
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

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return ErrorStateWidget(
        message: _error!,
        onRetry: reload,
      );
    }

    if (_allocatedCustomers.isEmpty) {
      return const Center(
        child: Text(
          'No allocated customers in this company.',
          style: TextStyle(color: AppTheme.grey, fontSize: 16),
        ),
      );
    }

    return Stack(
      children: [
        Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: DropdownButtonFormField<String>(
                value: _selectedSalesmanFilter,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Filter by Salesman',
                  prefixIcon: const Icon(Icons.filter_list),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: AppTheme.white,
                ),
                items: [
                  DropdownMenuItem(
                    value: _allSalesmen,
                    child: Text(
                      'All Salesmen (${_allocatedCustomers.length})',
                    ),
                  ),
                  ..._salesmen.map((salesman) {
                    final count = _allocatedCustomers
                        .where(
                          (c) => c.assignedSalesmanIds.contains(salesman.id),
                        )
                        .length;
                    return DropdownMenuItem(
                      value: salesman.id,
                      child: Text('${salesman.name} ($count)'),
                    );
                  }),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  _selectedSalesmanFilter = value;
                  _selectedParent = _allParents;
                  _selectedCategory = _allCategories;
                  _selectedCustomerIds.clear();
                  _applyFilters();
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          onChanged: (_) => _applyFilters(),
                          decoration: InputDecoration(
                            labelText: 'Search Customers',
                            hintText: 'Search by name, salesman, parent, or category',
                            prefixIcon: const Icon(Icons.search),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: AppTheme.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Badge(
                        isLabelVisible: _hasGroupFilters,
                        label: Text('$_activeFilterCount'),
                        child: IconButton(
                          tooltip:
                              _filtersVisible ? 'Hide filters' : 'Show filters',
                          onPressed: () {
                            setState(
                              () => _filtersVisible = !_filtersVisible,
                            );
                          },
                          style: IconButton.styleFrom(
                            backgroundColor:
                                _filtersVisible || _hasGroupFilters
                                    ? const Color(0xFFEFF6FF)
                                    : const Color(0xFFF3F4F6),
                            foregroundColor:
                                _filtersVisible || _hasGroupFilters
                                    ? AppTheme.primaryBlue
                                    : AppTheme.darkGrey,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(
                                color: _filtersVisible || _hasGroupFilters
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
                                    final parentFilter = _groupFilterField(
                                      caption: 'Parent',
                                      value: _selectedParent,
                                      allValue: _allParents,
                                      allLabel: 'All parents',
                                      allCount:
                                          _matching(applyParent: false).length,
                                      names: _parentNames,
                                      countFor: (name) =>
                                          _matching(applyParent: false)
                                              .where((c) =>
                                                  c.parentGroupName == name)
                                              .length,
                                      onChanged: (value) {
                                        _selectedParent = value;
                                        _applyFilters();
                                      },
                                    );
                                    final categoryFilter = _groupFilterField(
                                      caption: 'Category',
                                      value: _selectedCategory,
                                      allValue: _allCategories,
                                      allLabel: 'All categories',
                                      allCount: _matching(applyCategory: false)
                                          .length,
                                      names: _categoryNames,
                                      countFor: (name) =>
                                          _matching(applyCategory: false)
                                              .where(
                                                (c) => c.groupName == name,
                                              )
                                              .length,
                                      onChanged: (value) {
                                        _selectedCategory = value;
                                        _applyFilters();
                                      },
                                    );
                                    if (constraints.maxWidth >= 640) {
                                      return Row(
                                        children: [
                                          Expanded(child: parentFilter),
                                          const SizedBox(width: 12),
                                          Expanded(child: categoryFilter),
                                        ],
                                      );
                                    }
                                    return Column(
                                      children: [
                                        parentFilter,
                                        const SizedBox(height: 10),
                                        categoryFilter,
                                      ],
                                    );
                                  },
                                ),
                                if (_hasGroupFilters)
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton.icon(
                                      onPressed: () {
                                        _selectedParent = _allParents;
                                        _selectedCategory = _allCategories;
                                        _applyFilters();
                                      },
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
                  if (!_filtersVisible && _hasGroupFilters)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (_selectedParent != _allParents)
                            InputChip(
                              label: Text('Parent: $_selectedParent'),
                              onDeleted: () {
                                _selectedParent = _allParents;
                                _applyFilters();
                              },
                            ),
                          if (_selectedCategory != _allCategories)
                            InputChip(
                              label: Text('Category: $_selectedCategory'),
                              onDeleted: () {
                                _selectedCategory = _allCategories;
                                _applyFilters();
                              },
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                children: [
                  Checkbox(
                    value: _filteredCustomers.isEmpty
                        ? false
                        : _allFilteredSelected,
                    onChanged: _filteredCustomers.isEmpty
                        ? null
                        : (_) => _toggleSelectAll(),
                    activeColor: AppTheme.primaryBlue,
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap:
                          _filteredCustomers.isEmpty ? null : _toggleSelectAll,
                      child: Text(
                        _allFilteredSelected ? 'Deselect All' : 'Select All',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppTheme.darkGrey,
                        ),
                      ),
                    ),
                  ),
                  Text(
                    '${_filteredCustomers.length} listed',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppTheme.grey,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${_selectedCustomerIds.length} selected',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryBlue,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _filteredCustomers.isEmpty
                  ? const Center(
                      child: Text(
                        'No allocated customers match these filters.',
                        style: TextStyle(color: AppTheme.grey),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
                      itemCount: _filteredCustomers.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final customer = _filteredCustomers[index];
                        return CheckboxListTile(
                          value: _selectedCustomerIds.contains(customer.id),
                          onChanged: (checked) =>
                              _toggleCustomer(customer.id, checked),
                          title: Text(
                            customer.customerName,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            [
                              _salesmanLabel(customer),
                              if (customer.parentGroupName != 'Ungrouped')
                                customer.parentGroupName,
                              if (customer.groupName != 'Ungrouped' &&
                                  customer.groupName !=
                                      customer.parentGroupName)
                                customer.groupName,
                              if (customer.city != null &&
                                  customer.city!.isNotEmpty)
                                customer.city!,
                            ].join(' • '),
                          ),
                          activeColor: AppTheme.primaryBlue,
                          controlAffinity: ListTileControlAffinity.leading,
                        );
                      },
                    ),
            ),
          ],
        ),
        if (_selectedCustomerIds.isNotEmpty)
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton.extended(
              onPressed: _isSaving ? null : _deallocateSelected,
              label: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text('Deallocate (${_selectedCustomerIds.length})'),
              icon: _isSaving ? null : const Icon(Icons.person_remove),
              backgroundColor: AppTheme.error,
            ),
          ),
      ],
    );
  }
}
