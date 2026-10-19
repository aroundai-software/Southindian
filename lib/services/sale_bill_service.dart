import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:Orderx/models/sale_bill_model.dart';
import 'package:Orderx/models/order_model.dart';
import 'package:Orderx/utils/company_query.dart';

class SaleBillService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// App-created order numbers for this company (ORD…).
  Future<List<String>> _appOrderNumbers({String? companyId}) async {
    try {
      dynamic query = _supabase.from('sales_orders').select('order_number');
      if (companyId != null && companyId.isNotEmpty && companyId != 'ALL') {
        final keys = await companyKeys(companyId);
        query = applySalesOrderCompanyFilter(query, keys);
      }
      final rows = await query as List;
      return rows
          .map((row) => row['order_number']?.toString().trim() ?? '')
          .where((number) => number.isNotEmpty)
          .toList();
    } catch (e) {
      print('Error loading app order numbers: $e');
      return [];
    }
  }

  Future<List<SaleBillModel>> _billsForOrderNumbers(List<String> orderNumbers) async {
    if (orderNumbers.isEmpty) return [];

    final List bills = [];
    const chunkSize = 200;
    for (var i = 0; i < orderNumbers.length; i += chunkSize) {
      final end = (i + chunkSize < orderNumbers.length)
          ? i + chunkSize
          : orderNumbers.length;
      final chunk = orderNumbers.sublist(i, end);
      final response = await _supabase
          .from('sale_bill')
          .select()
          .inFilter('order_number', chunk)
          .order('date', ascending: false);
      bills.addAll(response as List);
    }

    return bills.map((json) => SaleBillModel.fromJson(json)).toList();
  }

  /// Tally bills that belong to an app sales order only.
  Future<List<SaleBillModel>> getAllSaleBills({String? companyId}) async {
    try {
      final orderNumbers = await _appOrderNumbers(companyId: companyId);
      return _billsForOrderNumbers(orderNumbers);
    } catch (e) {
      print('Error fetching sale bills: $e');
      rethrow;
    }
  }

  /// Get sale bills by date range
  Future<List<SaleBillModel>> getSaleBillsByDateRange({
    required DateTime startDate,
    required DateTime endDate,
    String? companyId,
  }) async {
    try {
      final bills = await getAllSaleBills(companyId: companyId);
      final start = startDate.toIso8601String().split('T')[0];
      final end = endDate.toIso8601String().split('T')[0];
      final startDay = DateTime.parse(start);
      final endDay = DateTime.parse(end);
      return bills.where((bill) {
        final day = DateTime(bill.date.year, bill.date.month, bill.date.day);
        return !day.isBefore(startDay) && !day.isAfter(endDay);
      }).toList();
    } catch (e) {
      print('Error fetching sale bills by date range: $e');
      rethrow;
    }
  }

  /// Get sale bills by status
  Future<List<SaleBillModel>> getSaleBillsByStatus(
    String status, {
    String? companyId,
  }) async {
    try {
      final bills = await getAllSaleBills(companyId: companyId);
      return bills.where((bill) => bill.status == status).toList();
    } catch (e) {
      print('Error fetching sale bills by status: $e');
      rethrow;
    }
  }

  /// Get sale bill by ID
  Future<SaleBillModel?> getSaleBillById(String id) async {
    try {
      final response =
          await _supabase.from('sale_bill').select().eq('id', id).maybeSingle();

      if (response == null) return null;
      return SaleBillModel.fromJson(response);
    } catch (e) {
      print('Error fetching sale bill by ID: $e');
      rethrow;
    }
  }

  Future<SaleBillModel?> getSaleBillByOrderNumber(
    String orderNumber, {
    String? companyId,
  }) async {
    try {
      dynamic query = _supabase
          .from('sale_bill')
          .select()
          .eq('order_number', orderNumber);

      if (companyId != null && companyId.isNotEmpty) {
        final keys = await companyKeys(companyId);
        query = applyCompanyIdFilter(query, keys);
      }

      final response = await query.order('date', ascending: false).maybeSingle();
      if (response == null) return null;
      return SaleBillModel.fromJson(response);
    } on PostgrestException catch (e) {
      if (e.code == '42703') {
        final response = await _supabase
            .from('sale_bill')
            .select()
            .eq('order_number', orderNumber)
            .order('date', ascending: false)
            .maybeSingle();
        if (response == null) return null;
        return SaleBillModel.fromJson(response);
      }
      rethrow;
    } catch (e) {
      print('Error fetching sale bill by order number $orderNumber: $e');
      rethrow;
    }
  }

  /// Search sale bills by order number or invoice number
  Future<List<SaleBillModel>> searchSaleBills(
    String query, {
    String? companyId,
  }) async {
    try {
      final bills = await getAllSaleBills(companyId: companyId);
      final needle = query.toLowerCase();
      return bills
          .where((bill) =>
              bill.orderNumber.toLowerCase().contains(needle) ||
              (bill.invoiceNumber?.toLowerCase().contains(needle) ?? false))
          .toList();
    } catch (e) {
      print('Error searching sale bills: $e');
      rethrow;
    }
  }

  /// Get count of sale bills by status
  Future<Map<String, int>> getSaleBillStats({String? companyId}) async {
    try {
      final bills = await getAllSaleBills(companyId: companyId);
      final pending = bills.where((bill) => bill.status == 'Pending').length;
      final completed = bills.where((bill) => bill.status == 'Completed').length;
      final cancelled = bills.where((bill) => bill.status == 'Cancelled').length;
      return {
        'pending': pending,
        'completed': completed,
        'cancelled': cancelled,
        'total': bills.length,
      };
    } catch (e) {
      print('Error fetching sale bill stats: $e');
      rethrow;
    }
  }

  /// Create a sale bill entry for a given order.
  /// This is used when converting a Sales Order to a SALE BILL.
  Future<SaleBillModel> createSaleBillForOrder(
    OrderModel order, {
    String? companyId,
  }) async {
    final existing =
        await getSaleBillByOrderNumber(order.orderNumber, companyId: companyId);
    if (existing != null) {
      return existing;
    }

    final now = DateTime.now().toUtc();
    final invoiceNumber = _generateInvoiceNumber();
    final Map<String, dynamic> baseData = {
      'order_number': order.orderNumber,
      'date': now.toIso8601String().split('T')[0],
      'invoice_number': invoiceNumber,
      'status': 'Completed',
      'created_at': now.toIso8601String(),
    };

    final Map<String, dynamic> withCompany = {
      ...baseData,
      if (companyId != null && companyId.isNotEmpty) 'company_id': companyId,
    };

    try {
      final response = await _supabase
          .from('sale_bill')
          .insert(withCompany)
          .select()
          .single();
      return SaleBillModel.fromJson(response);
    } on PostgrestException catch (e) {
      // If company_id column does not exist, retry without it.
      if (e.code == '42703') {
        final response = await _supabase
            .from('sale_bill')
            .insert(baseData)
            .select()
            .single();
        return SaleBillModel.fromJson(response);
      }
      rethrow;
    } catch (e) {
      print('Error creating sale bill for order ${order.orderNumber}: $e');
      rethrow;
    }
  }

  String _generateInvoiceNumber() {
    final now = DateTime.now().toUtc();
    final y = now.year.toString();
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    final h = now.hour.toString().padLeft(2, '0');
    final min = now.minute.toString().padLeft(2, '0');
    final s = now.second.toString().padLeft(2, '0');
    return 'SB$y$m$d$h$min$s';
  }
}
