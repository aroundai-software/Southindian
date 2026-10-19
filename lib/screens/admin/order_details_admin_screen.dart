import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:Orderx/core/theme/app_theme.dart';
import 'package:Orderx/models/order_model.dart';
import 'package:Orderx/models/tally_company_model.dart';
import 'package:Orderx/providers/auth_provider.dart';
import 'package:Orderx/screens/salesman/edit_order_screen.dart';
import 'package:Orderx/services/admin_settings_service.dart';
import 'package:Orderx/services/invoice_service.dart';
import 'package:Orderx/services/order_service.dart';
import 'package:Orderx/services/pdf_service.dart';
import 'package:Orderx/services/tally_company_service.dart';
import 'package:Orderx/widgets/location_address_widget.dart';
import 'package:Orderx/widgets/pending_order_item_details.dart';
import 'package:Orderx/widgets/order_edit_history_widget.dart';

class OrderDetailsAdminScreen extends StatefulWidget {
  final OrderModel order;

  const OrderDetailsAdminScreen({super.key, required this.order});

  @override
  State<OrderDetailsAdminScreen> createState() =>
      _OrderDetailsAdminScreenState();
}

class _OrderDetailsAdminScreenState extends State<OrderDetailsAdminScreen> {
  final OrderService _orderService = OrderService();
  final InvoiceService _invoiceService = InvoiceService();
  final PdfService _pdfService = PdfService();
  final TallyCompanyService _companyService = TallyCompanyService();
  List<OrderItemModel> _items = [];
  bool _isLoading = true;
  bool _isGeneratingPdf = false;
  late OrderModel _currentOrder;
  bool _isAdminCreated = false;
  bool _isBilled = false;
  int _editWindowMinutes = 30;
  bool _allowOrderEditing = true;
  bool _settingsLoaded = false;
  Timer? _countdownTimer;

  bool get _orderIsBilled => _isBilled || _currentOrder.isSaleBilled;

  bool get _canEditOrder {
    if (!_isAdminCreated || _orderIsBilled) return false;
    if (!_allowOrderEditing) return true;
    return _isWithinInitialEditWindow();
  }

  @override
  void initState() {
    super.initState();
    _currentOrder = widget.order;
    _loadItems();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadEditContext());
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _loadEditContext() async {
    try {
      final companyId = _currentOrder.companyId ??
          context.read<AuthProvider>().selectedCompanyId;
      final createdByAdmin =
          await _orderService.isCreatedByAdmin(_currentOrder.salesmanId);
      var minutes = 30;
      var allowEditing = true;
      if (companyId != null && companyId != 'ALL') {
        final svc = AdminSettingsService();
        minutes = await svc.getOrderEditWindowMinutes(companyId);
        final settings = await svc.getAdminSettings(companyId);
        allowEditing = settings.allowOrderEditing;
      }
      if (!mounted) return;
      setState(() {
        _isAdminCreated = createdByAdmin;
        _editWindowMinutes = minutes;
        _allowOrderEditing = allowEditing;
        _settingsLoaded = true;
      });
      if (createdByAdmin) _startCountdown();
    } catch (e) {
      print('Error loading admin edit settings: $e');
      if (mounted) setState(() => _settingsLoaded = true);
    }
  }

  Future<void> _refreshOrder() async {
    try {
      final updated = await _orderService.getOrderById(_currentOrder.id);
      if (updated != null && mounted) {
        setState(() => _currentOrder = updated);
      }
    } catch (e) {
      print('Error refreshing order: $e');
    }
  }

  Future<void> _loadItems() async {
    final items = await _orderService.getOrderItems(_currentOrder.id);
    bool billed = false;
    try {
      billed = await _invoiceService
          .checkOrderBilledInTally(_currentOrder.orderNumber);
    } catch (_) {}
    if (mounted) {
      setState(() {
        _items = items;
        _isBilled = billed;
        _isLoading = false;
      });
    }
  }

  DateTime _createdAtLocal() {
    final createdAt = _currentOrder.createdAt;
    if (!createdAt.isUtc) return createdAt;
    return DateTime(
      createdAt.year,
      createdAt.month,
      createdAt.day,
      createdAt.hour,
      createdAt.minute,
      createdAt.second,
    );
  }

  bool _isWithinInitialEditWindow() {
    return DateTime.now()
        .isBefore(_createdAtLocal().add(Duration(minutes: _editWindowMinutes)));
  }

  Duration? _getInitialWindowRemaining() {
    if (!_isWithinInitialEditWindow()) return null;
    return _createdAtLocal()
        .add(Duration(minutes: _editWindowMinutes))
        .difference(DateTime.now());
  }

  String _formatDuration(Duration duration) {
    if (duration.isNegative) return 'Expired';
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return minutes > 0 ? '${hours}h ${minutes}m' : '${hours}h';
    }
    if (minutes > 0) {
      return seconds > 0 ? '${minutes}m ${seconds}s' : '${minutes}m';
    }
    return '${seconds}s';
  }

  Future<void> _editOrder() async {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No items to edit'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (!_canEditOrder) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _orderIsBilled
                ? 'This order has been billed and cannot be edited'
                : 'Edit window has expired',
          ),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => EditOrderScreen(
          order: _currentOrder,
          items: _items,
        ),
      ),
    );
    if (result == true && mounted) {
      setState(() => _isLoading = true);
      await _refreshOrder();
      await _loadItems();
    }
  }

  Future<void> _shareOrder() async {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No items to share'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isGeneratingPdf = true);

    try {
      TallyCompanyModel? company;
      final companyId = _currentOrder.companyId;
      if (companyId != null && companyId.isNotEmpty) {
        try {
          company = await _companyService.getCompanyById(companyId);
        } catch (e) {
          print('Error fetching company for admin PDF share: $e');
        }
      }

      final pdfBytes = await _pdfService.generateOrderPdf(
        _currentOrder,
        _items,
        company: company,
        companyName: _currentOrder.companyName,
      );

      if (!mounted) return;

      setState(() => _isGeneratingPdf = false);

      await _pdfService.sharePdf(pdfBytes, _currentOrder.orderNumber);
    } catch (e) {
      print('Error sharing: $e');
      if (!mounted) return;

      setState(() => _isGeneratingPdf = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error sharing order: ${e.toString()}'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  Future<void> _printOrder() async {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No items to print'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isGeneratingPdf = true);

    try {
      TallyCompanyModel? company;
      final companyId = _currentOrder.companyId;
      if (companyId != null && companyId.isNotEmpty) {
        try {
          company = await _companyService.getCompanyById(companyId);
        } catch (e) {
          print('Error fetching company for admin PDF print: $e');
        }
      }

      final pdfBytes = await _pdfService.generateOrderPdf(
        _currentOrder,
        _items,
        company: company,
        companyName: _currentOrder.companyName,
      );
      await _pdfService.printPdf(pdfBytes);

      if (!mounted) return;

      setState(() => _isGeneratingPdf = false);
    } catch (e) {
      if (!mounted) return;

      setState(() => _isGeneratingPdf = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error printing order: ${e.toString()}'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Order Details'),
        actions: [
          if (!_isLoading)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
              onPressed: () async {
                setState(() => _isLoading = true);
                await _refreshOrder();
                await _loadItems();
                await _loadEditContext();
              },
            ),
          if (!_isLoading)
            IconButton(
              icon: const Icon(Icons.print),
              onPressed: _isGeneratingPdf ? null : _printOrder,
              tooltip: 'Print',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_settingsLoaded && _isAdminCreated)
                  _buildEditPermissionBar(),
                Expanded(
                  child: Stack(
                    children: [
                      SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildOrderInfoCard(),
                            if (_currentOrder.isEdited)
                              OrderEditHistoryWidget(order: _currentOrder),
                            const SizedBox(height: 16),
                            if (_currentOrder.customerName != null)
                              _buildCustomerInfoCard(),
                            if (_currentOrder.customerName != null)
                              const SizedBox(height: 16),
                            _buildPendingToSaleBanner(),
                            Text(
                              'Order Items',
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 12),
                            if (_items.isEmpty)
                              const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(20),
                                  child: Text('No items found'),
                                ),
                              )
                            else
                              ..._displayItems
                                  .map((item) => _buildItemCard(item)),
                            const SizedBox(height: 16),
                            _buildSummaryCard(),
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                      if (_isGeneratingPdf)
                        Container(
                          color: Colors.black54,
                          child: const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(color: Colors.white),
                                SizedBox(height: 16),
                                Text(
                                  'Generating PDF...',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
      floatingActionButton:
          !_isLoading &&
                  !_isGeneratingPdf &&
                  _items.isNotEmpty &&
                  !_canEditOrder
              ? FloatingActionButton.extended(
                  onPressed: _shareOrder,
                  icon: const Icon(Icons.share),
                  label: const Text('Share Order'),
                  backgroundColor: AppTheme.primaryBlue,
                )
              : null,
    );
  }

  Widget _buildEditPermissionBar() {
    if (_orderIsBilled) return const SizedBox.shrink();

    if (_canEditOrder) {
      final remaining =
          _allowOrderEditing ? _getInitialWindowRemaining() : null;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(
          color: AppTheme.success,
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.edit, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'You can edit this order',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  if (remaining != null)
                    Text(
                      'Time remaining: ${_formatDuration(remaining)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
            ),
            ElevatedButton.icon(
              onPressed: _isGeneratingPdf ? null : _editOrder,
              icon: const Icon(Icons.edit, size: 16),
              label: const Text('Edit'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppTheme.success,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _isGeneratingPdf ? null : _shareOrder,
              icon: _isGeneratingPdf
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.share, size: 16),
              label: const Text('Share'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildOrderInfoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _currentOrder.orderNumber,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: AppTheme.primaryBlue,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (_currentOrder.isSaleBilled)
                  _detailSaleChip('Billed', AppTheme.success)
                else if (_currentOrder.isPartiallyBilled)
                  _detailSaleChip('Partial — pending to sale', AppTheme.warning)
                else if (_isBilled)
                  _detailSaleChip('Billed', AppTheme.success),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Order Date',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.grey,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      DateFormat('MMM dd, yyyy - hh:mm a')
                          .format(_currentOrder.orderDate),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Status',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.grey,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _currentOrder.status == 'completed'
                            ? AppTheme.success.withOpacity(0.1)
                            : AppTheme.warning.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: _currentOrder.status == 'completed'
                              ? AppTheme.success
                              : AppTheme.warning,
                        ),
                      ),
                      child: Text(
                        _currentOrder.status.toUpperCase(),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _currentOrder.status == 'completed'
                              ? AppTheme.success
                              : AppTheme.warning,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (_currentOrder.orderLatitude != null && _currentOrder.orderLongitude != null) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Creation Location',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.grey,
                        ),
                  ),
                  const SizedBox(height: 6),
                  LocationAddressWidget(
                    latitude: _currentOrder.orderLatitude!,
                    longitude: _currentOrder.orderLongitude!,
                  ),
                ],
              ),
            ],
            if (_currentOrder.remarks != null && _currentOrder.remarks!.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Order Remarks / Notes',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.grey,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _currentOrder.remarks!,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _detailSaleChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  bool get _showSaleProgress {
    return _currentOrder.isPartiallyBilled ||
        _items.any((item) => item.billedQty > 0);
  }

  bool get _showingBilledQty =>
      _showSaleProgress && _items.any((item) => item.billedQty > 0);

  List<OrderItemModel> get _displayItems {
    if (!_showingBilledQty) return _items;
    return _items.where((item) => item.billedQty > 0).toList();
  }

  Widget _buildPendingToSaleBanner() {
    if (!_showSaleProgress) return const SizedBox.shrink();
    final pending = _items.where((item) => item.isLinePending).toList();
    if (pending.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        color: AppTheme.warning.withOpacity(0.08),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.pending_actions,
                      color: AppTheme.warning, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${pending.length} item(s) pending to sale',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppTheme.warning,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...pending.map(
                (item) => PendingOrderItemDetails(item: item),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCustomerInfoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Customer Information',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            _buildInfoRow('Name', _currentOrder.customerName ?? 'N/A'),
            if (_currentOrder.customerMobile != null)
              _buildInfoRow('Mobile', _currentOrder.customerMobile!),
            if (_currentOrder.customerGst != null)
              _buildInfoRow('GST Number', _currentOrder.customerGst!),
            if (_currentOrder.customerAddress != null)
              _buildInfoRow('Address', _currentOrder.customerAddress!),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.grey,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemCard(OrderItemModel item) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.ItemName,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      if (item.PartNumber != null)
                        Text(
                          'Code: ${item.PartNumber}',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppTheme.grey,
                                  ),
                        ),
                      if (item.note != null && item.note!.trim().isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.amber.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                                color: Colors.amber.shade300, width: 0.8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.notes,
                                  size: 13, color: Colors.amber.shade900),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  'Note: ${item.note!.trim()}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.amber.shade900,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Qty: ${OrderItemModel.formatQty(_showingBilledQty ? item.billedQty : item.ItemQuantity)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  '₹${item.ItemRate.toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'GST: ${item.GstRate}%',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.grey,
                      ),
                ),
                Text(
                  '₹${(_showingBilledQty ? item.billedLineAmount : item.totalAmount).toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryBlue,
                      ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard() {
    final rows = _displayItems;
    final useBilled = _showingBilledQty;
    final subtotal = rows.fold<double>(
      0,
      (sum, item) =>
          sum + (item.ItemRate * (useBilled ? item.billedQty : item.ItemQuantity)),
    );
    final gstTotal = rows.fold<double>(
      0,
      (sum, item) => sum + (useBilled ? item.billedGstAmount : item.gstAmount),
    );
    final total = rows.fold<double>(
      0,
      (sum, item) =>
          sum + (useBilled ? item.billedLineAmount : item.totalAmount),
    );

    return Card(
      color: AppTheme.primaryBlue.withOpacity(0.05),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              useBilled ? 'Billed Summary' : 'Order Summary',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            _buildSummaryRow('Subtotal', '₹${subtotal.toStringAsFixed(2)}'),
            _buildSummaryRow('GST', '₹${gstTotal.toStringAsFixed(2)}'),
            if (!useBilled && _currentOrder.orderDiscountAmount > 0)
              _buildSummaryRow(
                'Discount',
                '-₹${_currentOrder.orderDiscountAmount.toStringAsFixed(2)}',
                isDiscount: true,
              ),
            if (_currentOrder.isEdited &&
                _currentOrder.originalAmount != null &&
                (_currentOrder.originalAmount! - _currentOrder.netAmount).abs() > 0.01) ...[
              _buildSummaryRow(
                'Original Total (Before Edit)',
                '₹${_currentOrder.originalAmount!.toStringAsFixed(2)}',
              ),
            ],
            const Divider(height: 16),
            _buildSummaryRow(
              'Total',
              '₹${(useBilled ? total : _currentOrder.netAmount).toStringAsFixed(2)}',
              isBold: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value,
      {bool isBold = false, bool isDiscount = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                  color: isDiscount ? AppTheme.success : AppTheme.primaryBlue,
                ),
          ),
        ],
      ),
    );
  }
}
