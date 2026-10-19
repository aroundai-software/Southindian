import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import 'package:Orderx/models/order_model.dart';
import 'package:Orderx/utils/pdf_downloader_stub.dart'
    if (dart.library.html) 'package:Orderx/utils/pdf_downloader_web.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PartialOrdersExcelService {
  static const _xlsxMime =
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

  Future<void> sharePendingOrders({
    required List<OrderModel> orders,
    required Map<String, List<OrderItemModel>> itemsByOrderId,
    String itemNameFilter = '',
  }) async {
    final salesmanNames = await _resolveSalesmanNames(orders);
    final bytes = _buildExcel(
      orders: orders,
      itemsByOrderId: itemsByOrderId,
      itemNameFilter: itemNameFilter,
      salesmanNames: salesmanNames,
    );
    if (bytes.isEmpty) {
      throw StateError('No pending items to share');
    }
    final filename =
        'partial_orders_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.xlsx';
    if (kIsWeb) {
      await downloadBytesOnWeb(filename, bytes, mimeType: _xlsxMime);
      return;
    }
    await Share.shareXFiles(
      [
        XFile.fromData(
          bytes,
          mimeType: _xlsxMime,
          name: filename,
        ),
      ],
      fileNameOverrides: [filename],
      subject: 'Partial pending orders',
      text: 'Pending items for ${orders.length} partial order(s)',
    );
  }

  Uint8List _buildExcel({
    required List<OrderModel> orders,
    required Map<String, List<OrderItemModel>> itemsByOrderId,
    required String itemNameFilter,
    required Map<String, String> salesmanNames,
  }) {
    final excel = Excel.createExcel();
    final sheet = excel['Pending Items'];
    final defaultSheet = excel.getDefaultSheet();
    if (defaultSheet != null && defaultSheet != 'Pending Items') {
      excel.delete(defaultSheet);
    }

    final headers = [
      'Order Number',
      'Customer',
      'Salesman',
      'Item',
      'Quantity',
      'Rate',
      'GST %',
      'GST Amount',
      'Discount %',
      'Discount Amount',
      'Amount',
    ];
    sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());

    final query = itemNameFilter.trim().toLowerCase();
    var rowCount = 0;
    for (final order in orders) {
      final pending = (itemsByOrderId[order.id] ?? [])
          .where((item) => item.isLinePending)
          .where((item) {
        if (query.isEmpty) return true;
        return item.ItemName.toLowerCase().contains(query) ||
            (item.PartNumber ?? '').toLowerCase().contains(query);
      });
      for (final item in pending) {
        sheet.appendRow([
          TextCellValue(order.orderNumber),
          TextCellValue(order.customerName ?? ''),
          TextCellValue(salesmanNames[order.id] ?? order.salesmanName ?? ''),
          TextCellValue(item.ItemName),
          DoubleCellValue(item.pendingQty),
          DoubleCellValue(item.ItemRate),
          DoubleCellValue(item.GstRate),
          DoubleCellValue(double.parse(item.pendingGstAmount.toStringAsFixed(2))),
          DoubleCellValue(item.discountPercentage),
          DoubleCellValue(
              double.parse(item.pendingDiscountAmount.toStringAsFixed(2))),
          DoubleCellValue(
              double.parse(item.pendingLineAmount.toStringAsFixed(2))),
        ]);
        rowCount++;
      }
    }

    if (rowCount == 0) return Uint8List(0);
    final encoded = excel.encode();
    if (encoded == null) return Uint8List(0);
    return Uint8List.fromList(encoded);
  }

  Future<Map<String, String>> _resolveSalesmanNames(
    List<OrderModel> orders,
  ) async {
    final names = <String, String>{
      for (final order in orders)
        if ((order.salesmanName ?? '').trim().isNotEmpty)
          order.id: order.salesmanName!.trim(),
    };
    final missingIds = orders
        .where((order) => !names.containsKey(order.id) && order.salesmanId.isNotEmpty)
        .map((order) => order.salesmanId)
        .toSet()
        .toList();
    if (missingIds.isEmpty) return names;
    try {
      final rows = await Supabase.instance.client
          .from('users')
          .select('id, name')
          .inFilter('id', missingIds);
      final byUserId = <String, String>{};
      for (final row in rows as List) {
        final id = row['id']?.toString() ?? '';
        final name = (row['name'] as String?)?.trim() ?? '';
        if (id.isNotEmpty && name.isNotEmpty) {
          byUserId[id] = name;
        }
      }
      for (final order in orders) {
        if (names.containsKey(order.id)) continue;
        final name = byUserId[order.salesmanId];
        if (name != null) names[order.id] = name;
      }
    } catch (e) {
      print('Error fetching salesman names for Excel: $e');
    }
    return names;
  }
}
