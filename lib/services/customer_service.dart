import 'package:Orderx/models/customer_model.dart';
import 'package:Orderx/utils/company_query.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CustomerService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<List<String>> getAssignedCustomerIds({
    required String salesmanId,
    String? companyId,
  }) async {
    final List<String> ids = [];
    int page = 0;
    const int pageSize = 1000;
    bool hasMore = true;

    while (hasMore) {
      final offset = page * pageSize;
      final response = await _supabase
          .from('customer_salesman_assignments')
          .select('customer_id')
          .eq('salesman_id', salesmanId)
          .range(offset, offset + pageSize - 1);
      final batch = (response as List)
          .map((row) => row['customer_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();
      ids.addAll(batch);
      hasMore = batch.length >= pageSize;
      page++;
    }

    return ids.toSet().toList();
  }

  Future<List<String>> getAssignedCustomerNames({
    required String salesmanId,
    String? companyId,
  }) async {
    final customers = await getAllCustomers(
      companyId: companyId,
      salesmanId: salesmanId,
    );
    return customers
        .map((c) => c.customerName.trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList();
  }

  Future<List<CustomerModel>> _fetchCustomersByIds(
    List<String> ids, {
    String? companyId,
  }) async {
    if (ids.isEmpty) return [];
    final List<CustomerModel> allCustomers = [];
    const int chunkSize = 120;
    for (var i = 0; i < ids.length; i += chunkSize) {
      final end = i + chunkSize > ids.length ? ids.length : i + chunkSize;
      final chunk = ids.sublist(i, end);
      dynamic query = _supabase
          .from('customers')
          .select(
              '*, customer_salesman_assignments(salesman_id), customer_categories(category_name)')
          .inFilter('id', chunk);
      if (companyId != null && companyId.isNotEmpty) {
        final keys = await companyKeys(companyId);
        query = applyCompanyIdFilter(query, keys);
      }
      final response = await query;
      allCustomers.addAll(
        (response as List).map((json) => CustomerModel.fromJson(json)),
      );
    }
    allCustomers.sort(
      (a, b) => a.customerName.toLowerCase().compareTo(b.customerName.toLowerCase()),
    );
    return allCustomers;
  }

  // FOR BOTH: Get all customers (paginated to bypass Supabase 1000-row limit)
  Future<List<CustomerModel>> getAllCustomers({String? companyId, String? salesmanId}) async {
    try {
      print('🔍 CustomerService: Fetching ALL customers for companyId=$companyId salesmanId=$salesmanId');

      if (salesmanId != null && salesmanId.isNotEmpty) {
        final ids = await getAssignedCustomerIds(
          salesmanId: salesmanId,
          companyId: companyId,
        );
        print('🔍 CustomerService: Salesman has ${ids.length} allocated customers');
        return _fetchCustomersByIds(ids, companyId: companyId);
      }
      
      final List<CustomerModel> allCustomers = [];
      int page = 0;
      const int pageSize = 1000;
      bool hasMore = true;
      
      while (hasMore) {
        final offset = page * pageSize;
        dynamic query = _supabase
            .from('customers')
            .select('*, customer_salesman_assignments(salesman_id), customer_categories(category_name)');
        
        if (companyId != null && companyId.isNotEmpty) {
          final keys = await companyKeys(companyId);
          query = applyCompanyIdFilter(query, keys);
        }
        
        final response = await query
            .order('customer_name', ascending: true)
            .range(offset, offset + pageSize - 1);

        final batch = (response as List)
            .map((json) => CustomerModel.fromJson(json))
            .toList();
        
        allCustomers.addAll(batch);
        print('🔍 CustomerService: Page $page fetched ${batch.length} customers (total so far: ${allCustomers.length})');
        
        if (batch.length < pageSize) {
          hasMore = false;
        } else {
          page++;
        }
      }
      
      print('🔍 CustomerService: Fetched ${allCustomers.length} TOTAL customers from database');
      return allCustomers;
    } catch (e) {
      print('❌ Error fetching customers: $e');
      rethrow;
    }
  }

  // FOR BOTH: Get customers with pagination (1000 per page)
  Future<List<CustomerModel>> getAllCustomersPaginated({
    String? companyId,
    String? salesmanId,
    int page = 0,
    int limit = 1000,
  }) async {
    try {
      if (salesmanId != null && salesmanId.isNotEmpty) {
        final all = await getAllCustomers(
          companyId: companyId,
          salesmanId: salesmanId,
        );
        final offset = page * limit;
        if (offset >= all.length) return [];
        final end = offset + limit > all.length ? all.length : offset + limit;
        return all.sublist(offset, end);
      }

      final offset = page * limit;
      dynamic query = _supabase
          .from('customers')
          .select('*, customer_salesman_assignments(salesman_id), customer_categories(category_name)');
      
      // Filter by company_id if provided
      if (companyId != null && companyId.isNotEmpty) {
        final keys = await companyKeys(companyId);
        query = applyCompanyIdFilter(query, keys);
      }
      
      final response = await query
          .order('customer_name', ascending: true)
          .range(offset, offset + limit - 1);

      return (response as List)
          .map((json) => CustomerModel.fromJson(json))
          .toList();
    } catch (e) {
      print('❌ Error fetching paginated customers: $e');
      rethrow;
    }
  }

  // Get total count of customers
  Future<int> getTotalCustomerCount({String? companyId, String? salesmanId}) async {
    try {
      if (salesmanId != null && salesmanId.isNotEmpty) {
        final customers = await getAllCustomers(
          companyId: companyId,
          salesmanId: salesmanId,
        );
        return customers.length;
      }

      dynamic query = _supabase.from('customers').select('id');
      
      if (companyId != null && companyId.isNotEmpty) {
        final keys = await companyKeys(companyId);
        query = applyCompanyIdFilter(query, keys);
      }
      
      final response = await query.count(CountOption.exact);
      return response.count ?? 0;
    } catch (e) {
      print('❌ Error fetching customer count: $e');
      return 0;
    }
  }

  // Alias for consistency with admin screens
  Future<List<CustomerModel>> getCustomers({String? companyId, String? salesmanId}) async {
    return getAllCustomers(companyId: companyId, salesmanId: salesmanId);
  }

  // FOR BOTH: Get customer by ID
  Future<CustomerModel?> getCustomerById(String id) async {
    try {
      final response =
          await _supabase.from('customers').select().eq('id', id).single();

      return CustomerModel.fromJson(response);
    } catch (e) {
      print('Error fetching customer: $e');
      return null;
    }
  }

  // FOR BOTH: Search customers
  Future<List<CustomerModel>> searchCustomers(String query,
      {String? companyId, String? salesmanId}) async {
    try {
      final trimmed = query.trim();
      if (trimmed.isEmpty) return [];

      print('🔍 Searching customers: query="$trimmed", companyId=$companyId, salesmanId=$salesmanId');

      if (salesmanId != null && salesmanId.isNotEmpty) {
        final allocated = await getAllCustomers(
          companyId: companyId,
          salesmanId: salesmanId,
        );
        final q = trimmed.toLowerCase();
        return allocated.where((c) {
          return c.customerName.toLowerCase().contains(q) ||
              (c.mobileNumber?.toLowerCase().contains(q) ?? false) ||
              (c.city?.toLowerCase().contains(q) ?? false) ||
              (c.address?.toLowerCase().contains(q) ?? false);
        }).toList();
      }

      dynamic dbQuery = _supabase
          .from('customers')
          .select('*, customer_salesman_assignments(salesman_id), customer_categories(category_name)');
      
      // Filter by company_id if provided
      if (companyId != null && companyId.isNotEmpty) {
        final keys = await companyKeys(companyId);
        dbQuery = applyCompanyIdFilter(dbQuery, keys);
        print('🔍 Filtering by company_id: $companyId');
      }
      
      // Use database OR query for name, mobile, city, address
      final searchPattern = 'customer_name.ilike.%$trimmed%,mobile_number.ilike.%$trimmed%,city.ilike.%$trimmed%,address.ilike.%$trimmed%';
      print('🔍 Search pattern: $searchPattern');
      
      dbQuery = dbQuery.or(searchPattern);
      
      final response = await dbQuery
          .order('customer_name', ascending: true)
          .limit(1000);

      final results = (response as List)
          .map((json) => CustomerModel.fromJson(json))
          .toList();
      
      print('🔍 Search results: ${results.length} customers found');
      return results;
    } catch (e) {
      print('❌ Error searching customers: $e');
      rethrow;
    }
  }

  // ================== FIX START ==================
  // This new method matches what your UI is calling.
  Future<String> createCustomer(Map<String, dynamic> customerData) async {
    // It takes the map from the dialog and calls the existing 'addCustomer' method.
    return addCustomer(
      customerName: customerData['customer_name'],
      mobileNumber: customerData['mobile_number'],
      address: customerData['address'],
      city: customerData['city'],
      state: customerData['state'],
      pincode: customerData['pincode'],
      gstNumber: customerData['gst_number'],
      companyId: customerData['company_id'],
      salesmanId: customerData['salesman_id'],
      // You can add 'createdBy' here if you pass it from the UI
    );
  }
  // =================== FIX END ===================

  // FOR ADMIN: Add customer (This is the original method, now used by `createCustomer`)
  Future<String> addCustomer({
    required String customerName,
    String? mobileNumber,
    String? address,
    String? city,
    String? state,
    String? pincode,
    String? gstNumber,
    String? createdBy,
    String? companyId,
    String? salesmanId,
  }) async {
    try {
      final response = await _supabase
          .from('customers')
          .insert({
            'customer_name': customerName,
            'mobile_number': mobileNumber,
            'address': address,
            'city': city,
            'state': state,
            'pincode': pincode,
            'gst_number': gstNumber,
            'created_by': createdBy,
            'company_id': companyId,
          })
          .select()
          .single();
          
      final customerId = response['id'];
      
      if (salesmanId != null && salesmanId.isNotEmpty) {
         await _supabase.from('customer_salesman_assignments').insert({
            'customer_id': customerId,
            'salesman_id': salesmanId,
            'company_id': companyId,
         });
      }

      return customerId;
    } catch (e) {
      print('Error creating customer: $e');
      rethrow;
    }
  }

  // FOR ADMIN: Update customer
  Future<void> updateCustomer({
    required String id,
    required String customerName,
    String? mobileNumber,
    String? address,
    String? city,
    String? state,
    String? pincode,
    String? gstNumber,
    String? salesmanId,
  }) async {
    try {
      await _supabase.from('customers').update({
        'customer_name': customerName,
        'mobile_number': mobileNumber,
        'address': address,
        'city': city,
        'state': state,
        'pincode': pincode,
        'gst_number': gstNumber,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', id);
      
      if (salesmanId != null && salesmanId.isNotEmpty) {
         // Assuming company_id is needed, we would need to fetch it or pass it.
         // Actually, if updateCustomer is just updating details, salesman_id is managed in assign customers.
         // For now, if passed, we upsert it. But companyId might be missing here. 
         // Let's just insert ignoring conflicts (using upsert if we don't have company_id readily available)
         // Note: to be safe, we just ignore updating salesman assignment from here since it's an admin operation.
      }
    } catch (e) {
      print('Error updating customer: $e');
      rethrow;
    }
  }

  // FOR ADMIN: Delete customer
  Future<void> deleteCustomer(String id) async {
    try {
      await _supabase.from('customers').delete().eq('id', id);
    } catch (e) {
      print('Error deleting customer: $e');
      rethrow;
    }
  }

  // Get all customer categories
  Future<List<Map<String, dynamic>>> getAllCustomerCategories() async {
    try {
      final response = await _supabase
          .from('customer_categories')
          .select('id, category_name')
          .order('category_name', ascending: true);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error fetching customer categories: $e');
      rethrow;
    }
  }

  // Get customer category name by ID
  Future<String?> getCategoryNameById(String categoryId) async {
    try {
      final response = await _supabase
          .from('customer_categories')
          .select('category_name')
          .eq('id', categoryId)
          .maybeSingle();

      return response?['category_name'] as String?;
    } catch (e) {
      print('❌ Error fetching customer category name: $e');
      rethrow;
    }
  }

  // FOR ADMIN: Batch assign customers to salesman
  Future<void> batchAssignCustomersToSalesman({
    required String salesmanId,
    required String companyId,
    required List<String> assignedCustomerIds,
  }) async {
    try {
      // Step 1: Remove salesman from all currently assigned customers in this company
      await _supabase
          .from('customer_salesman_assignments')
          .delete()
          .eq('salesman_id', salesmanId)
          .eq('company_id', companyId);

      // Step 2: Assign salesman to explicitly selected customers
      if (assignedCustomerIds.isNotEmpty) {
        const int chunkSize = 200;
        for (var i = 0; i < assignedCustomerIds.length; i += chunkSize) {
          final chunk = assignedCustomerIds.skip(i).take(chunkSize).toList();
          
          final inserts = chunk.map((cId) => {
            'customer_id': cId,
            'salesman_id': salesmanId,
            'company_id': companyId,
          }).toList();
          
          await _supabase
              .from('customer_salesman_assignments')
              .insert(inserts);
        }
      }
    } catch (e) {
      print('❌ Error batch assigning customers: $e');
      rethrow;
    }
  }

  Future<void> deallocateCustomers({
    required String companyId,
    required List<String> customerIds,
    String? salesmanId,
  }) async {
    if (customerIds.isEmpty) return;
    try {
      const int chunkSize = 200;
      for (var i = 0; i < customerIds.length; i += chunkSize) {
        final chunk = customerIds.skip(i).take(chunkSize).toList();
        var query = _supabase
            .from('customer_salesman_assignments')
            .delete()
            .eq('company_id', companyId)
            .inFilter('customer_id', chunk);
        if (salesmanId != null && salesmanId.isNotEmpty) {
          query = query.eq('salesman_id', salesmanId);
        }
        await query;
      }
    } catch (e) {
      print('❌ Error deallocating customers: $e');
      rethrow;
    }
  }
}
