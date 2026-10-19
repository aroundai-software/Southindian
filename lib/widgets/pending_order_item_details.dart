import 'package:flutter/material.dart';
import 'package:Orderx/core/theme/app_theme.dart';
import 'package:Orderx/models/order_model.dart';

class PendingOrderItemDetails extends StatelessWidget {
  final OrderItemModel item;
  final bool compact;

  const PendingOrderItemDetails({
    super.key,
    required this.item,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(top: compact ? 8 : 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.ItemName,
            style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          if (item.PartNumber != null && item.PartNumber!.isNotEmpty)
            Text(
              'Code: ${item.PartNumber}',
              style: textTheme.bodySmall?.copyWith(color: AppTheme.grey),
            ),
          if (item.note != null && item.note!.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.12),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.amber.shade300, width: 0.8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.notes, size: 12, color: Colors.amber.shade900),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      'Note: ${item.note!.trim()}',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.amber.shade900,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              _detail('Qty', OrderItemModel.formatQty(item.pendingQty)),
              _detail('Rate', '₹${item.ItemRate.toStringAsFixed(2)}'),
              _detail(
                'GST',
                '${item.GstRate.toStringAsFixed(item.GstRate.truncateToDouble() == item.GstRate ? 0 : 2)}%  ₹${item.pendingGstAmount.toStringAsFixed(2)}',
              ),
              if (item.hasDiscount)
                _detail(
                  'Disc',
                  [
                    if (item.discountPercentage > 0.001)
                      '${item.discountPercentage.toStringAsFixed(1)}%',
                    if (item.pendingDiscountAmount > 0.001)
                      '₹${item.pendingDiscountAmount.toStringAsFixed(2)}',
                  ].join('  '),
                ),
              _detail(
                'Amount',
                '₹${item.pendingLineAmount.toStringAsFixed(2)}',
                emphasize: true,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _detail(String label, String value, {bool emphasize = false}) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 88),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: AppTheme.grey, fontSize: 11),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: emphasize ? FontWeight.bold : FontWeight.w600,
              color: emphasize ? AppTheme.primaryBlue : null,
            ),
          ),
        ],
      ),
    );
  }
}
