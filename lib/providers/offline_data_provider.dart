import 'package:flutter/material.dart';

import 'package:Orderx/models/customer_model.dart';
import 'package:Orderx/models/product_model.dart';
import 'package:Orderx/services/admin_settings_service.dart';
import 'package:Orderx/services/customer_service.dart';
import 'package:Orderx/services/offline_cache_service.dart';
import 'package:Orderx/services/product_service.dart';

class OfflineDataProvider with ChangeNotifier {
  final CustomerService _customerService = CustomerService();
  final ProductService _productService = ProductService();
  final OfflineCacheService _cacheService = OfflineCacheService();

  bool _isSyncing = false;
  bool get isSyncing => _isSyncing;

  Future<void> logHealth() async {
    await _cacheService.logDatabaseHealth();
  }

  Future<void> syncAll(String companyId, {String? salesmanId}) async {
    if (companyId.isEmpty) return;
    if (_isSyncing) return;
    _isSyncing = true;
    notifyListeners();

    debugPrint('🔄 [SYNC]: Starting Full Sync for Company: $companyId');

    try {
      // Sync Customers
      try {
        debugPrint('👥 [SYNC]: Fetching customers...');
        final customers =
            await _customerService.getAllCustomers(companyId: companyId, salesmanId: salesmanId);
        debugPrint(
            '👥 [SYNC]: Received ${customers.length} customers from server.');

        await _cacheService.refreshCacheCustomers(customers,
            companyId: companyId);
        debugPrint('✅ [SYNC]: Customers refreshed successfully.');
      } catch (e) {
        debugPrint('❌ [SYNC]: Customer sync failed: $e');
      }

      // Sync Products
      try {
        debugPrint('📦 [SYNC]: Fetching products...');
        final products =
            await _productService.getProducts(companyId: companyId);
        debugPrint(
            '📦 [SYNC]: Received ${products.length} products from server.');

        await _cacheService.refreshCacheProducts(products,
            companyId: companyId);
        debugPrint('✅ [SYNC]: Products refreshed successfully.');
      } catch (e) {
        debugPrint('❌ [SYNC]: Product sync failed: $e');
      }

      final cCount = await _cacheService.cachedCustomerCount(companyId);
      final pCount = await _cacheService.cachedProductCount(companyId);
      debugPrint(
          '🏁 [SYNC FINISHED]: Cache Status: Customers=$cCount, Products=$pCount');
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  List<CustomerModel> _scopeToSalesman(
    List<CustomerModel> customers,
    String? salesmanId,
  ) {
    if (salesmanId == null || salesmanId.isEmpty) return customers;
    return customers
        .where((c) => c.assignedSalesmanIds.contains(salesmanId))
        .toList();
  }

  Future<List<CustomerModel>> fetchCustomers({
    required String? companyId,
    String? salesmanId,
    bool preferOnline = true,
  }) async {
    if (companyId == null) return [];

    if (preferOnline) {
      try {
        debugPrint(
            '🌐 OfflineDataProvider: Fetching customers online for $companyId salesmanId=$salesmanId...');
        final customers = await _customerService
            .getAllCustomers(companyId: companyId, salesmanId: salesmanId)
            .timeout(const Duration(seconds: 15));

        await _cacheService.refreshCacheCustomers(customers,
            companyId: companyId);
        debugPrint(
            '✅ OfflineDataProvider: Received ${customers.length} customers online.');
        return customers;
      } catch (e) {
        debugPrint(
            '📡 OfflineDataProvider: Online customer fetch failed/timed out: $e');
        debugPrint('📦 OfflineDataProvider: Falling back to local cache.');
      }
    }

    final cachedResults =
        await _cacheService.getCachedCustomers(companyId: companyId);
    debugPrint(
        '📦 OfflineDataProvider: Loaded ${cachedResults.length} customers from local cache.');
    return _scopeToSalesman(cachedResults, salesmanId);
  }

  Future<List<CustomerModel>> searchCustomers(
    String query, {
    required String? companyId,
    String? salesmanId,
    bool preferOnline = true,
  }) async {
    if (companyId == null) return [];
    if (preferOnline) {
      try {
        if (query.trim().isEmpty) {
          return fetchCustomers(
            companyId: companyId,
            salesmanId: salesmanId,
            preferOnline: true,
          );
        }
        debugPrint(
            '🌐 OfflineDataProvider: Searching customers online for "$query"...');
        final results = await _customerService
            .searchCustomers(query, companyId: companyId, salesmanId: salesmanId)
            .timeout(const Duration(seconds: 15));

        if (results.isNotEmpty) {
          // Use UPSERT for searches so we don't wipe the rest of the cache
          await _cacheService.upsertCustomers(results, companyId: companyId);
        }
        debugPrint(
            '✅ OfflineDataProvider: Found ${results.length} customers online.');
        return results;
      } catch (e) {
        debugPrint(
            '📡 OfflineDataProvider: Online customer search failed/timed out: $e');
        debugPrint('📦 OfflineDataProvider: Falling back to local cache.');
      }
    }

    final cachedResults =
        await _cacheService.searchCachedCustomers(query, companyId: companyId);
    debugPrint(
        '📦 OfflineDataProvider: Found ${cachedResults.length} customers in local cache.');
    return _scopeToSalesman(cachedResults, salesmanId);
  }

  Future<List<ProductModel>> searchProducts(
    String query, {
    required String? companyId,
    bool preferOnline = true,
  }) async {
    if (companyId == null) return [];
    final trimmed = query.trim();

    // For empty queries, load a page of products instead of using search
    if (preferOnline && trimmed.isEmpty) {
      try {
        debugPrint(
            '🌐 OfflineDataProvider: Loading products online for empty search...');
        final results = await _productService
            .getAllProducts(companyId: companyId)
            .timeout(const Duration(seconds: 15));

        if (results.isNotEmpty) {
          await _cacheService.refreshCacheProducts(results, companyId: companyId);
        }
        debugPrint(
            '✅ OfflineDataProvider: Loaded ${results.length} products online for empty search.');
        return await _filterVisibleOrderProducts(results, companyId);
      } catch (e) {
        debugPrint(
            '📡 OfflineDataProvider: Online product load (empty search) failed/timed out: $e');
        debugPrint('📦 OfflineDataProvider: Falling back to local cache.');
      }
    }

    if (preferOnline && trimmed.isNotEmpty) {
      try {
        debugPrint(
            '🌐 OfflineDataProvider: Searching products online for "$trimmed"...');
        final results = await _productService
            .searchProducts(trimmed, companyId: companyId)
            .timeout(const Duration(seconds: 5));

        if (results.isNotEmpty) {
          // Use UPSERT for searches so we don't wipe the rest of the cache
          await _cacheService.upsertProducts(results, companyId: companyId);
        }
        debugPrint(
            '✅ OfflineDataProvider: Found ${results.length} products online.');
        return await _filterVisibleOrderProducts(results, companyId);
      } catch (e) {
        debugPrint(
            '📡 OfflineDataProvider: Online product search failed/timed out: $e');
        debugPrint('📦 OfflineDataProvider: Falling back to local cache.');
      }
    }

    // Fallback to cache (no-op on web, real on mobile/desktop)
    final cachedResults = await _cacheService.searchCachedProducts(trimmed,
        companyId: companyId);
    debugPrint(
        '📦 OfflineDataProvider: Found ${cachedResults.length} products in local cache.');
    return await _filterVisibleOrderProducts(cachedResults, companyId);
  }

  Future<List<ProductModel>> getCachedProducts({
    required String? companyId,
  }) async {
    if (companyId == null) return [];
    final cached = await _cacheService.getCachedProducts(companyId: companyId);
    return await _filterVisibleOrderProducts(cached, companyId);
  }

  Future<List<ProductModel>> _filterVisibleOrderProducts(
    List<ProductModel> products,
    String? companyId,
  ) async {
    if (products.isEmpty || companyId == null || companyId.isEmpty) {
      return products;
    }
    try {
      return await AdminSettingsService().filterVisibleOrderProducts(
        products,
        companyId: companyId,
      );
    } catch (e) {
      debugPrint('⚠️ Category visibility filter failed: $e');
      return products;
    }
  }

  Future<void> refreshProductCache({
    required String? companyId,
  }) async {
    if (companyId == null) return;
    try {
      debugPrint('🔄 OfflineDataProvider: Force refreshing product cache...');
      final results = await _productService
          .getProductsPaginated(companyId: companyId, page: 0, limit: 1000)
          .timeout(const Duration(seconds: 10));
      
      if (results.isNotEmpty) {
        await _cacheService.refreshCacheProducts(results, companyId: companyId);
      }
      debugPrint('✅ OfflineDataProvider: Product cache refreshed with ${results.length} products.');
    } catch (e) {
      debugPrint('❌ OfflineDataProvider: Failed to refresh product cache: $e');
    }
  }
}
