import 'package:Orderx/core/theme/app_theme.dart';
import 'package:Orderx/models/order_model.dart';
import 'package:Orderx/providers/auth_provider.dart';
import 'package:Orderx/screens/salesman/product_details_screen.dart';
import 'package:Orderx/screens/salesman/product_selection_screen.dart';
import 'package:Orderx/services/order_service.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:Orderx/services/pdf_service.dart';
import 'package:Orderx/utils/rounding_utils.dart';
import 'package:Orderx/widgets/order_edit_history_widget.dart';

class EditOrderScreen extends StatefulWidget {
  final OrderModel order;
  final List<OrderItemModel> items;

  const EditOrderScreen({
    super.key,
    required this.order,
    required this.items,
  });

  @override
  State<EditOrderScreen> createState() => _EditOrderScreenState();
}

class _EditOrderScreenState extends State<EditOrderScreen> {
  final OrderService _orderService = OrderService();
  late List<OrderItemModel> _editableItems;
  late List<TextEditingController> _qtyControllers;
  late List<TextEditingController> _rateControllers;
  late List<TextEditingController> _discountControllers;
  late TextEditingController _notesController;
  late TextEditingController _shippingAddressController;
  bool _isUpdating = false;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _editableItems = widget.items
        .map((item) => OrderItemModel(
              id: item.id,
              orderId: item.orderId,
              productId: item.productId,
              ItemName: item.ItemName,
              PartNumber: item.PartNumber,
              hsn: item.hsn,
              ItemQuantity: item.ItemQuantity,
              ItemRate: item.ItemRate,
              GstRate: item.GstRate,
              gstAmount: item.gstAmount,
              totalAmount: item.totalAmount,
              discountPercentage: item.discountPercentage,
              discountAmount: item.discountAmount,
            ))
        .toList();
    _qtyControllers = _editableItems
        .map((item) =>
            TextEditingController(text: _formatQty(item.ItemQuantity)))
        .toList();
    _rateControllers = _editableItems
        .map((item) =>
            TextEditingController(text: item.ItemRate.toStringAsFixed(2)))
        .toList();
    _discountControllers = _editableItems
        .map((item) => TextEditingController(
            text: item.discountPercentage > 0
                ? item.discountPercentage.toStringAsFixed(2)
                : ''))
        .toList();
    _notesController = TextEditingController(
      text: (widget.order.remarks ?? '').trim().isNotEmpty
          ? widget.order.remarks!.trim()
          : (widget.order.notes ?? '').trim(),
    );
    _shippingAddressController =
        TextEditingController(text: widget.order.shippingAddress ?? '');
  }

  @override
  void dispose() {
    for (final c in _qtyControllers) {
      c.dispose();
    }
    for (final c in _rateControllers) {
      c.dispose();
    }
    for (final c in _discountControllers) {
      c.dispose();
    }
    _notesController.dispose();
    _shippingAddressController.dispose();
    super.dispose();
  }

  String _formatQty(double qty) =>
      qty == qty.truncateToDouble() ? qty.toInt().toString() : qty.toString();

  void _updateQuantity(int index, double newQuantity) {
    if (newQuantity < 0) return;

    setState(() {
      if (newQuantity == 0) {
        _editableItems.removeAt(index);
        _qtyControllers[index].dispose();
        _rateControllers[index].dispose();
        _discountControllers[index].dispose();
        _qtyControllers.removeAt(index);
        _rateControllers.removeAt(index);
        _discountControllers.removeAt(index);
      } else {
        _qtyControllers[index].text = _formatQty(newQuantity);
        _recalculateItem(index);
      }
      _hasChanges = true;
    });
  }

  void _updateRate(int index, double newRate) {
    if (newRate < 0) return;
    setState(() {
      _recalculateItem(index);
      _hasChanges = true;
    });
  }

  void _updateDiscount(int index, double newDiscount) {
    if (newDiscount < 0 || newDiscount > 100) return;
    setState(() {
      _recalculateItem(index);
      _hasChanges = true;
    });
  }

  void _recalculateItem(int index) {
    final item = _editableItems[index];
    final qtyText = _qtyControllers[index].text.trim();
    final rateText = _rateControllers[index].text.trim();
    final discText = _discountControllers[index].text.trim();

    final qty = qtyText.isEmpty ? 0.0 : (double.tryParse(qtyText) ?? item.ItemQuantity);
    final rate = rateText.isEmpty ? 0.0 : (double.tryParse(rateText) ?? item.ItemRate);
    final discountPercent = discText.isEmpty ? 0.0 : (double.tryParse(discText) ?? 0.0);
    final gstRate = item.GstRate;

    final subtotal = rate * qty;
    final discountAmount = (subtotal * discountPercent) / 100;
    final discountedSubtotal = subtotal - discountAmount;
    final gstAmount = (discountedSubtotal * gstRate) / 100;
    final total = discountedSubtotal + gstAmount;

    _editableItems[index] = OrderItemModel(
      id: item.id,
      orderId: item.orderId,
      productId: item.productId,
      ItemName: item.ItemName,
      PartNumber: item.PartNumber,
      hsn: item.hsn,
      ItemQuantity: qty,
      ItemRate: rate,
      GstRate: gstRate,
      gstAmount: gstAmount,
      totalAmount: total,
      discountPercentage: discountPercent,
      discountAmount: discountAmount,
    );
  }

  Future<void> _openProductCatalog() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProductSelectionScreen(
          isSelectionMode: true,
          onProductPicked: _addPickedProductToOrder,
        ),
      ),
    );
  }

  void _addPickedProductToOrder(PickedOrderProduct picked) {
    final product = picked.product;
    final qty = picked.quantity;
    final rate = picked.unitPrice;
    final discPct = picked.discountPercentage;
    final lineBase = rate * qty;
    final discAmt = picked.discountAmount > 0
        ? picked.discountAmount
        : lineBase * discPct / 100;
    final afterDisc = lineBase - discAmt;
    final gst = afterDisc * product.gstRate / 100;

    setState(() {
      _editableItems.add(
        OrderItemModel(
          id: '',
          orderId: widget.order.id,
          productId: product.id,
          ItemName: product.productName,
          PartNumber: product.productCode,
          hsn: product.hsn,
          ItemQuantity: qty,
          ItemRate: rate,
          GstRate: product.gstRate,
          gstAmount: gst,
          totalAmount: afterDisc + gst,
          discountPercentage: discPct,
          discountAmount: discAmt,
          mrp: product.mrp,
          note: picked.note,
        ),
      );
      _qtyControllers.add(TextEditingController(text: _formatQty(qty)));
      _rateControllers
          .add(TextEditingController(text: rate.toStringAsFixed(2)));
      _discountControllers.add(TextEditingController(
        text: discPct > 0 ? discPct.toStringAsFixed(2) : '',
      ));
      _hasChanges = true;
    });
  }

  double _calculateOrderTotal() {
    return _editableItems.fold<double>(
      0.0,
      (sum, item) => sum + item.totalAmount,
    );
  }

  double _calculateOrderGst() {
    return _editableItems.fold<double>(
      0.0,
      (sum, item) => sum + item.gstAmount,
    );
  }

  double _calculateOrderSubtotal() {
    return _editableItems.fold<double>(
      0.0,
      (sum, item) => sum + (item.totalAmount - item.gstAmount),
    );
  }

  double _calculateGrossTotal() {
    return _editableItems.fold<double>(
      0.0,
      (sum, item) => sum + (item.ItemQuantity * item.ItemRate),
    );
  }

  double _calculateTotalDiscount() {
    return _editableItems.fold<double>(
      0.0,
      (sum, item) => sum + item.discountAmount,
    );
  }

  Future<void> _saveChanges() async {
    if (widget.order.isSaleBilled || widget.order.isPartiallyBilled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This order has been billed and cannot be edited'),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    if (_editableItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Order must have at least one item'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Flush all typed values from text fields
    for (int i = 0; i < _editableItems.length; i++) {
      _recalculateItem(i);
    }

    setState(() => _isUpdating = true);

    try {
      final newSubtotal = _calculateOrderSubtotal();
      final newGst = _calculateOrderGst();
      final newNetAmount = _calculateOrderTotal();

      print('Saving order with:');
      print('Subtotal: $newSubtotal');
      print('GST: $newGst');
      print('Net Amount: $newNetAmount');
      print('Items: ${_editableItems.length}');

      final authProvider = context.read<AuthProvider>();
      final companyId = authProvider.selectedCompanyId;

      await _orderService.updateOrder(
        orderId: widget.order.id,
        items: _editableItems,
        totalAmount: newSubtotal,
        gstAmount: newGst,
        netAmount: newNetAmount,
        notes: _notesController.text.trim(),
        remarks: _notesController.text.trim(),
        shippingAddress: _shippingAddressController.text.trim(),
        companyId: companyId,
        editedBy: authProvider.currentUser?.name ?? 'Dispatch',
      );

      if (!mounted) return;
      _hasChanges = false;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      setState(() => _isUpdating = false);

      print('Error updating order: $e');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating order: ${e.toString()}'),
          backgroundColor: AppTheme.error,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Future<void> _showDeleteConfirmation(int index) async {
    final itemName = _editableItems[index].ItemName;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Item'),
        content: Text('Remove $itemName from order?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() {
        _qtyControllers[index].dispose();
        _rateControllers[index].dispose();
        _discountControllers[index].dispose();
        _qtyControllers.removeAt(index);
        _rateControllers.removeAt(index);
        _discountControllers.removeAt(index);
        _editableItems.removeAt(index);
        _hasChanges = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Order'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _isUpdating
              ? null
              : () {
                  if (_hasChanges) {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Discard Changes?'),
                        content: const Text(
                            'You have unsaved changes. Are you sure you want to discard them?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            onPressed: () {
                              Navigator.pop(context);
                              Navigator.pop(context);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.error,
                            ),
                            child: const Text('Discard'),
                          ),
                        ],
                      ),
                    );
                  } else {
                    Navigator.pop(context);
                  }
                },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: 'Share PDF',
            onPressed: _isUpdating
                ? null
                : () async {
                    try {
                      setState(() => _isUpdating = true);
                      final pdfService = PdfService();
                      final pdfBytes = await pdfService.generateOrderPdf(
                        widget.order,
                        _editableItems,
                      );
                      await pdfService.sharePdf(pdfBytes, widget.order.orderNumber);
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Error sharing PDF: $e'),
                            backgroundColor: AppTheme.error,
                          ),
                        );
                      }
                    } finally {
                      if (mounted) {
                        setState(() => _isUpdating = false);
                      }
                    }
                  },
          ),
        ],
      ),
      body: _isUpdating
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Updating order...'),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Order Info Card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  'Order #${widget.order.orderNumber}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(
                                        color: AppTheme.primaryBlue,
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                              ),
                              if (widget.order.isEdited)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                        color: Colors.orange.withValues(alpha: 0.4)),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.edit_note,
                                          size: 14, color: Colors.orange),
                                      SizedBox(width: 4),
                                      Text(
                                        'Edited',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.orange,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Customer: ${widget.order.customerName ?? 'Walk-in'}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Created: ${DateFormat('MMM dd, yyyy - hh:mm a').format(widget.order.createdAt)}',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: AppTheme.grey),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (widget.order.isEdited) ...[
                    const SizedBox(height: 16),
                    OrderEditHistoryWidget(order: widget.order),
                  ],
                  const SizedBox(height: 24),

                  // Items List
                  Text(
                    'Order Items (${_editableItems.length})',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  if (_editableItems.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          'No items in order',
                          style: TextStyle(color: AppTheme.grey),
                        ),
                      ),
                    )
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _editableItems.length,
                      itemBuilder: (context, index) {
                        final item = _editableItems[index];
                        return _buildEditableItemCard(context, item, index);
                      },
                    ),
                  const SizedBox(height: 12),
                  // Add Item Button
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _openProductCatalog,
                      icon: const Icon(Icons.add),
                      label: const Text('ADD ITEM'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primaryBlue,
                        side: const BorderSide(color: AppTheme.primaryBlue),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Shipping Address Section
                  Text(
                    'Shipping Address (Optional)',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _shippingAddressController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: 'Enter shipping address... ',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                    onChanged: (value) {
                      setState(() => _hasChanges = true);
                    },
                  ),
                  const SizedBox(height: 24),

                  // Remarks Section
                  Text(
                    'Remarks (Optional)',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _notesController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'Enter any additional instructions or remarks...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                    onChanged: (value) {
                      setState(() => _hasChanges = true);
                    },
                  ),
                  const SizedBox(height: 24),

                  // Summary Card
                  Card(
                    color: AppTheme.primaryBlue.withValues(alpha: 0.05),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _buildSummaryRow(
                            'Gross Amount',
                            '₹${_calculateGrossTotal().toStringAsFixed(2)}',
                          ),
                          const SizedBox(height: 8),
                          _buildSummaryRow(
                            'Total Discount',
                            '- ₹${_calculateTotalDiscount().toStringAsFixed(2)}',
                          ),
                          const SizedBox(height: 8),
                          _buildSummaryRow(
                            'Taxable Amount',
                            '₹${_calculateOrderSubtotal().toStringAsFixed(2)}',
                          ),
                          const SizedBox(height: 8),
                          _buildSummaryRow(
                            'Total GST',
                            '₹${_calculateOrderGst().toStringAsFixed(2)}',
                          ),
                          Builder(
                            builder: (context) {
                              final total = _calculateOrderTotal();
                              final roundOff = calculateRoundOff(total);
                              return Column(
                                children: [
                                  const SizedBox(height: 8),
                                  _buildSummaryRow(
                                    'Round Off',
                                    roundOff.formattedRoundOff,
                                  ),
                                  const Divider(height: 24),
                                  _buildSummaryRow(
                                    'Grand Total',
                                    '₹${roundOff.roundedTotal.toStringAsFixed(2)}',
                                    isBold: true,
                                    isLarge: true,
                                  ),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Save Button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _isUpdating ? null : _saveChanges,
                      icon: const Icon(Icons.save),
                      label: const Text('SAVE CHANGES'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.success,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
    );
  }

  Widget _buildEditableItemCard(
      BuildContext context, OrderItemModel item, int index) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.ItemName,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Code: ${item.PartNumber ?? "N/A"}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.grey,
                        ),
                      ),
                      if (item.note != null && item.note!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Note: ${item.note}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.amber.shade900,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  color: AppTheme.error,
                  onPressed: () => _showDeleteConfirmation(index),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),

            // Row 1: Rate and Discount
            Row(
              children: [
                // Rate
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Rate (₹)',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppTheme.grey, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          isDense: true,
                          prefixText: '₹ ',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                        ),
                        controller: _rateControllers[index],
                        onChanged: (value) {
                          setState(() {
                            _hasChanges = true;
                            _recalculateItem(index);
                          });
                        },
                        onSubmitted: (value) {
                          final rate = double.tryParse(value);
                          if (rate != null && rate >= 0) {
                            _updateRate(index, rate);
                          }
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Discount
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Disc %',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppTheme.grey, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          isDense: true,
                          suffixText: '%',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                        ),
                        controller: _discountControllers[index],
                        onChanged: (value) {
                          setState(() {
                            _hasChanges = true;
                            _recalculateItem(index);
                          });
                        },
                        onSubmitted: (value) {
                          final discount = double.tryParse(value);
                          if (discount != null && discount >= 0 && discount <= 100) {
                            _updateDiscount(index, discount);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Row 2: Quantity Stepper & Line Total
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Quantity Stepper
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Quantity',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppTheme.grey, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Material(
                          color: AppTheme.primaryBlue.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                          child: InkWell(
                            onTap: () {
                              final qty = double.tryParse(_qtyControllers[index].text) ?? item.ItemQuantity;
                              _updateQuantity(index, qty - 1);
                            },
                            borderRadius: BorderRadius.circular(6),
                            child: const Padding(
                              padding: EdgeInsets.all(7),
                              child: Icon(Icons.remove, size: 18, color: AppTheme.primaryBlue),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        SizedBox(
                          width: 56,
                          child: TextField(
                            textAlign: TextAlign.center,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                            decoration: InputDecoration(
                              isDense: true,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 8,
                              ),
                            ),
                            controller: _qtyControllers[index],
                            onChanged: (value) {
                              setState(() {
                                _hasChanges = true;
                                _recalculateItem(index);
                              });
                            },
                            onSubmitted: (value) {
                              final qty = double.tryParse(value);
                              if (qty != null && qty > 0) {
                                _updateQuantity(index, qty);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 6),
                        Material(
                          color: AppTheme.primaryBlue.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                          child: InkWell(
                            onTap: () {
                              final qty = double.tryParse(_qtyControllers[index].text) ?? item.ItemQuantity;
                              _updateQuantity(index, qty + 1);
                            },
                            borderRadius: BorderRadius.circular(6),
                            child: const Padding(
                              padding: EdgeInsets.all(7),
                              child: Icon(Icons.add, size: 18, color: AppTheme.primaryBlue),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                // Amount display
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '₹${(item.totalAmount - item.gstAmount).toStringAsFixed(2)} (excl. GST)',
                      style: const TextStyle(fontSize: 11, color: AppTheme.grey),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '₹${item.totalAmount.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: AppTheme.primaryBlue,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(
    String label,
    String value, {
    bool isBold = false,
    bool isLarge = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            fontSize: isLarge ? 16 : 14,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: isLarge ? 18 : 14,
            color: isBold ? AppTheme.primaryBlue : AppTheme.darkGrey,
          ),
        ),
      ],
    );
  }
}
