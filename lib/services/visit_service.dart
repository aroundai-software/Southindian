import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';

class VisitModel {
  final String id;
  final String salesmanId;
  final String customerId;
  final String companyId;
  final DateTime checkInTime;
  final double? checkInLat;
  final double? checkInLng;
  final DateTime? checkOutTime;
  final double? checkOutLat;
  final double? checkOutLng;
  final String? visitNotes;
  final String status;
  final String? customerName;

  VisitModel({
    required this.id,
    required this.salesmanId,
    required this.customerId,
    required this.companyId,
    required this.checkInTime,
    this.checkInLat,
    this.checkInLng,
    this.checkOutTime,
    this.checkOutLat,
    this.checkOutLng,
    this.visitNotes,
    required this.status,
    this.customerName,
  });

  factory VisitModel.fromJson(Map<String, dynamic> json) {
    return VisitModel(
      id: json['id'],
      salesmanId: json['salesman_id'],
      customerId: json['customer_id'],
      companyId: json['company_id'],
      checkInTime: DateTime.parse(json['check_in_time']).toLocal(),
      checkInLat: json['check_in_lat']?.toDouble(),
      checkInLng: json['check_in_lng']?.toDouble(),
      checkOutTime: json['check_out_time'] != null ? DateTime.parse(json['check_out_time']).toLocal() : null,
      checkOutLat: json['check_out_lat']?.toDouble(),
      checkOutLng: json['check_out_lng']?.toDouble(),
      visitNotes: json['visit_notes'],
      status: json['status'],
      customerName: json['customers']?['customer_name'],
    );
  }
}

class VisitService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<Position?> _getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return null;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return null;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return null;
    }

    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }

  Future<VisitModel> checkIn({
    required String salesmanId,
    required String customerId,
    required String companyId,
  }) async {
    final pos = await _getCurrentLocation();
    
    final response = await _supabase.from('salesman_visits').insert({
      'salesman_id': salesmanId,
      'customer_id': customerId,
      'company_id': companyId,
      'check_in_time': DateTime.now().toUtc().toIso8601String(),
      'check_in_lat': pos?.latitude,
      'check_in_lng': pos?.longitude,
      'status': 'in_progress',
    }).select().single();

    return VisitModel.fromJson(response);
  }

  Future<void> checkOut({
    required String visitId,
    String? notes,
  }) async {
    final pos = await _getCurrentLocation();

    await _supabase.from('salesman_visits').update({
      'check_out_time': DateTime.now().toUtc().toIso8601String(),
      'check_out_lat': pos?.latitude,
      'check_out_lng': pos?.longitude,
      'visit_notes': notes,
      'status': 'completed',
    }).eq('id', visitId);
  }

  Future<VisitModel?> getActiveVisit(String salesmanId, String companyId) async {
    final response = await _supabase
        .from('salesman_visits')
        .select('*, customers!salesman_visits_customer_id_fkey(customer_name)')
        .eq('salesman_id', salesmanId)
        .eq('company_id', companyId)
        .eq('status', 'in_progress')
        .order('check_in_time', ascending: false)
        .limit(1)
        .maybeSingle();

    if (response == null) return null;
    return VisitModel.fromJson(response);
  }
  
  Future<List<Map<String, dynamic>>> getVisitLogs({
    String? companyId,
    String? salesmanId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    var query = _supabase
        .from('salesman_visits')
        .select('''
          *,
          users!salesman_visits_salesman_id_fkey(name),
          customers!salesman_visits_customer_id_fkey(customer_name)
        ''');

    if (companyId != null && companyId != 'ALL') {
      query = query.eq('company_id', companyId);
    }
    if (salesmanId != null && salesmanId.isNotEmpty) {
      query = query.eq('salesman_id', salesmanId);
    }
    if (startDate != null) {
      query = query.gte('check_in_time', startDate.toUtc().toIso8601String());
    }
    if (endDate != null) {
      query = query.lte('check_in_time', endDate.toUtc().toIso8601String());
    }

    final response = await query.order('check_in_time', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }
}
