import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:Orderx/core/theme/app_theme.dart';
import 'package:Orderx/models/order_model.dart';
import 'package:Orderx/providers/auth_provider.dart';
import 'package:Orderx/services/order_service.dart';
import 'package:Orderx/screens/salesman/edit_order_screen.dart';
import 'package:Orderx/widgets/error_state_widget.dart';
import 'package:Orderx/widgets/order_edit_history_widget.dart';

class DispatchDashboard extends StatefulWidget {
  const DispatchDashboard({super.key});

  @override
  State<DispatchDashboard> createState() => _DispatchDashboardState();
}

class _DispatchDashboardState extends State<DispatchDashboard> {
  final OrderService _orderService = OrderService();
  final ScrollController _scrollController = ScrollController();
  
  final List<OrderModel> _orders = [];
  bool _isLoading = false;
  String? _errorMessage;
  bool _hasMore = true;
  int _currentPage = 1;
  static const int _pageSize = 20;

  final TextEditingController _searchController = TextEditingController();
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadOrders(reset: true);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200 &&
        !_isLoading &&
        _hasMore) {
      _loadOrders();
    }
  }

  Future<void> _loadOrders({bool reset = false}) async {
    if (_isLoading) return;
    
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      if (reset) {
        _orders.clear();
        _currentPage = 1;
        _hasMore = true;
      }
    });

    try {
      final authProvider = context.read<AuthProvider>();
      final String? selectedCompanyId = authProvider.selectedCompanyId;
      final String? effectiveCompanyId = (selectedCompanyId == 'ALL') ? null : selectedCompanyId;

      final newOrders = await _orderService.getOrdersWithFilters(
        companyId: effectiveCompanyId,
        page: _currentPage,
        pageSize: _pageSize,
        searchQuery: _searchController.text.trim(),
        startDate: _startDate,
        endDate: _endDate,
      );

      if (mounted) {
        setState(() {
          if (newOrders.length < _pageSize) {
            _hasMore = false;
          }
          _orders.addAll(newOrders);
          _currentPage++;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString().replaceAll('Exception: ', '');
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_errorMessage!)),
        );
      }
    }
  }

  Future<void> _openOrderDetails(OrderModel order) async {
    // Show a loading indicator while fetching items
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final items = await _orderService.getOrderItems(order.id);
      
      if (!mounted) return;
      Navigator.pop(context); // Dismiss loading

      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => EditOrderScreen(
            order: order,
            items: items,
          ),
        ),
      );

      if (!mounted) return;

      // If the order was edited, refresh the list
      if (result == true) {
        _loadOrders(reset: true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Order updated successfully'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // Dismiss loading
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading order details: $e'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  void _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await context.read<AuthProvider>().logout();
    }
  }

  Future<void> _showFilterDialog() async {
    DateTime? tempStart = _startDate;
    DateTime? tempEnd = _endDate;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Filter Orders'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    title: const Text('Date Range'),
                    subtitle: Text(tempStart != null && tempEnd != null
                        ? '${DateFormat('MMM d, y').format(tempStart!)} - ${DateFormat('MMM d, y').format(tempEnd!)}'
                        : 'All time'),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () async {
                      final picked = await showDateRangePicker(
                        context: context,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                        initialDateRange: tempStart != null && tempEnd != null
                            ? DateTimeRange(start: tempStart!, end: tempEnd!)
                            : null,
                      );
                      if (picked != null) {
                        setStateDialog(() {
                          tempStart = picked.start;
                          tempEnd = picked.end;
                        });
                      }
                    },
                  ),
                  if (tempStart != null || tempEnd != null)
                    TextButton(
                      onPressed: () {
                        setStateDialog(() {
                          tempStart = null;
                          tempEnd = null;
                        });
                      },
                      child: const Text('Clear Dates'),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _startDate = tempStart;
                      _endDate = tempEnd;
                    });
                    Navigator.pop(context);
                    _loadOrders(reset: true);
                  },
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showEditDetailsModal(OrderModel order) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        contentPadding: const EdgeInsets.all(16),
        titlePadding: const EdgeInsets.fromLTRB(18, 16, 12, 0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Row(
                children: [
                  const Icon(Icons.history_toggle_off_rounded,
                      color: Color(0xFFB45309), size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Order #${order.orderNumber} - Edit Details',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: OrderEditHistoryWidget(
              order: order,
              initialExpanded: true,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMetaChip(IconData icon, String text, {FontWeight fontWeight = FontWeight.normal}) {
    return Text.rich(
      TextSpan(
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.only(right: 3),
              child: Icon(
                icon,
                size: 12,
                color: const Color(0xFF64748B),
              ),
            ),
          ),
          TextSpan(
            text: text,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: fontWeight,
              color: const Color(0xFF64748B),
            ),
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildStatusBadge(String label, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderCard(OrderModel order) {
    final bool hasOlderAmount = order.isEdited &&
        order.originalAmount != null &&
        (order.originalAmount! - order.netAmount).abs() > 0.01;

    final Color accentColor = order.isEdited
        ? const Color(0xFFF59E0B) // Amber for edited
        : order.isSaleBilled
            ? const Color(0xFF10B981) // Emerald for billed
            : AppTheme.primaryBlue;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: order.isEdited
              ? const Color(0xFFFDE68A)
              : const Color(0xFFE2E8F0),
          width: order.isEdited ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left status accent stripe
              Container(
                width: 4,
                color: accentColor,
              ),
              // Main card body
              Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _openOrderDetails(order),
                    splashColor: accentColor.withValues(alpha: 0.08),
                    highlightColor: accentColor.withValues(alpha: 0.04),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ─── Header: Order Number, Date, Badges ───────────
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Order number pill
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryBlue.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: AppTheme.primaryBlue.withValues(alpha: 0.2),
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.receipt_long_rounded,
                                      size: 13,
                                      color: AppTheme.primaryBlue,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      order.orderNumber,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 12,
                                        color: AppTheme.primaryBlue,
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Creation date & time
                              Expanded(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.access_time_rounded,
                                      size: 12,
                                      color: Colors.grey.shade500,
                                    ),
                                    const SizedBox(width: 3),
                                    Flexible(
                                      child: Text(
                                        DateFormat('MMM dd, yyyy • hh:mm a').format(order.createdAt.toLocal()),
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          color: Colors.grey.shade600,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              // Status & Edited badges
                              Wrap(
                                spacing: 4,
                                runSpacing: 3,
                                alignment: WrapAlignment.end,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  if (order.isEdited)
                                    Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: () => _showEditDetailsModal(order),
                                        borderRadius: BorderRadius.circular(5),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFEF3C7),
                                            borderRadius: BorderRadius.circular(5),
                                            border: Border.all(color: const Color(0xFFFCD34D)),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.edit_note_rounded,
                                                size: 13,
                                                color: Color(0xFFB45309),
                                              ),
                                              SizedBox(width: 2),
                                              Text(
                                                'EDITED',
                                                style: TextStyle(
                                                  fontSize: 9.5,
                                                  fontWeight: FontWeight.w800,
                                                  color: Color(0xFFB45309),
                                                  letterSpacing: 0.3,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  if (order.status.toLowerCase() != 'approved' &&
                                      order.status.toLowerCase() != 'pending' &&
                                      order.status.isNotEmpty)
                                    _buildStatusBadge(
                                      order.status.toUpperCase(),
                                      order.status.toLowerCase() == 'completed'
                                          ? const Color(0xFF059669)
                                          : const Color(0xFFD97706),
                                      order.status.toLowerCase() == 'completed'
                                          ? Icons.check_circle_rounded
                                          : Icons.schedule_rounded,
                                    ),
                                  if (order.isSaleBilled)
                                    _buildStatusBadge(
                                      'BILLED',
                                      AppTheme.success,
                                      Icons.receipt_rounded,
                                    )
                                  else if (order.isPartiallyBilled)
                                    _buildStatusBadge(
                                      'PARTIAL',
                                      AppTheme.warning,
                                      Icons.pending_actions_rounded,
                                    ),
                                ],
                              ),
                            ],
                          ),

                          const SizedBox(height: 6),

                          // ─── Customer & Metadata ─────────────────────────
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                ),
                                child: const Icon(
                                  Icons.storefront_rounded,
                                  size: 17,
                                  color: Color(0xFF475569),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      order.customerName ?? 'Walk-in Customer',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF0F172A),
                                        letterSpacing: -0.2,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Wrap(
                                      spacing: 10,
                                      runSpacing: 2,
                                      children: [
                                        if (order.companyName != null && order.companyName!.isNotEmpty)
                                          _buildMetaChip(
                                            Icons.apartment_rounded,
                                            order.companyName!,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        if (order.salesmanName != null && order.salesmanName!.isNotEmpty)
                                          _buildMetaChip(
                                            Icons.badge_outlined,
                                            'Salesman: ${order.salesmanName!}',
                                          ),
                                        if (order.destination != null && order.destination!.isNotEmpty)
                                          _buildMetaChip(
                                            Icons.local_shipping_outlined,
                                            order.destination!,
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),

                          // Subtle compact divider
                          Container(
                            margin: const EdgeInsets.only(top: 6, bottom: 5),
                            height: 1,
                            color: const Color(0xFFF1F5F9),
                          ),

                          // ─── Footer: Action Hint & Amounts ───────────────
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Action hint (Expanded with ellipsis to prevent narrow screen overflow)
                              Expanded(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: AppTheme.primaryBlue.withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(5),
                                      ),
                                      child: const Icon(
                                        Icons.edit_document,
                                        size: 11,
                                        color: AppTheme.primaryBlue,
                                      ),
                                    ),
                                    const SizedBox(width: 5),
                                    const Flexible(
                                      child: Text(
                                        'Tap to view / edit items',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                          color: AppTheme.primaryBlue,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 2),
                                    const Icon(
                                      Icons.chevron_right_rounded,
                                      size: 14,
                                      color: AppTheme.primaryBlue,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),

                              // Amounts: Older Amount before edit + New Amount
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  if (hasOlderAmount) ...[
                                    Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: () => _showEditDetailsModal(order),
                                        borderRadius: BorderRadius.circular(4),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFEF2F2),
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(color: const Color(0xFFFECACA)),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                'Before edit',
                                                style: TextStyle(
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.w700,
                                                  color: Color(0xFFDC2626),
                                                ),
                                              ),
                                              SizedBox(width: 2),
                                              Icon(Icons.info_outline, size: 9, color: Color(0xFFDC2626)),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '₹${order.originalAmount!.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF94A3B8),
                                        decoration: TextDecoration.lineThrough,
                                        decorationColor: Color(0xFFEF4444),
                                        decorationThickness: 1.5,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.baseline,
                                    textBaseline: TextBaseline.alphabetic,
                                    children: [
                                      if (hasOlderAmount)
                                        const Text(
                                          'Now: ',
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF059669),
                                          ),
                                        ),
                                      Text(
                                        '₹${order.netAmount.toStringAsFixed(2)}',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF0F172A),
                                          letterSpacing: -0.3,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Dispatch Dashboard - Orders'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadOrders(reset: true),
          ),
          IconButton(
            tooltip: 'Logout',
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            decoration: InputDecoration(
                              hintText: 'Search order #, customer name...',
                              prefixIcon: const Icon(Icons.search),
                              suffixIcon: IconButton(
                                icon: const Icon(Icons.arrow_forward),
                                onPressed: () => _loadOrders(reset: true),
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              filled: true,
                              fillColor: Colors.white,
                            ),
                            onSubmitted: (_) => _loadOrders(reset: true),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          decoration: BoxDecoration(
                            color: (_startDate != null || _endDate != null)
                                ? AppTheme.primaryBlue.withValues(alpha: 0.1)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: (_startDate != null || _endDate != null)
                                  ? AppTheme.primaryBlue
                                  : Colors.grey.shade400,
                            ),
                          ),
                          child: IconButton(
                            icon: Icon(
                              Icons.filter_list,
                              color: (_startDate != null || _endDate != null)
                                  ? AppTheme.primaryBlue
                                  : Colors.grey.shade700,
                            ),
                            onPressed: _showFilterDialog,
                            tooltip: 'Filter Orders',
                          ),
                        ),
                      ],
                    ),
                    if (_startDate != null && _endDate != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          children: [
                            const Icon(Icons.date_range, size: 14, color: Colors.grey),
                            const SizedBox(width: 4),
                            Text(
                              '${DateFormat('MMM d, y').format(_startDate!)} - ${DateFormat('MMM d, y').format(_endDate!)}',
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                            const Spacer(),
                            InkWell(
                              onTap: () {
                                setState(() {
                                  _startDate = null;
                                  _endDate = null;
                                });
                                _loadOrders(reset: true);
                              },
                              child: const Text('Clear', style: TextStyle(fontSize: 12, color: Colors.red)),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: _isLoading && _orders.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : _errorMessage != null && _orders.isEmpty
                        ? ErrorStateWidget(
                            message: _errorMessage!,
                            onRetry: () => _loadOrders(reset: true),
                          )
                        : _orders.isEmpty && !_isLoading
                            ? const Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.shopping_cart_outlined,
                                      size: 64,
                                      color: Colors.grey,
                                    ),
                                    SizedBox(height: 16),
                                    Text(
                                      'No orders found',
                                      style: TextStyle(
                                        color: Colors.grey,
                                        fontSize: 18,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                controller: _scrollController,
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                itemCount: _orders.length + (_hasMore ? 1 : 0),
                                itemBuilder: (context, index) {
                                  if (index == _orders.length) {
                                    return const Center(
                                      child: Padding(
                                        padding: EdgeInsets.all(16.0),
                                        child: CircularProgressIndicator(),
                                      ),
                                    );
                                  }

                                  final order = _orders[index];
                                  return _buildOrderCard(order);
                                },
                              ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

