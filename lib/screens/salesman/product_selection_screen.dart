import 'dart:async';

import 'package:Orderx/core/theme/app_theme.dart';
import 'package:Orderx/models/customer_model.dart';
import 'package:Orderx/models/product_model.dart';
import 'package:Orderx/providers/auth_provider.dart';
import 'package:Orderx/providers/cart_provider.dart';
import 'package:Orderx/providers/connectivity_provider.dart';
import 'package:Orderx/providers/offline_data_provider.dart';
import 'package:Orderx/screens/salesman/cart_screen.dart';
import 'package:Orderx/screens/salesman/product_details_screen.dart';
import 'package:Orderx/screens/salesman/qr_scanner_screen.dart';
import 'package:Orderx/services/admin_settings_service.dart';
import 'package:Orderx/services/product_service.dart';
import 'package:Orderx/widgets/app_bar_actions.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

class ProductSelectionScreen extends StatefulWidget {
  final CustomerModel? preSelectedCustomer;
  final bool canScanQr;
  final bool isSelectionMode;
  final void Function(PickedOrderProduct picked)? onProductPicked;

  const ProductSelectionScreen({
    super.key,
    this.preSelectedCustomer,
    this.canScanQr = false,
    this.isSelectionMode = false,
    this.onProductPicked,
  });

  @override
  State<ProductSelectionScreen> createState() => _ProductSelectionScreenState();
}

class _ProductSelectionScreenState extends State<ProductSelectionScreen> {
  final ProductService _productService = ProductService();
  final AdminSettingsService _settingsService = AdminSettingsService();
  final TextEditingController _searchController = TextEditingController();
  static const String _ungroupedKey = '__ungrouped__';

  List<ProductModel> _searchResults = [];
  List<String> _stockGroups = [];
  bool _hasUngrouped = false;
  String? _selectedStockGroup;
  bool _isSearching = false;
  bool _isInitialLoading = true;
  Timer? _debounceTimer;
  bool _hasLoadedOnce = false;
  final ScrollController _tabScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Perform initial empty search to show all products
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _performSearch('');
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Refresh products when screen becomes visible (e.g., after returning from cart)
    // Only refresh after the initial load to prevent excessive refreshes
    if (_hasLoadedOnce) {
      print('🔄 ProductSelectionScreen: didChangeDependencies triggered, refreshing products');
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        // Force refresh product cache to get updated stock
        final authProvider = context.read<AuthProvider>();
        String? companyId = authProvider.selectedCompanyId;
        if (companyId == null && authProvider.currentUser?.companyId != null) {
          companyId = authProvider.currentUser!.companyId;
        }
        if (companyId != null) {
          print('🔄 ProductSelectionScreen: Calling refreshProductCache for company $companyId');
          await context.read<OfflineDataProvider>().refreshProductCache(companyId: companyId);
          print('🔄 ProductSelectionScreen: Cache refresh completed');
        }
        // Then perform search with updated cache
        print('🔄 ProductSelectionScreen: Performing search with query "${_searchController.text.trim()}"');
        _performSearch(_searchController.text.trim());
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabScrollController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();

    if (query.trim().isEmpty) {
      _debounceTimer = Timer(const Duration(milliseconds: 300), () {
        _performSearch('');
      });
      return;
    }

    setState(() => _isSearching = true);
    _debounceTimer = Timer(const Duration(milliseconds: 400), () {
      _performSearch(query.trim());
    });
  }

  Future<void> _performSearch(String query) async {
    if (!mounted) return;
    setState(() => _isSearching = true);
    try {
      final authProvider = context.read<AuthProvider>();
      String? companyId = authProvider.selectedCompanyId;
      final isOnline = context.read<ConnectivityProvider>().isOnline;

      // Recovery if companyId is missing
      if (companyId == null && authProvider.currentUser?.companyId != null) {
        companyId = authProvider.currentUser!.companyId;
        debugPrint('♻️ ProductSelection: Recovered companyId: $companyId');
      }

      var results = await context.read<OfflineDataProvider>().searchProducts(
            query,
            companyId: companyId,
            preferOnline: isOnline,
          );
      try {
        results = await AdminSettingsService().filterVisibleOrderProducts(
          results,
          companyId: companyId,
        );
      } catch (e) {
        debugPrint('ProductSelection category filter failed: $e');
      }

      if (!mounted) return;
      setState(() {
        _searchResults = results;
        if (query.isEmpty) {
          _rebuildStockGroups(results);
        }
        _isSearching = false;
        _isInitialLoading = false;
        _hasLoadedOnce = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSearching = false;
        _isInitialLoading = false;
        _searchResults = [];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Search failed: ${e.toString()}')),
      );
    }
  }

  String? _itemCategoryOf(ProductModel product) {
    final category = product.itemCategory?.trim();
    if (category == null || category.isEmpty) return null;
    return category;
  }

  void _rebuildStockGroups(List<ProductModel> products) {
    final names = products
        .map(_itemCategoryOf)
        .whereType<String>()
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    _stockGroups = names;
    _hasUngrouped = products.any((p) => _itemCategoryOf(p) == null);
    if (_selectedStockGroup != null &&
        _selectedStockGroup != _ungroupedKey &&
        !_stockGroups.contains(_selectedStockGroup)) {
      _selectedStockGroup = null;
    }
  }

  List<ProductModel> get _visibleProducts {
    if (_selectedStockGroup == null) return _searchResults;
    if (_selectedStockGroup == _ungroupedKey) {
      return _searchResults.where((p) => _itemCategoryOf(p) == null).toList();
    }
    return _searchResults
        .where((p) => _itemCategoryOf(p) == _selectedStockGroup)
        .toList();
  }

  bool get _showStockGroupTabs => _stockGroups.isNotEmpty || _hasUngrouped;

  void _selectStockGroup(String? group) {
    if (_selectedStockGroup == group) return;
    setState(() => _selectedStockGroup = group);
  }

  void _clearSearch() {
    _searchController.clear();
    _performSearch('');
  }

  Future<void> _openProductDetails(ProductModel product) async {
    final picked = await ProductDetailsDialog.show(
      context,
      product: product,
      customer: widget.preSelectedCustomer,
      returnSelection: widget.onProductPicked != null,
    );
    if (!mounted) return;
    if (picked != null && widget.onProductPicked != null) {
      widget.onProductPicked!(picked);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${picked.product.productName} added to order'),
          backgroundColor: AppTheme.success,
          duration: const Duration(seconds: 1),
        ),
      );
    }
    if (_searchController.text.trim().isNotEmpty) {
      _performSearch(_searchController.text.trim());
    }
  }

  Future<void> _scanAndFetchProduct() async {
    if (!widget.canScanQr || !mounted) return;
    final scannedCode = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const QRScannerScreen()),
    );
    if (scannedCode != null && mounted) {
      await _fetchAndShowProduct(scannedCode);
    }
  }

  Future<void> _fetchAndShowProduct(String code) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final authProvider = context.read<AuthProvider>();
      final companyId = authProvider.selectedCompanyId;

      // Try to find the product in cache first if it's a code scan
      final products = await context
          .read<OfflineDataProvider>()
          .getCachedProducts(companyId: companyId);
      ProductModel? product;
      try {
        product = products.firstWhere(
          (p) => p.productCode == code || p.vtNumber == code,
        );
      } catch (_) {
        // Fallback to online if not found in cache and isOnline
        if (context.read<ConnectivityProvider>().isOnline) {
          product = await _productService.getProductByCode(code,
              companyId: companyId);
        }
      }

      if (!mounted) return;
      Navigator.pop(context);
      if (product != null) {
        final visible = await _settingsService.isProductVisibleForOrders(
          product,
          companyId: companyId,
        );
        if (!mounted) return;
        if (!visible) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                  content: Text(
                      'This item belongs to a hidden item category and cannot be added.'),
            ),
          );
          return;
        }
        await _openProductDetails(product);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Product not found in this company.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
    }
  }

  Future<void> _openCart() async {
    final orderCreated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => CartScreen(
          preSelectedCustomer: widget.preSelectedCustomer,
        ),
      ),
    );

    if (orderCreated == true && mounted) {
      Navigator.pop(context, true);
    }
  }

  bool get _isPickingForOrder => widget.onProductPicked != null;

  void _returnToPreviousScreen() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      child: GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        appBar: _isPickingForOrder
            ? AppBar(
                title: const Text('Add Item'),
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: 'Back to Edit Order',
                  onPressed: _returnToPreviousScreen,
                ),
                actions: [
                  TextButton(
                    onPressed: _returnToPreviousScreen,
                    child: const Text(
                      'DONE',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              )
            : null,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                child: Row(
                  children: [
                    if (!_isPickingForOrder)
                      IconButton(
                        icon: const Icon(Icons.arrow_back),
                        tooltip: 'Back',
                        onPressed: _returnToPreviousScreen,
                      ),
                    if (!_isPickingForOrder) const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: _onSearchChanged,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: 'Search by Item Code or Name...',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _buildSuffixIcon(),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14.0),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: Colors.grey.withOpacity(0.15),
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 14.0,
                            horizontal: 12,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      tooltip: 'Refresh',
                      onPressed: _isInitialLoading || _isSearching
                          ? null
                          : () => _performSearch(_searchController.text.trim()),
                    ),
                    if (!widget.isSelectionMode && widget.onProductPicked == null)
                      AppBarCartButton(onPressed: _openCart),
                  ],
                ),
              ),
              if (_showStockGroupTabs && !_isInitialLoading)
                _buildStockGroupTabs(),
              if (!_isInitialLoading && !_isSearching)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${_visibleProducts.length} Products Found',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              if (!_isInitialLoading && !_isSearching)
                const SizedBox(height: 8),
              Expanded(
                child: _isInitialLoading || _isSearching
                    ? const Center(child: CircularProgressIndicator())
                    : _visibleProducts.isEmpty
                        ? _buildEmptyState()
                        : _buildResultList(),
              ),
              if (!_isPickingForOrder)
              Consumer<CartProvider>(
                builder: (context, cartProvider, child) {
                  if (cartProvider.itemCount == 0) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    child: Card(
                      color: AppTheme.success.withOpacity(0.1),
                      child: ListTile(
                        leading: const Icon(Icons.shopping_cart,
                            color: AppTheme.success, size: 32),
                        title: Text(
                          'Current Cart',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                        subtitle: Text(
                          '${cartProvider.totalQuantity == cartProvider.totalQuantity.truncateToDouble() ? cartProvider.totalQuantity.toInt() : cartProvider.totalQuantity} items • ₹${cartProvider.grandTotal.toStringAsFixed(2)}',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: AppTheme.success,
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                        trailing: const Icon(Icons.arrow_forward_ios,
                            color: AppTheme.success, size: 18),
                        onTap: _openCart,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }

  void _scrollTabsBy(double delta) {
    if (!_tabScrollController.hasClients) return;
    final next = (_tabScrollController.offset + delta).clamp(
      0.0,
      _tabScrollController.position.maxScrollExtent,
    );
    _tabScrollController.animateTo(
      next,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  Widget _buildStockGroupTabs() {
    final tabs = <MapEntry<String?, String>>[
      const MapEntry(null, 'All'),
      ..._stockGroups.map((name) => MapEntry<String?, String>(name, name)),
      if (_hasUngrouped) const MapEntry(_ungroupedKey, 'Others'),
    ];

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: SizedBox(
        height: 48,
        child: Row(
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Previous groups',
            onPressed: () => _scrollTabsBy(-180),
            icon: const Icon(Icons.chevron_left, size: 22),
          ),
          Expanded(
            child: Listener(
              onPointerSignal: (event) {
                if (event is! PointerScrollEvent) return;
                if (!_tabScrollController.hasClients) return;
                final delta = event.scrollDelta.dx != 0
                    ? event.scrollDelta.dx
                    : event.scrollDelta.dy;
                final next = (_tabScrollController.offset + delta).clamp(
                  0.0,
                  _tabScrollController.position.maxScrollExtent,
                );
                _tabScrollController.jumpTo(next);
              },
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(
                  scrollbars: false,
                  dragDevices: {
                    PointerDeviceKind.touch,
                    PointerDeviceKind.mouse,
                    PointerDeviceKind.trackpad,
                    PointerDeviceKind.stylus,
                  },
                ),
                child: ListView.separated(
                  controller: _tabScrollController,
                  primary: false,
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  itemCount: tabs.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final tab = tabs[index];
                    final selected = _selectedStockGroup == tab.key;
                    return Material(
                      color: selected ? AppTheme.primaryBlue : AppTheme.lightGrey,
                      borderRadius: BorderRadius.circular(20),
                      child: InkWell(
                        onTap: () => _selectStockGroup(tab.key),
                        borderRadius: BorderRadius.circular(20),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          child: Text(
                            tab.value,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight:
                                  selected ? FontWeight.w600 : FontWeight.w500,
                              color: selected ? Colors.white : AppTheme.darkGrey,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Next groups',
            onPressed: () => _scrollTabsBy(180),
            icon: const Icon(Icons.chevron_right, size: 22),
          ),
        ],
        ),
      ),
    );
  }

  Widget? _buildSuffixIcon() {
    if (_isSearching) {
      return const Padding(
        padding: EdgeInsets.all(12.0),
        child: SizedBox(
          height: 20,
          width: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (_searchController.text.isNotEmpty) {
      return IconButton(
        icon: const Icon(Icons.clear),
        onPressed: _clearSearch,
        tooltip: 'Clear Search',
      );
    }

    return null;
  }

  Widget _buildEmptyState() {
    final hasSearch = _searchController.text.trim().isNotEmpty;
    final hasGroup = _selectedStockGroup != null;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2,
                size: 64, color: AppTheme.primaryBlue.withOpacity(0.4)),
            const SizedBox(height: 16),
            Text(
              hasSearch
                  ? 'No products match your search.'
                  : hasGroup
                      ? 'No products in this category.'
                      : 'No products found.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AppTheme.grey,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultList() {
    return ListView.separated(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      itemCount: _visibleProducts.length,
      separatorBuilder: (_, __) => const Divider(height: 1, thickness: 0.4),
      itemBuilder: (context, index) {
        final product = _visibleProducts[index];
        final isSalesman = context.read<AuthProvider>().currentUser?.isSalesman ?? false;
        final isOutOfStock = !isSalesman && product.stock <= 0;

        return InkWell(
          onTap: () => _openProductDetails(product),
          child: Container(
            decoration: BoxDecoration(
              border:
                  Border.all(color: Colors.black.withOpacity(0.12), width: 0.8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ProductThumbnail(
                  imageUrl: product.imageUrl,
                  isOutOfStock: isOutOfStock,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              product.productName,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color:
                                    isOutOfStock ? Colors.grey : Colors.black,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isOutOfStock) _OutOfStockBadge(),
                        ],
                      ),
                      const SizedBox(height: 0.5),
                      Row(
                        children: [
                          if (product.hsn != null && product.hsn!.isNotEmpty) ...[
                            Text(
                              product.hsn!,
                              style: TextStyle(
                                fontSize: 10,
                                color: isOutOfStock ? Colors.grey : AppTheme.grey,
                              ),
                            ),
                            const SizedBox(width: 10),
                          ],
                          Text(
                            'GST: ${product.gstRate.toStringAsFixed(product.gstRate.truncateToDouble() == product.gstRate ? 0 : 1)}%',
                            style: TextStyle(
                              fontSize: 10,
                              color: isOutOfStock ? Colors.grey : AppTheme.grey,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      if (!isSalesman)
                        Text(
                          'Stock: ${product.stock}',
                          style: TextStyle(
                            fontSize: 10,
                            color: isOutOfStock
                                ? Colors.orange
                                : AppTheme.primaryBlue,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '₹${product.price.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: isOutOfStock ? Colors.grey : Colors.black,
                      ),
                    ),
                    Text(
                      '₹${(product.price + (product.price * product.gstRate / 100)).toStringAsFixed(2)} incl. GST',
                      style: TextStyle(
                        fontSize: 8.5,
                        color: isOutOfStock ? Colors.grey : AppTheme.grey,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ProductThumbnail extends StatelessWidget {
  final String? imageUrl;
  final bool isOutOfStock;

  const _ProductThumbnail({
    required this.imageUrl,
    required this.isOutOfStock,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      width: 44,
      decoration: BoxDecoration(
        color: isOutOfStock ? Colors.grey.withOpacity(0.2) : AppTheme.lightGrey,
        borderRadius: BorderRadius.zero,
        image: (imageUrl != null && imageUrl!.isNotEmpty)
            ? DecorationImage(
                image: NetworkImage(imageUrl!),
                fit: BoxFit.cover,
                colorFilter: isOutOfStock
                    ? const ColorFilter.mode(Colors.grey, BlendMode.saturation)
                    : null,
              )
            : null,
      ),
      child: (imageUrl == null || imageUrl!.isEmpty)
          ? Icon(
              Icons.inventory_2,
              color: isOutOfStock ? Colors.grey : AppTheme.primaryBlue,
            )
          : null,
    );
  }
}

class _OutOfStockBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.error.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.error, width: 0.8),
      ),
      child: const Text(
        'Out of Stock',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: AppTheme.error,
        ),
      ),
    );
  }
}
