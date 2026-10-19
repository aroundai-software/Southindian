class CustomerModel {
  final String id;
  final String customerName;
  final String? mobileNumber;
  final String? address;
  final String? city;
  final String? state;
  final String? pincode;
  final String? gstNumber;
  final String? createdBy;
  final String? customerCategoryId;
  final String? customerCategoryName;
  final String? ledgerGroup;
  final String? ledgerGroupParent;
  final String? custCategory;
  final List<String> assignedSalesmanIds;
  final DateTime createdAt;
  final DateTime updatedAt;

  CustomerModel({
    required this.id,
    required this.customerName,
    this.mobileNumber,
    this.address,
    this.city,
    this.state,
    this.pincode,
    this.gstNumber,
    this.createdBy,
    this.customerCategoryId,
    this.customerCategoryName,
    this.ledgerGroup,
    this.ledgerGroupParent,
    this.custCategory,
    this.assignedSalesmanIds = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  static String? _asText(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static String? _categoryNameFromJson(Map<String, dynamic> json) {
    final direct = _asText(json['customer_category_name']) ??
        _asText(json['ledger_group']) ??
        _asText(json['customer_category']);
    if (direct != null) return direct;

    final joined = json['customer_categories'];
    if (joined is Map) {
      return _asText(joined['category_name']);
    }
    return null;
  }

  factory CustomerModel.fromJson(Map<String, dynamic> json) {
    return CustomerModel(
      id: json['id'] as String,
      customerName: json['customer_name'] as String,
      mobileNumber: json['mobile_number'] as String?,
      address: json['address'] as String?,
      city: json['city'] as String?,
      state: json['state'] as String?,
      pincode: json['pincode'] as String?,
      gstNumber: json['gst_number'] as String?,
      createdBy: json['created_by'] as String?,
      customerCategoryId: json['customer_category_id'] as String?,
      customerCategoryName: _categoryNameFromJson(json),
      ledgerGroup: _asText(json['ledger_group']),
      ledgerGroupParent: _asText(json['ledger_group_parent']),
      custCategory: _asText(json['cust_category']),
      assignedSalesmanIds: json['customer_salesman_assignments'] != null
          ? (json['customer_salesman_assignments'] as List)
              .map((e) => e['salesman_id'].toString())
              .toList()
          : (json['assigned_salesman_ids'] != null
              ? List<String>.from(json['assigned_salesman_ids'])
              : []),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'customer_name': customerName,
      'mobile_number': mobileNumber,
      'address': address,
      'city': city,
      'state': state,
      'pincode': pincode,
      'gst_number': gstNumber,
      'created_by': createdBy,
      'customer_category_id': customerCategoryId,
      'customer_category_name': customerCategoryName,
      'ledger_group': ledgerGroup,
      'ledger_group_parent': ledgerGroupParent,
      'cust_category': custCategory,
      'assigned_salesman_ids': assignedSalesmanIds,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  String get fullAddress {
    List<String> parts = [];
    if (address != null && address!.isNotEmpty) parts.add(address!);
    if (city != null && city!.isNotEmpty) parts.add(city!);
    if (state != null && state!.isNotEmpty) parts.add(state!);
    if (pincode != null && pincode!.isNotEmpty) parts.add(pincode!);
    return parts.join(', ');
  }

  String get groupName {
    final name = (ledgerGroup ?? customerCategoryName)?.trim();
    if (name != null && name.isNotEmpty) return name;
    return 'Ungrouped';
  }

  String get parentGroupName {
    final name = ledgerGroupParent?.trim();
    if (name != null && name.isNotEmpty) return name;
    return 'Ungrouped';
  }

  String get custCategoryName {
    final name = custCategory?.trim();
    if (name != null && name.isNotEmpty) return name;
    return 'Ungrouped';
  }
}