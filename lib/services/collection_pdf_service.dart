import 'dart:typed_data';

import 'package:Orderx/models/collection_model.dart';
import 'package:Orderx/services/pdf_service.dart';
import 'package:Orderx/utils/location_utils.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class CollectionPdfService {
  final _money = NumberFormat.currency(locale: 'en_IN', symbol: 'Rs. ');
  final _date = DateFormat('dd MMM yyyy');
  final _dateTime = DateFormat('dd MMM yyyy, hh:mm a');

  Future<Map<String, String>> _resolveLocations(
    List<CollectionModel> collections,
  ) async {
    final addresses = <String, String>{};
    for (final item in collections) {
      final stored = item.locationDisplay;
      if (stored != null && stored.trim().isNotEmpty) {
        addresses[item.id] = stored.trim();
        continue;
      }
      if (item.latitude != null && item.longitude != null) {
        final resolved = await reverseGeocodeAddress(
          item.latitude!,
          item.longitude!,
          allowNominatim: false,
        );
        if (resolved != null && resolved.trim().isNotEmpty) {
          addresses[item.id] = resolved.trim();
        }
      }
    }
    return addresses;
  }

  Future<Uint8List> generate({
    required List<CollectionModel> collections,
    String? companyName,
    String? filterSummary,
  }) async {
    final locations = await _resolveLocations(collections);
    final total = collections.fold<double>(0, (sum, e) => sum + e.amount);
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Collection Report',
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            if (companyName != null && companyName.trim().isNotEmpty)
              pw.Text(
                companyName.trim(),
                style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey800),
              ),
            pw.SizedBox(height: 4),
            if (filterSummary != null && filterSummary.trim().isNotEmpty)
              pw.Text(
                'Filters: $filterSummary',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
              ),
            pw.Text(
              'Generated: ${_dateTime.format(DateTime.now())}',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            ),
            pw.Text(
              '${collections.length} collection${collections.length == 1 ? '' : 's'}  ·  Total ${_money.format(total)}',
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
            ),
            pw.Divider(thickness: 1),
          ],
        ),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey),
          ),
        ),
        build: (context) {
          if (collections.isEmpty) {
            return [pw.Text('No collections found for these filters.')];
          }
          return [
            for (var i = 0; i < collections.length; i++) ...[
              _collectionBlock(collections[i], i + 1, locations),
              pw.SizedBox(height: 10),
            ],
          ];
        },
      ),
    );

    return pdf.save();
  }

  pw.Widget _collectionBlock(
    CollectionModel item,
    int index,
    Map<String, String> locations,
  ) {
    final rows = <List<String>>[
      ['Salesman', item.salesmanName ?? ''],
      ['Customer', item.customerName],
      ['Amount', _money.format(item.amount)],
      ['Collection date', _date.format(item.collectionDate)],
      ['Payment method', item.paymentMethod],
      ['Location', locations[item.id] ?? item.locationAddress ?? 'Not recorded'],
      ['Received from', item.receivedFrom ?? ''],
      [
        item.paymentMethod == PaymentMethod.cheque
            ? 'Cheque no.'
            : item.paymentMethod == PaymentMethod.demandDraft
                ? 'DD no.'
                : 'Instrument no.',
        item.instrumentNumber ?? '',
      ],
      [
        item.paymentMethod == PaymentMethod.cheque
            ? 'Cheque date'
            : 'Instrument date',
        item.instrumentDate != null ? _date.format(item.instrumentDate!) : '',
      ],
      ['Bank', item.bankName ?? ''],
      ['Branch', item.bankBranch ?? ''],
      ['IFSC', item.ifscCode ?? ''],
      ['Drawer', item.drawerName ?? ''],
      ['Transfer mode', item.transferMode ?? ''],
      ['A/c last 4', item.accountLast4 ?? ''],
      ['UPI ID', item.upiId ?? ''],
      ['Txn ID', item.transactionId ?? ''],
      ['Card last 4', item.cardLast4 ?? ''],
      ['Card type', item.cardType ?? ''],
      ['Approval', item.approvalCode ?? ''],
      ['Gateway', item.gatewayName ?? ''],
      ['Wallet', item.walletName ?? ''],
      ['Other method', item.otherMethodDetail ?? ''],
      ['Reference', item.referenceNumber ?? ''],
      ['Remarks', item.remarks ?? ''],
    ].where((row) => row[1].trim().isNotEmpty).toList();

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Expanded(
                child: pw.Text(
                  '$index. ${item.customerName}',
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.Text(
                _money.format(item.amount),
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 6),
          ...rows.map(
            (row) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 3),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.SizedBox(
                    width: 110,
                    child: pw.Text(
                      row[0],
                      style: const pw.TextStyle(
                        fontSize: 9,
                        color: PdfColors.grey700,
                      ),
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Text(
                      row[1],
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> share({
    required List<CollectionModel> collections,
    String? companyName,
    String? filterSummary,
    String filenameLabel = 'Collections',
  }) async {
    final bytes = await generate(
      collections: collections,
      companyName: companyName,
      filterSummary: filterSummary,
    );
    final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    await PdfService().sharePdf(
      bytes,
      stamp,
      filenamePrefix: '${filenameLabel}_',
    );
  }
}
