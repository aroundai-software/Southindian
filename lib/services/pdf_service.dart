import 'dart:io';
import 'dart:typed_data';

import 'package:Orderx/models/order_model.dart';
import 'package:Orderx/models/tally_company_model.dart';
import 'package:Orderx/utils/rounding_utils.dart';
import 'package:Orderx/utils/number_to_words.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:Orderx/utils/pdf_downloader_stub.dart'
    if (dart.library.html) 'package:Orderx/utils/pdf_downloader_web.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:Orderx/models/admin_settings.dart';
import 'package:Orderx/models/activity_log_model.dart';
import 'package:Orderx/services/admin_settings_service.dart';
import 'package:Orderx/services/tally_company_service.dart';
import 'package:Orderx/utils/location_utils.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PdfService {

  Future<Uint8List> generateOrderPdf(
    OrderModel order,
    List<OrderItemModel> items, {
    TallyCompanyModel? company,
    String? companyName,
    AdminSettings? settings,
    String documentTitle = 'SALES ORDER',
  }) async {
    try {
      if (order.companyId != null && order.companyId!.isNotEmpty) {
        try {
          company ??= await TallyCompanyService().getCompanyById(order.companyId!);
        } catch (e) {
          print('Error fetching company for PDF: $e');
        }
        if (settings == null) {
          try {
            settings = await AdminSettingsService().getAdminSettings(order.companyId!);
          } catch (e) {
            print('Error fetching settings for PDF: $e');
          }
        }
      }
      final pdf = pw.Document();

      // Load Roboto Bold font dynamically to support the Indian Rupee symbol (₹)
      pw.Font? rupeeFont;
      try {
        rupeeFont = await PdfGoogleFonts.robotoBold();
      } catch (e) {
        // Fallback to null if offline, we'll use Rs. instead
      }

      Uint8List? logoBytes;
      // try {
      //   final ByteData data = await rootBundle.load('assets/images/sip_logo.png');
      //   logoBytes = data.buffer.asUint8List();
      // } catch (e) {
      //   logoBytes = null;
      // }
      logoBytes = null;
      final String finalCompanyName = companyName ?? company?.companyName ?? '';
      final String companyGst = _firstNonEmpty([
            company?.gstNumber,
            settings?.invoiceGst,
          ]) ??
          '';
      final String companyGstCode =
          companyGst.length >= 2 ? companyGst.substring(0, 2) : '00';
      final String addressLine1 = _firstNonEmpty([
            company?.addressLine1,
            settings?.invoiceAddressLine1,
          ]) ??
          '';
      final String addressLine2 = _firstNonEmpty([
            company?.addressLine2,
            settings?.invoiceAddressLine2,
          ]) ??
          '';
      final String cityStatePin = _firstNonEmpty([
            _formatCityStatePin(company),
            settings?.invoiceCityStatePin,
          ]) ??
          '';
      final String? companyPhone = _firstNonEmpty([
        company?.phoneNumber,
        settings?.contactPhone,
      ]);
      final String? companyEmail = _firstNonEmpty([
        company?.email,
        settings?.contactEmail,
      ]);
      final String salesmanName = await _resolveSalesmanName(order);

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(30),
          header: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                if (context.pageNumber == 1) ...[
                  pw.Container(
                    alignment: pw.Alignment.center,
                    padding: const pw.EdgeInsets.only(bottom: 8),
                    child: pw.Text(
                      documentTitle,
                      style: pw.TextStyle(
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                        decoration: pw.TextDecoration.underline,
                      ),
                    ),
                  ),
                  _buildHeaderGrid(
                    logoBytes,
                    order,
                    finalCompanyName,
                    companyGst,
                    companyGstCode,
                    addressLine1: addressLine1,
                    addressLine2: addressLine2,
                    cityStatePin: cityStatePin,
                    phone: companyPhone,
                    email: companyEmail,
                    salesmanName: salesmanName,
                  ),
                ],
                _buildItemsTableHeader(
                  withTopBorder: context.pageNumber > 1,
                ),
              ],
            );
          },
          build: (pw.Context context) {
            return [
              _buildItemsTableBody(items),
              ..._buildSummaryTables(
                items,
                order,
                rupeeFont,
                companyGst,
                companyState: company?.state,
              ),
              _buildFooterGrid(order, items),
            ];
          },
        ),
      );

      return await pdf.save();
    } catch (e) {
      rethrow;
    }
  }

  pw.Widget _buildHeaderGrid(
    Uint8List? logoBytes,
    OrderModel order,
    String companyName,
    String companyGst,
    String companyGstCode, {
    required String addressLine1,
    required String addressLine2,
    required String cityStatePin,
    String? phone,
    String? email,
    String salesmanName = '',
  }) {
    return pw.Table(
      columnWidths: const {
        0: pw.FlexColumnWidth(1),
        1: pw.FlexColumnWidth(1),
      },
      border: const pw.TableBorder(
        top: pw.BorderSide(color: PdfColors.black, width: 0.5),
        left: pw.BorderSide(color: PdfColors.black, width: 0.5),
        right: pw.BorderSide(color: PdfColors.black, width: 0.5),
        bottom: pw.BorderSide(color: PdfColors.black, width: 0.5),
        verticalInside: pw.BorderSide(color: PdfColors.black, width: 0.5),
      ),
      children: [
        pw.TableRow(
          children: [
            // Left Column
            pw.Container(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // Company Details
                  pw.Container(
                    padding: const pw.EdgeInsets.all(6),
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        if (logoBytes != null)
                          pw.Container(
                            width: 45,
                            height: 45,
                            margin: const pw.EdgeInsets.only(right: 8),
                            child: pw.Image(
                              pw.MemoryImage(logoBytes),
                              fit: pw.BoxFit.contain,
                            ),
                          ),
                        pw.Expanded(
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(companyName, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                              if (addressLine1.isNotEmpty) ...[
                                pw.SizedBox(height: 2),
                                pw.Text(addressLine1, style: const pw.TextStyle(fontSize: 8)),
                              ],
                              if (addressLine2.isNotEmpty) ...[
                                pw.SizedBox(height: 1),
                                pw.Text(addressLine2, style: const pw.TextStyle(fontSize: 8)),
                              ],
                              if (cityStatePin.isNotEmpty) ...[
                                pw.SizedBox(height: 1),
                                pw.Text(cityStatePin, style: const pw.TextStyle(fontSize: 8)),
                              ],
                              if (companyGst.isNotEmpty) ...[
                                pw.SizedBox(height: 1),
                                pw.Text('GSTIN/UIN: $companyGst', style: const pw.TextStyle(fontSize: 8)),
                              ],
                              if (_getStateFromGst(companyGst).isNotEmpty) ...[
                                pw.SizedBox(height: 1),
                                pw.Text(_getStateFromGst(companyGst), style: const pw.TextStyle(fontSize: 8)),
                              ],
                              if (phone != null && phone.isNotEmpty) ...[
                                pw.SizedBox(height: 1),
                                pw.Text('Phone: $phone', style: const pw.TextStyle(fontSize: 8)),
                              ],
                              if (email != null && email.isNotEmpty) ...[
                                pw.SizedBox(height: 1),
                                pw.Text('Email: $email', style: const pw.TextStyle(fontSize: 8)),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  pw.Divider(thickness: 0.5, color: PdfColors.black, height: 0),
                  // Buyer Details
                  pw.Container(
                    padding: const pw.EdgeInsets.all(6),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Buyer (Bill to)', style: const pw.TextStyle(fontSize: 8)),
                        pw.SizedBox(height: 2),
                        if (order.customerName != null && order.customerName!.isNotEmpty)
                          pw.Text(order.customerName!, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                        pw.SizedBox(height: 2),
                        pw.Text(order.customerAddress ?? '', style: const pw.TextStyle(fontSize: 8)),
                        pw.SizedBox(height: 2),
                        if (_getStateFromGst(order.customerGst).isNotEmpty)
                          pw.Text(_getStateFromGst(order.customerGst), style: const pw.TextStyle(fontSize: 8)),
                        pw.SizedBox(height: 2),
                        pw.Text('Contact        : ${order.customerMobile ?? ''}', style: const pw.TextStyle(fontSize: 8)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Right Column
            pw.Column(
              children: [
                pw.Table(
                  columnWidths: const {
                    0: pw.FlexColumnWidth(1),
                    1: pw.FlexColumnWidth(1),
                  },
                  children: [
                    pw.TableRow(
                      children: [
                        pw.Container(padding: const pw.EdgeInsets.all(6), decoration: const pw.BoxDecoration(border: pw.Border(right: pw.BorderSide(color: PdfColors.black, width: 0.5))), child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [pw.Text('Voucher No.', style: const pw.TextStyle(fontSize: 8)), pw.SizedBox(height: 2), pw.Text(order.orderNumber, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))])),
                        pw.Container(padding: const pw.EdgeInsets.all(6), child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [pw.Text('Dated', style: const pw.TextStyle(fontSize: 8)), pw.SizedBox(height: 2), pw.Text(DateFormat('d-MMM-yy').format(order.orderDate), style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))])),
                      ],
                    ),
                  ],
                ),
                pw.Divider(thickness: 0.5, color: PdfColors.black, height: 0),
                pw.Table(
                  columnWidths: const {
                    0: pw.FlexColumnWidth(1),
                    1: pw.FlexColumnWidth(1),
                  },
                  children: [
                    pw.TableRow(
                      children: [
                        pw.Container(padding: const pw.EdgeInsets.all(6), decoration: const pw.BoxDecoration(border: pw.Border(right: pw.BorderSide(color: PdfColors.black, width: 0.5))), child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [pw.Text('Mode/Terms of Payment', style: const pw.TextStyle(fontSize: 8)), pw.SizedBox(height: 2), pw.Text(order.ledger, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))])),
                        pw.Container(padding: const pw.EdgeInsets.all(6), child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [pw.Text('Created by', style: const pw.TextStyle(fontSize: 8)), pw.SizedBox(height: 2), pw.Text(salesmanName, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))])),
                      ],
                    ),
                  ],
                ),
                pw.Divider(thickness: 0.5, color: PdfColors.black, height: 0),
                pw.Container(width: double.infinity, padding: const pw.EdgeInsets.all(6), child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [pw.Text('Buyer\'s Ref./Order No.', style: const pw.TextStyle(fontSize: 8)), pw.SizedBox(height: 2), pw.Text(order.orderNumber, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))])),
                pw.Divider(thickness: 0.5, color: PdfColors.black, height: 0),
                pw.Table(
                  columnWidths: const {
                    0: pw.FlexColumnWidth(1),
                    1: pw.FlexColumnWidth(1),
                  },
                  children: [
                    pw.TableRow(
                      children: [
                        pw.Container(padding: const pw.EdgeInsets.all(6), decoration: const pw.BoxDecoration(border: pw.Border(right: pw.BorderSide(color: PdfColors.black, width: 0.5))), child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [pw.Text('Dispatched through', style: const pw.TextStyle(fontSize: 8)), pw.SizedBox(height: 2), pw.Text(order.dispatchedThrough ?? '', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))])),
                        pw.Container(padding: const pw.EdgeInsets.all(6), child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [pw.Text('Destination', style: const pw.TextStyle(fontSize: 8)), pw.SizedBox(height: 2), pw.Text(order.destination ?? '', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))])),
                      ],
                    ),
                  ],
                ),
                pw.Divider(thickness: 0.5, color: PdfColors.black, height: 0),
                pw.Container(
                  padding: const pw.EdgeInsets.all(6),
                  width: double.infinity,
                  constraints: const pw.BoxConstraints(minHeight: 48),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Remarks', style: const pw.TextStyle(fontSize: 8)),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        _orderRemarksText(order),
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  static const Map<int, pw.TableColumnWidth> _itemColumnWidths = {
    0: pw.FlexColumnWidth(0.5),
    1: pw.FlexColumnWidth(3.6),
    2: pw.FlexColumnWidth(1.65),
    3: pw.FlexColumnWidth(0.75),
    4: pw.FlexColumnWidth(0.8),
    5: pw.FlexColumnWidth(0.5),
    6: pw.FlexColumnWidth(1.2),
  };

  pw.Widget _buildItemsTableHeader({bool withTopBorder = false}) {
    const headers = [
      'Sl\nNo.',
      'Description of Goods',
      'Part No.',
      'Qty',
      'Rate',
      'per',
      'Amount',
    ];
    return pw.Table(
      border: pw.TableBorder(
        top: withTopBorder
            ? const pw.BorderSide(color: PdfColors.black, width: 0.5)
            : const pw.BorderSide(width: 0),
        left: const pw.BorderSide(color: PdfColors.black, width: 0.5),
        right: const pw.BorderSide(color: PdfColors.black, width: 0.5),
        verticalInside: const pw.BorderSide(color: PdfColors.black, width: 0.5),
      ),
      columnWidths: _itemColumnWidths,
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: PdfColors.black, width: 0.5),
            ),
          ),
          children: headers
              .map(
                (h) => _buildTableCell(
                  h,
                  align: pw.TextAlign.center,
                  isHeader: true,
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  pw.Widget _buildItemsTableBody(List<OrderItemModel> items) {
    final itemRows = <pw.TableRow>[];

    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      final totalWithGst = item.totalAmount;
      double amountExcludingGst = totalWithGst - item.gstAmount;
      if (amountExcludingGst < 0) amountExcludingGst = 0;

      itemRows.add(
        pw.TableRow(
          children: [
            _buildTableCell('${i + 1}', align: pw.TextAlign.center),
            pw.Container(
              padding: const pw.EdgeInsets.all(4),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    item.ItemName,
                    style: pw.TextStyle(
                      fontSize: 8,
                      fontWeight: pw.FontWeight.bold,
                    ),
                    maxLines: 2,
                  ),
                  if (item.note != null && item.note!.trim().isNotEmpty)
                    pw.Text(
                      'Note: ${item.note!.trim()}',
                      style: pw.TextStyle(
                        fontSize: 6.5,
                        fontStyle: pw.FontStyle.italic,
                        color: PdfColors.grey700,
                      ),
                    ),
                ],
              ),
            ),
            _buildTableCell(
              (item.PartNumber ?? '').trim(),
              align: pw.TextAlign.left,
              maxLines: 1,
              fontSize: 7,
              padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 4),
            ),
            _buildTableCell(
              '${item.ItemQuantity.toStringAsFixed(0)} nos',
              align: pw.TextAlign.right,
              isBold: true,
            ),
            _buildTableCell(
              item.ItemRate.toStringAsFixed(2),
              align: pw.TextAlign.right,
            ),
            _buildTableCell('nos', align: pw.TextAlign.center),
            _buildTableCell(
              amountExcludingGst.toStringAsFixed(2),
              align: pw.TextAlign.right,
              isBold: true,
            ),
          ],
        ),
      );
    }

    if (itemRows.isEmpty) {
      itemRows.add(
        pw.TableRow(
          children: List.generate(7, (_) => _buildTableCell('')),
        ),
      );
    }

    return pw.Table(
      border: const pw.TableBorder(
        left: pw.BorderSide(color: PdfColors.black, width: 0.5),
        right: pw.BorderSide(color: PdfColors.black, width: 0.5),
        verticalInside: pw.BorderSide(color: PdfColors.black, width: 0.5),
      ),
      columnWidths: _itemColumnWidths,
      children: itemRows,
    );
  }

  List<pw.Widget> _buildSummaryTables(
    List<OrderItemModel> items,
    OrderModel order,
    pw.Font? rupeeFont,
    String companyGst, {
    String? companyState,
  }) {
    final double tableSubtotal = items.fold(0.0, (sum, it) {
      final baseAmount = it.totalAmount - it.gstAmount;
      return sum + (baseAmount < 0 ? 0 : baseAmount);
    });
    final double unroundedTotal = tableSubtotal - order.orderDiscountAmount + order.gstAmount;
    final RoundOffResult roundOff = calculateRoundOff(unroundedTotal);
    final double roundedGrandTotal = roundOff.roundedTotal;
    final int totalQty = items.fold(0, (sum, it) => sum + it.ItemQuantity.toInt());

    final summaryRows = <pw.TableRow>[
      pw.TableRow(
        children: [
          _buildTableCell(''),
          _buildTableCell(''),
          _buildTableCell(''),
          _buildTableCell(''),
          _buildTableCell(''),
          _buildTableCell(''),
          pw.Container(
            padding: const pw.EdgeInsets.all(4),
            alignment: pw.Alignment.centerRight,
            decoration: const pw.BoxDecoration(
              border: pw.Border(top: pw.BorderSide(color: PdfColors.black, width: 0.5)),
            ),
            child: pw.Text(tableSubtotal.toStringAsFixed(2), style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
          ),
        ],
      ),
    ];

    if (order.orderDiscountAmount > 0) {
      summaryRows.add(
        pw.TableRow(
          children: [
            _buildTableCell(''),
            pw.Padding(
              padding: const pw.EdgeInsets.all(4),
              child: pw.Text('Discount', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 8, fontStyle: pw.FontStyle.italic, fontWeight: pw.FontWeight.bold)),
            ),
            _buildTableCell(''), _buildTableCell(''), _buildTableCell(''), _buildTableCell(''),
            pw.Padding(
              padding: const pw.EdgeInsets.all(4),
              child: pw.Text('-${order.orderDiscountAmount.toStringAsFixed(2)}', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
            ),
          ],
        ),
      );
    }

    if (order.gstAmount > 0) {
      final isLocal = _isIntraStateSupply(
        companyGst: companyGst,
        customerGst: order.customerGst,
        companyState: companyState,
      );

      if (isLocal) {
        final halfGst = order.gstAmount / 2;
        summaryRows.add(
          pw.TableRow(
            children: [
              _buildTableCell(''),
              pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: pw.Text('CGST', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 8, fontStyle: pw.FontStyle.italic, fontWeight: pw.FontWeight.bold)),
              ),
              _buildTableCell(''), _buildTableCell(''), _buildTableCell(''), _buildTableCell(''),
              pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: pw.Text(halfGst.toStringAsFixed(2), textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
              ),
            ],
          ),
        );
        summaryRows.add(
          pw.TableRow(
            children: [
              _buildTableCell(''),
              pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: pw.Text('SGST', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 8, fontStyle: pw.FontStyle.italic, fontWeight: pw.FontWeight.bold)),
              ),
              _buildTableCell(''), _buildTableCell(''), _buildTableCell(''), _buildTableCell(''),
              pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: pw.Text(halfGst.toStringAsFixed(2), textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
              ),
            ],
          ),
        );
      } else {
        summaryRows.add(
          pw.TableRow(
            children: [
              _buildTableCell(''),
              pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: pw.Text('IGST', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 8, fontStyle: pw.FontStyle.italic, fontWeight: pw.FontWeight.bold)),
              ),
              _buildTableCell(''), _buildTableCell(''), _buildTableCell(''), _buildTableCell(''),
              pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: pw.Text(order.gstAmount.toStringAsFixed(2), textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
              ),
            ],
          ),
        );
      }
    }

    final formattedRoundOff = roundOff.formattedRoundOff;
    final isDeduction = formattedRoundOff.startsWith('-');
    final displayValue = isDeduction ? formattedRoundOff : '+${formattedRoundOff.replaceFirst('+', '')}';
    final prefixText = isDeduction ? 'Less :' : 'Add :';

    summaryRows.add(
      pw.TableRow(
        children: [
          _buildTableCell(''),
          pw.Padding(
            padding: const pw.EdgeInsets.all(4),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(prefixText, style: pw.TextStyle(fontSize: 8, fontStyle: pw.FontStyle.italic)),
                pw.Text('Round Off', style: pw.TextStyle(fontSize: 8, fontStyle: pw.FontStyle.italic, fontWeight: pw.FontWeight.bold)),
              ],
            ),
          ),
          _buildTableCell(''),
          _buildTableCell(''),
          _buildTableCell(''),
          _buildTableCell(''),
          pw.Padding(
            padding: const pw.EdgeInsets.all(4),
            child: pw.Text(displayValue, textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
          ),
        ],
      ),
    );

    return [
      pw.Table(
        border: const pw.TableBorder(
          left: pw.BorderSide(color: PdfColors.black, width: 0.5),
          right: pw.BorderSide(color: PdfColors.black, width: 0.5),
          verticalInside: pw.BorderSide(color: PdfColors.black, width: 0.5),
        ),
        columnWidths: _itemColumnWidths,
        children: summaryRows,
      ),
      pw.Table(
        border: const pw.TableBorder(
          left: pw.BorderSide(color: PdfColors.black, width: 0.5),
          right: pw.BorderSide(color: PdfColors.black, width: 0.5),
        ),
        columnWidths: _itemColumnWidths,
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(
              border: pw.Border(top: pw.BorderSide(color: PdfColors.black, width: 0.5)),
            ),
            children: [
              pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: pw.Text('Total', textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 8)),
              ),
              pw.SizedBox(),
              pw.SizedBox(),
              pw.Container(
                padding: const pw.EdgeInsets.all(4),
                alignment: pw.Alignment.centerRight,
                decoration: const pw.BoxDecoration(
                  border: pw.Border(right: pw.BorderSide(color: PdfColors.black, width: 0.5)),
                ),
                child: pw.Text('$totalQty nos', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
              ),
              pw.SizedBox(),
              pw.Container(
                decoration: const pw.BoxDecoration(
                  border: pw.Border(right: pw.BorderSide(color: PdfColors.black, width: 0.5)),
                ),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: pw.Text(
                  rupeeFont != null ? '₹ ${roundedGrandTotal.toStringAsFixed(2)}' : 'Rs. ${roundedGrandTotal.toStringAsFixed(2)}',
                  textAlign: pw.TextAlign.right,
                  style: pw.TextStyle(
                    font: rupeeFont,
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ];
  }

  Future<String> _resolveSalesmanName(OrderModel order) async {
    final existing = (order.salesmanName ?? '').trim();
    if (existing.isNotEmpty) return existing;
    if (order.salesmanId.isEmpty) return '';
    try {
      final row = await Supabase.instance.client
          .from('users')
          .select('name')
          .eq('id', order.salesmanId)
          .maybeSingle();
      return (row?['name'] as String?)?.trim() ?? '';
    } catch (e) {
      print('Error fetching salesman name for PDF: $e');
      return '';
    }
  }

  String _orderRemarksText(OrderModel order) {
    final remarks = (order.remarks ?? '').trim();
    if (remarks.isNotEmpty) return remarks;
    return (order.notes ?? '').trim();
  }

  String? _firstNonEmpty(List<String?> values) {
    for (final value in values) {
      if (value != null && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return null;
  }

  String? _formatCityStatePin(TallyCompanyModel? company) {
    if (company == null) return null;
    final cityState = [
      company.city,
      company.state,
    ].whereType<String>().where((part) => part.trim().isNotEmpty).join(', ');
    final pin = company.pinCode?.trim() ?? '';
    if (cityState.isEmpty && pin.isEmpty) return null;
    if (pin.isEmpty) return cityState;
    if (cityState.isEmpty) return 'Pincode: $pin';
    return '$cityState\nPincode: $pin';
  }

  String? _gstStateCode(String? gst) {
    final cleaned = (gst ?? '').replaceAll(RegExp(r'[\s-]'), '');
    if (cleaned.length < 2) return null;
    final code = cleaned.substring(0, 2);
    if (!RegExp(r'^\d{2}$').hasMatch(code) || code == '00') return null;
    return code;
  }

  static const Map<String, String> _gstStateNames = {
    '01': 'Jammu & Kashmir', '02': 'Himachal Pradesh', '03': 'Punjab', '04': 'Chandigarh',
    '05': 'Uttarakhand', '06': 'Haryana', '07': 'Delhi', '08': 'Rajasthan',
    '09': 'Uttar Pradesh', '10': 'Bihar', '11': 'Sikkim', '12': 'Arunachal Pradesh',
    '13': 'Nagaland', '14': 'Manipur', '15': 'Mizoram', '16': 'Tripura',
    '17': 'Meghalaya', '18': 'Assam', '19': 'West Bengal', '20': 'Jharkhand',
    '21': 'Odisha', '22': 'Chhattisgarh', '23': 'Madhya Pradesh', '24': 'Gujarat',
    '25': 'Daman & Diu', '26': 'Dadra & Nagar Haveli', '27': 'Maharashtra',
    '29': 'Karnataka', '30': 'Goa', '31': 'Lakshadweep', '32': 'Kerala',
    '33': 'Tamil Nadu', '34': 'Puducherry', '35': 'Andaman & Nicobar Islands',
    '36': 'Telangana', '37': 'Andhra Pradesh', '38': 'Ladakh'
  };

  bool _isIntraStateSupply({
    required String companyGst,
    String? customerGst,
    String? companyState,
  }) {
    final companyCode = _gstStateCode(companyGst);
    final customerCode = _gstStateCode(customerGst);
    if (companyCode != null && customerCode != null) {
      return companyCode == customerCode;
    }
    final companyStateName = (companyState ?? '').trim().toLowerCase();
    if (companyStateName.isNotEmpty && customerCode != null) {
      final customerState = _gstStateNames[customerCode]?.toLowerCase();
      if (customerState != null) {
        return companyStateName == customerState;
      }
    }
    // If company GST is missing, default to CGST/SGST (intra-state).
    return true;
  }

  String _getStateFromGst(String? gst) {
    final code = _gstStateCode(gst);
    if (code == null) return '';
    final stateName = _gstStateNames[code];
    if (stateName != null) {
      return 'State : $stateName, Code : $code';
    }
    return '';
  }

  pw.Widget _buildTableCell(String text, {
    pw.TextAlign align = pw.TextAlign.left, 
    bool isBold = false, 
    bool isItalic = false,
    bool isHeader = false,
    bool isLast = false,
    int? maxLines,
    double fontSize = 8,
    pw.EdgeInsets padding = const pw.EdgeInsets.all(4),
  }) {
    return pw.Container(
      padding: padding,
      child: text.isEmpty ? pw.SizedBox() : pw.Text(
        text,
        textAlign: align,
        maxLines: maxLines,
        overflow: maxLines == 1 ? pw.TextOverflow.clip : pw.TextOverflow.visible,
        style: pw.TextStyle(
          fontSize: fontSize, 
          fontWeight: isBold || isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
          fontStyle: isItalic ? pw.FontStyle.italic : pw.FontStyle.normal,
        ),
      ),
    );
  }

  pw.Widget _buildFooterGrid(OrderModel order, List<OrderItemModel> items) {
    final double tableSubtotal = items.fold(0.0, (sum, it) {
      final baseAmount = it.totalAmount - it.gstAmount;
      return sum + (baseAmount < 0 ? 0 : baseAmount);
    });
    final double unroundedTotal = tableSubtotal - order.orderDiscountAmount + order.gstAmount;
    final RoundOffResult roundOff = calculateRoundOff(unroundedTotal);
    final double roundedGrandTotal = roundOff.roundedTotal;
    final String amountInWords = NumberToWords.convertAmount(roundedGrandTotal);

    return pw.Container(
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: PdfColors.black, width: 0.5),
          left: pw.BorderSide(color: PdfColors.black, width: 0.5),
          right: pw.BorderSide(color: PdfColors.black, width: 0.5),
          bottom: pw.BorderSide(color: PdfColors.black, width: 0.5),
        ),
      ),
      child: pw.Container(
        padding: const pw.EdgeInsets.all(4),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Amount Chargeable (in words)', style: const pw.TextStyle(fontSize: 8)),
                pw.Text(amountInWords, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
              ],
            ),
            pw.Text('E. & O.E', style: pw.TextStyle(fontSize: 8, fontStyle: pw.FontStyle.italic)),
          ],
        ),
      ),
    );
  }

  Future<Map<String, String>> _resolveActivityLocations(
    List<ActivityLog> logs,
  ) async {
    final addresses = <String, String>{};
    final pending = <({String key, double lat, double lng})>[];
    for (final log in logs) {
      if (log.latitude == null || log.longitude == null) continue;
      final lat = log.latitude!;
      final lng = log.longitude!;
      final key = geocodeCacheKey(lat, lng);
      if (addresses.containsKey(key)) continue;
      final cached = cachedGeocodedAddress(lat, lng);
      if (cached != null) {
        addresses[key] = cached;
        continue;
      }
      pending.add((key: key, lat: lat, lng: lng));
    }

    if (pending.isEmpty) return addresses;

    await Future.wait(pending.map((item) async {
      final resolved = await reverseGeocodeAddress(
        item.lat,
        item.lng,
        allowNominatim: false,
      );
      if (resolved != null && resolved.trim().isNotEmpty) {
        addresses[item.key] = resolved.trim();
      }
    }));
    return addresses;
  }

  String _activityLocation(
    ActivityLog log,
    Map<String, String> locations,
  ) {
    if (log.latitude == null || log.longitude == null) return 'Not recorded';
    final key = geocodeCacheKey(log.latitude!, log.longitude!);
    return locations[key] ?? 'Recorded';
  }

  pw.Widget _pdfSectionTitle(String title) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 6, bottom: 2),
      child: pw.Text(
        title,
        style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
      ),
    );
  }

  pw.Widget _pdfDetailLine(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 1),
      child: pw.Text(text, style: const pw.TextStyle(fontSize: 8)),
    );
  }

  Future<Uint8List> generateActivityReportPdf({
    required String title,
    required String periodLabel,
    required String salesmanLabel,
    required List<ActivityLog> logs,
  }) async {
    final pdf = pw.Document();
    final dateFmt = DateFormat('EEE, dd MMM yyyy');
    final timeFmt = DateFormat('hh:mm a');
    final reports = groupActivityLogs(logs);
    final locations = await _resolveActivityLocations(logs);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              title,
              style: pw.TextStyle(
                fontSize: 16,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text('Period: $periodLabel',
                style: const pw.TextStyle(fontSize: 10)),
            pw.Text('Salesman: $salesmanLabel',
                style: const pw.TextStyle(fontSize: 10)),
            pw.Text(
              'Generated: ${DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now())}',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
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
          if (reports.isEmpty) {
            return [pw.Text('No activity found for this period.')];
          }

          return [
            pw.Text(
              '${reports.length} salesman  ·  '
              '${logs.where((l) => l.type == ActivityLogType.login).length} login  ·  '
              '${logs.where((l) => l.type == ActivityLogType.logout).length} logout  ·  '
              '${logs.where((l) => l.type == ActivityLogType.punch).length} punches  ·  '
              '${logs.where((l) => l.type == ActivityLogType.orderCreated).length} orders  ·  '
              '${logs.where((l) => l.type == ActivityLogType.collection).length} collections',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 12),
            ...reports.expand((report) {
              return [
                pw.Container(
                  width: double.infinity,
                  color: PdfColors.blue50,
                  padding: const pw.EdgeInsets.symmetric(
                      horizontal: 8, vertical: 6),
                  child: pw.Text(
                    report.mobile == null || report.mobile!.isEmpty
                        ? report.salesmanName
                        : '${report.salesmanName}  (${report.mobile})',
                    style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
                pw.SizedBox(height: 6),
                ...report.days.map((day) {
                  return pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 12),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          dateFmt.format(day.day),
                          style: pw.TextStyle(
                            fontSize: 11,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        _pdfSectionTitle('Login'),
                        if (day.logins.isEmpty)
                          _pdfDetailLine('No login recorded')
                        else
                          ...day.logins.map((login) => pw.Column(
                                crossAxisAlignment:
                                    pw.CrossAxisAlignment.start,
                                children: [
                                  _pdfDetailLine(
                                    'Time: ${timeFmt.format(login.timestamp)}',
                                  ),
                                  _pdfDetailLine(
                                    'Location: ${_activityLocation(login, locations)}',
                                  ),
                                  if (login.deviceInfo != null &&
                                      login.deviceInfo!.isNotEmpty)
                                    _pdfDetailLine(
                                      'Device: ${login.deviceInfo}',
                                    ),
                                ],
                              )),
                        _pdfSectionTitle('Logout'),
                        if (day.stillLoggedIn)
                          _pdfDetailLine('Still logged in')
                        else if (day.logouts.isEmpty)
                          _pdfDetailLine('No logout recorded')
                        else
                          ...day.logouts.map((logout) => pw.Column(
                                crossAxisAlignment:
                                    pw.CrossAxisAlignment.start,
                                children: [
                                  _pdfDetailLine(
                                    'Time: ${timeFmt.format(logout.timestamp)}',
                                  ),
                                  _pdfDetailLine(
                                    'Location: ${_activityLocation(logout, locations)}',
                                  ),
                                ],
                              )),
                        _pdfSectionTitle('Location punches'),
                        if (day.punches.isEmpty)
                          _pdfDetailLine('No punches')
                        else
                          ...day.punches.map((punch) => pw.Column(
                                crossAxisAlignment:
                                    pw.CrossAxisAlignment.start,
                                children: [
                                  _pdfDetailLine(
                                    '${punch.notes != null && punch.notes!.isNotEmpty ? punch.notes! : 'Punch'}  ·  ${timeFmt.format(punch.timestamp)}',
                                  ),
                                  _pdfDetailLine(
                                    'Location: ${_activityLocation(punch, locations)}',
                                  ),
                                ],
                              )),
                        _pdfSectionTitle('Orders created'),
                        if (day.orders.isEmpty)
                          _pdfDetailLine('No orders')
                        else
                          ...day.orders.map((order) => pw.Column(
                                crossAxisAlignment:
                                    pw.CrossAxisAlignment.start,
                                children: [
                                  _pdfDetailLine(
                                    '${order.orderNumber ?? 'Order'}  ·  ${order.customerName ?? 'Walk-in'}  ·  ${timeFmt.format(order.timestamp)}'
                                    '${order.orderAmount == null ? '' : '  ·  Rs. ${order.orderAmount!.toStringAsFixed(2)}'}',
                                  ),
                                  _pdfDetailLine(
                                    'Location: ${_activityLocation(order, locations)}',
                                  ),
                                ],
                              )),
                        _pdfSectionTitle('Collections'),
                        if (day.collections.isEmpty)
                          _pdfDetailLine('No collections')
                        else
                          ...day.collections.map((collection) => pw.Column(
                                crossAxisAlignment:
                                    pw.CrossAxisAlignment.start,
                                children: [
                                  _pdfDetailLine(
                                    '${collection.customerName ?? 'Unknown customer'}  ·  ${collection.paymentMethod ?? 'Payment'}  ·  ${timeFmt.format(collection.timestamp)}',
                                  ),
                                  _pdfDetailLine(
                                    'Txn ID: ${(collection.transactionId == null || collection.transactionId!.trim().isEmpty) ? '-' : collection.transactionId}',
                                  ),
                                ],
                              )),
                      ],
                    ),
                  );
                }),
                pw.SizedBox(height: 8),
              ];
            }),
          ];
        },
      ),
    );

    return pdf.save();
  }

  Future<void> sharePdf(Uint8List pdfBytes, String orderNumber, {String filenamePrefix = 'Order_'}) async {
    try {
      final sanitizedOrderNumber = orderNumber.replaceAll('/', '_').replaceAll('\\', '_');
      final filename = '$filenamePrefix$sanitizedOrderNumber.pdf';

      if (kIsWeb) {
        await downloadPdfOnWeb(filename, pdfBytes);
      } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        await Printing.sharePdf(bytes: pdfBytes, filename: filename);
      } else {
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/$filename');
        await file.writeAsBytes(pdfBytes);
        await Share.shareXFiles(
          [XFile(file.path)],
          subject: 'Invoice $orderNumber',
          text: 'Please find attached invoice $orderNumber',
        );
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> printPdf(Uint8List pdfBytes) async {
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdfBytes,
    );
  }
}
