// lib/services/admin_settings_service.dart
import 'package:Orderx/models/admin_settings.dart';
import 'package:Orderx/models/product_model.dart';
import 'package:Orderx/utils/item_category_visibility.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminSettingsService {
  final SupabaseClient _client = Supabase.instance.client;
  static final Map<String, List<String>> _hiddenItemCategoriesCache = {};
  static final Map<String, DateTime> _hiddenItemCategoriesCachedAt = {};

  Future<String> _canonicalCompanyId(String companyId) async {
    final key = companyId.trim();
    if (key.isEmpty || key == 'ALL') return key;

    Future<List<Map<String, dynamic>>> lookup(String column) async {
      final res = await _client
          .from('tally_companies')
          .select('id')
          .eq(column, key)
          .limit(1);
      return List<Map<String, dynamic>>.from(res as List);
    }

    final byId = await lookup('id');
    if (byId.isNotEmpty) return byId.first['id'] as String;
    final byGuid = await lookup('Guid');
    if (byGuid.isNotEmpty) return byGuid.first['id'] as String;
    return key;
  }

  Future<List<Map<String, dynamic>>> _settingsRows(
    String companyId, {
    String columns = '*',
    int? limit,
  }) async {
    final List response;
    if (limit != null) {
      response = await _client
          .from('company_settings')
          .select(columns)
          .eq('company_id', companyId)
          .limit(limit);
    } else {
      response = await _client
          .from('company_settings')
          .select(columns)
          .eq('company_id', companyId);
    }
    final rows = List<Map<String, dynamic>>.from(response);
    rows.sort((a, b) {
      final aDate = DateTime.tryParse('${a['updated_at'] ?? ''}') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = DateTime.tryParse('${b['updated_at'] ?? ''}') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });
    return rows;
  }

  Future<Map<String, dynamic>?> _latestSettingsRow(String companyId) async {
    final rows = await _settingsRows(companyId, limit: 50);
    if (rows.isEmpty) return null;
    return rows.first;
  }

  Future<void> _dedupeSettings(String companyId) async {
    final rows = await _settingsRows(companyId, columns: 'id,updated_at');
    if (rows.length <= 1) return;

    final keepId = rows.first['id'];
    try {
      await _client
          .from('company_settings')
          .delete()
          .eq('company_id', companyId)
          .neq('id', keepId)
          .select('id');
      print(
          'Removed ${rows.length - 1} duplicate company_settings rows for $companyId');
    } catch (e) {
      print('Could not remove duplicate company_settings: $e');
    }
  }

  Future<Map<String, dynamic>> _ensureSettingsRow(String companyId) async {
    final resolved = await _canonicalCompanyId(companyId);
    var row = await _latestSettingsRow(resolved);
    if (row == null && resolved != companyId) {
      row = await _latestSettingsRow(companyId);
    }
    if (row == null) {
      await _createDefaultSettings(resolved);
      row = await _latestSettingsRow(resolved);
    } else {
      await _dedupeSettings(resolved);
      row = await _latestSettingsRow(resolved) ??
          await _latestSettingsRow(companyId) ??
          row;
    }
    if (row == null) {
      throw Exception('Unable to load company settings for $companyId');
    }
    return row;
  }

  /// Updates every matching settings row. Never uses .single()/.maybeSingle().
  Future<void> _applySettingsUpdate(
      String companyId, Map<String, dynamic> data) async {
    final resolved = await _canonicalCompanyId(companyId);
    if (resolved.isEmpty || resolved == 'ALL') {
      throw Exception('Select a company before changing settings');
    }

    final payload = <String, dynamic>{
      ...data,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

    Future<List<dynamic>> patchByCompanyId(String id) async {
      final res = await _client
          .from('company_settings')
          .update(payload)
          .eq('company_id', id)
          .select('id');
      return List<dynamic>.from(res as List);
    }

    var updated = await patchByCompanyId(resolved);
    if (updated.isEmpty && companyId != resolved) {
      updated = await patchByCompanyId(companyId);
    }

    if (updated.isEmpty) {
      await _createDefaultSettings(resolved);
      updated = await patchByCompanyId(resolved);
    }

    if (updated.length > 1) {
      await _dedupeSettings(resolved);
    }
  }

  Future<void> _createDefaultSettings(String companyId) async {
    try {
      final existing = await _settingsRows(companyId, columns: 'id', limit: 1);
      if (existing.isNotEmpty) return;

      final companyRows = await _client
          .from('tally_companies')
          .select('company_name')
          .eq('id', companyId)
          .limit(1);
      final companyList = List<Map<String, dynamic>>.from(companyRows as List);
      final actualCompanyName = companyList.isNotEmpty
          ? (companyList.first['company_name'] as String?) ?? 'Unknown Company'
          : 'Unknown Company';

      final defaultSettings = AdminSettings(
        companyId: companyId,
        companyName: actualCompanyName,
        contactEmail: null,
        contactPhone: null,
        notificationsEnabled: true,
        lastUpdated: DateTime.now(),
        allowCustomerCreation: true,
        allowQrScanning: true,
        allowItemDiscounts: true,
        allowOrderDiscounts: true,
        allowCategorySelection: true,
        allowPriceLevelSalesmanDashboardControl: true,
        orderEditWindowMinutes: 30,
        allowOrderEditing: true,
        syncSoToTally: true,
        globalGstRate: 0.0,
      );

      await _client
          .from('company_settings')
          .insert(defaultSettings.toJson())
          .select('id');
    } catch (e) {
      print('Error creating default settings: $e');
      rethrow;
    }
  }

  Future<AdminSettings> getAdminSettings(String companyId) async {
    try {
      final row = await _ensureSettingsRow(companyId);
      return AdminSettings.fromJson(row);
    } catch (e) {
      print('Error fetching admin settings: $e');
      rethrow;
    }
  }

  Future<String> getSettingsId(String companyId) async {
    try {
      final row = await _ensureSettingsRow(companyId);
      return row['id'] as String;
    } catch (e) {
      print('Error fetching settings ID: $e');
      rethrow;
    }
  }

  Future<void> updateSettings(
      String companyId, Map<String, dynamic> data) async {
    try {
      await _applySettingsUpdate(companyId, data);
    } catch (e) {
      print('Error updating settings: $e');
      rethrow;
    }
  }

  Future<bool> canSalesmanAddCustomer(String companyId) async {
    try {
      final row = await _ensureSettingsRow(companyId);
      return row['allow_customer_creation'] ?? true;
    } catch (e) {
      print('Error fetching customer creation setting: $e');
      return true;
    }
  }

  Future<bool> canSalesmanScanQr(String companyId) async {
    try {
      final row = await _ensureSettingsRow(companyId);
      return row['allow_qr_scanning'] ?? true;
    } catch (e) {
      print('Error fetching QR scanning setting: $e');
      return true;
    }
  }

  Future<bool> canUseItemDiscounts(String companyId) async {
    try {
      final row = await _ensureSettingsRow(companyId);
      return row['allow_item_discounts'] ?? true;
    } catch (e) {
      print('Error fetching item discount setting: $e');
      return true;
    }
  }

  Future<bool> canUseOrderDiscounts(String companyId) async {
    try {
      final row = await _ensureSettingsRow(companyId);
      return row['allow_order_discounts'] ?? true;
    } catch (e) {
      print('Error fetching order discount setting: $e');
      return true;
    }
  }

  Future<bool> canUseCategorySelection(String companyId) async {
    try {
      final row = await _ensureSettingsRow(companyId);
      return row['allow_category_selection'] ?? true;
    } catch (e) {
      print('Error fetching category selection setting: $e');
      return true;
    }
  }

  Future<bool> canUsePaymentType(String companyId) async {
    try {
      final row = await _ensureSettingsRow(companyId);
      return row['allow_payment_type'] ?? true;
    } catch (e) {
      print('Error fetching payment type setting: $e');
      return true;
    }
  }

  Future<bool> canSalesmanControlPriceLevelFromDashboard(
      String companyId) async {
    try {
      final row = await _ensureSettingsRow(companyId);
      return row['allow_price_level_salesman_dashboard_control'] ?? true;
    } catch (e) {
      print('Error fetching price level dashboard control setting: $e');
      return true;
    }
  }

  Future<int> getOrderEditWindowMinutes(String companyId) async {
    try {
      final row = await _ensureSettingsRow(companyId);
      return (row['order_edit_window_minutes'] as num?)?.toInt() ?? 30;
    } catch (e) {
      print('Error fetching order edit window minutes: $e');
      return 30;
    }
  }

  Future<void> saveOrderEditWindowMinutes(String companyId, int minutes) async {
    try {
      await _applySettingsUpdate(
          companyId, {'order_edit_window_minutes': minutes});
    } catch (e) {
      print('Error saving order edit window minutes: $e');
      rethrow;
    }
  }

  Future<bool> getOrderEditingEnabled(String companyId) async {
    try {
      final row = await _ensureSettingsRow(companyId);
      return row['allow_order_editing'] ?? true;
    } catch (e) {
      print('Error fetching order editing enabled: $e');
      return true;
    }
  }

  Future<void> saveOrderEditingEnabled(String companyId, bool value) async {
    try {
      await _applySettingsUpdate(companyId, {'allow_order_editing': value});
    } catch (e) {
      print('Error saving order editing enabled: $e');
      rethrow;
    }
  }

  Future<void> updateAdminSettingsWithId(
      AdminSettings settings, String id) async {
    await _client
        .from('company_settings')
        .update(settings.toJson())
        .eq('id', id)
        .select('id');
  }

  Future<double> getGlobalGstRate(String companyId) async {
    try {
      final row = await _ensureSettingsRow(companyId);
      return (row['global_gst_rate'] as num?)?.toDouble() ?? 0.0;
    } catch (e) {
      print('Error fetching global GST rate: $e');
      return 0.0;
    }
  }

  Future<List<String>> getHiddenItemCategoryNames(String companyId) async {
    final key = companyId.trim();
    if (key.isEmpty || key == 'ALL') return const [];
    final cachedAt = _hiddenItemCategoriesCachedAt[key];
    final cached = _hiddenItemCategoriesCache[key];
    if (cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt).inSeconds < 60) {
      return cached;
    }
    try {
      final row = await _ensureSettingsRow(key);
      final names = parseHiddenItemCategoryNames(row['hidden_stock_group_names']);
      _hiddenItemCategoriesCache[key] = names;
      _hiddenItemCategoriesCachedAt[key] = DateTime.now();
      return names;
    } catch (e) {
      print('Error fetching hidden item categories: $e');
      return _hiddenItemCategoriesCache[key] ?? const [];
    }
  }

  Future<void> saveHiddenItemCategoryNames(
      String companyId, List<String> names) async {
    final unique = names
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    await _applySettingsUpdate(
        companyId, {'hidden_stock_group_names': unique});
    invalidateHiddenItemCategoriesCache(companyId);
    _hiddenItemCategoriesCache[companyId.trim()] = unique;
    _hiddenItemCategoriesCachedAt[companyId.trim()] = DateTime.now();
  }

  static void invalidateHiddenItemCategoriesCache([String? companyId]) {
    if (companyId == null || companyId.trim().isEmpty) {
      _hiddenItemCategoriesCache.clear();
      _hiddenItemCategoriesCachedAt.clear();
      return;
    }
    final key = companyId.trim();
    _hiddenItemCategoriesCache.remove(key);
    _hiddenItemCategoriesCachedAt.remove(key);
  }

  Future<List<ProductModel>> filterVisibleOrderProducts(
    List<ProductModel> products, {
    required String? companyId,
  }) async {
    if (products.isEmpty || companyId == null || companyId.isEmpty) {
      return products;
    }
    final hidden = await getHiddenItemCategoryNames(companyId);
    return filterProductsByEnabledItemCategories(products, hidden);
  }

  Future<bool> isProductVisibleForOrders(
    ProductModel product, {
    required String? companyId,
  }) async {
    if (companyId == null || companyId.isEmpty) return true;
    final hidden = await getHiddenItemCategoryNames(companyId);
    return isProductInEnabledItemCategory(product, hidden);
  }
}
