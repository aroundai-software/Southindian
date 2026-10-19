import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:Orderx/models/order_model.dart';

class OrderEditHistoryWidget extends StatefulWidget {
  final OrderModel order;
  final bool initialExpanded;

  const OrderEditHistoryWidget({
    super.key,
    required this.order,
    this.initialExpanded = true,
  });

  @override
  State<OrderEditHistoryWidget> createState() => _OrderEditHistoryWidgetState();
}

class _OrderEditHistoryWidgetState extends State<OrderEditHistoryWidget> {
  late bool _isExpanded;
  late Set<int> _expandedRevisions;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initialExpanded;
    _initExpandedRevisions();
  }

  void _initExpandedRevisions() {
    final editHistory = widget.order.editHistory;
    if (editHistory != null && editHistory.isNotEmpty) {
      // By default, expand the latest revision (last element in the list).
      // Older revisions start collapsed so the screen is clean, but user can tap to expand any of them.
      _expandedRevisions = {editHistory.length - 1};
    } else {
      _expandedRevisions = {};
    }
  }

  @override
  void didUpdateWidget(covariant OrderEditHistoryWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.order != widget.order) {
      final oldLen = oldWidget.order.editHistory?.length ?? 0;
      final newLen = widget.order.editHistory?.length ?? 0;
      if (newLen != oldLen && newLen > 0) {
        _expandedRevisions.add(newLen - 1);
      }
    }
  }

  void _toggleRevision(int index) {
    setState(() {
      if (_expandedRevisions.contains(index)) {
        _expandedRevisions.remove(index);
      } else {
        _expandedRevisions.add(index);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.order.isEdited) {
      return const SizedBox.shrink();
    }

    final editHistory = widget.order.editHistory;
    final hasHistoryRecords = editHistory != null && editHistory.isNotEmpty;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFCD34D), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── Header ────────────────────────────────────────────────────────
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7).withValues(alpha: 0.6),
                borderRadius: _isExpanded
                    ? const BorderRadius.vertical(top: Radius.circular(15))
                    : BorderRadius.circular(15),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.history_toggle_off_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            Text(
                              'Previous Edit Details',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF92400E),
                              ),
                            ),
                            _Badge(
                              label: 'EDITED',
                              bgColor: Color(0xFFFDE68A),
                              textColor: Color(0xFFB45309),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          hasHistoryRecords
                              ? '${editHistory.length} edit revision(s) recorded with item changes'
                              : (widget.order.originalAmount != null
                                  ? 'Older amount before edit: ₹${widget.order.originalAmount!.toStringAsFixed(2)}'
                                  : 'Order has been modified'),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFFB45309),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _isExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: const Color(0xFF92400E),
                  ),
                ],
              ),
            ),
          ),

          // ─── Body (Expanded) ───────────────────────────────────────────────
          if (_isExpanded)
            Padding(
              padding: const EdgeInsets.all(16),
              child: hasHistoryRecords
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (editHistory.length > 1) ...[
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '${editHistory.length} Revisions recorded',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF92400E),
                                  ),
                                ),
                                Row(
                                  children: [
                                    InkWell(
                                      onTap: () {
                                        setState(() {
                                          _expandedRevisions = Set.from(
                                            List.generate(
                                                editHistory.length, (i) => i),
                                          );
                                        });
                                      },
                                      borderRadius: BorderRadius.circular(4),
                                      child: const Padding(
                                        padding: EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        child: Text(
                                          'Expand All',
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFFB45309),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const Text('•',
                                        style: TextStyle(
                                            color: Color(0xFFCBD5E1))),
                                    InkWell(
                                      onTap: () {
                                        setState(() {
                                          _expandedRevisions.clear();
                                        });
                                      },
                                      borderRadius: BorderRadius.circular(4),
                                      child: const Padding(
                                        padding: EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        child: Text(
                                          'Collapse All',
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF64748B),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                        for (int i = editHistory.length - 1; i >= 0; i--)
                          _buildEditRecordCard(
                            editHistory[i],
                            revisionNumber: i + 1,
                            isLatest: i == editHistory.length - 1,
                            revisionIndex: i,
                          ),
                      ],
                    )
                  : _buildLegacyEditInfo(),
            ),
        ],
      ),
    );
  }

  // ─── Legacy / Fallback Card (When edit_history wasn't logged yet) ──────────
  Widget _buildLegacyEditInfo() {
    final original = widget.order.originalAmount;
    final current = widget.order.netAmount;
    final diff = original != null ? current - original : null;
    final pct = (original != null && original > 0 && diff != null)
        ? (diff / original * 100).abs()
        : null;

    final isIncreased = diff != null && diff > 0.01;
    final isDecreased = diff != null && diff < -0.01;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline_rounded,
                  size: 20, color: Color(0xFFB45309)),
              const SizedBox(width: 8),
              Text(
                'Prior Edit Information',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Colors.amber.shade900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (original != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      const Text(
                        'Amount Before Edit: ',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF475569)),
                      ),
                      Text(
                        '₹${original.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade700,
                          decoration: TextDecoration.lineThrough,
                          decorationThickness: 2,
                        ),
                      ),
                      const Icon(Icons.arrow_forward_rounded,
                          size: 14, color: Color(0xFF64748B)),
                      Text(
                        'Current Amount: ₹${current.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                  if (diff != null && (isIncreased || isDecreased)) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isIncreased
                            ? const Color(0xFFECFDF5)
                            : const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isIncreased
                              ? const Color(0xFFA7F3D0)
                              : const Color(0xFFFECACA),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isIncreased
                                ? Icons.arrow_upward_rounded
                                : Icons.arrow_downward_rounded,
                            size: 14,
                            color: isIncreased
                                ? const Color(0xFF059669)
                                : const Color(0xFFDC2626),
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              isIncreased
                                  ? 'Overall Order Amount was INCREASED by ₹${diff.toStringAsFixed(2)}${pct != null ? " (+${pct.toStringAsFixed(1)}%)" : ""}'
                                  : 'Overall Order Amount was DECREASED by ₹${diff.abs().toStringAsFixed(2)}${pct != null ? " (-${pct.toStringAsFixed(1)}%)" : ""}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: isIncreased
                                    ? const Color(0xFF065F46)
                                    : const Color(0xFF991B1B),
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
            const SizedBox(height: 12),
          ],

          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF9C3).withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFDE047)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.auto_awesome_rounded,
                        size: 16, color: Color(0xFFB45309)),
                    SizedBox(width: 6),
                    Text(
                      'Item-Level Rate & Quantity Tracking',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF92400E),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'This previous edit was saved before Migration 020 was applied. For all edits saved from now on, the system records:',
                  style: TextStyle(fontSize: 12, color: Color(0xFF78350F), height: 1.4),
                ),
                const SizedBox(height: 4),
                _buildBulletPoint('Which specific items were edited, added, or removed'),
                _buildBulletPoint('Whether item rate was increased or decreased (with exact ₹ difference)'),
                _buildBulletPoint('Whether quantity was increased or decreased (with exact quantity difference)'),
                _buildBulletPoint('Any discount percentage or product note changes'),
                const SizedBox(height: 8),
                const Text(
                  '👉 Tip: Make sure migration 020_add_edit_history_to_sales_orders.sql is executed in your Supabase SQL editor. Any edit saved now will show the full item-by-item breakdown here.',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFB45309),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBulletPoint(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFB45309))),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 11.5, color: Color(0xFF78350F)),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Single Revision Record Card ──────────────────────────────────────────
  Widget _buildEditRecordCard(
    OrderEditRecord record, {
    required int revisionNumber,
    required bool isLatest,
    required int revisionIndex,
  }) {
    final isCardExpanded = _expandedRevisions.contains(revisionIndex);
    final prevNet = record.previousNetAmount;
    final newNet = record.newNetAmount;
    final netDiff = (prevNet != null && newNet != null) ? (newNet - prevNet) : null;
    final netPct = (prevNet != null && prevNet > 0 && netDiff != null)
        ? (netDiff / prevNet * 100).abs()
        : null;
    final isNetIncreased = netDiff != null && netDiff > 0.01;
    final isNetDecreased = netDiff != null && netDiff < -0.01;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isLatest ? const Color(0xFFFCD34D) : const Color(0xFFCBD5E1),
          width: isLatest ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Revision Header (with individual Dropdown Toggle Arrow)
          InkWell(
            onTap: () => _toggleRevision(revisionIndex),
            borderRadius: isCardExpanded
                ? const BorderRadius.vertical(top: Radius.circular(13))
                : (prevNet != null && newNet != null
                    ? const BorderRadius.vertical(top: Radius.circular(13))
                    : BorderRadius.circular(13)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isLatest ? const Color(0xFFFEF3C7) : const Color(0xFFF1F5F9),
                borderRadius: isCardExpanded
                    ? const BorderRadius.vertical(top: Radius.circular(13))
                    : (prevNet != null && newNet != null
                        ? const BorderRadius.vertical(top: Radius.circular(13))
                        : BorderRadius.circular(13)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2.5),
                          decoration: BoxDecoration(
                            color: isLatest
                                ? const Color(0xFFF59E0B)
                                : const Color(0xFF64748B),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            'Rev #$revisionNumber${isLatest ? " (Latest)" : ""}',
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        Text(
                          DateFormat('MMM dd, yyyy • hh:mm a')
                              .format(record.editedAt),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isLatest
                                ? const Color(0xFF92400E)
                                : const Color(0xFF334155),
                          ),
                        ),
                        if (record.editedBy != null && record.editedBy!.isNotEmpty)
                          Text(
                            'by ${record.editedBy}',
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontStyle: FontStyle.italic,
                              color: Color(0xFF64748B),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Dropdown Toggle Arrow
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: isLatest
                          ? const Color(0xFFFDE68A).withValues(alpha: 0.7)
                          : const Color(0xFFE2E8F0),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isCardExpanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: isLatest
                          ? const Color(0xFF92400E)
                          : const Color(0xFF475569),
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Collapsed preview bar (shows quick difference when revision is collapsed)
          if (!isCardExpanded && (prevNet != null && newNet != null))
            InkWell(
              onTap: () => _toggleRevision(revisionIndex),
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(13)),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      BorderRadius.vertical(bottom: Radius.circular(13)),
                ),
                child: Row(
                  children: [
                    Icon(
                      isNetIncreased
                          ? Icons.trending_up_rounded
                          : (isNetDecreased
                              ? Icons.trending_down_rounded
                              : Icons.compare_arrows_rounded),
                      size: 16,
                      color: isNetIncreased
                          ? const Color(0xFF059669)
                          : (isNetDecreased
                              ? const Color(0xFFDC2626)
                              : const Color(0xFF64748B)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '₹${prevNet.toStringAsFixed(2)} → ₹${newNet.toStringAsFixed(2)}${record.itemChanges.isNotEmpty ? " • ${record.itemChanges.length} item(s) modified" : ""}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF334155),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'View details',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isLatest
                                ? const Color(0xFFB45309)
                                : const Color(0xFF2563EB),
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 14,
                          color: isLatest
                              ? const Color(0xFFB45309)
                              : const Color(0xFF2563EB),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

          // Expanded full breakdown
          if (isCardExpanded)
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                // Total Net Amount Diff Banner
                if (prevNet != null && newNet != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.currency_rupee_rounded,
                                    size: 16, color: Color(0xFF64748B)),
                                SizedBox(width: 4),
                                Text(
                                  'Order Total: ',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF475569),
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              '₹${prevNet.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey.shade600,
                                decoration: TextDecoration.lineThrough,
                                decorationThickness: 2,
                              ),
                            ),
                            const Icon(Icons.arrow_forward_rounded,
                                size: 14, color: Color(0xFF94A3B8)),
                            Text(
                              '₹${newNet.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                          ],
                        ),
                        if (netDiff != null && (isNetIncreased || isNetDecreased)) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(
                                isNetIncreased
                                    ? Icons.arrow_upward_rounded
                                    : Icons.arrow_downward_rounded,
                                size: 14,
                                color: isNetIncreased
                                    ? const Color(0xFF059669)
                                    : const Color(0xFFDC2626),
                              ),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  isNetIncreased
                                      ? 'Order total INCREASED by ₹${netDiff.toStringAsFixed(2)}${netPct != null ? " (+${netPct.toStringAsFixed(1)}%)" : ""}'
                                      : 'Order total DECREASED by ₹${netDiff.abs().toStringAsFixed(2)}${netPct != null ? " (-${netPct.toStringAsFixed(1)}%)" : ""}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: isNetIncreased
                                        ? const Color(0xFF065F46)
                                        : const Color(0xFF991B1B),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // ─── Executive Summary: What Changed In This Edit ─────────────
                if (record.itemChanges.isNotEmpty) ...[
                  _buildRevisionSummaryBox(record.itemChanges),
                  const SizedBox(height: 14),
                ],

                // ─── Item-by-Item Detailed Change Cards ──────────────────────
                if (record.itemChanges.isNotEmpty) ...[
                  Row(
                    children: [
                      const Icon(Icons.inventory_2_outlined,
                          size: 15, color: Color(0xFF475569)),
                      const SizedBox(width: 6),
                      Text(
                        'Item Details (${record.itemChanges.length} modified)',
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  for (final item in record.itemChanges)
                    _buildItemChangeCard(item),
                ] else ...[
                  const Text(
                    'No item rates, discounts, or quantities were modified in this revision.',
                    style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
                        fontStyle: FontStyle.italic),
                  ),
                ],

                // Remarks Change
                if (record.previousRemarks != record.newRemarks &&
                    (record.previousRemarks != null ||
                        record.newRemarks != null)) ...[
                  const SizedBox(height: 10),
                  _buildFieldDiffRow(
                    'Remarks',
                    record.previousRemarks ?? '(none)',
                    record.newRemarks ?? '(none)',
                  ),
                ],

                // Shipping Address Change
                if (record.previousShippingAddress !=
                        record.newShippingAddress &&
                    (record.previousShippingAddress != null ||
                        record.newShippingAddress != null)) ...[
                  const SizedBox(height: 8),
                  _buildFieldDiffRow(
                    'Shipping Address',
                    record.previousShippingAddress ?? '(none)',
                    record.newShippingAddress ?? '(none)',
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Executive Summary Box: Quick-Glance What Changed ──────────────────────
  Widget _buildRevisionSummaryBox(List<OrderItemChange> items) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.checklist_rounded, size: 16, color: Color(0xFF16A34A)),
              SizedBox(width: 6),
              Text(
                'Change Summary (What was modified):',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF15803D),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final item in items) _buildSummaryLine(item),
        ],
      ),
    );
  }

  Widget _buildSummaryLine(OrderItemChange item) {
    final List<String> changeDescriptions = [];

    if (item.changeType == 'added') {
      changeDescriptions.add(
        'Added to order (Qty: ${_formatQty(item.newQuantity ?? 0)}, Rate: ₹${(item.newRate ?? 0).toStringAsFixed(2)})',
      );
    } else if (item.changeType == 'removed') {
      changeDescriptions.add(
        'Removed from order (Previous Qty: ${_formatQty(item.oldQuantity ?? 0)}, Rate: ₹${(item.oldRate ?? 0).toStringAsFixed(2)})',
      );
    } else {
      // Modified
      if (item.hasRateChanged) {
        if (item.isRateIncreased) {
          changeDescriptions.add(
            'Rate INCREASED by ₹${item.rateDiff.toStringAsFixed(2)} (₹${item.oldRate!.toStringAsFixed(2)} → ₹${item.newRate!.toStringAsFixed(2)})',
          );
        } else {
          changeDescriptions.add(
            'Rate DECREASED by ₹${item.rateDiff.abs().toStringAsFixed(2)} (₹${item.oldRate!.toStringAsFixed(2)} → ₹${item.newRate!.toStringAsFixed(2)})',
          );
        }
      }

      if (item.hasQuantityChanged) {
        if (item.isQuantityIncreased) {
          changeDescriptions.add(
            'Quantity INCREASED by ${_formatQty(item.quantityDiff)} (${_formatQty(item.oldQuantity!)} → ${_formatQty(item.newQuantity!)})',
          );
        } else {
          changeDescriptions.add(
            'Quantity DECREASED by ${_formatQty(item.quantityDiff.abs())} (${_formatQty(item.oldQuantity!)} → ${_formatQty(item.newQuantity!)})',
          );
        }
      }

      if (item.hasDiscountChanged) {
        if (item.isDiscountIncreased) {
          changeDescriptions.add(
            'Discount increased by ${item.discountDiff.toStringAsFixed(1)}% (${item.oldDiscountPercentage!.toStringAsFixed(1)}% → ${item.newDiscountPercentage!.toStringAsFixed(1)}%)',
          );
        } else {
          changeDescriptions.add(
            'Discount decreased by ${item.discountDiff.abs().toStringAsFixed(1)}% (${item.oldDiscountPercentage!.toStringAsFixed(1)}% → ${item.newDiscountPercentage!.toStringAsFixed(1)}%)',
          );
        }
      }

      if (item.hasNoteChanged) {
        changeDescriptions.add('Note modified');
      }
    }

    if (changeDescriptions.isEmpty) {
      changeDescriptions.add('Details updated');
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF16A34A))),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(fontSize: 12, color: Color(0xFF1E293B)),
                children: [
                  TextSpan(
                    text: '${item.productName}: ',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(
                    text: changeDescriptions.join(' • '),
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Item Change Card ─────────────────────────────────────────────────────
  Widget _buildItemChangeCard(OrderItemChange item) {
    Color badgeBg;
    Color badgeText;
    String badgeLabel;

    switch (item.changeType) {
      case 'added':
        badgeBg = const Color(0xFFECFDF5);
        badgeText = const Color(0xFF059669);
        badgeLabel = '+ ADDED';
        break;
      case 'removed':
        badgeBg = const Color(0xFFFEF2F2);
        badgeText = const Color(0xFFDC2626);
        badgeLabel = '- REMOVED';
        break;
      default:
        badgeBg = const Color(0xFFEFF6FF);
        badgeText = const Color(0xFF2563EB);
        badgeLabel = 'MODIFIED';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Item Name & Status Badges
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.productName,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    if (item.productCode != null &&
                        item.productCode!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Code: ${item.productCode}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _Badge(
                label: badgeLabel,
                bgColor: badgeBg,
                textColor: badgeText,
              ),
            ],
          ),

          // Modification Pills (Rate Increased/Decreased, Qty Increased/Decreased)
          if (item.changeType == 'modified') ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (item.hasRateChanged)
                  _buildChangePill(
                    label: item.isRateIncreased
                        ? '▲ Rate Increased (+₹${item.rateDiff.toStringAsFixed(2)})'
                        : '▼ Rate Decreased (-₹${item.rateDiff.abs().toStringAsFixed(2)})',
                    color: item.isRateIncreased
                        ? const Color(0xFF059669)
                        : const Color(0xFFDC2626),
                    bgColor: item.isRateIncreased
                        ? const Color(0xFFECFDF5)
                        : const Color(0xFFFEF2F2),
                    borderColor: item.isRateIncreased
                        ? const Color(0xFFA7F3D0)
                        : const Color(0xFFFECACA),
                    icon: item.isRateIncreased
                        ? Icons.trending_up_rounded
                        : Icons.trending_down_rounded,
                  ),
                if (item.hasQuantityChanged)
                  _buildChangePill(
                    label: item.isQuantityIncreased
                        ? '▲ Qty Increased (+${_formatQty(item.quantityDiff)})'
                        : '▼ Qty Decreased (-${_formatQty(item.quantityDiff.abs())})',
                    color: item.isQuantityIncreased
                        ? const Color(0xFF2563EB)
                        : const Color(0xFFD97706),
                    bgColor: item.isQuantityIncreased
                        ? const Color(0xFFEFF6FF)
                        : const Color(0xFFFFFBEB),
                    borderColor: item.isQuantityIncreased
                        ? const Color(0xFFBFDBFE)
                        : const Color(0xFFFDE68A),
                    icon: item.isQuantityIncreased
                        ? Icons.add_circle_outline_rounded
                        : Icons.remove_circle_outline_rounded,
                  ),
                if (item.hasDiscountChanged)
                  _buildChangePill(
                    label: item.isDiscountIncreased
                        ? '▲ Discount (+${item.discountDiff.toStringAsFixed(1)}%)'
                        : '▼ Discount (-${item.discountDiff.abs().toStringAsFixed(1)}%)',
                    color: const Color(0xFF7C3AED),
                    bgColor: const Color(0xFFF5F3FF),
                    borderColor: const Color(0xFFDDD6FE),
                    icon: Icons.percent_rounded,
                  ),
                if (item.hasNoteChanged)
                  _buildChangePill(
                    label: 'Note Updated',
                    color: const Color(0xFFB45309),
                    bgColor: const Color(0xFFFEF3C7),
                    borderColor: const Color(0xFFFDE68A),
                    icon: Icons.edit_note_rounded,
                  ),
              ],
            ),
          ],

          const SizedBox(height: 8),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 8),

          // ─── Property Diff Blocks ──────────────────────────────────────────
          if (item.changeType == 'modified') ...[
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                // Quantity Diff
                if (item.oldQuantity != null &&
                    item.newQuantity != null &&
                    (item.oldQuantity! - item.newQuantity!).abs() > 0.001)
                  _buildStructuredDiffTile(
                    title: 'Quantity',
                    oldVal: _formatQty(item.oldQuantity!),
                    newVal: _formatQty(item.newQuantity!),
                    isIncreased: item.isQuantityIncreased,
                    diffText: item.isQuantityIncreased
                        ? '▲ Increased by ${_formatQty(item.quantityDiff)}'
                        : '▼ Decreased by ${_formatQty(item.quantityDiff.abs())}',
                    accentColor: item.isQuantityIncreased
                        ? const Color(0xFF2563EB)
                        : const Color(0xFFD97706),
                  ),

                // Rate Diff
                if (item.oldRate != null &&
                    item.newRate != null &&
                    (item.oldRate! - item.newRate!).abs() > 0.009)
                  _buildStructuredDiffTile(
                    title: 'Unit Rate',
                    oldVal: '₹${item.oldRate!.toStringAsFixed(2)}',
                    newVal: '₹${item.newRate!.toStringAsFixed(2)}',
                    isIncreased: item.isRateIncreased,
                    diffText: item.isRateIncreased
                        ? '▲ Rate Increased by ₹${item.rateDiff.toStringAsFixed(2)}'
                        : '▼ Rate Decreased by ₹${item.rateDiff.abs().toStringAsFixed(2)}',
                    accentColor: item.isRateIncreased
                        ? const Color(0xFF059669)
                        : const Color(0xFFDC2626),
                  ),

                // Discount Diff
                if (item.oldDiscountPercentage != null &&
                    item.newDiscountPercentage != null &&
                    (item.oldDiscountPercentage! -
                                item.newDiscountPercentage!)
                            .abs() >
                        0.01)
                  _buildStructuredDiffTile(
                    title: 'Discount',
                    oldVal:
                        '${item.oldDiscountPercentage!.toStringAsFixed(1)}%',
                    newVal:
                        '${item.newDiscountPercentage!.toStringAsFixed(1)}%',
                    isIncreased: item.isDiscountIncreased,
                    diffText: item.isDiscountIncreased
                        ? '▲ +${item.discountDiff.toStringAsFixed(1)}%'
                        : '▼ -${item.discountDiff.abs().toStringAsFixed(1)}%',
                    accentColor: const Color(0xFF7C3AED),
                  ),

                // Item Total Diff
                if (item.oldTotal != null &&
                    item.newTotal != null &&
                    (item.oldTotal! - item.newTotal!).abs() > 0.01)
                  _buildStructuredDiffTile(
                    title: 'Item Total',
                    oldVal: '₹${item.oldTotal!.toStringAsFixed(2)}',
                    newVal: '₹${item.newTotal!.toStringAsFixed(2)}',
                    isIncreased: item.isTotalIncreased,
                    diffText: item.isTotalIncreased
                        ? '▲ Line Total Increased by ₹${item.totalDiff.toStringAsFixed(2)}'
                        : '▼ Line Total Decreased by ₹${item.totalDiff.abs().toStringAsFixed(2)}',
                    accentColor: item.isTotalIncreased
                        ? const Color(0xFF059669)
                        : const Color(0xFFDC2626),
                  ),
              ],
            ),
            if (item.oldNote != item.newNote) ...[
              const SizedBox(height: 8),
              _buildFieldDiffRow(
                'Product Note',
                item.oldNote ?? '(none)',
                item.newNote ?? '(none)',
              ),
            ],
          ] else if (item.changeType == 'added') ...[
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                if (item.newQuantity != null)
                  _buildValueLabel('Qty', _formatQty(item.newQuantity!)),
                if (item.newRate != null)
                  _buildValueLabel('Rate', '₹${item.newRate!.toStringAsFixed(2)}'),
                if (item.newDiscountPercentage != null &&
                    item.newDiscountPercentage! > 0)
                  _buildValueLabel('Discount',
                      '${item.newDiscountPercentage!.toStringAsFixed(1)}%'),
                if (item.newTotal != null)
                  _buildValueLabel(
                      'Total', '₹${item.newTotal!.toStringAsFixed(2)}'),
              ],
            ),
            if (item.newNote != null && item.newNote!.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Note: ${item.newNote!.trim()}',
                style: const TextStyle(
                  fontSize: 11.5,
                  color: Color(0xFF64748B),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ] else if (item.changeType == 'removed') ...[
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                if (item.oldQuantity != null)
                  _buildValueLabel(
                      'Previous Qty', _formatQty(item.oldQuantity!)),
                if (item.oldRate != null)
                  _buildValueLabel(
                      'Previous Rate', '₹${item.oldRate!.toStringAsFixed(2)}'),
                if (item.oldTotal != null)
                  _buildValueLabel(
                      'Previous Total', '₹${item.oldTotal!.toStringAsFixed(2)}'),
              ],
            ),
            if (item.oldNote != null && item.oldNote!.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Previous Note: ${item.oldNote!.trim()}',
                style: const TextStyle(
                  fontSize: 11.5,
                  color: Color(0xFF94A3B8),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  // ─── Small Change Tag / Pill ──────────────────────────────────────────────
  Widget _buildChangePill({
    required String label,
    required Color color,
    required Color bgColor,
    required Color borderColor,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Structured Diff Tile (Old → New with Delta Banner) ───────────────────
  Widget _buildStructuredDiffTile({
    required String title,
    required String oldVal,
    required String newVal,
    required bool isIncreased,
    required String diffText,
    required Color accentColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF64748B),
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                oldVal,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade600,
                  decoration: TextDecoration.lineThrough,
                  decorationThickness: 1.5,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Icons.arrow_forward_rounded,
                    size: 11, color: Color(0xFF94A3B8)),
              ),
              Text(
                newVal,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            diffText,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: accentColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildValueLabel(String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
            color: Color(0xFF64748B),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0F172A),
          ),
        ),
      ],
    );
  }

  Widget _buildFieldDiffRow(String fieldName, String oldVal, String newVal) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Text(
            '$fieldName: ',
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF64748B),
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    oldVal,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.grey.shade600,
                      decoration: TextDecoration.lineThrough,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.arrow_forward_rounded,
                    size: 11, color: Color(0xFF94A3B8)),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    newVal,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0F172A),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatQty(double qty) {
    if (qty == qty.truncateToDouble()) return qty.toInt().toString();
    return qty.toStringAsFixed(2);
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color bgColor;
  final Color textColor;

  const _Badge({
    required this.label,
    required this.bgColor,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: textColor,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
