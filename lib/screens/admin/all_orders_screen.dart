import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:Orderx/core/theme/app_theme.dart';
import 'package:Orderx/models/order_model.dart';
import 'package:Orderx/providers/auth_provider.dart';
import 'package:Orderx/services/order_service.dart';
import 'package:Orderx/services/tally_company_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:Orderx/services/pdf_service.dart';
import 'package:Orderx/services/company_selection_service.dart';
import 'package:Orderx/services/admin_settings_service.dart';
import 'package:Orderx/models/tally_company_model.dart';
import 'package:Orderx/widgets/location_address_widget.dart';
import 'package:Orderx/widgets/app_bar_actions.dart';
import 'package:Orderx/screens/admin/order_details_admin_screen.dart';
import 'package:Orderx/services/partial_orders_excel_service.dart';
import 'package:Orderx/utils/error_handler.dart';
import 'package:Orderx/widgets/error_state_widget.dart';
import 'package:Orderx/widgets/pending_order_item_details.dart';

class AllOrdersScreen extends StatefulWidget {
  const AllOrdersScreen({super.key});

  @override
  State<AllOrdersScreen> createState() => _AllOrdersScreenState();
}

class _AllOrdersScreenState extends State<AllOrdersScreen>
    with SingleTickerProviderStateMixin {
  final OrderService _orderService = OrderService();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late final TabController _tabController;

  static const int _tabAll = 0;
  static const int _tabAdmin = 1;
  static const int _tabSalesman = 2;
  static const int _tabPartial = 3;

  // Data
  final List<OrderModel> _orders = [];
  bool _isLoading = false;
  bool _isSharingPartial = false;
  String? _errorMessage;
  bool _hasMore = true;
  int _currentPage = 1;
  static const int _pageSize = 20;

  // Filters
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _itemSearchController = TextEditingController();
  final TextEditingController _minAmountController = TextEditingController();
  final TextEditingController _maxAmountController = TextEditingController();

  DateTime? _startDate;
  DateTime? _endDate;
  static const String _allCreators = '__all__';
  String _selectedCreatorId = _allCreators;
  List<({String id, String name})> _admins = [];
  List<({String id, String name})> _salesmen = [];
  final Map<String, List<OrderItemModel>> _partialItems = {};

  bool get _isPartialTab => _tabController.index == _tabPartial;

  String? get _createdByRole {
    switch (_tabController.index) {
      case _tabAdmin:
        return 'admin';
      case _tabSalesman:
        return 'salesman';
      default:
        return null;
    }
  }

  List<({String id, String name})> get _creatorOptions {
    if (_tabController.index == _tabAdmin) return _admins;
    if (_tabController.index == _tabSalesman) return _salesmen;
    return const [];
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_onTabChanged);
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCreators();
      _loadOrders(reset: true);
    });
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _scrollController.dispose();
    _searchController.dispose();
    _itemSearchController.dispose();
    _minAmountController.dispose();
    _maxAmountController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) {
      setState(() {});
      return;
    }
    _selectedCreatorId = _allCreators;
    _loadOrders(reset: true);
  }

  Future<void> _loadCreators() async {
    final companyId = context.read<AuthProvider>().selectedCompanyId;
    final effectiveCompanyId = (companyId == 'ALL') ? null : companyId;
    try {
      final results = await Future.wait([
        _orderService.listUsersByRole(
          role: 'admin',
          companyId: effectiveCompanyId,
        ),
        _orderService.listUsersByRole(
          role: 'salesman',
          companyId: effectiveCompanyId,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _admins = results[0];
        _salesmen = results[1];
        if (_selectedCreatorId != _allCreators &&
            _creatorOptions.every((u) => u.id != _selectedCreatorId)) {
          _selectedCreatorId = _allCreators;
        }
      });
    } catch (e) {
      print('Error loading order creators: $e');
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200 &&
        !_isLoading &&
        _hasMore) {
      _loadOrders();
    }
  }

  Future<void> _loadOrders({bool reset = false}) async {
    if (_isLoading) return;
    
    print('🔄 AllOrdersScreen: _loadOrders called (reset: $reset)');
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      if (reset) {
        _orders.clear();
        _partialItems.clear();
        _currentPage = 1;
        _hasMore = true;
      }
    });

    try {
      final authProvider = context.read<AuthProvider>();
      final String? selectedCompanyId = authProvider.selectedCompanyId;
      final String? effectiveCompanyId = (selectedCompanyId == 'ALL') ? null : selectedCompanyId;
      print('🔄 AllOrdersScreen: selectedCompanyId: $selectedCompanyId, effectiveCompanyId: $effectiveCompanyId');

      final double? minAmount = double.tryParse(_minAmountController.text);
      final double? maxAmount = double.tryParse(_maxAmountController.text);

      final newOrders = await _orderService.getOrdersWithFilters(
        companyId: effectiveCompanyId,
        page: _currentPage,
        pageSize: _isPartialTab ? 200 : _pageSize,
        searchQuery: _isPartialTab ? null : _searchController.text.trim(),
        itemName: _itemSearchController.text.trim(),
        startDate: _startDate,
        endDate: _endDate,
        minAmount: _isPartialTab ? null : minAmount,
        maxAmount: _isPartialTab ? null : maxAmount,
        createdByRole: _createdByRole,
        createdByUserId:
            _selectedCreatorId == _allCreators ? null : _selectedCreatorId,
        partiallyBilledOnly: _isPartialTab,
      );

      print('🔄 AllOrdersScreen: Received ${newOrders.length} orders from service');

      var ordersToAdd = newOrders;
      if (_isPartialTab && newOrders.isNotEmpty) {
        final itemsByOrder = await _orderService.getOrderItemsByOrderIds(
          newOrders.map((order) => order.id).toList(),
        );
        _partialItems.addAll(itemsByOrder);
        ordersToAdd = newOrders.where(_matchesPartialFilters).toList();
      }

      if (mounted) {
        setState(() {
          if (newOrders.length < (_isPartialTab ? 200 : _pageSize)) {
            _hasMore = false;
          }
          _orders.addAll(ordersToAdd);
          _currentPage++;
          _isLoading = false;
        });
        print('🔄 AllOrdersScreen: UI updated, total orders: ${_orders.length}');
      }
    } catch (e) {
      print('❌ AllOrdersScreen: Error loading orders: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = ErrorHandler.getFriendlyErrorMessage(e);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_errorMessage!)),
        );
      }
    }
  }

  List<OrderItemModel> _itemsFor(OrderModel order) =>
      _partialItems[order.id] ?? const [];

  double _pendingAmountFor(OrderModel order) {
    final items = _itemsFor(order);
    if (items.isNotEmpty) {
      return items.fold<double>(
        0,
        (sum, item) => sum + item.pendingLineAmount,
      );
    }
    return order.pendingAmount;
  }

  bool _matchesPartialFilters(OrderModel order) {
    final items = _itemsFor(order);
    final search = _searchController.text.trim().toLowerCase();
    if (search.isNotEmpty) {
      final inHeader = order.orderNumber.toLowerCase().contains(search) ||
          (order.customerName ?? '').toLowerCase().contains(search) ||
          (order.salesmanName ?? '').toLowerCase().contains(search);
      final inItems = items.any(
        (item) =>
            item.ItemName.toLowerCase().contains(search) ||
            (item.PartNumber ?? '').toLowerCase().contains(search),
      );
      if (!inHeader && !inItems) return false;
    }
    final itemQuery = _itemSearchController.text.trim().toLowerCase();
    if (itemQuery.isNotEmpty) {
      final hasItem = items.any(
        (item) =>
            item.ItemName.toLowerCase().contains(itemQuery) ||
            (item.PartNumber ?? '').toLowerCase().contains(itemQuery),
      );
      if (!hasItem) return false;
    }
    final pending = _pendingAmountFor(order);
    final minAmount = double.tryParse(_minAmountController.text);
    final maxAmount = double.tryParse(_maxAmountController.text);
    if (minAmount != null && pending < minAmount) return false;
    if (maxAmount != null && pending > maxAmount) return false;
    return true;
  }

  Future<void> _sharePartialOrdersExcel({OrderModel? order}) async {
    final orders = order == null ? List<OrderModel>.from(_orders) : [order];
    if (orders.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No partial orders to share')),
      );
      return;
    }
    setState(() => _isSharingPartial = true);
    try {
      await PartialOrdersExcelService().sharePendingOrders(
        orders: orders,
        itemsByOrderId: _partialItems,
        itemNameFilter: _itemSearchController.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            order == null
                ? 'Shared ${orders.length} filtered partial order(s)'
                : 'Shared ${order.orderNumber}',
          ),
        ),
      );
    } on StateError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.orange),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not share Excel: $e'),
          backgroundColor: AppTheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSharingPartial = false);
    }
  }

  void _applyFilters() {
    Navigator.of(context).pop(); // Close drawer
    _loadOrders(reset: true);
  }

  void _resetFilters() {
    _itemSearchController.clear();
    _minAmountController.clear();
    _maxAmountController.clear();
    setState(() {
      _startDate = null;
      _endDate = null;
      _selectedCreatorId = _allCreators;
    });
    // Don't close drawer immediately so user can see it's cleared? Or close and reload.
    // Let's reload.
    _applyFilters();
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppTheme.primaryBlue,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
    }
  }

  Future<void> _shareOrder(OrderModel order) async {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Generating PDF...'), duration: Duration(seconds: 1)));
    try {
      final items = await _orderService.getOrderItems(order.id);
      if (items.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No items to share'), backgroundColor: Colors.orange));
        return;
      }
      TallyCompanyModel? company;
      var settings;
      if (order.companyId != null && order.companyId!.isNotEmpty) {
        final companyData = await CompanySelectionService().getCompanyById(order.companyId!);
        if (companyData != null) {
          company = TallyCompanyModel.fromJson(companyData);
        }
        settings = await AdminSettingsService().getAdminSettings(order.companyId!);
      }
      final pdfBytes = await PdfService().generateOrderPdf(order, items, company: company, companyName: order.companyName, settings: settings);
      await PdfService().sharePdf(pdfBytes, order.orderNumber);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error sharing: $e'), backgroundColor: AppTheme.error));
    }
  }

  Future<void> _printOrder(OrderModel order) async {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Generating PDF...'), duration: Duration(seconds: 1)));
    try {
      final items = await _orderService.getOrderItems(order.id);
      if (items.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No items to print'), backgroundColor: Colors.orange));
        return;
      }
      TallyCompanyModel? company;
      var settings;
      if (order.companyId != null && order.companyId!.isNotEmpty) {
        final companyData = await CompanySelectionService().getCompanyById(order.companyId!);
        if (companyData != null) {
          company = TallyCompanyModel.fromJson(companyData);
        }
        settings = await AdminSettingsService().getAdminSettings(order.companyId!);
      }
      final pdfBytes = await PdfService().generateOrderPdf(order, items, company: company, companyName: order.companyName, settings: settings);
      await PdfService().printPdf(pdfBytes);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error printing: $e'), backgroundColor: AppTheme.error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: const Text('All Orders'),
        actions: [
          GlobalCompanySwitcher(onCompanyChanged: () {
            _loadCreators();
            _loadOrders(reset: true);
          }),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => _loadOrders(reset: true),
          ),
          if (_isPartialTab)
            IconButton(
              icon: _isSharingPartial
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.share),
              tooltip: 'Share filtered pending orders as Excel',
              onPressed: _isSharingPartial ? null : _sharePartialOrdersExcel,
            ),
          IconButton(
            icon: const Icon(Icons.filter_list_alt),
            onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
            tooltip: 'Filters',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'All'),
            Tab(text: 'Admin created'),
            Tab(text: 'Salesman created'),
            Tab(text: 'Partial'),
          ],
        ),
      ),
      endDrawer: Drawer(
        width: 300,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 50, 16, 16),
              color: AppTheme.primaryBlue,
              child: Row(
                children: [
                  const Icon(Icons.filter_alt, color: Colors.white),
                  const SizedBox(width: 12),
                  const Text(
                    'Filter Orders',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_tabController.index == _tabAdmin ||
                      _tabController.index == _tabSalesman) ...[
                    Text(
                      _tabController.index == _tabAdmin
                          ? 'Created by admin'
                          : 'Created by salesman',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: _selectedCreatorId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: _allCreators,
                          child: Text(
                            _tabController.index == _tabAdmin
                                ? 'All admins'
                                : 'All salesmen',
                          ),
                        ),
                        ..._creatorOptions.map(
                          (user) => DropdownMenuItem(
                            value: user.id,
                            child: Text(
                              user.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _selectedCreatorId = value);
                      },
                    ),
                    const Divider(height: 32),
                  ],
                   // Date Range
                  const Text('Date Range', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: _selectDateRange,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.date_range, color: AppTheme.grey, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _startDate == null
                                  ? 'Select Dates'
                                  : '${DateFormat('MMM dd').format(_startDate!)} - ${DateFormat('MMM dd, yyyy').format(_endDate!)}',
                              style: TextStyle(
                                color: _startDate == null ? AppTheme.grey : Colors.black,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const Divider(height: 32),

                  // Item Name
                  const Text('Contains Item', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _itemSearchController,
                    decoration: const InputDecoration(
                      hintText: 'Item name or code',
                      prefixIcon: Icon(Icons.shopping_basket_outlined),
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                  ),

                  const Divider(height: 32),

                  // Amount Range
                  Text(
                    _isPartialTab ? 'Pending amount range' : 'Amount Range',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _minAmountController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            hintText: 'Min',
                            prefixText: '₹ ',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          ),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text('-'),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _maxAmountController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            hintText: 'Max',
                            prefixText: '₹ ',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _resetFilters,
                      child: const Text('Reset'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _applyFilters,
                      child: const Text('Apply'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Main Search Bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: _isPartialTab
                    ? 'Search partial order #, customer, item...'
                    : 'Search order #, customer name...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: () => _loadOrders(reset: true), // Trigger search manually
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onSubmitted: (_) => _loadOrders(reset: true),
            ),
          ),

          // Active Filters Chips (Optional visual feedback)
          if (_startDate != null ||
              _itemSearchController.text.isNotEmpty ||
              _minAmountController.text.isNotEmpty ||
              _selectedCreatorId != _allCreators)
             SingleChildScrollView(
               scrollDirection: Axis.horizontal,
               padding: const EdgeInsets.symmetric(horizontal: 16),
               child: Row(
                 children: [
                   if (_selectedCreatorId != _allCreators)
                     Padding(
                       padding: const EdgeInsets.only(right: 8),
                       child: Chip(
                         label: Text(
                           _creatorOptions
                               .where((u) => u.id == _selectedCreatorId)
                               .map((u) => u.name)
                               .firstWhere(
                                 (_) => true,
                                 orElse: () => 'Selected',
                               ),
                         ),
                         onDeleted: () {
                           setState(() => _selectedCreatorId = _allCreators);
                           _loadOrders(reset: true);
                         },
                       ),
                     ),
                   if (_startDate != null)
                     Padding(
                       padding: const EdgeInsets.only(right: 8),
                       child: Chip(
                         label: Text('${DateFormat('MMM dd').format(_startDate!)} - ${DateFormat('MMM dd').format(_endDate!)}'),
                         onDeleted: () {
                           setState(() {
                             _startDate = null;
                             _endDate = null;
                           });
                           _loadOrders(reset: true);
                         },
                       ),
                     ),
                   if (_itemSearchController.text.isNotEmpty)
                     Padding(
                       padding: const EdgeInsets.only(right: 8),
                       child: Chip(
                         label: Text('Item: ${_itemSearchController.text}'),
                         onDeleted: () {
                           _itemSearchController.clear();
                           _loadOrders(reset: true);
                         },
                       ),
                     ),
                   if (_minAmountController.text.isNotEmpty)
                      Padding(
                       padding: const EdgeInsets.only(right: 8),
                       child: Chip(
                         label: Text('Min: ₹${_minAmountController.text}'),
                         onDeleted: () {
                           _minAmountController.clear();
                           _loadOrders(reset: true);
                         },
                       ),
                     ),
                 ],
               ),
             ),

          // Orders List
          Expanded(
            child: _isLoading && _orders.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null && _orders.isEmpty
                    ? ErrorStateWidget(
                        message: _errorMessage!,
                        onRetry: () => _loadOrders(reset: true),
                      )
                    : _orders.isEmpty && !_isLoading
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.shopping_cart_outlined,
                          size: 64,
                          color: AppTheme.grey.withOpacity(0.5),
                        ),
                         const SizedBox(height: 16),
                        Text(
                          _isPartialTab
                              ? 'No partial orders found'
                              : 'No orders found',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            color: AppTheme.grey,
                          ),
                        ),
                        if (_startDate != null || _searchController.text.isNotEmpty || _itemSearchController.text.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: TextButton(
                              onPressed: _resetFilters,
                              child: const Text('Clear Filters'),
                            ),
                          ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    itemCount: _orders.length + (_hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _orders.length) {
                        return const Center(
                          child: CircularProgressIndicator(),
                        );
                      }

                      final order = _orders[index];
                      if (_isPartialTab) {
                        return _buildPartialOrderTile(order);
                      }
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => OrderDetailsAdminScreen(
                                  order: order,
                                ),
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        order.orderNumber,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                    Flexible(
                                      child: Wrap(
                                        alignment: WrapAlignment.end,
                                        spacing: 4,
                                        runSpacing: 4,
                                        children: [
                                          if (order.isSaleBilled)
                                            _buildStatusBadge(
                                              'Billed',
                                              AppTheme.success,
                                              Icons.receipt_long,
                                            )
                                          else if (order.isPartiallyBilled)
                                            _buildStatusBadge(
                                              'Partial',
                                              AppTheme.warning,
                                              Icons.pending_actions,
                                            ),
                                          if (order.syncedToTally)
                                            _buildStatusBadge(
                                              'Synced',
                                              Colors.teal,
                                              Icons.sync,
                                            ),
                                          if (order.isEdited)
                                            _buildStatusBadge(
                                              'Edited',
                                              Colors.orange,
                                              Icons.edit_note,
                                            ),
                                          if (!order.isSaleBilled &&
                                              !order.isPartiallyBilled &&
                                              !order.syncedToTally &&
                                              !order.isEdited)
                                            _buildBillingBadge(false),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                if (order.companyName != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.business, size: 14, color: AppTheme.primaryBlue),
                                        const SizedBox(width: 4),
                                        Text(
                                          order.companyName!,
                                          style: const TextStyle(
                                            color: AppTheme.primaryBlue,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                if (order.salesmanName != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.badge, size: 14, color: AppTheme.grey),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Salesman: ${order.salesmanName}',
                                          style: const TextStyle(
                                            color: AppTheme.grey,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    const Icon(Icons.person_outline, size: 16, color: AppTheme.grey),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        order.customerName ?? 'Unknown Customer',
                                        style: const TextStyle(color: AppTheme.grey),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                if (order.customerMobile != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.phone_android, size: 16, color: AppTheme.grey),
                                        const SizedBox(width: 4),
                                        Text(
                                          order.customerMobile!,
                                          style: const TextStyle(color: AppTheme.grey),
                                        ),
                                      ],
                                    ),
                                  ),
                                const Divider(height: 24),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            DateFormat('MMM dd, yyyy h:mm a').format(order.orderDate),
                                            style: const TextStyle(
                                              color: AppTheme.grey,
                                              fontSize: 12,
                                            ),
                                          ),
                                          if (order.orderLatitude != null && order.orderLongitude != null)
                                            Padding(
                                              padding: const EdgeInsets.only(top: 4),
                                              child: LocationAddressWidget(
                                                latitude: order.orderLatitude!,
                                                longitude: order.orderLongitude!,
                                              ),
                                            ),
                                          const SizedBox(height: 6),
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              IconButton(
                                                icon: const Icon(Icons.print, size: 20, color: AppTheme.grey),
                                                constraints: const BoxConstraints(),
                                                padding: const EdgeInsets.only(right: 12, top: 2, bottom: 2),
                                                onPressed: () => _printOrder(order),
                                              ),
                                              IconButton(
                                                icon: const Icon(Icons.share, size: 20, color: AppTheme.grey),
                                                constraints: const BoxConstraints(),
                                                padding: const EdgeInsets.only(right: 12, top: 2, bottom: 2),
                                                onPressed: () => _shareOrder(order),
                                              ),
                                              if (order.orderLatitude != null && order.orderLongitude != null)
                                                IconButton(
                                                  icon: const Icon(Icons.map, size: 20, color: AppTheme.success),
                                                  constraints: const BoxConstraints(),
                                                  padding: const EdgeInsets.only(right: 12, top: 2, bottom: 2),
                                                  tooltip: 'View Location',
                                                  onPressed: () async {
                                                    final url = Uri.parse('https://www.google.com/maps/search/?api=1&query=${order.orderLatitude},${order.orderLongitude}');
                                                    if (await canLaunchUrl(url)) {
                                                      await launchUrl(url);
                                                    } else {
                                                      if (context.mounted) {
                                                        ScaffoldMessenger.of(context).showSnackBar(
                                                          const SnackBar(content: Text('Could not open map')),
                                                        );
                                                      }
                                                    }
                                                  },
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (order.isEdited &&
                                            order.originalAmount != null &&
                                            (order.originalAmount! - order.netAmount).abs() > 0.01) ...[
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFFEF2F2),
                                                  borderRadius: BorderRadius.circular(4),
                                                  border: Border.all(color: const Color(0xFFFECACA)),
                                                ),
                                                child: const Text(
                                                  'Before edit',
                                                  style: TextStyle(
                                                    fontSize: 9.5,
                                                    fontWeight: FontWeight.w700,
                                                    color: Color(0xFFDC2626),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 5),
                                              Text(
                                                '₹${order.originalAmount!.toStringAsFixed(2)}',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: Color(0xFF94A3B8),
                                                  decoration: TextDecoration.lineThrough,
                                                  decorationColor: Color(0xFFEF4444),
                                                  decorationThickness: 2,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 2),
                                        ],
                                        Text(
                                          '₹${order.displayAmount.toStringAsFixed(2)}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                            color: AppTheme.primaryBlue,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPartialOrderTile(OrderModel order) {
    final items = _itemsFor(order);
    final pendingItems = items.where((item) => item.isLinePending).toList();
    final pendingAmount = _pendingAmountFor(order);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(
            order.orderNumber,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              [
                if (order.customerName != null) order.customerName!,
                '${pendingItems.length} item(s) pending',
              ].join('  ·  '),
              style: const TextStyle(color: AppTheme.grey, fontSize: 12),
            ),
          ),
          trailing: Text(
            '₹${pendingAmount.toStringAsFixed(2)}',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: AppTheme.warning,
            ),
          ),
          children: [
            const Divider(height: 1),
            const SizedBox(height: 8),
            if (pendingItems.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No pending item details',
                  style: TextStyle(color: AppTheme.grey),
                ),
              )
            else
              ...pendingItems.map(
                (item) => PendingOrderItemDetails(item: item, compact: true),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: _isSharingPartial
                        ? null
                        : () => _sharePartialOrdersExcel(order: order),
                    icon: const Icon(Icons.share, size: 18),
                    label: const Text('Share Excel'),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => OrderDetailsAdminScreen(
                            order: order,
                          ),
                        ),
                      );
                    },
                    child: const Text('Open order'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String label, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBillingBadge(bool billed) {
    final color = billed ? AppTheme.success : AppTheme.warning;
    final label = billed ? 'Billed' : 'Pending';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
