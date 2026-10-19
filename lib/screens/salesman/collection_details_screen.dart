import 'package:Orderx/core/theme/app_theme.dart';
import 'package:Orderx/models/collection_model.dart';
import 'package:Orderx/services/collection_pdf_service.dart';
import 'package:Orderx/services/collection_service.dart';
import 'package:Orderx/utils/error_handler.dart';
import 'package:Orderx/widgets/location_address_widget.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

class CollectionDetailsScreen extends StatelessWidget {
  final CollectionModel collection;

  const CollectionDetailsScreen({super.key, required this.collection});

  static final _money = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

  Future<void> _openMaps() async {
    final lat = collection.latitude;
    final lng = collection.longitude;
    if (lat == null || lng == null) return;
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete collection?'),
        content: Text(
          'This will permanently delete the collection from ${collection.customerName}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await CollectionService().deleteCollection(collection.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Collection deleted')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ErrorHandler.getFriendlyErrorMessage(e)),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  Future<void> _sharePdf(BuildContext context) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Preparing PDF...'), duration: Duration(seconds: 1)),
    );
    try {
      await CollectionPdfService().share(
        collections: [collection],
        filterSummary: 'Single collection',
        filenameLabel: 'Collection',
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not share PDF: $e'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = collection;
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Collection Details'),
        actions: [
          IconButton(
            tooltip: 'Share PDF',
            icon: const Icon(Icons.share),
            onPressed: () => _sharePdf(context),
          ),
          IconButton(
            tooltip: 'Delete collection',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _confirmDelete(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.customerName,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _money.format(item.amount),
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.success,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${item.paymentMethod} · ${DateFormat('dd MMM yyyy').format(item.collectionDate)}',
                  style: const TextStyle(color: AppTheme.grey),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Location',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: AppTheme.darkBlue,
                  ),
                ),
                const SizedBox(height: 10),
                if (item.hasLocation)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.location_on, color: AppTheme.error, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: item.latitude != null && item.longitude != null
                            ? LocationAddressWidget(
                                latitude: item.latitude!,
                                longitude: item.longitude!,
                                storedAddress: item.locationAddress,
                                compact: false,
                                showIcon: false,
                              )
                            : Text(
                                item.locationAddress!,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                      ),
                    ],
                  )
                else
                  const Text(
                    'Location was not recorded for this collection.',
                    style: TextStyle(color: AppTheme.grey),
                  ),
                if (item.latitude != null && item.longitude != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _openMaps,
                      icon: const Icon(Icons.map_outlined),
                      label: const Text('Open in Maps'),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          _card(
            child: Column(
              children: [
                _row('Salesman', item.salesmanName),
                _row('Method', item.paymentMethod),
                _row(
                  'Collection date',
                  DateFormat('dd MMM yyyy').format(item.collectionDate),
                ),
                _row('Received from', item.receivedFrom),
                _row(
                  item.paymentMethod == PaymentMethod.cheque
                      ? 'Cheque no.'
                      : item.paymentMethod == PaymentMethod.demandDraft
                          ? 'DD no.'
                          : 'Instrument no.',
                  item.instrumentNumber,
                ),
                _row(
                  item.paymentMethod == PaymentMethod.cheque
                      ? 'Cheque date'
                      : 'Instrument date',
                  item.instrumentDate != null
                      ? DateFormat('dd MMM yyyy').format(item.instrumentDate!)
                      : null,
                ),
                _row('Bank', item.bankName),
                _row('Branch', item.bankBranch),
                _row('IFSC', item.ifscCode),
                _row('Drawer', item.drawerName),
                _row('Transfer', item.transferMode),
                _row('A/c last 4', item.accountLast4),
                _row('UPI ID', item.upiId),
                _row('Txn ID', item.transactionId),
                _row('Card last 4', item.cardLast4),
                _row('Card type', item.cardType),
                _row('Approval', item.approvalCode),
                _row('Gateway', item.gatewayName),
                _row('Wallet', item.walletName),
                _row('Other', item.otherMethodDetail),
                _row('Reference', item.referenceNumber),
                _row('Remarks', item.remarks),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _row(String label, String? value) {
    if (value == null || value.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(color: AppTheme.grey, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
