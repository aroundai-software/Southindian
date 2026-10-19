import 'package:Orderx/models/collection_model.dart';
import 'package:Orderx/utils/company_query.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CollectionService {
  final SupabaseClient _supabase = Supabase.instance.client;

  String _dateOnly(DateTime date) {
    final local = date.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  Future<List<CollectionModel>> getCollections({
    String? salesmanId,
    String? companyId,
  }) async {
    dynamic query = _supabase.from('payment_collections').select();
    if (salesmanId != null && salesmanId.isNotEmpty) {
      query = query.eq('salesman_id', salesmanId);
    }
    if (companyId != null && companyId.isNotEmpty && companyId != 'ALL') {
      final keys = await companyKeys(companyId);
      query = applyCompanyIdFilter(query, keys);
    }
    query = query
        .order('collection_date', ascending: false)
        .order('created_at', ascending: false);

    final response = await query;
    return (response as List)
        .map((row) => CollectionModel.fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<CollectionModel?> getCollectionById(String id) async {
    if (id.isEmpty) return null;
    final row = await _supabase
        .from('payment_collections')
        .select()
        .eq('id', id)
        .maybeSingle();
    if (row == null) return null;
    return CollectionModel.fromJson(Map<String, dynamic>.from(row));
  }

  Future<CollectionModel> createCollection({
    required String companyId,
    required String salesmanId,
    String? salesmanName,
    String? customerId,
    required String customerName,
    required double amount,
    required DateTime collectionDate,
    required String paymentMethod,
    String? referenceNumber,
    String? remarks,
    String? receivedFrom,
    String? instrumentNumber,
    DateTime? instrumentDate,
    String? bankName,
    String? bankBranch,
    String? ifscCode,
    String? drawerName,
    String? transferMode,
    String? accountLast4,
    String? transactionId,
    String? upiId,
    String? cardLast4,
    String? cardType,
    String? approvalCode,
    String? gatewayName,
    String? walletName,
    String? otherMethodDetail,
    double? latitude,
    double? longitude,
    String? locationAddress,
  }) async {
    final data = {
      'company_id': companyId,
      'salesman_id': salesmanId,
      'salesman_name': salesmanName,
      'customer_id': customerId,
      'customer_name': customerName,
      'amount': amount,
      'collection_date': _dateOnly(collectionDate),
      'payment_method': paymentMethod,
      'reference_number': referenceNumber,
      'remarks': remarks,
      'received_from': receivedFrom,
      'instrument_number': instrumentNumber,
      'instrument_date':
          instrumentDate != null ? _dateOnly(instrumentDate) : null,
      'bank_name': bankName,
      'bank_branch': bankBranch,
      'ifsc_code': ifscCode,
      'drawer_name': drawerName,
      'transfer_mode': transferMode,
      'account_last4': accountLast4,
      'transaction_id': transactionId,
      'upi_id': upiId,
      'card_last4': cardLast4,
      'card_type': cardType,
      'approval_code': approvalCode,
      'gateway_name': gatewayName,
      'wallet_name': walletName,
      'other_method_detail': otherMethodDetail,
      'latitude': latitude,
      'longitude': longitude,
      'location_address': locationAddress,
    };

    final response = await _supabase
        .from('payment_collections')
        .insert(data)
        .select()
        .single();

    return CollectionModel.fromJson(Map<String, dynamic>.from(response));
  }

  Future<void> deleteCollection(String id) async {
    if (id.isEmpty) {
      throw Exception('Collection id is missing');
    }
    await _supabase.from('payment_collections').delete().eq('id', id);
  }
}
