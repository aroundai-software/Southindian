import 'package:intl/intl.dart';

class OrderModel {
  final String id;
  final String orderNumber;
  final String? customerId;
  final String? customerName;
  final String salesmanId;
  final String? salesmanName; // ✅ NEW
  final DateTime orderDate;
  final double totalAmount;
  final double gstAmount;
  final double netAmount;
  final double? roundOff;
  final String status;
  final String? notes;
  final bool syncedToTally;
  final DateTime? tallySyncDate;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final bool isSaleBilled;
  final bool isPartiallyBilled;
  final double billedAmount;
  final bool isEdited;
  final double? originalAmount;
  final List<OrderEditRecord>? editHistory;

  // Customer details
  String? customerMobile;
  String? customerAddress;
  String? customerGst;

  // ✅ NEW: Shipping address
  String? shippingAddress;

  String? dispatchedThrough;
  String? destination;

  String? remarks;

  // Company info
  final String? companyId;
  final String? companyName;

  // Payment type
  final String ledger; // 'Cash' or 'Credit'

  // Discount fields
  final double subtotalBeforeDiscount;
  final double orderDiscountAmount;
  final double orderDiscountPercentage;

  // Edit permission fields
  final DateTime? canEditUntil;
  final String editRequestStatus;
  final DateTime? editRequestedAt;
  final DateTime? editApprovedAt;
  final DateTime? editRejectedAt;

  // Order geotagging fields
  final double? orderLatitude;
  final double? orderLongitude;
  final String? orderAddress;
  final double? distanceFromCustomer;

  OrderModel({
    required this.id,
    required this.orderNumber,
    this.customerId,
    this.customerName,
    required this.salesmanId,
    this.salesmanName, // ✅ NEW
    required this.orderDate,
    required this.totalAmount,
    required this.gstAmount,
    required this.netAmount,
    this.roundOff,
    required this.status,
    this.notes,
    required this.syncedToTally,
    this.tallySyncDate,
    required this.createdAt,
    this.updatedAt,
    this.isSaleBilled = false,
    this.isPartiallyBilled = false,
    this.billedAmount = 0.0,
    this.isEdited = false,
    this.originalAmount,
    this.editHistory,
    this.customerMobile,
    this.customerAddress,
    this.customerGst,
    this.shippingAddress,
    this.dispatchedThrough,
    this.destination,
    this.remarks,
    this.companyId,
    this.companyName,
    this.ledger = 'Credit', // Default to Credit
    this.subtotalBeforeDiscount = 0.0,
    this.orderDiscountAmount = 0.0,
    this.orderDiscountPercentage = 0.0,
    this.canEditUntil,
    this.editRequestStatus = 'none',
    this.editRequestedAt,
    this.editApprovedAt,
    this.editRejectedAt,
    this.orderLatitude,
    this.orderLongitude,
    this.orderAddress,
    this.distanceFromCustomer,
  });
  // ✅ Helper getters for edit permissions

  bool get hasTallySale => isSaleBilled || isPartiallyBilled;

  double get displayAmount {
    if (hasTallySale && billedAmount > 0) return billedAmount;
    return netAmount;
  }

  double get pendingAmount {
    if (billedAmount > 0) {
      final pending = netAmount - billedAmount;
      return pending < 0 ? 0 : pending;
    }
    return 0;
  }

  /// Checks if order is within edit window from creation
  /// Note: This getter is deprecated. Use the editWindowMinutes parameter from admin settings instead.
  bool get canEditDirectly {
    final now = DateTime.now();
    const editWindowMinutes = 3; // Default to 3 minutes
    final windowEnd = createdAt.add(const Duration(minutes: editWindowMinutes));
    return now.isBefore(windowEnd);
  }

  bool get hasApprovedEditWindow {
    if (editRequestStatus != 'approved') return false;
    if (canEditUntil == null) return false;
    // Only consider approved window if there was actually an edit request made
    if (editRequestedAt == null) return false;
    final now = DateTime.now();
    return now.isBefore(canEditUntil!);
  }

  /// Can request edit from admin if direct window expired and no active request
  bool get hasEditPermission {
    return canEditDirectly || hasApprovedEditWindow;
  }

  bool get canRequestEdit {
    return !canEditDirectly &&
        editRequestStatus == 'none' &&
        !hasApprovedEditWindow;
  }

  Duration? get editTimeRemaining {
    if (hasApprovedEditWindow && canEditUntil != null) {
      final now = DateTime.now();
      return canEditUntil!.difference(now);
    }
    return null;
  }

  /// Status label for edit request
  String get editStatusLabel {
    switch (editRequestStatus) {
      case 'pending':
        return 'Edit Request Pending';
      case 'approved':
        return 'Edit Approved';
      case 'rejected':
        return 'Edit Request Rejected';
      default:
        return '';
    }
  }

  factory OrderModel.fromJson(Map<String, dynamic> json) {
    // Parse datetime - ISO8601 UTC strings already return UTC DateTime
    DateTime parseDate(String dateStr) {
      return DateTime.parse(dateStr);
    }

    return OrderModel(
      id: json['id'] as String,
      orderNumber: json['order_number'] as String,
      customerId: json['customer_id'] as String?,
      customerName: json['customer_name'] as String?,
      salesmanId: json['salesman_id'] as String,
      salesmanName: json['salesman_name'] as String?, // ✅ NEW
      orderDate: parseDate(json['order_date'] as String),
      totalAmount: (json['total_amount'] as num).toDouble(),
      gstAmount: (json['gst_amount'] as num).toDouble(),
      netAmount: (json['net_amount'] as num).toDouble(),
      roundOff: (json['round_off'] as num?)?.toDouble(),
      status: json['status'] as String,
      notes: json['notes'] as String?,
      syncedToTally: json['so_synced_to_tally'] == true ||
          json['synced_to_tally'] == true,
      tallySyncDate: json['so_tally_sync_date'] != null
          ? parseDate(json['so_tally_sync_date'] as String)
          : (json['tally_sync_date'] != null
              ? parseDate(json['tally_sync_date'] as String)
              : null),
      createdAt: parseDate(json['created_at'] as String),
      updatedAt: json['updated_at'] != null
          ? parseDate(json['updated_at'] as String)
          : null,
      isSaleBilled: json['is_sale_billed'] == true,
      isPartiallyBilled: json['is_partially_billed'] == true,
      billedAmount: (json['billed_amount'] as num?)?.toDouble() ?? 0.0,
      isEdited: json['is_edited'] == true,
      originalAmount: (json['original_amount'] as num?)?.toDouble(),
      editHistory: (json['edit_history'] as List<dynamic>?)
          ?.map((e) => OrderEditRecord.fromJson(e is Map<String, dynamic>
              ? e
              : Map<String, dynamic>.from(e as Map)))
          .toList(),
      customerMobile: json['customer_mobile'] as String?,
      customerAddress: json['customer_address'] as String?,
      customerGst: json['customer_gst'] as String?,
      shippingAddress: json['shipping_address'] as String?,
      dispatchedThrough: json['dispatched_through'] as String?,
      destination: json['destination'] as String?,
      remarks: json['remarks'] as String?,
      companyId: json['company_id'] as String?,
      companyName: json['company_name'] as String? ??
          (json['tally_companies'] as Map<String, dynamic>?)?['name']
              as String?,
      ledger: json['Type'] as String? ?? 'Credit',
      subtotalBeforeDiscount:
          (json['subtotal_before_discount'] as num?)?.toDouble() ?? 0.0,
      orderDiscountAmount: (json['discount_amount'] as num?)?.toDouble() ?? 0.0,
      orderDiscountPercentage:
          (json['discount_percentage'] as num?)?.toDouble() ?? 0.0,
      canEditUntil: json['can_edit_until'] != null
          ? parseDate(json['can_edit_until'] as String)
          : null,
      editRequestStatus: json['edit_request_status'] as String? ?? 'none',
      editRequestedAt: json['edit_requested_at'] != null
          ? parseDate(json['edit_requested_at'] as String)
          : null,
      editApprovedAt: json['edit_approved_at'] != null
          ? parseDate(json['edit_approved_at'] as String)
          : null,
      editRejectedAt: json['edit_rejected_at'] != null
          ? parseDate(json['edit_rejected_at'] as String)
          : null,
      orderLatitude: (json['order_latitude'] as num?)?.toDouble(),
      orderLongitude: (json['order_longitude'] as num?)?.toDouble(),
      orderAddress: json['order_address'] as String?,
      distanceFromCustomer:
          (json['distance_from_customer'] as num?)?.toDouble(),
    );
  }

  // Helper method to parse datetime and keep as UTC
  static DateTime _parseLocalDateTime(String dateString) {
    return DateTime.parse(dateString).toUtc();
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'order_number': orderNumber,
      'customer_id': customerId,
      'customer_name': customerName,
      'salesman_id': salesmanId,
      'salesman_name': salesmanName, // ✅ NEW
      'order_date': orderDate.toIso8601String(),
      'subtotal_before_discount': subtotalBeforeDiscount,
      'discount_amount': orderDiscountAmount,
      'discount_percentage': orderDiscountPercentage,
      'total_amount': totalAmount,
      'gst_amount': gstAmount,
      'net_amount': netAmount,
      'round_off': roundOff,
      'status': status,
      'notes': notes,
      'remarks': remarks,
      'synced_to_tally': syncedToTally,
      'so_synced_to_tally': syncedToTally,
      'tally_sync_date': tallySyncDate?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'is_sale_billed': isSaleBilled,
      'is_partially_billed': isPartiallyBilled,
      'billed_amount': billedAmount,
      'is_edited': isEdited,
      'original_amount': originalAmount,
      'edit_history': editHistory?.map((e) => e.toJson()).toList(),
      'shipping_address': shippingAddress,
      'dispatched_through': dispatchedThrough,
      'destination': destination,
      'can_edit_until': canEditUntil?.toIso8601String(),
      'edit_request_status': editRequestStatus,
      'edit_requested_at': editRequestedAt?.toIso8601String(),
      'edit_approved_at': editApprovedAt?.toIso8601String(),
      'edit_rejected_at': editRejectedAt?.toIso8601String(),
      'order_latitude': orderLatitude,
      'order_longitude': orderLongitude,
      'order_address': orderAddress,
      'distance_from_customer': distanceFromCustomer,
    };
  }
}

class OrderItemModel {
  final String id;
  final String orderId;
  final String productId;
  final String ItemName;
  final String? PartNumber;
  final String? vtNumber; // VT Number (Alias)
  final String? hsn; // HSN Code
  final double ItemQuantity;
  final double ItemRate;
  final double GstRate;
  final double gstAmount;
  final double totalAmount;
  final double discountPercentage;
  final double discountAmount;
  final double? mrp;
  // Discount fields for PDF table
  final double cashDiscountAmount; // Category discount (customer category)
  final double offerDiscountAmount; // Special offer discount
  final double itemDiscountAmount; // Product screen discount
  final double orderDiscountAmount; // Cart screen manual discount
  final double billedQty; // Qty already billed in Tally sales
  final String? note; // Note/instructions for this item

  OrderItemModel({
    required this.id,
    required this.orderId,
    required this.productId,
    required this.ItemName,
    this.PartNumber,
    this.vtNumber,
    this.hsn,
    required this.ItemQuantity,
    required this.ItemRate,
    required this.GstRate,
    required this.gstAmount,
    required this.totalAmount,
    this.discountPercentage = 0.0,
    this.discountAmount = 0.0,
    this.mrp,
    this.cashDiscountAmount = 0.0,
    this.offerDiscountAmount = 0.0,
    this.itemDiscountAmount = 0.0,
    this.orderDiscountAmount = 0.0,
    this.billedQty = 0.0,
    this.note,
  });

  double get pendingQty {
    final pending = ItemQuantity - billedQty;
    return pending < 0 ? 0 : pending;
  }

  bool get isLineFullyBilled =>
      ItemQuantity > 0 && billedQty + 0.0001 >= ItemQuantity;

  bool get isLinePending => pendingQty > 0.0001;

  double get billedShare {
    if (ItemQuantity <= 0) return 0;
    final share = billedQty / ItemQuantity;
    if (share < 0) return 0;
    if (share > 1) return 1;
    return share;
  }

  double get billedLineAmount => totalAmount * billedShare;

  double get billedGstAmount => gstAmount * billedShare;

  double get pendingLineAmount {
    if (ItemQuantity <= 0) return 0;
    return totalAmount * (pendingQty / ItemQuantity);
  }

  double get pendingShare {
    if (ItemQuantity <= 0) return 0;
    final share = pendingQty / ItemQuantity;
    if (share < 0) return 0;
    if (share > 1) return 1;
    return share;
  }

  double get pendingGstAmount => gstAmount * pendingShare;

  double get lineDiscountTotal {
    final extras = cashDiscountAmount +
        offerDiscountAmount +
        itemDiscountAmount;
    if (orderDiscountAmount > 0.001 &&
        (orderDiscountAmount - discountAmount).abs() < 0.01) {
      return extras + discountAmount;
    }
    return extras + discountAmount + orderDiscountAmount;
  }

  double get pendingDiscountAmount => lineDiscountTotal * pendingShare;

  bool get hasDiscount =>
      discountPercentage > 0.001 || lineDiscountTotal > 0.001;

  static String formatQty(double qty) {
    if (qty == qty.truncateToDouble()) return qty.toInt().toString();
    return qty.toStringAsFixed(2);
  }

  static double _positiveOrFallback(double? primary, double? fallback) {
    if (primary != null && primary > 0) return primary;
    if (fallback != null && fallback > 0) return fallback;
    return primary ?? fallback ?? 0.0;
  }

  factory OrderItemModel.fromJson(Map<String, dynamic> json) {
    return OrderItemModel(
      id: json['id'] as String,
      orderId: json['order_id'] as String,
      productId: json['product_id'] as String,
      ItemName: json['ItemName'] as String? ??
          json['product_name'] as String? ??
          'N/A',
      PartNumber:
          json['PartNumber'] as String? ?? json['product_code'] as String?,
      vtNumber: json['vtNumber'] as String? ?? json['vt_number'] as String?,
      hsn: json['hsn'] as String?,
      ItemQuantity: (json['ItemQuantity'] as num?)?.toDouble() ??
          (json['quantity'] as num).toDouble(),
      ItemRate: (json['ItemRate'] as num?)?.toDouble() ??
          (json['unit_price'] as num).toDouble(),
      GstRate: _positiveOrFallback(
            (json['GstRate'] as num?)?.toDouble(),
            (json['gst_rate'] as num?)?.toDouble(),
          ),
      gstAmount: (json['gst_amount'] as num?)?.toDouble() ?? 0.0,
      totalAmount: (json['total_amount'] as num).toDouble(),
      discountPercentage:
          (json['discount_percentage'] as num?)?.toDouble() ?? 0.0,
      discountAmount: (json['discount_amount'] as num?)?.toDouble() ?? 0.0,
      mrp: (json['mrp'] as num?)?.toDouble(),
      cashDiscountAmount:
          (json['cash_discount_amount'] as num?)?.toDouble() ?? 0.0,
      offerDiscountAmount:
          (json['offer_discount_amount'] as num?)?.toDouble() ?? 0.0,
      itemDiscountAmount:
          (json['item_discount_amount'] as num?)?.toDouble() ?? 0.0,
      orderDiscountAmount:
          (json['order_discount_amount'] as num?)?.toDouble() ?? 0.0,
      billedQty: (json['billed_qty'] as num?)?.toDouble() ?? 0.0,
      note: json['note'] as String? ?? json['remarks'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'order_id': orderId,
      'product_id': productId,
      'ItemName': ItemName,
      'PartNumber': PartNumber,
      'vtNumber': vtNumber,
      'hsn': hsn,
      'ItemQuantity': ItemQuantity,
      'ItemRate': ItemRate,
      'GstRate': GstRate,
      'gst_amount': gstAmount,
      'total_amount': totalAmount,
      'discount_percentage': discountPercentage,
      'discount_amount': discountAmount,
      'mrp': mrp,
      'cash_discount_amount': cashDiscountAmount,
      'offer_discount_amount': offerDiscountAmount,
      'item_discount_amount': itemDiscountAmount,
      'order_discount_amount': orderDiscountAmount,
      'billed_qty': billedQty,
      'note': note,
    };
  }
}

class OrderEditRecord {
  final DateTime editedAt;
  final String? editedBy;
  final double? previousNetAmount;
  final double? newNetAmount;
  final String? previousRemarks;
  final String? newRemarks;
  final String? previousShippingAddress;
  final String? newShippingAddress;
  final List<OrderItemChange> itemChanges;

  OrderEditRecord({
    required this.editedAt,
    this.editedBy,
    this.previousNetAmount,
    this.newNetAmount,
    this.previousRemarks,
    this.newRemarks,
    this.previousShippingAddress,
    this.newShippingAddress,
    this.itemChanges = const [],
  });

  double? get netAmountDiff {
    if (previousNetAmount != null && newNetAmount != null) {
      return newNetAmount! - previousNetAmount!;
    }
    return null;
  }

  bool get isNetAmountIncreased =>
      netAmountDiff != null && netAmountDiff! > 0.01;

  bool get isNetAmountDecreased =>
      netAmountDiff != null && netAmountDiff! < -0.01;

  factory OrderEditRecord.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic d) {
      if (d is String) return DateTime.tryParse(d)?.toLocal() ?? DateTime.now();
      return DateTime.now();
    }

    return OrderEditRecord(
      editedAt: parseDate(json['edited_at']),
      editedBy: json['edited_by'] as String?,
      previousNetAmount: (json['previous_net_amount'] as num?)?.toDouble(),
      newNetAmount: (json['new_net_amount'] as num?)?.toDouble(),
      previousRemarks: json['previous_remarks'] as String?,
      newRemarks: json['new_remarks'] as String?,
      previousShippingAddress: json['previous_shipping_address'] as String?,
      newShippingAddress: json['new_shipping_address'] as String?,
      itemChanges: (json['item_changes'] as List<dynamic>?)
              ?.map((item) => OrderItemChange.fromJson(
                  item is Map<String, dynamic>
                      ? item
                      : Map<String, dynamic>.from(item as Map)))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'edited_at': editedAt.toUtc().toIso8601String(),
      'edited_by': editedBy,
      'previous_net_amount': previousNetAmount,
      'new_net_amount': newNetAmount,
      'previous_remarks': previousRemarks,
      'new_remarks': newRemarks,
      'previous_shipping_address': previousShippingAddress,
      'new_shipping_address': newShippingAddress,
      'item_changes': itemChanges.map((c) => c.toJson()).toList(),
    };
  }
}

class OrderItemChange {
  final String productName;
  final String? productCode;
  final String changeType; // 'modified', 'added', 'removed'
  final double? oldQuantity;
  final double? newQuantity;
  final double? oldRate;
  final double? newRate;
  final double? oldDiscountPercentage;
  final double? newDiscountPercentage;
  final double? oldTotal;
  final double? newTotal;
  final String? oldNote;
  final String? newNote;

  OrderItemChange({
    required this.productName,
    this.productCode,
    required this.changeType,
    this.oldQuantity,
    this.newQuantity,
    this.oldRate,
    this.newRate,
    this.oldDiscountPercentage,
    this.newDiscountPercentage,
    this.oldTotal,
    this.newTotal,
    this.oldNote,
    this.newNote,
  });

  bool get hasRateChanged =>
      oldRate != null && newRate != null && (newRate! - oldRate!).abs() > 0.009;
  bool get isRateIncreased => hasRateChanged && newRate! > oldRate!;
  bool get isRateDecreased => hasRateChanged && newRate! < oldRate!;
  double get rateDiff => (newRate ?? 0) - (oldRate ?? 0);

  bool get hasQuantityChanged =>
      oldQuantity != null &&
      newQuantity != null &&
      (newQuantity! - oldQuantity!).abs() > 0.001;
  bool get isQuantityIncreased =>
      hasQuantityChanged && newQuantity! > oldQuantity!;
  bool get isQuantityDecreased =>
      hasQuantityChanged && newQuantity! < oldQuantity!;
  double get quantityDiff => (newQuantity ?? 0) - (oldQuantity ?? 0);

  bool get hasDiscountChanged =>
      oldDiscountPercentage != null &&
      newDiscountPercentage != null &&
      (newDiscountPercentage! - oldDiscountPercentage!).abs() > 0.01;
  bool get isDiscountIncreased =>
      hasDiscountChanged && newDiscountPercentage! > oldDiscountPercentage!;
  bool get isDiscountDecreased =>
      hasDiscountChanged && newDiscountPercentage! < oldDiscountPercentage!;
  double get discountDiff =>
      (newDiscountPercentage ?? 0) - (oldDiscountPercentage ?? 0);

  bool get hasTotalChanged =>
      oldTotal != null &&
      newTotal != null &&
      (newTotal! - oldTotal!).abs() > 0.01;
  bool get isTotalIncreased => hasTotalChanged && newTotal! > oldTotal!;
  bool get isTotalDecreased => hasTotalChanged && newTotal! < oldTotal!;
  double get totalDiff => (newTotal ?? 0) - (oldTotal ?? 0);

  bool get hasNoteChanged => (oldNote ?? '').trim() != (newNote ?? '').trim();

  factory OrderItemChange.fromJson(Map<String, dynamic> json) {
    return OrderItemChange(
      productName: (json['product_name'] ?? 'Unknown Item') as String,
      productCode: json['product_code'] as String?,
      changeType: (json['change_type'] ?? 'modified') as String,
      oldQuantity: (json['old_quantity'] as num?)?.toDouble(),
      newQuantity: (json['new_quantity'] as num?)?.toDouble(),
      oldRate: (json['old_rate'] as num?)?.toDouble(),
      newRate: (json['new_rate'] as num?)?.toDouble(),
      oldDiscountPercentage:
          (json['old_discount_percentage'] as num?)?.toDouble(),
      newDiscountPercentage:
          (json['new_discount_percentage'] as num?)?.toDouble(),
      oldTotal: (json['old_total'] as num?)?.toDouble(),
      newTotal: (json['new_total'] as num?)?.toDouble(),
      oldNote: json['old_note'] as String?,
      newNote: json['new_note'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'product_name': productName,
      'product_code': productCode,
      'change_type': changeType,
      'old_quantity': oldQuantity,
      'new_quantity': newQuantity,
      'old_rate': oldRate,
      'new_rate': newRate,
      'old_discount_percentage': oldDiscountPercentage,
      'new_discount_percentage': newDiscountPercentage,
      'old_total': oldTotal,
      'new_total': newTotal,
      'old_note': oldNote,
      'new_note': newNote,
    };
  }
}
