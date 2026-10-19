class PaymentMethod {
  static const cash = 'Cash';
  static const cheque = 'Cheque';
  static const demandDraft = 'Demand Draft';
  static const neft = 'NEFT';
  static const rtgs = 'RTGS';
  static const imps = 'IMPS';
  static const upi = 'UPI';
  static const creditCard = 'Credit Card';
  static const debitCard = 'Debit Card';
  static const online = 'Online Payment';
  static const wallet = 'Wallet';
  static const other = 'Other';

  static const all = [
    cash,
    cheque,
    demandDraft,
    neft,
    rtgs,
    imps,
    upi,
    creditCard,
    debitCard,
    online,
    wallet,
    other,
  ];

  static const filterGroups = [
    'All',
    cash,
    cheque,
    'Bank',
    upi,
    'Card',
    online,
    wallet,
    other,
  ];

  static bool matchesFilter(String method, String filter) {
    if (filter == 'All') return true;
    if (filter == 'Bank') {
      return method == neft || method == rtgs || method == imps || method == demandDraft;
    }
    if (filter == 'Card') {
      return method == creditCard || method == debitCard;
    }
    return method == filter;
  }
}

class CollectionModel {
  final String id;
  final String companyId;
  final String salesmanId;
  final String? salesmanName;
  final String? customerId;
  final String customerName;
  final double amount;
  final DateTime collectionDate;
  final String paymentMethod;
  final String? referenceNumber;
  final String? remarks;
  final String? receivedFrom;
  final String? instrumentNumber;
  final DateTime? instrumentDate;
  final String? bankName;
  final String? bankBranch;
  final String? ifscCode;
  final String? drawerName;
  final String? transferMode;
  final String? accountLast4;
  final String? transactionId;
  final String? upiId;
  final String? cardLast4;
  final String? cardType;
  final String? approvalCode;
  final String? gatewayName;
  final String? walletName;
  final String? otherMethodDetail;
  final double? latitude;
  final double? longitude;
  final String? locationAddress;
  final DateTime createdAt;

  CollectionModel({
    required this.id,
    required this.companyId,
    required this.salesmanId,
    this.salesmanName,
    this.customerId,
    required this.customerName,
    required this.amount,
    required this.collectionDate,
    required this.paymentMethod,
    this.referenceNumber,
    this.remarks,
    this.receivedFrom,
    this.instrumentNumber,
    this.instrumentDate,
    this.bankName,
    this.bankBranch,
    this.ifscCode,
    this.drawerName,
    this.transferMode,
    this.accountLast4,
    this.transactionId,
    this.upiId,
    this.cardLast4,
    this.cardType,
    this.approvalCode,
    this.gatewayName,
    this.walletName,
    this.otherMethodDetail,
    this.latitude,
    this.longitude,
    this.locationAddress,
    required this.createdAt,
  });

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    try {
      return DateTime.parse(value.toString());
    } catch (_) {
      return null;
    }
  }

  static double? _parseOptionalDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  bool get hasLocation =>
      (locationAddress != null && locationAddress!.trim().isNotEmpty) ||
      (latitude != null && longitude != null);

  String? get locationDisplay {
    if (locationAddress != null &&
        locationAddress!.trim().isNotEmpty &&
        !RegExp(r'^\s*-?\d+(\.\d+)?\s*,\s*-?\d+(\.\d+)?\s*$')
            .hasMatch(locationAddress!.trim())) {
      return locationAddress;
    }
    return null;
  }

  static double _parseAmount(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString().replaceAll(',', '')) ?? 0;
  }

  factory CollectionModel.fromJson(Map<String, dynamic> json) {
    return CollectionModel(
      id: (json['id'] ?? '').toString(),
      companyId: (json['company_id'] ?? '').toString(),
      salesmanId: (json['salesman_id'] ?? '').toString(),
      salesmanName: json['salesman_name'] as String?,
      customerId: json['customer_id']?.toString(),
      customerName: (json['customer_name'] ?? '').toString(),
      amount: _parseAmount(json['amount']),
      collectionDate: _parseDate(json['collection_date']) ?? DateTime.now(),
      paymentMethod: (json['payment_method'] ?? '').toString(),
      referenceNumber: json['reference_number'] as String?,
      remarks: json['remarks'] as String?,
      receivedFrom: json['received_from'] as String?,
      instrumentNumber: json['instrument_number'] as String?,
      instrumentDate: _parseDate(json['instrument_date']),
      bankName: json['bank_name'] as String?,
      bankBranch: json['bank_branch'] as String?,
      ifscCode: json['ifsc_code'] as String?,
      drawerName: json['drawer_name'] as String?,
      transferMode: json['transfer_mode'] as String?,
      accountLast4: json['account_last4'] as String?,
      transactionId: json['transaction_id'] as String?,
      upiId: json['upi_id'] as String?,
      cardLast4: json['card_last4'] as String?,
      cardType: json['card_type'] as String?,
      approvalCode: json['approval_code'] as String?,
      gatewayName: json['gateway_name'] as String?,
      walletName: json['wallet_name'] as String?,
      otherMethodDetail: json['other_method_detail'] as String?,
      latitude: _parseOptionalDouble(json['latitude']),
      longitude: _parseOptionalDouble(json['longitude']),
      locationAddress: json['location_address'] as String?,
      createdAt: _parseDate(json['created_at']) ?? DateTime.now(),
    );
  }

  String get detailsSummary {
    final parts = <String>[];
    if (instrumentNumber != null && instrumentNumber!.isNotEmpty) {
      parts.add('No. $instrumentNumber');
    }
    if (instrumentDate != null) {
      parts.add(
        '${instrumentDate!.day.toString().padLeft(2, '0')}-'
        '${instrumentDate!.month.toString().padLeft(2, '0')}-'
        '${instrumentDate!.year}',
      );
    }
    if (bankName != null && bankName!.isNotEmpty) parts.add(bankName!);
    if (transactionId != null && transactionId!.isNotEmpty) {
      parts.add('Txn $transactionId');
    }
    if (upiId != null && upiId!.isNotEmpty) parts.add(upiId!);
    if (referenceNumber != null && referenceNumber!.isNotEmpty) {
      parts.add(referenceNumber!);
    }
    if (otherMethodDetail != null && otherMethodDetail!.isNotEmpty) {
      parts.add(otherMethodDetail!);
    }
    return parts.join(' · ');
  }

  bool matchesQuery(String query) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase();
    bool hit(String? value) =>
        value != null && value.toLowerCase().contains(q);
    return hit(customerName) ||
        hit(salesmanName) ||
        hit(salesmanId) ||
        hit(paymentMethod) ||
        hit(referenceNumber) ||
        hit(remarks) ||
        hit(receivedFrom) ||
        hit(instrumentNumber) ||
        hit(bankName) ||
        hit(bankBranch) ||
        hit(ifscCode) ||
        hit(drawerName) ||
        hit(transactionId) ||
        hit(upiId) ||
        hit(cardLast4) ||
        hit(cardType) ||
        hit(approvalCode) ||
        hit(otherMethodDetail) ||
        hit(walletName) ||
        hit(gatewayName) ||
        hit(locationAddress) ||
        amount.toString().contains(q);
  }
}
