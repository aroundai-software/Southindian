// order_service.dart
// All order data is stored in sales_orders + order_items tables.
// OrderModel is a view over sales_orders — column mapping is handled here.

import 'package:Orderx/models/cart_item_model.dart';
import 'package:Orderx/models/order_model.dart';
import 'package:Orderx/models/admin_settings.dart';
import 'package:Orderx/services/admin_settings_service.dart';
import 'package:Orderx/services/customer_service.dart';
import 'package:Orderx/utils/company_query.dart';
import 'package:Orderx/utils/rounding_utils.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class OrderService {
  final SupabaseClient _supabase = Supabase.instance.client;



  // ─── Column mapping ────────────────────────────────────────────────────────
  // sales_orders column  →  OrderModel field
  // order_number         →  orderNumber
  // order_date           →  orderDate
  // is_edited            →  isEdited
  // is_sale_billed       →  isSaleBilled
  // is_partially_billed  →  isPartiallyBilled
  // so_synced_to_tally   →  syncedToTally (fallback: synced_to_tally)
  // (no round_off col)   →  roundOff (default null)
  // ──────────────────────────────────────────────────────────────────────────

  double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) {
      try {
        return double.parse(value.replaceAll('+', ''));
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// Build an OrderModel from a sales_orders row.
  OrderModel _buildOrderModelFromJson(
    Map<String, dynamic> json, {
    String? customerMobile,
    String? customerGst,
    String? customerAddress,
    String? salesmanName,
  }) {
    DateTime? parseDateTime(dynamic value) {
      if (value == null) return null;
      try {
        return DateTime.parse(value as String).toLocal();
      } catch (_) {
        return null;
      }
    }

    return OrderModel(
      id: json['id'] as String,
      orderNumber: (json['order_number'] ?? '') as String,
      customerId: json['customer_id'] as String?,
      customerName: json['customer_name'] as String?,
      salesmanId: json['salesman_id'] as String,
      salesmanName: salesmanName,
      orderDate: parseDateTime(json['order_date']) ?? DateTime.now(),
      subtotalBeforeDiscount:
          _parseDouble(json['subtotal_before_discount']) ?? 0.0,
      orderDiscountAmount: _parseDouble(json['discount_amount']) ?? 0.0,
      orderDiscountPercentage: _parseDouble(json['discount_percentage']) ?? 0.0,
      totalAmount: _parseDouble(json['total_amount']) ?? 0.0,
      gstAmount: _parseDouble(json['gst_amount']) ?? 0.0,
      netAmount: _parseDouble(json['net_amount']) ?? 0.0,
      roundOff: _parseDouble(json['round_off']),
      status: json['status'] as String? ?? 'approved',
      notes: json['notes'] as String?,
      syncedToTally: json['so_synced_to_tally'] == true ||
          json['synced_to_tally'] == true,
      tallySyncDate: parseDateTime(
          json['so_tally_sync_date'] ?? json['tally_sync_date']),
      createdAt: parseDateTime(json['created_at']) ?? DateTime.now(),
      updatedAt: parseDateTime(json['updated_at']),
      isSaleBilled: json['is_sale_billed'] == true,
      isPartiallyBilled: json['is_partially_billed'] == true,
      billedAmount: _parseDouble(json['billed_amount']) ?? 0.0,
      isEdited: json['is_edited'] == true,
      originalAmount: _parseDouble(json['original_amount']),
      editHistory: (json['edit_history'] as List<dynamic>?)
          ?.map((e) => OrderEditRecord.fromJson(e is Map<String, dynamic>
              ? e
              : Map<String, dynamic>.from(e as Map)))
          .toList(),
      customerMobile: customerMobile,
      customerAddress: customerAddress,
      customerGst: customerGst,
      shippingAddress: json['shipping_address'] as String?,
      remarks: json['remarks'] as String?,
      dispatchedThrough: json['dispatched_through'] as String?,
      destination: json['destination'] as String?,
      companyId: json['company_id'] as String?,
      companyName: json['company_name'] as String?,
      ledger: json['Type'] as String? ?? 'Credit',
      canEditUntil: parseDateTime(json['can_edit_until']),
      editRequestStatus: json['edit_request_status'] as String? ?? 'none',
      editRequestedAt: parseDateTime(json['edit_requested_at']),
      editApprovedAt: parseDateTime(json['edit_approved_at']),
      editRejectedAt: parseDateTime(json['edit_rejected_at']),
      orderLatitude: _parseDouble(json['order_latitude']),
      orderLongitude: _parseDouble(json['order_longitude']),
      orderAddress: json['order_address'] as String?,
      distanceFromCustomer: _parseDouble(json['distance_from_customer']),
    );
  }

  /// Batch fetch customer details map keyed by customer id.
  Future<Map<String, Map<String, String?>>> _fetchCustomerMap(
      Set<String> customerIds) async {
    final Map<String, Map<String, String?>> result = {};
    if (customerIds.isEmpty) return result;
    try {
      final orExpr = customerIds.map((id) => 'id.eq.$id').join(',');
      final rows = await _supabase
          .from('customers')
          .select(
              'id, mobile_number, address, city, state, pincode, gst_number')
          .or(orExpr);
      for (final c in rows as List) {
        final parts = <String>[];
        if (c['address'] != null) parts.add(c['address']);
        if (c['city'] != null) parts.add(c['city']);
        if (c['state'] != null) parts.add(c['state']);
        if (c['pincode'] != null) parts.add(c['pincode']);
        result[c['id'] as String] = {
          'mobile': c['mobile_number'] as String?,
          'gst': c['gst_number'] as String?,
          'address': parts.isNotEmpty ? parts.join(', ') : null,
        };
      }
    } catch (_) {}
    return result;
  }

  // ─── READ ─────────────────────────────────────────────────────────────────

  /// Get orders created by this salesman.
  Future<List<OrderModel>> getOrdersBySalesman(String salesmanId,
      {String? companyId}) async {
    try {
      print(
          '🔍 getOrdersBySalesman - salesmanId: $salesmanId, companyId: $companyId');
      dynamic query = _supabase
          .from('sales_orders')
          .select()
          .eq('salesman_id', salesmanId);

      if (companyId != null &&
          companyId.isNotEmpty &&
          companyId != 'ALL') {
        final keys = await companyKeys(companyId);
        query = applySalesOrderCompanyFilter(query, keys);
      }

      query = query.order('created_at', ascending: false);
      final List data = await query as List;

      print('🔍 getOrdersBySalesman - fetched ${data.length} orders');
      final rows = data
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();

      final fetchedCustomerIds = {
        for (final row in rows)
          if (row['customer_id'] != null &&
              row['customer_id'].toString().isNotEmpty)
            row['customer_id'] as String,
      };
      final customerMap = await _fetchCustomerMap(fetchedCustomerIds);

      return rows.map((json) {
        final cid = json['customer_id'] as String?;
        final details = cid != null ? customerMap[cid] : null;
        return _buildOrderModelFromJson(
          json,
          customerMobile: details?['mobile'],
          customerGst: details?['gst'],
          customerAddress: details?['address'],
        );
      }).toList();
    } catch (e) {
      print('Error fetching orders: $e');
      rethrow;
    }
  }

  /// Get all orders (admin view, reads from sales_orders).
  Future<List<OrderModel>> getAllOrders({String? companyId}) async {
    try {
      dynamic query = _supabase.from('sales_orders').select();

      if (companyId != null && companyId != 'ALL') {
        final keys = await companyKeys(companyId);
        query = applySalesOrderCompanyFilter(query, keys);
      }

      query = query.order('order_date', ascending: false);

      final List data = await query as List;

      final customerIds = {
        for (final row in data)
          if (row['customer_id'] != null &&
              row['customer_id'].toString().isNotEmpty)
            row['customer_id'] as String,
      };
      final customerMap = await _fetchCustomerMap(customerIds);

      // Batch fetch salesman names
      final salesmanIds = {
        for (final row in data)
          if (row['salesman_id'] != null &&
              row['salesman_id'].toString().isNotEmpty)
            row['salesman_id'] as String,
      };
      final Map<String, String> salesmanNameMap = {};
      if (salesmanIds.isNotEmpty) {
        try {
          final orExpr = salesmanIds.map((id) => 'id.eq.$id').join(',');
          final rows =
              await _supabase.from('users').select('id, name').or(orExpr);
          for (final s in rows as List) {
            if (s['name'] != null) {
              salesmanNameMap[s['id'] as String] = s['name'] as String;
            }
          }
        } catch (_) {}
      }

      return data.map((json) {
        final cid = json['customer_id'] as String?;
        final sid = json['salesman_id'] as String?;
        final details = cid != null ? customerMap[cid] : null;
        return _buildOrderModelFromJson(
          json as Map<String, dynamic>,
          customerMobile: details?['mobile'],
          customerGst: details?['gst'],
          customerAddress: details?['address'],
          salesmanName: sid != null ? salesmanNameMap[sid] : null,
        );
      }).toList();
    } catch (e) {
      print('Error fetching all orders: $e');
      return [];
    }
  }

  Future<List<({String id, String name})>> listUsersByRole({
    required String role,
    String? companyId,
  }) async {
    dynamic query = _supabase.from('users').select('id, name');
    if (role == 'admin') {
      query = query.inFilter('user_type', ['admin', 'super_admin']);
    } else {
      query = query.eq('user_type', 'salesman');
    }
    if (companyId != null && companyId.isNotEmpty && companyId != 'ALL') {
      query = query.eq('company_id', companyId);
    }
    final rows = await query as List;
    final users = rows
        .map((row) => (
              id: row['id']?.toString() ?? '',
              name: (row['name'] ?? 'Unknown').toString(),
            ))
        .where((user) => user.id.isNotEmpty)
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return users;
  }

  Future<List<String>> _userIdsForCreatorRole({
    required String role,
    String? companyId,
  }) async {
    final users = await listUsersByRole(role: role, companyId: companyId);
    return users.map((user) => user.id).toList();
  }

  Future<bool> isCreatedByAdmin(String userId) async {
    try {
      final row = await _supabase
          .from('users')
          .select('user_type')
          .eq('id', userId)
          .maybeSingle();
      final type = (row?['user_type'] ?? '').toString().toLowerCase();
      return type == 'admin' || type == 'super_admin';
    } catch (e) {
      print('Error checking order creator type: $e');
      return false;
    }
  }

  /// Get orders with filters for admin screen.
  Future<List<OrderModel>> getOrdersWithFilters({
    String? companyId,
    int page = 1,
    int pageSize = 20,
    String? searchQuery,
    String? itemName,
    DateTime? startDate,
    DateTime? endDate,
    double? minAmount,
    double? maxAmount,
    String? createdByRole,
    String? createdByUserId,
    bool partiallyBilledOnly = false,
  }) async {
    try {
      print(
          '🔍 getOrdersWithFilters - companyId: $companyId, page: $page, searchQuery: $searchQuery, createdByRole: $createdByRole');
      dynamic query = _supabase.from('sales_orders').select();

      if (companyId != null && companyId != 'ALL') {
        final keys = await companyKeys(companyId);
        query = applySalesOrderCompanyFilter(query, keys);
      }

      if (createdByUserId != null && createdByUserId.isNotEmpty) {
        query = query.eq('salesman_id', createdByUserId);
      } else if (createdByRole == 'admin' || createdByRole == 'salesman') {
        final ids = await _userIdsForCreatorRole(
          role: createdByRole!,
          companyId: companyId,
        );
        if (ids.isEmpty) return [];
        query = query.inFilter('salesman_id', ids);
      }

      if (startDate != null) {
        final startOfDay = DateTime(
          startDate.year,
          startDate.month,
          startDate.day,
        );
        query = query.gte('order_date', startOfDay.toIso8601String());
      }

      if (endDate != null) {
        final endOfDay = DateTime(
          endDate.year,
          endDate.month,
          endDate.day,
          23,
          59,
          59,
          999,
        );
        query = query.lte('order_date', endOfDay.toIso8601String());
      }

      if (minAmount != null) {
        query = query.gte('net_amount', minAmount);
      }

      if (maxAmount != null) {
        query = query.lte('net_amount', maxAmount);
      }

      if (searchQuery != null && searchQuery.isNotEmpty) {
        query = query.or(
            'order_number.ilike.%$searchQuery%,customer_name.ilike.%$searchQuery%');
      }

      if (partiallyBilledOnly) {
        query = query.eq('is_partially_billed', true);
      }

      query = query.order('created_at', ascending: false);

      final offset = (page - 1) * pageSize;
      query = query.range(offset, offset + pageSize - 1);

      final List data = await query as List;
      print('🔍 getOrdersWithFilters - fetched ${data.length} orders');

      final customerIds = {
        for (final row in data)
          if (row['customer_id'] != null &&
              row['customer_id'].toString().isNotEmpty)
            row['customer_id'] as String,
      };
      final customerMap = await _fetchCustomerMap(customerIds);

      // Batch fetch salesman names
      final salesmanIds = {
        for (final row in data)
          if (row['salesman_id'] != null &&
              row['salesman_id'].toString().isNotEmpty)
            row['salesman_id'] as String,
      };
      final Map<String, String> salesmanNameMap = {};
      if (salesmanIds.isNotEmpty) {
        try {
          final orExpr = salesmanIds.map((id) => 'id.eq.$id').join(',');
          final rows =
              await _supabase.from('users').select('id, name').or(orExpr);
          for (final s in rows as List) {
            if (s['name'] != null) {
              salesmanNameMap[s['id'] as String] = s['name'] as String;
            }
          }
        } catch (_) {}
      }

      return data.map((json) {
        final cid = json['customer_id'] as String?;
        final sid = json['salesman_id'] as String?;
        final details = cid != null ? customerMap[cid] : null;
        return _buildOrderModelFromJson(
          json as Map<String, dynamic>,
          customerMobile: details?['mobile'],
          customerGst: details?['gst'],
          customerAddress: details?['address'],
          salesmanName: sid != null ? salesmanNameMap[sid] : null,
        );
      }).toList();
    } catch (e) {
      print('Error fetching orders with filters: $e');
      return [];
    }
  }

  Future<Map<String, List<OrderItemModel>>> getOrderItemsByOrderIds(
    List<String> orderIds,
  ) async {
    final Map<String, List<OrderItemModel>> result = {
      for (final id in orderIds) id: <OrderItemModel>[],
    };
    if (orderIds.isEmpty) return result;
    try {
      const chunkSize = 80;
      for (var i = 0; i < orderIds.length; i += chunkSize) {
        final end =
            i + chunkSize > orderIds.length ? orderIds.length : i + chunkSize;
        final chunk = orderIds.sublist(i, end);
        final rows = await _supabase
            .from('order_items')
            .select()
            .inFilter('order_id', chunk);
        for (final json in rows as List) {
          final item = OrderItemModel.fromJson(
            Map<String, dynamic>.from(json as Map),
          );
          result.putIfAbsent(item.orderId, () => <OrderItemModel>[]).add(item);
        }
      }
    } catch (e) {
      print('Error fetching order items by order ids: $e');
    }
    return result;
  }

  /// Get order by ID.
  Future<OrderModel?> getOrderById(String orderId) async {
    try {
      final response = await _supabase
          .from('sales_orders')
          .select()
          .eq('id', orderId)
          .maybeSingle();

      if (response == null) return null;

      final json = response as Map<String, dynamic>;
      final customerId = json['customer_id'] as String?;

      Map<String, String?>? customerDetails;
      if (customerId != null) {
        final customerMap = await _fetchCustomerMap({customerId});
        customerDetails = customerMap[customerId];
      }

      return _buildOrderModelFromJson(
        json,
        customerMobile: customerDetails?['mobile'],
        customerGst: customerDetails?['gst'],
        customerAddress: customerDetails?['address'],
      );
    } catch (e) {
      print('Error fetching order by ID: $e');
      return null;
    }
  }

  /// Get items for an order (reads from order_items using order_id).
  Future<List<OrderItemModel>> getOrderItems(String orderId) async {
    try {
      final response =
          await _supabase.from('order_items').select().eq('order_id', orderId);

      final items = response as List;
      if (items.isEmpty) return [];

      // Fetch product data for vt_number, mrp, hsn
      final productIds = items
          .map((item) => item['product_id']?.toString())
          .where((id) => id != null && id.isNotEmpty)
          .toSet()
          .cast<String>()
          .toList();

      final Map<String, Map<String, dynamic>> productMap = {};
      for (final pid in productIds) {
        try {
          final p = await _supabase
              .from('products')
              .select('id, ItemAlias1, MRP, hsn, GstRate')
              .eq('id', pid)
              .maybeSingle();
          if (p != null) productMap[pid] = p;
        } catch (_) {}
      }

      return items.map((json) {
        final modifiedJson = Map<String, dynamic>.from(json as Map);
        final unitPrice = _parseDouble(json['unit_price']) ?? 0.0;
        final quantity = (json['quantity'] as num?)?.toDouble() ?? 0.0;

        final productId = json['product_id']?.toString();
        if (productId != null && productMap.containsKey(productId)) {
          final p = productMap[productId]!;
          modifiedJson['vtNumber'] = p['ItemAlias1'];
          modifiedJson['mrp'] = p['MRP'];
          modifiedJson['hsn'] = modifiedJson['hsn'] ?? p['hsn'];
          final itemGst = _parseDouble(json['gst_rate']) ??
              _parseDouble(json['GstRate']) ??
              0.0;
          final productGst = _parseDouble(p['GstRate']) ?? 0.0;
          if (itemGst <= 0 && productGst > 0) {
            modifiedJson['gst_rate'] = productGst;
            modifiedJson['GstRate'] = productGst;
            final storedGst = _parseDouble(json['gst_amount']) ?? 0.0;
            if (storedGst <= 0) {
              final discountAmt = _parseDouble(json['discount_amount']) ?? 0.0;
              final taxable = (unitPrice * quantity) - discountAmt;
              final gstAmount = taxable * productGst / 100;
              modifiedJson['gst_amount'] = gstAmount;
              modifiedJson['total_amount'] = taxable + gstAmount;
            }
          }
        }

        // Compute discount sub-types
        final catDiscPct =
            _parseDouble(json['category_discount_percentage']) ?? 0.0;
        modifiedJson['cash_discount_amount'] =
            unitPrice * catDiscPct / 100 * quantity;
        modifiedJson['order_discount_amount'] =
            _parseDouble(json['discount_amount']) ?? 0.0;
        modifiedJson['item_discount_amount'] = 0.0;
        modifiedJson['offer_discount_amount'] = 0.0;

        return OrderItemModel.fromJson(modifiedJson);
      }).toList();
    } catch (e) {
      print('Error fetching order items: $e');
      return [];
    }
  }

  // ─── STATS ────────────────────────────────────────────────────────────────

  /// Today's order count and total amount for the dashboard.
  Future<Map<String, dynamic>> getTodayStats(String salesmanId,
      {String? companyId}) async {
    try {
      print(
          '📊 getTodayStats - salesmanId: $salesmanId, companyId: $companyId');
      final nowUtc = DateTime.now().toUtc();
      final startOfDayUtc = DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day);
      final endOfDayUtc = startOfDayUtc.add(const Duration(days: 1));

      dynamic query = _supabase
          .from('sales_orders')
          .select('id, net_amount')
          .eq('salesman_id', salesmanId)
          .gte('created_at', startOfDayUtc.toIso8601String())
          .lt('created_at', endOfDayUtc.toIso8601String());

      if (companyId != null && companyId.isNotEmpty) {
        final keys = await companyKeys(companyId);
        query = applySalesOrderCompanyFilter(query, keys);
      }

      final List data = await query as List;
      print('📊 getTodayStats - fetched ${data.length} orders');
      double todayAmount = 0.0;
      for (final row in data) {
        todayAmount += (row['net_amount'] as num?)?.toDouble() ?? 0.0;
      }

      return {
        'todayOrders': data.length,
        'todayAmount': todayAmount,
      };
    } catch (e) {
      print('❌ Error getting today stats: $e');
      return {'todayOrders': 0, 'todayAmount': 0.0};
    }
  }

  // ─── CREATE ───────────────────────────────────────────────────────────────

  /// Generate order number as YYYYMMDD + daily sequence (e.g. 2026092201).
  Future<String> _generateOrderNumber({String? companyId}) async {
    final now = DateTime.now().toLocal();
    final prefix =
        '${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';

    int nextSeq = 1;
    try {
      dynamic query = _supabase
          .from('sales_orders')
          .select('order_number')
          .like('order_number', '$prefix%');
      if (companyId != null &&
          companyId.isNotEmpty &&
          companyId != 'ALL') {
        final keys = await companyKeys(companyId);
        query = applySalesOrderCompanyFilter(query, keys);
      }
      final rows = await query as List;
      var maxSeq = 0;
      for (final row in rows) {
        final raw = (row['order_number'] ?? '').toString();
        if (!raw.startsWith(prefix)) continue;
        final seq = int.tryParse(raw.substring(prefix.length)) ?? 0;
        if (seq > maxSeq) maxSeq = seq;
      }
      nextSeq = maxSeq + 1;
    } catch (e) {
      print('Error generating order number: $e');
      nextSeq = 1;
    }

    return '$prefix${nextSeq.toString().padLeft(2, '0')}';
  }

  /// Create order — inserts into sales_orders + order_items.
  Future<String> createOrder({
    required String salesmanId,
    required List<CartItem> items,
    required double totalAmount,
    required double gstAmount,
    required double netAmount,
    required double orderDiscountAmount,
    required double orderDiscountPercentage,
    required double subtotalBeforeDiscount,
    String? customerId,
    String? customerName,
    String? customerGst,
    String? notes,
    String? shippingAddress,
    String? remarks,
    String? dispatchedThrough,
    String? destination,
    String? companyId,
    String? customerCategoryId,
    String? customerCategoryName,
    String? ledger,
    String? orderNumber,
    double? orderLatitude,
    double? orderLongitude,
  }) async {
    try {
      final adminService = AdminSettingsService();
      final globalGstRate = await adminService.getGlobalGstRate(companyId!);

      print('📝 createOrder - salesmanId: $salesmanId, companyId: $companyId');
      final RoundOffResult roundOffResult = calculateRoundOff(netAmount);
      final now = DateTime.now().toUtc().toIso8601String();

      String? finalCategoryId = customerCategoryId;
      String? finalCategoryName = customerCategoryName;
      String? customerGstNumber = customerGst;

      if (customerId != null) {
        try {
          final customerResponse = await _supabase
              .from('customers')
              .select(
                  'customer_category_id, gst_number, customer_categories(category_name)')
              .eq('id', customerId)
              .maybeSingle();

          if (customerResponse != null) {
            customerGstNumber = customerResponse['gst_number'] as String?;
            finalCategoryId ??=
                customerResponse['customer_category_id'] as String?;
            if (finalCategoryName == null) {
              final cat = customerResponse['customer_categories'];
              finalCategoryName = (cat?['category_name'] as String?)?.trim();
            }
          }
        } catch (_) {}
      }

      String? guid;
      String? companyName;
      if (companyId != null) {
        try {
          final companyResponse = await _supabase
              .from('tally_companies')
              .select('Guid, company_name')
              .eq('id', companyId)
              .single();
          guid = companyResponse['Guid'] as String?;
          companyName = companyResponse['company_name'] as String?;
        } catch (_) {
          guid = const Uuid().v4();
        }
      } else {
        guid = const Uuid().v4();
      }

      final finalOrderNumber = orderNumber ??
          await _generateOrderNumber(companyId: companyId);

      final orderData = {
        'Guid': guid,
        'order_number': finalOrderNumber,
        'salesman_id': salesmanId,
        'customer_id': customerId,
        'customer_name': customerName ?? 'Walk-in Customer',
        'customer_category_id': finalCategoryId,
        'customer_category_name': finalCategoryName,
        'order_date': now,
        'subtotal_before_discount': subtotalBeforeDiscount,
        'discount_amount': orderDiscountAmount,
        'discount_percentage': orderDiscountPercentage,
        'total_amount': totalAmount,
        'gst_amount': gstAmount,
        'net_amount': roundOffResult.roundedTotal,
        'status': 'approved',
        'notes': notes ?? '',
        'remarks': remarks ?? '',
        'dispatched_through': dispatchedThrough,
        'destination': destination,
        'synced_to_tally': false,
        'created_at': now,
        'edit_request_status': 'none',
        'shipping_address': shippingAddress,
        'company_id': companyId,
        'company_name': companyName,
        'Type': ledger ?? 'Credit',
        'order_latitude': orderLatitude,
        'order_longitude': orderLongitude,
      };

      print(
          '💾 Saving order with company_id: $companyId, salesman_id: $salesmanId');
      final orderResponse = await _supabase
          .from('sales_orders')
          .insert(orderData)
          .select()
          .single();
      print(
          '✅ Order saved with ID: ${orderResponse['id']}, company_id: ${orderResponse['company_id']}');

      final orderId = orderResponse['id'] as String;

      // Insert order items
      final orderItems = items.map((item) {
        final manualDiscPct = item.manualDiscountPercentage ?? 0.0;
        final catDiscPct = item.categoryDiscountPercentage ?? 0.0;
        final basePrice = item.product.price;
        final afterAuto = basePrice - (basePrice * catDiscPct / 100);
        final manualDiscAmt = manualDiscPct > 0
            ? (afterAuto * manualDiscPct / 100) * item.quantity
            : 0.0;

        return {
          'Guid': const Uuid().v4(),
          'order_id': orderId,
          'product_id': item.product.id,
          'product_name': item.product.productName,
          'product_code': item.product.productCode ?? '',
          'quantity': item.quantity.round(),
          'unit_price': item.product.price,
          'gst_rate': item.product.gstRate,
          'discount_percentage': manualDiscPct,
          'category_discount_percentage': catDiscPct,
          'discount_amount': manualDiscAmt,
          'cash_discount_amount': 0.0,
          'offer_discount_amount': 0.0,
          'item_discount_amount': 0.0,
          'order_discount_amount': 0.0,
          'mrp': item.product.mrp ?? item.product.price,
          'gst_amount': item.subtotal * (item.product.gstRate / 100),
          'total_amount': item.subtotal + (item.subtotal * (item.product.gstRate / 100)),
          if (item.note != null && item.note!.trim().isNotEmpty)
            'note': item.note!.trim(),
        };
      }).toList();

      try {
        await _supabase.from('order_items').insert(orderItems);
      } catch (e) {
        final errStr = e.toString().toLowerCase();
        if (errStr.contains('note') || errStr.contains('column') || errStr.contains('schema cache')) {
          final fallbackItems = orderItems.map((map) {
            final copy = Map<String, dynamic>.from(map);
            copy.remove('note');
            return copy;
          }).toList();
          await _supabase.from('order_items').insert(fallbackItems);
        } else {
          rethrow;
        }
      }

      // Reduce stock
      try {
        print('📦 Starting stock reduction for ${items.length} items');
        for (final item in items) {
          try {
            print(
                '📦 Reducing stock for product ${item.product.id} (${item.product.productName}) by ${item.quantity.round()}');
            await _reduceProductStock(item.product.id, item.quantity.round(), salesmanId: salesmanId);
            print('✅ Stock reduced for ${item.product.productName}');
          } catch (e) {
            print('❌ Error reducing stock for ${item.product.id}: $e');
          }
        }
      } catch (e) {
        print('❌ Error in stock reduction loop: $e');
      }

      return orderResponse['order_number'] as String;
    } catch (e) {
      print('Error creating order: $e');
      rethrow;
    }
  }

  // ─── UPDATE ───────────────────────────────────────────────────────────────

  /// Update order — updates sales_orders + replaces order_items.
  Future<void> updateOrder({
    required String orderId,
    required List<OrderItemModel> items,
    required double totalAmount,
    required double gstAmount,
    required double netAmount,
    double orderDiscountPercentage = 0.0,
    double orderDiscountAmount = 0.0,
    String? notes,
    String? shippingAddress,
    String? remarks,
    String? companyId,
    String? editedBy,
  }) async {
    try {
      final RoundOffResult roundOffResult = calculateRoundOff(netAmount);

      // Fetch old items before deletion to adjust stock AND compute edit changes
      final oldItemsData = await _supabase
          .from('order_items')
          .select('*')
          .eq('order_id', orderId);

      // Build map of old quantities for inventory adjustment
      final oldQuantities = <String, int>{};
      for (final item in oldItemsData) {
        final pid = item['product_id'] as String?;
        if (pid != null) {
          oldQuantities[pid] = (item['quantity'] as num?)?.toInt() ?? 0;
        }
      }

      final updateData = <String, dynamic>{
        'subtotal_before_discount': totalAmount,
        // total_amount = subtotal after discount (before GST)
        'total_amount': totalAmount - orderDiscountAmount,
        'gst_amount': gstAmount,
        'net_amount': roundOffResult.roundedTotal,
        'discount_percentage': orderDiscountPercentage,
        'discount_amount': orderDiscountAmount,
        'notes': notes ?? '',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'edit_request_status': 'none',
        'can_edit_until': null,
        'edit_requested_at': null,
        'edit_approved_at': null,
      };

      if (shippingAddress != null) {
        updateData['shipping_address'] = shippingAddress;
      }
      if (remarks != null) {
        updateData['remarks'] = remarks;
      }

      // Mark as edited so the Tally exe will overwrite this SO on the next sync
      updateData['is_edited'] = true;
      updateData['alter_id'] = const Uuid().v4();

      // Fetch current order to preserve original_amount and append detailed edit_history
      try {
        Map<String, dynamic>? currentOrderData;
        try {
          currentOrderData = await _supabase
              .from('sales_orders')
              .select('net_amount, original_amount, remarks, shipping_address, edit_history')
              .eq('id', orderId)
              .maybeSingle();
        } catch (_) {
          // Fallback if edit_history column doesn't exist yet in Supabase
          try {
            currentOrderData = await _supabase
                .from('sales_orders')
                .select('net_amount, original_amount, remarks, shipping_address')
                .eq('id', orderId)
                .maybeSingle();
          } catch (_) {}
        }

        if (currentOrderData != null) {
          final double? existingOriginal =
              _parseDouble(currentOrderData['original_amount']);
          final double currentNetAmount =
              _parseDouble(currentOrderData['net_amount']) ?? 0.0;
          updateData['original_amount'] = existingOriginal ?? currentNetAmount;

          // ─── Build item-level changes ─────────────────────────────────────
          final itemChanges = <OrderItemChange>[];

          // Map old items by product_id AND product_name
          final Map<String, Map<String, dynamic>> oldItemsByPid = {};
          final Map<String, Map<String, dynamic>> oldItemsByName = {};
          for (final row in oldItemsData) {
            final pid = (row['product_id'] ?? '').toString().trim();
            final name = (row['product_name'] ?? '').toString().trim().toLowerCase();
            if (pid.isNotEmpty) oldItemsByPid[pid] = row;
            if (name.isNotEmpty) oldItemsByName[name] = row;
          }

          final Set<Map<String, dynamic>> processedOldRows = {};

          for (final newItem in items) {
            final pid = newItem.productId.trim();
            final name = newItem.ItemName.trim().toLowerCase();
            final oldItem = (pid.isNotEmpty ? oldItemsByPid[pid] : null) ?? oldItemsByName[name];

            if (oldItem != null) {
              processedOldRows.add(oldItem);
              final double oldQty = (oldItem['quantity'] as num?)?.toDouble() ?? 0.0;
              final double newQty = newItem.ItemQuantity;
              final double oldRate = (oldItem['unit_price'] as num?)?.toDouble() ?? 0.0;
              final double newRate = newItem.ItemRate;
              final double oldDisc = (oldItem['discount_percentage'] as num?)?.toDouble() ?? 0.0;
              final double newDisc = newItem.discountPercentage;
              final double oldTotal = (oldItem['total_amount'] as num?)?.toDouble() ?? 0.0;
              final double newTotal = newItem.totalAmount;
              final String? oldNote = oldItem['note'] as String?;
              final String? newNote = newItem.note;

              final bool qtyChanged = (oldQty - newQty).abs() > 0.001;
              final bool rateChanged = (oldRate - newRate).abs() > 0.009;
              final bool discChanged = (oldDisc - newDisc).abs() > 0.01;
              final bool noteChanged = (oldNote ?? '').trim() != (newNote ?? '').trim();

              if (qtyChanged || rateChanged || discChanged || noteChanged) {
                itemChanges.add(OrderItemChange(
                  productName: newItem.ItemName,
                  productCode: newItem.PartNumber,
                  changeType: 'modified',
                  oldQuantity: oldQty,
                  newQuantity: newQty,
                  oldRate: oldRate,
                  newRate: newRate,
                  oldDiscountPercentage: oldDisc,
                  newDiscountPercentage: newDisc,
                  oldTotal: oldTotal,
                  newTotal: newTotal,
                  oldNote: oldNote,
                  newNote: newNote,
                ));
              }
            } else {
              // Newly added item
              itemChanges.add(OrderItemChange(
                productName: newItem.ItemName,
                productCode: newItem.PartNumber,
                changeType: 'added',
                newQuantity: newItem.ItemQuantity,
                newRate: newItem.ItemRate,
                newDiscountPercentage: newItem.discountPercentage,
                newTotal: newItem.totalAmount,
                newNote: newItem.note,
              ));
            }
          }

          // Check for removed items
          for (final oldRow in oldItemsData) {
            if (!processedOldRows.contains(oldRow)) {
              itemChanges.add(OrderItemChange(
                productName: (oldRow['product_name'] ?? 'Item') as String,
                productCode: oldRow['product_code'] as String?,
                changeType: 'removed',
                oldQuantity: (oldRow['quantity'] as num?)?.toDouble(),
                oldRate: (oldRow['unit_price'] as num?)?.toDouble(),
                oldDiscountPercentage: (oldRow['discount_percentage'] as num?)?.toDouble(),
                oldTotal: (oldRow['total_amount'] as num?)?.toDouble(),
                oldNote: oldRow['note'] as String?,
              ));
            }
          }

          final String? prevRemarks = currentOrderData['remarks'] as String?;
          final String? prevAddress = currentOrderData['shipping_address'] as String?;

          final editRecord = OrderEditRecord(
            editedAt: DateTime.now().toUtc(),
            editedBy: editedBy ?? 'Dispatch',
            previousNetAmount: currentNetAmount,
            newNetAmount: roundOffResult.roundedTotal,
            previousRemarks: prevRemarks,
            newRemarks: remarks,
            previousShippingAddress: prevAddress,
            newShippingAddress: shippingAddress,
            itemChanges: itemChanges,
          );

          final existingHistory = currentOrderData['edit_history'];
          final List<dynamic> historyList = (existingHistory is List)
              ? List.from(existingHistory)
              : <dynamic>[];

          historyList.add(editRecord.toJson());
          updateData['edit_history'] = historyList;
        }
      } catch (e) {
        print('Could not fetch existing original_amount or build edit_history: $e');
      }

      await _updateSalesOrderHeader(orderId, updateData);

      await _supabase.from('order_items').delete().eq('order_id', orderId);

      if (items.isNotEmpty) {
        final itemsList = items.map((item) {
          final gstRate = item.GstRate;
          final taxable = (item.ItemRate * item.ItemQuantity) - item.discountAmount;
          final lineGst = taxable * (gstRate / 100);
          return {
            'order_id': orderId,
            'product_id': item.productId,
            'product_name': item.ItemName,
            'product_code': item.PartNumber ?? '',
            'quantity': item.ItemQuantity.round(),
            'unit_price': item.ItemRate,
            'gst_rate': gstRate,
            'gst_amount': lineGst,
            'total_amount': taxable + lineGst,
            'discount_percentage': item.discountPercentage,
            'category_discount_percentage': 0.0,
            'discount_amount': item.discountAmount,
            'cash_discount_amount': item.cashDiscountAmount,
            'offer_discount_amount': item.offerDiscountAmount,
            'item_discount_amount': item.itemDiscountAmount,
            'order_discount_amount': item.orderDiscountAmount,
            'mrp': item.mrp ?? item.ItemRate,
            if (companyId != null) 'company_id': companyId,
            if (item.note != null && item.note!.trim().isNotEmpty)
              'note': item.note!.trim(),
          };
        }).toList();

        try {
          await _supabase.from('order_items').insert(itemsList);
        } catch (e) {
          final errStr = e.toString().toLowerCase();
          if (errStr.contains('note') || errStr.contains('column') || errStr.contains('schema cache')) {
            final fallbackItems = itemsList.map((map) {
              final copy = Map<String, dynamic>.from(map);
              copy.remove('note');
              return copy;
            }).toList();
            await _supabase.from('order_items').insert(fallbackItems);
          } else {
            rethrow;
          }
        }

        // Stock is secondary — do not block or fail the order save.
        final stockJobs = <Future<void>>[];
        for (final item in items) {
          final oldQty = oldQuantities[item.productId] ?? 0;
          final newQty = item.ItemQuantity.round();
          final diff = newQty - oldQty;
          if (diff > 0) {
            stockJobs.add(_reduceProductStock(item.productId, diff));
          } else if (diff < 0) {
            stockJobs.add(_increaseProductStock(item.productId, diff.abs()));
          }
        }
        for (final entry in oldQuantities.entries) {
          final stillExists = items.any((item) => item.productId == entry.key);
          if (!stillExists && entry.value > 0) {
            stockJobs.add(_increaseProductStock(entry.key, entry.value));
          }
        }
        if (stockJobs.isNotEmpty) {
          Future.wait(stockJobs.map((job) async {
            try {
              await job;
            } catch (e) {
              print('Warning: stock adjust after order edit failed: $e');
            }
          }));
        }
      }
    } catch (e) {
      print('❌ Error updating order: $e');
      rethrow;
    }
  }

  // ─── DELETE ───────────────────────────────────────────────────────────────

  /// Delete order — deletes from sales_orders (order_items cascade via FK).
  Future<void> deleteOrder(String orderId) async {
    try {
      await _supabase.from('order_items').delete().eq('order_id', orderId);
      await _supabase.from('sales_orders').delete().eq('id', orderId);
    } catch (e) {
      print('❌ Error deleting order: $e');
      rethrow;
    }
  }

  // ─── HELPERS ──────────────────────────────────────────────────────────────

  /// Updates the sales_orders header. If alter_id / is_edited columns are not
  /// in the database yet, retries without them so editing still works.
  Future<void> _updateSalesOrderHeader(
      String orderId, Map<String, dynamic> updateData) async {
    try {
      await _supabase.from('sales_orders').update(updateData).eq('id', orderId);
    } catch (e) {
      final err = e.toString();
      if ((err.contains('PGRST204') || err.contains('42703')) &&
          (updateData.containsKey('alter_id') ||
              updateData.containsKey('is_edited') ||
              updateData.containsKey('original_amount') ||
              updateData.containsKey('edit_history'))) {
        print(
            'Warning: alter_id/is_edited/original_amount/edit_history columns missing on sales_orders. Run migration 020.');
        updateData.remove('alter_id');
        updateData.remove('is_edited');
        updateData.remove('original_amount');
        updateData.remove('edit_history');
        await _supabase
            .from('sales_orders')
            .update(updateData)
            .eq('id', orderId);
      } else {
        rethrow;
      }
    }
  }

  Future<void> _reduceProductStock(String productId, int quantity, {String? salesmanId}) async {
    try {
      print('📦 _reduceProductStock: productId=$productId, quantity=$quantity, salesmanId=$salesmanId');
      final response = await _supabase
          .from('products')
          .select('ItemQuantity, ItemName, company_id')
          .eq('id', productId)
          .single();
      final currentStock = (response['ItemQuantity'] as num?)?.toInt() ?? 0;
      final productName = response['ItemName'] as String?;
      final companyId = response['company_id'] as String?;
      print('📦 Current stock: $currentStock');
      final newStock = (currentStock - quantity).clamp(0, 999999);
      print('📦 New stock after reduction: $newStock');
      await _supabase
          .from('products')
          .update({'ItemQuantity': newStock}).eq('id', productId);
      print('✅ Stock updated in database');

      // Check if stock is now low or out of stock and send notification
      if (newStock == 0 && currentStock > 0) {
        // Stock became out of stock
        await _sendStockNotification(
          productId: productId,
          productName: productName ?? 'Unknown Product',
          stockLevel: newStock,
          notificationType: 'out_of_stock',
          companyId: companyId,
          salesmanId: salesmanId,
        );
      } else if (newStock <= 10 && currentStock > 10) {
        // Stock became low (threshold: 10)
        await _sendStockNotification(
          productId: productId,
          productName: productName ?? 'Unknown Product',
          stockLevel: newStock,
          notificationType: 'low_stock',
          companyId: companyId,
          salesmanId: salesmanId,
        );
      }
    } catch (e) {
      print('❌ Error in _reduceProductStock: $e');
    }
  }

  Future<void> _increaseProductStock(String productId, int quantity) async {
    try {
      final response = await _supabase
          .from('products')
          .select('ItemQuantity')
          .eq('id', productId)
          .single();
      final currentStock = (response['ItemQuantity'] as num?)?.toInt() ?? 0;
      final newStock = currentStock + quantity;
      await _supabase
          .from('products')
          .update({'ItemQuantity': newStock}).eq('id', productId);
    } catch (_) {}
  }

  Future<void> _sendStockNotification({
    required String productId,
    required String productName,
    required int stockLevel,
    required String notificationType,
    String? companyId,
    String? salesmanId,
  }) async {
    try {
      // Resolve the current user from Supabase auth if salesmanId is not provided
      String finalSalesmanId = salesmanId ?? '';
      if (finalSalesmanId.isEmpty) {
        final authUser = _supabase.auth.currentUser;
        if (authUser == null) {
          print('⚠️ _sendStockNotification: no auth user, skipping');
          return;
        }
        finalSalesmanId = authUser.id;
      }

      // Resolve salesman name from the custom users table
      String salesmanName = 'Salesman';
      try {
        final userRow = await _supabase
            .from('users')
            .select('name')
            .eq('id', finalSalesmanId)
            .maybeSingle();
        if (userRow != null && userRow['name'] != null) {
          salesmanName = userRow['name'] as String;
        }
      } catch (_) {}

      // Dedup: skip if an identical alert was already sent within the last 24 hours
      final since = DateTime.now()
          .toUtc()
          .subtract(const Duration(hours: 24))
          .toIso8601String();

      final existing = await _supabase
          .from('notifications')
          .select('id')
          .eq('product_id', productId)
          .eq('type', notificationType)
          .gte('created_at', since)
          .limit(1);

      if ((existing as List).isNotEmpty) {
        print(
            'ℹ️ Stock notification for $productName already sent within 24 h — skipping');
        return;
      }

      final title = notificationType == 'out_of_stock'
          ? 'Out of Stock Alert'
          : 'Low Stock Alert';
      final message = notificationType == 'out_of_stock'
          ? '$productName is out of stock'
          : '$productName is running low (Stock: $stockLevel)';

      await _supabase.from('notifications').insert({
        'type': notificationType,
        'title': title,
        'message': message,
        'product_id': productId,
        'product_name': productName,
        'current_stock': stockLevel,
        'salesman_id': finalSalesmanId,
        'salesman_name': salesmanName,
        'company_id': companyId,
        'is_read': false,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      print(
          '✅ Auto stock notification sent: $title — $productName (stock: $stockLevel)');
    } catch (e) {
      print('❌ Error sending stock notification: $e');
    }
  }
}
