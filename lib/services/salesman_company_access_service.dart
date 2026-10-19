import 'package:supabase_flutter/supabase_flutter.dart';

class SalesmanCompanyAccessService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Get all companies a salesman can access
  Future<List<Map<String, dynamic>>> getAccessibleCompanies(
      String salesmanId) async {
    try {
      print('🔍 Fetching accessible companies for salesman: $salesmanId');

      final response = await _supabase
          .from('salesman_company_access')
          .select(
              'company_id, tally_companies(id, company_name, company_number)')
          .eq('salesman_id', salesmanId);

      print('✅ Found ${response.length} accessible companies');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error fetching accessible companies: $e');
      print('⚠️ salesman_company_access table not available - using salesman company only');
      try {
        final userRows = await _supabase
            .from('users')
            .select('company_id')
            .eq('id', salesmanId)
            .limit(1);
        final userList = List<Map<String, dynamic>>.from(userRows as List);
        final companyId = userList.isEmpty
            ? null
            : userList.first['company_id'] as String?;
        if (companyId == null) return [];

        Future<List<Map<String, dynamic>>> lookup(String column) async {
          final rows = await _supabase
              .from('tally_companies')
              .select('id, company_name, company_number')
              .eq(column, companyId)
              .limit(1);
          return List<Map<String, dynamic>>.from(rows as List);
        }

        var companyList = await lookup('id');
        if (companyList.isEmpty) companyList = await lookup('Guid');
        if (companyList.isEmpty) return [];
        final company = companyList.first;

        return [
          {
            'company_id': company['id'],
            'tally_companies': company,
          }
        ];
      } catch (fallbackError) {
        print('❌ Fallback also failed: $fallbackError');
        return [];
      }
    }
  }

  Future<Set<String>> _companyKeys(String companyId) async {
    final keys = <String>{if (companyId.trim().isNotEmpty) companyId.trim()};
    try {
      Future<List<Map<String, dynamic>>> lookup(String column) async {
        final rows = await _supabase
            .from('tally_companies')
            .select('id, Guid')
            .eq(column, companyId)
            .limit(1);
        return List<Map<String, dynamic>>.from(rows as List);
      }

      var rows = await lookup('id');
      if (rows.isEmpty) rows = await lookup('Guid');
      if (rows.isNotEmpty) {
        final id = rows.first['id']?.toString();
        final guid = rows.first['Guid']?.toString();
        if (id != null && id.isNotEmpty) keys.add(id);
        if (guid != null && guid.isNotEmpty) keys.add(guid);
      }
    } catch (e) {
      print('⚠️ Could not resolve company keys: $e');
    }
    return keys;
  }

  /// Check if salesman can access a specific company
  Future<bool> canAccessCompany(String salesmanId, String companyId) async {
    print(
        '🔐 Checking access for salesman: $salesmanId, company: $companyId');
    final keys = await _companyKeys(companyId);

    try {
      final response = await _supabase
          .from('salesman_company_access')
          .select('company_id')
          .eq('salesman_id', salesmanId);
      final rows = List<Map<String, dynamic>>.from(response as List);
      for (final row in rows) {
        final cid = row['company_id']?.toString();
        if (cid != null && keys.contains(cid)) {
          print('✅ Access granted via salesman_company_access');
          return true;
        }
      }
    } catch (e) {
      print(
          '⚠️ salesman_company_access table not available or failed: $e');
    }

    try {
      final userRows = await _supabase
          .from('users')
          .select('company_id')
          .eq('id', salesmanId)
          .limit(1);
      final list = List<Map<String, dynamic>>.from(userRows as List);
      final linked = list.isEmpty ? null : list.first['company_id']?.toString();
      if (linked != null && linked.isNotEmpty) {
        if (keys.contains(linked)) {
          print('✅ Access granted via users.company_id');
          return true;
        }
        final linkedKeys = await _companyKeys(linked);
        if (keys.intersection(linkedKeys).isNotEmpty) {
          print('✅ Access granted via resolved company id/Guid');
          return true;
        }
      }
    } catch (e) {
      print('❌ User company fallback failed: $e');
    }

    print('❌ Access denied');
    return false;
  }

  /// Grant salesman access to a company
  Future<void> grantAccess(String salesmanId, String companyId) async {
    try {
      print(
          '➕ Granting access to salesman: $salesmanId for company: $companyId');

      // salesman_company_access table doesn't exist - skipping
      print('⚠️ salesman_company_access table not available - access control disabled');
    } catch (e) {
      print('❌ Error granting access: $e');
      rethrow;
    }
  }

  /// Revoke salesman access to a company
  Future<void> revokeAccess(String salesmanId, String companyId) async {
    try {
      print(
          '➖ Revoking access for salesman: $salesmanId from company: $companyId');

      await _supabase
          .from('salesman_company_access')
          .delete()
          .eq('salesman_id', salesmanId)
          .eq('company_id', companyId);

      print('✅ Access revoked successfully');
    } catch (e) {
      print('❌ Error revoking access: $e');
      rethrow;
    }
  }

  /// Get all salesmen who can access a company
  Future<List<Map<String, dynamic>>> getSalesmenForCompany(
      String companyId) async {
    try {
      print('🔍 Fetching salesmen for company: $companyId');

      final response = await _supabase
          .from('salesman_company_access')
          .select('salesman_id, users(id, name, mobile_number)')
          .eq('company_id', companyId);

      print('✅ Found ${response.length} salesmen');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error fetching salesmen: $e');
      return [];
    }
  }

  /// Get all companies and their access status for a salesman
  Future<List<Map<String, dynamic>>> getCompaniesWithAccessStatus(
    String salesmanId, {
    List<String>? restrictedCompanyIds,
  }) async {
    try {
      print(
          '🔍 Fetching companies with access status for salesman: $salesmanId');

      final userRows = await _supabase
          .from('users')
          .select('company_id')
          .eq('id', salesmanId)
          .limit(1);
      final userList = List<Map<String, dynamic>>.from(userRows as List);
      final linkedId =
          userList.isEmpty ? null : userList.first['company_id'] as String?;

      Map<String, dynamic>? companyRow;
      if (linkedId != null) {
        Future<List<Map<String, dynamic>>> lookup(String column) async {
          final rows = await _supabase
              .from('tally_companies')
              .select('id, company_name, company_number, is_active')
              .eq(column, linkedId)
              .limit(1);
          return List<Map<String, dynamic>>.from(rows as List);
        }

        var companyList = await lookup('id');
        if (companyList.isEmpty) companyList = await lookup('Guid');
        if (companyList.isNotEmpty) companyRow = companyList.first;
      }

      if (companyRow == null) return [];

      if (restrictedCompanyIds != null &&
          restrictedCompanyIds.isNotEmpty &&
          !restrictedCompanyIds.contains(companyRow['id']) &&
          !restrictedCompanyIds.contains(linkedId)) {
        return [];
      }

      return [
        {
          ...companyRow,
          'has_access': true,
        }
      ];
    } catch (e) {
      print('❌ Error fetching companies with status: $e');
      return [];
    }
  }

  /// Bulk grant access to multiple companies
  Future<void> grantAccessToMultipleCompanies(
    String salesmanId,
    List<String> companyIds,
  ) async {
    try {
      print(
          '➕ Granting access to $salesmanId for ${companyIds.length} companies');

      final records = companyIds
          .map((companyId) => {
                'salesman_id': salesmanId,
                'company_id': companyId,
              })
          .toList();

      await _supabase.from('salesman_company_access').insert(records);

      print('✅ Access granted to all companies');
    } catch (e) {
      print('❌ Error granting bulk access: $e');
      rethrow;
    }
  }

  /// Bulk revoke access from multiple companies
  Future<void> revokeAccessFromMultipleCompanies(
    String salesmanId,
    List<String> companyIds,
  ) async {
    try {
      print(
          '➖ Revoking access for $salesmanId from ${companyIds.length} companies');

      // salesman_company_access table doesn't exist - skipping
      print('⚠️ salesman_company_access table not available - access control disabled');
    } catch (e) {
      print('❌ Error revoking bulk access: $e');
      rethrow;
    }
  }
}
