import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:Orderx/core/theme/app_theme.dart';
import 'package:Orderx/models/activity_log_model.dart';
import 'package:Orderx/providers/auth_provider.dart';
import 'package:Orderx/screens/admin/order_details_admin_screen.dart';
import 'package:Orderx/screens/salesman/collection_details_screen.dart';
import 'package:Orderx/services/activity_log_service.dart';
import 'package:Orderx/services/collection_service.dart';
import 'package:Orderx/services/order_service.dart';
import 'package:Orderx/services/pdf_service.dart';
import 'package:Orderx/utils/error_handler.dart';
import 'package:Orderx/widgets/visit_day_timeline.dart';

enum _VisitDateFilter { inherited, date, range, all }

class SalesmanVisitDetailsScreen extends StatefulWidget {
  final String salesmanId;
  final String salesmanName;
  final String? mobile;
  final List<ActivityLog> initialLogs;
  final String initialPeriodLabel;

  SalesmanVisitDetailsScreen({
    super.key,
    required this.salesmanId,
    required this.salesmanName,
    this.mobile,
    required this.initialLogs,
    required this.initialPeriodLabel,
  });

  @override
  State<SalesmanVisitDetailsScreen> createState() =>
      _SalesmanVisitDetailsScreenState();
}

class _SalesmanVisitDetailsScreenState
    extends State<SalesmanVisitDetailsScreen> {
  final ActivityLogService _activityService = ActivityLogService();
  final PdfService _pdfService = PdfService();

  late List<ActivityLog> _logs;
  late SalesmanActivityReport _report;
  _VisitDateFilter _filter = _VisitDateFilter.inherited;
  DateTime _selectedDate = DateTime.now();
  DateTime _rangeStart = DateTime.now();
  DateTime _rangeEnd = DateTime.now();
  bool _isLoading = false;
  bool _isSharing = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _logs = List<ActivityLog>.from(widget.initialLogs);
    _report = _reportFrom(_logs);
  }

  String? get _companyId {
    final companyId = context.read<AuthProvider>().selectedCompanyId;
    return (companyId == 'ALL') ? null : companyId;
  }

  SalesmanActivityReport _reportFrom(List<ActivityLog> logs) {
    final reports = groupActivityLogs(logs);
    if (reports.isNotEmpty) return reports.first;
    return SalesmanActivityReport(
      salesmanId: widget.salesmanId,
      salesmanName: widget.salesmanName,
      mobile: widget.mobile,
      days: const [],
    );
  }

  String get _periodLabel {
    switch (_filter) {
      case _VisitDateFilter.inherited:
        return widget.initialPeriodLabel;
      case _VisitDateFilter.date:
        return DateFormat('dd MMM yyyy').format(_selectedDate);
      case _VisitDateFilter.range:
        return '${DateFormat('dd MMM yyyy').format(_rangeStart)} – ${DateFormat('dd MMM yyyy').format(_rangeEnd)}';
      case _VisitDateFilter.all:
        return 'All time';
    }
  }

  Future<void> _load({
    required _VisitDateFilter filter,
    DateTime? start,
    DateTime? end,
  }) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _filter = filter;
    });

    try {
      final logs = await _activityService.getActivityLogs(
        companyId: _companyId,
        salesmanId: widget.salesmanId,
        startDate: start,
        endDate: end,
      );
      if (!mounted) return;
      setState(() {
        _logs = logs;
        _report = _reportFrom(logs);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = ErrorHandler.getFriendlyErrorMessage(e);
      });
    }
  }

  void _restoreInherited() {
    setState(() {
      _filter = _VisitDateFilter.inherited;
      _logs = List<ActivityLog>.from(widget.initialLogs);
      _report = _reportFrom(_logs);
      _errorMessage = null;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: AppTheme.primaryBlue),
          ),
          child: child!,
        );
      },
    );
    if (picked == null) return;
    setState(() => _selectedDate = picked);
    await _load(
      filter: _VisitDateFilter.date,
      start: DateTime(picked.year, picked.month, picked.day),
      end: DateTime(picked.year, picked.month, picked.day, 23, 59, 59, 999),
    );
  }

  Future<void> _pickRange() async {
    DateTime start = _rangeStart;
    DateTime end = _rangeEnd;
    final result = await showDialog<(DateTime, DateTime)>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Select date range'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('From'),
                    subtitle: Text(DateFormat('dd MMM yyyy').format(start)),
                    trailing: const Icon(Icons.calendar_today_outlined),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: start,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        setDialogState(() => start = picked);
                      }
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('To'),
                    subtitle: Text(DateFormat('dd MMM yyyy').format(end)),
                    trailing: const Icon(Icons.calendar_today_outlined),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: end,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        setDialogState(() => end = picked);
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, (start, end)),
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );
    if (result == null) return;
    var from = result.$1;
    var to = result.$2;
    if (from.isAfter(to)) {
      final swap = from;
      from = to;
      to = swap;
    }
    setState(() {
      _rangeStart = from;
      _rangeEnd = to;
    });
    await _load(
      filter: _VisitDateFilter.range,
      start: DateTime(from.year, from.month, from.day),
      end: DateTime(to.year, to.month, to.day, 23, 59, 59, 999),
    );
  }

  Future<void> _share() async {
    if (_logs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No details to share')),
      );
      return;
    }
    setState(() => _isSharing = true);
    try {
      final stamp = DateFormat('yyyyMMdd').format(DateTime.now());
      final name = widget.salesmanName.replaceAll(' ', '_');
      final bytes = await _pdfService.generateActivityReportPdf(
        title: 'Salesman Visit Report',
        periodLabel: _periodLabel,
        salesmanLabel: widget.mobile == null || widget.mobile!.isEmpty
            ? widget.salesmanName
            : '${widget.salesmanName} (${widget.mobile})',
        logs: _logs,
      );
      await _pdfService.sharePdf(
        bytes,
        '${name}_$stamp',
        filenamePrefix: 'Visit_',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ErrorHandler.getFriendlyErrorMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  Future<void> _openOrder(ActivityLog log) async {
    if (log.orderId == null) return;
    try {
      final order = await OrderService().getOrderById(log.orderId!);
      if (!mounted) return;
      if (order == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Order details not found')),
        );
        return;
      }
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => OrderDetailsAdminScreen(order: order),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ErrorHandler.getFriendlyErrorMessage(e))),
      );
    }
  }

  Future<void> _openCollection(ActivityLog log) async {
    final id = log.collectionId;
    if (id == null || id.isEmpty) return;
    try {
      final collection = await CollectionService().getCollectionById(id);
      if (!mounted) return;
      if (collection == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Collection details not found')),
        );
        return;
      }
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) =>
              CollectionDetailsScreen(collection: collection),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ErrorHandler.getFriendlyErrorMessage(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text(widget.salesmanName),
        actions: [
          if (_isSharing)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            )
          else
            IconButton(
              tooltip: 'Share PDF',
              icon: const Icon(Icons.share),
              onPressed: _share,
            ),
        ],
      ),
      body: Column(
        children: [
          _buildFilters(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _filterButton(
                  icon: Icons.calendar_today_outlined,
                  label: _filter == _VisitDateFilter.date
                      ? DateFormat('dd MMM').format(_selectedDate)
                      : 'Date',
                  selected: _filter == _VisitDateFilter.date,
                  onTap: _pickDate,
                ),
                const SizedBox(width: 8),
                _filterButton(
                  icon: Icons.date_range_outlined,
                  label: _filter == _VisitDateFilter.range
                      ? '${DateFormat('dd MMM').format(_rangeStart)}–${DateFormat('dd MMM').format(_rangeEnd)}'
                      : 'Range',
                  selected: _filter == _VisitDateFilter.range,
                  onTap: _pickRange,
                ),
                const SizedBox(width: 8),
                _filterButton(
                  icon: Icons.all_inclusive,
                  label: 'All time',
                  selected: _filter == _VisitDateFilter.all,
                  onTap: () => _load(filter: _VisitDateFilter.all),
                ),
                if (_filter != _VisitDateFilter.inherited) ...[
                  const SizedBox(width: 8),
                  _filterButton(
                    icon: Icons.close,
                    label: 'Clear',
                    selected: false,
                    onTap: _restoreInherited,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            widget.salesmanName,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (widget.mobile != null && widget.mobile!.isNotEmpty)
            Text(
              widget.mobile!,
              style: const TextStyle(color: AppTheme.grey, fontSize: 13),
            ),
          const SizedBox(height: 4),
          Text(
            _periodLabel,
            style: const TextStyle(
              fontSize: 13,
              color: AppTheme.darkGrey,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chip('${_report.loginCount} login', AppTheme.success),
              _chip('${_report.logoutCount} logout', AppTheme.error),
              _chip('${_report.orderCount} orders', AppTheme.primaryBlue),
              _chip('${_report.collectionCount} collections', AppTheme.warning),
            ],
          ),
        ],
      ),
    );
  }

  Widget _filterButton({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return OutlinedButton.icon(
      onPressed: _isLoading ? null : onTap,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: selected ? AppTheme.primaryBlue : AppTheme.darkGrey,
        side: BorderSide(
          color: selected ? AppTheme.primaryBlue : Colors.grey.shade300,
        ),
        backgroundColor:
            selected ? AppTheme.primaryBlue.withValues(alpha: 0.08) : null,
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _errorMessage!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.error),
          ),
        ),
      );
    }
    if (_report.days.isEmpty) {
      return const Center(
        child: Text(
          'No visit details for this period',
          style: TextStyle(color: AppTheme.grey),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      itemCount: _report.days.length,
      itemBuilder: (context, index) {
        final day = _report.days[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: VisitDayTimeline(
              day: day,
              onOpenOrder: _openOrder,
              onOpenCollection: _openCollection,
            ),
          ),
        );
      },
    );
  }
}
