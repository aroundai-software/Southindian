import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:Orderx/models/outstanding_model.dart';
import 'package:Orderx/utils/company_query.dart';

class OutstandingService {
  final SupabaseClient _supabase = Supabase.instance.client;

  dynamic _applyFilterMode(dynamic query, int filterMode) {
    if (filterMode == 1) {
      final today = DateTime.now().toUtc().toIso8601String().split('T')[0];
      return query
          .gt('closing_balance', 0)
          .eq('payment_received', false)
          .eq('effective_date', today);
    }
    if (filterMode == 2) {
      final today = DateTime.now().toUtc().toIso8601String().split('T')[0];
      return query
          .gt('closing_balance', 0)
          .eq('payment_received', false)
          .lt('effective_date', today);
    }
    return query;
  }

  List<String> _uniqueNames(List<String> names) {
    return names
        .map((n) => n.trim())
        .where((n) => n.isNotEmpty)
        .toSet()
        .toList();
  }

  Future<List<OutstandingModel>> _fetchByCustomerNames({
    required List<String> customerNames,
    String? companyId,
    int filterMode = 0,
    String? search,
  }) async {
    final names = _uniqueNames(customerNames);
    if (names.isEmpty) return [];

    final all = <OutstandingModel>[];
    const chunkSize = 80;
    for (var i = 0; i < names.length; i += chunkSize) {
      final end = i + chunkSize > names.length ? names.length : i + chunkSize;
      final chunk = names.sublist(i, end);
      dynamic query = _supabase.from('outstanding_with_meta').select();
      query = _applyFilterMode(query, filterMode);
      query = query.inFilter('customer_name', chunk);
      if (search != null && search.trim().isNotEmpty) {
        final q = search.trim();
        query = query.or('customer_name.ilike.%$q%,invoicenumber.ilike.%$q%');
      }
      if (companyId != null) {
        final keys = await companyKeys(companyId);
        query = applyCompanyIdFilter(query, keys);
      }
      query = query.order('date', ascending: false);
      final response = await query;
      all.addAll(
        (response as List).map((json) => OutstandingModel.fromJson(json)),
      );
    }

    final unique = <String, OutstandingModel>{};
    for (final item in all) {
      unique[item.id] = item;
    }
    final rows = unique.values.toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return rows;
  }

  /// Get all outstanding records
  Future<List<OutstandingModel>> getAllOutstanding({
    String? companyId,
    int filterMode = 0, // 0 = All, 1 = Today, 2 = Overdue
    int offset = 0,
    int limit = 50,
    List<String>? customerNames,
  }) async {
    try {
      if (customerNames != null) {
        final rows = await _fetchByCustomerNames(
          customerNames: customerNames,
          companyId: companyId,
          filterMode: filterMode,
        );
        if (offset >= rows.length) return [];
        final end = offset + limit > rows.length ? rows.length : offset + limit;
        return rows.sublist(offset, end);
      }

      dynamic query = _supabase
          .from('outstanding_with_meta')
          .select();

      query = _applyFilterMode(query, filterMode);

      if (companyId != null) {
        final keys = await companyKeys(companyId);
        query = applyCompanyIdFilter(query, keys);
      }

      query = query
          .order('date', ascending: false)
          .range(offset, offset + limit - 1);
          
      final response = await query;

      return (response as List)
          .map((json) => OutstandingModel.fromJson(json))
          .toList();
    } catch (e) {
      print('Error fetching outstanding: $e');
      rethrow;
    }
  }

  /// Get total counts for All, Today, Overdue tabs
  Future<Map<String, int>> getOutstandingCounts({
    String? companyId,
    List<String>? customerNames,
  }) async {
    try {
      if (customerNames != null) {
        final all = await _fetchByCustomerNames(
          customerNames: customerNames,
          companyId: companyId,
          filterMode: 0,
        );
        final today = DateTime.now().toUtc().toIso8601String().split('T')[0];
        var todayCount = 0;
        var overdueCount = 0;
        for (final item in all) {
          if (item.closingBalance <= 0 || item.paymentReceived == true) {
            continue;
          }
          final effective = item.effectiveDate?.toUtc().toIso8601String().split('T')[0];
          if (effective == today) todayCount++;
          if (effective != null && effective.compareTo(today) < 0) overdueCount++;
        }
        return {
          'all': all.length,
          'today': todayCount,
          'overdue': overdueCount,
        };
      }

      final today = DateTime.now().toUtc().toIso8601String().split('T')[0];
      
      dynamic buildQuery(int mode) {
        dynamic q = _supabase.from('outstanding_with_meta').select();
        if (mode == 1) {
          q = q.gt('closing_balance', 0).eq('payment_received', false).eq('effective_date', today);
        } else if (mode == 2) {
          q = q.gt('closing_balance', 0).eq('payment_received', false).lt('effective_date', today);
        }
        return q;
      }
      
      dynamic allQ = buildQuery(0);
      dynamic todayQ = buildQuery(1);
      dynamic overdueQ = buildQuery(2);
      
      if (companyId != null) {
        final keys = await companyKeys(companyId);
        allQ = applyCompanyIdFilter(allQ, keys);
        todayQ = applyCompanyIdFilter(todayQ, keys);
        overdueQ = applyCompanyIdFilter(overdueQ, keys);
      }
      
      final allRes = await allQ.count(CountOption.exact);
      final todayRes = await todayQ.count(CountOption.exact);
      final overdueRes = await overdueQ.count(CountOption.exact);
      
      return {
        'all': allRes.count ?? 0,
        'today': todayRes.count ?? 0,
        'overdue': overdueRes.count ?? 0,
      };
    } catch (e) {
      print('Error fetching counts: $e');
      return {'all': 0, 'today': 0, 'overdue': 0};
    }
  }

  /// Get outstanding records by customer name
  Future<List<OutstandingModel>> getOutstandingByCustomer(
      String customerName) async {
    try {
      final response = await _supabase
          .from('outstanding')
          .select()
          .eq('customer_name', customerName)
          .order('date', ascending: false);

      return (response as List)
          .map((json) => OutstandingModel.fromJson(json))
          .toList();
    } catch (e) {
      print('Error fetching outstanding by customer: $e');
      rethrow;
    }
  }

  /// Get overdue outstanding records
  Future<List<OutstandingModel>> getOverdueOutstanding() async {
    try {
      final today = DateTime.now().toUtc().toIso8601String().split('T')[0];
      final response = await _supabase
          .from('outstanding')
          .select()
          .lt('duedate', today)
          .gt('closing_balance', 0)
          .order('duedate', ascending: true);

      return (response as List)
          .map((json) => OutstandingModel.fromJson(json))
          .toList();
    } catch (e) {
      print('Error fetching overdue outstanding: $e');
      rethrow;
    }
  }

  /// Search outstanding by customer name or invoice number
  Future<List<OutstandingModel>> searchOutstanding(String queryStr, {
    String? companyId,
    int filterMode = 0,
    int offset = 0,
    int limit = 50,
    List<String>? customerNames,
  }) async {
    try {
      if (customerNames != null) {
        final rows = await _fetchByCustomerNames(
          customerNames: customerNames,
          companyId: companyId,
          filterMode: filterMode,
          search: queryStr,
        );
        if (offset >= rows.length) return [];
        final end = offset + limit > rows.length ? rows.length : offset + limit;
        return rows.sublist(offset, end);
      }

      dynamic query = _supabase
          .from('outstanding_with_meta')
          .select()
          .or('customer_name.ilike.%$queryStr%,invoicenumber.ilike.%$queryStr%');

      // Apply filterMode
      if (filterMode == 1) { // Today
        final today = DateTime.now().toUtc().toIso8601String().split('T')[0];
        query = query
            .gt('closing_balance', 0)
            .eq('payment_received', false)
            .eq('effective_date', today);
      } else if (filterMode == 2) { // Overdue
        final today = DateTime.now().toUtc().toIso8601String().split('T')[0];
        query = query
            .gt('closing_balance', 0)
            .eq('payment_received', false)
            .lt('effective_date', today);
      }

      if (companyId != null) {
        final keys = await companyKeys(companyId);
        query = applyCompanyIdFilter(query, keys);
      }
      
      query = query
          .order('date', ascending: false)
          .range(offset, offset + limit - 1);

      final response = await query;

      return (response as List)
          .map((json) => OutstandingModel.fromJson(json))
          .toList();
    } catch (e) {
      print('Error searching outstanding: $e');
      rethrow;
    }
  }

  /// Get outstanding statistics
  Future<Map<String, dynamic>> getOutstandingStats({
    String? companyId,
    List<String>? customerNames,
  }) async {
    try {
      final allOutstanding = await getAllOutstanding(
        companyId: companyId,
        limit: 1000000,
        customerNames: customerNames,
      );

      double totalOpening = 0;
      double totalClosing = 0;
      int overdueCount = 0;

      for (var item in allOutstanding) {
        totalOpening += item.openingBalance;
        totalClosing += item.closingBalance;
        if (item.isOverdue) overdueCount++;
      }

      return {
        'total_records': allOutstanding.length,
        'total_opening_balance': totalOpening,
        'total_closing_balance': totalClosing,
        'total_outstanding': totalClosing - totalOpening,
        'overdue_count': overdueCount,
      };
    } catch (e) {
      print('Error fetching outstanding stats: $e');
      rethrow;
    }
  }

  /// Get outstanding grouped by customer
  Future<Map<String, List<OutstandingModel>>>
      getOutstandingGroupedByCustomer() async {
    try {
      final allOutstanding = await getAllOutstanding();
      final Map<String, List<OutstandingModel>> grouped = {};

      for (var item in allOutstanding) {
        if (!grouped.containsKey(item.customerName)) {
          grouped[item.customerName] = [];
        }
        grouped[item.customerName]!.add(item);
      }

      return grouped;
    } catch (e) {
      print('Error fetching grouped outstanding: $e');
      rethrow;
    }
  }
}
