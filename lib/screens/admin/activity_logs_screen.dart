import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:Orderx/core/theme/app_theme.dart';
import 'package:Orderx/models/activity_log_model.dart';
import 'package:Orderx/providers/auth_provider.dart';
import 'package:Orderx/screens/admin/salesman_visit_details_screen.dart';
import 'package:Orderx/services/activity_log_service.dart';
import 'package:Orderx/services/pdf_service.dart';
import 'package:Orderx/utils/error_handler.dart';
import 'package:Orderx/widgets/app_bar_actions.dart';
import 'package:Orderx/widgets/error_state_widget.dart';

enum _Period { today, month, all, customDate, customMonth }

enum _ViewFilter { all, attendance, orders }

enum _ShareKind { all, attendance, orders }

class ActivityLogsScreen extends StatefulWidget {
  const ActivityLogsScreen({super.key});

  @override
  State<ActivityLogsScreen> createState() => _ActivityLogsScreenState();
}

class _ActivityLogsScreenState extends State<ActivityLogsScreen> {
  final ActivityLogService _activityService = ActivityLogService();
  final PdfService _pdfService = PdfService();

  List<ActivityLog> _allLogs = [];
  List<ActivityLog> _logs = [];
  List<SalesmanActivityReport> _reports = [];
  List<SalesmanOption> _salesmen = [];
  bool _isLoading = false;
  bool _isSharing = false;
  String? _errorMessage;

  _Period _period = _Period.month;
  DateTime _selectedDate = DateTime.now();
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  String? _selectedSalesmanId;
  _ViewFilter _viewFilter = _ViewFilter.all;

  @override
  void initState() {
    super.initState();
    _loadSalesmen();
    _loadLogs();
  }

  String? get _effectiveCompanyId {
    final companyId = context.read<AuthProvider>().selectedCompanyId;
    return (companyId == 'ALL') ? null : companyId;
  }

  String get _periodLabel {
    switch (_period) {
      case _Period.today:
        return 'Today · ${DateFormat('dd MMM yyyy').format(DateTime.now())}';
      case _Period.month:
        return DateFormat('MMMM yyyy').format(DateTime.now());
      case _Period.all:
        return 'All time';
      case _Period.customDate:
        return DateFormat('dd MMM yyyy').format(_selectedDate);
      case _Period.customMonth:
        return DateFormat('MMMM yyyy').format(_selectedMonth);
    }
  }

  String get _salesmanLabel {
    if (_selectedSalesmanId == null) return 'All salesmen';
    final match = _salesmen.where((s) => s.id == _selectedSalesmanId);
    return match.isEmpty ? 'Salesman' : match.first.name;
  }

  (DateTime?, DateTime?) _range() {
    switch (_period) {
      case _Period.today:
        final now = DateTime.now();
        return (
          DateTime(now.year, now.month, now.day),
          DateTime(now.year, now.month, now.day, 23, 59, 59, 999),
        );
      case _Period.month:
        final now = DateTime.now();
        return (
          DateTime(now.year, now.month, 1),
          DateTime(now.year, now.month + 1, 0, 23, 59, 59, 999),
        );
      case _Period.all:
        return (null, null);
      case _Period.customDate:
        return (
          DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day),
          DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day,
              23, 59, 59, 999),
        );
      case _Period.customMonth:
        return (
          DateTime(_selectedMonth.year, _selectedMonth.month, 1),
          DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0, 23, 59, 59,
              999),
        );
    }
  }

  Future<void> _loadSalesmen() async {
    final salesmen =
        await _activityService.getSalesmen(companyId: _effectiveCompanyId);
    if (mounted) setState(() => _salesmen = salesmen);
  }

  Future<void> _loadLogs() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final range = _range();
      final allLogs = await _activityService.getActivityLogs(
        companyId: _effectiveCompanyId,
        startDate: range.$1,
        endDate: range.$2,
        salesmanId: _selectedSalesmanId,
      );
      var logs = allLogs;
      if (_viewFilter == _ViewFilter.attendance) {
        logs = logs
            .where((log) =>
                log.type == ActivityLogType.login ||
                log.type == ActivityLogType.logout)
            .toList();
      } else if (_viewFilter == _ViewFilter.orders) {
        logs = logs
            .where((log) => log.type == ActivityLogType.orderCreated)
            .toList();
      }

      if (mounted) {
        setState(() {
          _allLogs = allLogs;
          _logs = logs;
          _reports = groupActivityLogs(logs);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _allLogs = [];
          _logs = [];
          _reports = [];
          _isLoading = false;
          _errorMessage = ErrorHandler.getFriendlyErrorMessage(e);
        });
      }
    }
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
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _period = _Period.customDate;
      });
      _loadLogs();
    }
  }

  Future<void> _pickMonth() async {
    int year = _selectedMonth.year;
    int month = _selectedMonth.month;

    final result = await showDialog<DateTime>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Select month'),
              content: SizedBox(
                width: 320,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          onPressed: () => setDialogState(() => year--),
                          icon: const Icon(Icons.chevron_left),
                        ),
                        Text(
                          '$year',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        IconButton(
                          onPressed: year >= DateTime.now().year
                              ? null
                              : () => setDialogState(() => year++),
                          icon: const Icon(Icons.chevron_right),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: List.generate(12, (index) {
                        final m = index + 1;
                        final now = DateTime.now();
                        final disabled = DateTime(year, m)
                            .isAfter(DateTime(now.year, now.month));
                        final selected = month == m;
                        return ChoiceChip(
                          label:
                              Text(DateFormat.MMM().format(DateTime(year, m))),
                          selected: selected,
                          onSelected: disabled
                              ? null
                              : (_) => setDialogState(() => month = m),
                          selectedColor:
                              AppTheme.primaryBlue.withValues(alpha: 0.2),
                          labelStyle: TextStyle(
                            color: disabled
                                ? AppTheme.grey
                                : (selected
                                    ? AppTheme.primaryBlue
                                    : AppTheme.darkGrey),
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.normal,
                          ),
                        );
                      }),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () =>
                      Navigator.pop(context, DateTime(year, month, 1)),
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null) {
      setState(() {
        _selectedMonth = result;
        _period = _Period.customMonth;
      });
      _loadLogs();
    }
  }

  void _setPeriod(_Period period) {
    setState(() => _period = period);
    _loadLogs();
  }

  List<ActivityLog> _logsForShare(_ShareKind kind) {
    switch (kind) {
      case _ShareKind.all:
        return _logs;
      case _ShareKind.attendance:
        return _logs
            .where((l) =>
                l.type == ActivityLogType.login ||
                l.type == ActivityLogType.logout)
            .toList();
      case _ShareKind.orders:
        return _logs
            .where((l) => l.type == ActivityLogType.orderCreated)
            .toList();
    }
  }

  Future<void> _shareReport(_ShareKind kind) async {
    final logs = _logsForShare(kind);
    if (logs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No details to share for this filter')),
      );
      return;
    }

    setState(() => _isSharing = true);
    try {
      final title = switch (kind) {
        _ShareKind.all => 'Salesman Activity Report',
        _ShareKind.attendance => 'Login & Logout Report',
        _ShareKind.orders => 'Order Creation Report',
      };
      final prefix = switch (kind) {
        _ShareKind.all => 'Activity_',
        _ShareKind.attendance => 'LoginLogout_',
        _ShareKind.orders => 'Orders_',
      };
      final stamp = DateFormat('yyyyMMdd').format(DateTime.now());
      final salesmanPart = _selectedSalesmanId == null
          ? 'All'
          : _salesmanLabel.replaceAll(' ', '_');

      final bytes = await _pdfService.generateActivityReportPdf(
        title: title,
        periodLabel: _periodLabel,
        salesmanLabel: _salesmanLabel,
        logs: logs,
      );
      await _pdfService.sharePdf(
        bytes,
        '${salesmanPart}_$stamp',
        filenamePrefix: prefix,
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

  void _openSalesmanDetails(SalesmanActivityReport report) {
    final salesmanLogs =
        _allLogs.where((l) => l.salesmanId == report.salesmanId).toList();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SalesmanVisitDetailsScreen(
          salesmanId: report.salesmanId,
          salesmanName: report.salesmanName,
          mobile: report.mobile,
          initialLogs: salesmanLogs,
          initialPeriodLabel: _periodLabel,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Salesman Visit Logs'),
        actions: [
          const GlobalCompanySwitcher(),
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
            PopupMenuButton<_ShareKind>(
              tooltip: 'Share PDF',
              icon: const Icon(Icons.share),
              onSelected: _shareReport,
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: _ShareKind.all,
                  child: Text('Share all details'),
                ),
                PopupMenuItem(
                  value: _ShareKind.attendance,
                  child: Text('Share login & logout'),
                ),
                PopupMenuItem(
                  value: _ShareKind.orders,
                  child: Text('Share order details'),
                ),
              ],
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadLogs,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilters(),
          _buildSummaryBar(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _periodChip('Today', _Period.today),
                _periodChip('This month', _Period.month),
                _periodChip('All time', _Period.all),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _filterButton(
                    icon: Icons.calendar_today_outlined,
                    label: _period == _Period.customDate
                        ? DateFormat('dd MMM').format(_selectedDate)
                        : 'Date',
                    selected: _period == _Period.customDate,
                    onTap: _pickDate,
                  ),
                ),
                _filterButton(
                  icon: Icons.calendar_view_month_outlined,
                  label: _period == _Period.customMonth
                      ? DateFormat('MMM yyyy').format(_selectedMonth)
                      : 'Month',
                  selected: _period == _Period.customMonth,
                  onTap: _pickMonth,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _salesmanDropdown(),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _viewChip('All', _ViewFilter.all),
                _viewChip('Login / Logout', _ViewFilter.attendance),
                _viewChip('Orders', _ViewFilter.orders),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _periodChip(String label, _Period period) {
    final selected = _period == period;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => _setPeriod(period),
        selectedColor: AppTheme.primaryBlue.withValues(alpha: 0.15),
        labelStyle: TextStyle(
          color: selected ? AppTheme.primaryBlue : AppTheme.darkGrey,
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
        ),
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
      onPressed: onTap,
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

  Widget _salesmanDropdown() {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: 'Salesman',
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: _selectedSalesmanId,
          isExpanded: true,
          hint: const Text('All salesmen'),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('All salesmen'),
            ),
            ..._salesmen.map(
              (s) => DropdownMenuItem<String?>(
                value: s.id,
                child: Text(s.name, overflow: TextOverflow.ellipsis),
              ),
            ),
          ],
          onChanged: (value) {
            setState(() => _selectedSalesmanId = value);
            _loadLogs();
          },
        ),
      ),
    );
  }

  Widget _viewChip(String label, _ViewFilter filter) {
    final selected = _viewFilter == filter;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) {
          setState(() => _viewFilter = filter);
          _loadLogs();
        },
        selectedColor: AppTheme.primaryBlue.withValues(alpha: 0.15),
        labelStyle: TextStyle(
          color: selected ? AppTheme.primaryBlue : AppTheme.darkGrey,
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
    );
  }

  Widget _buildSummaryBar() {
    final logins =
        _logs.where((l) => l.type == ActivityLogType.login).length;
    final logouts =
        _logs.where((l) => l.type == ActivityLogType.logout).length;
    final orders =
        _logs.where((l) => l.type == ActivityLogType.orderCreated).length;
    final collections =
        _logs.where((l) => l.type == ActivityLogType.collection).length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      color: Colors.white,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _periodLabel,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.darkGrey,
                  ),
                ),
              ),
              Text(
                _salesmanLabel,
                style: const TextStyle(color: AppTheme.grey, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _statChip('Login', '$logins', AppTheme.success),
              const SizedBox(width: 8),
              _statChip('Logout', '$logouts', AppTheme.error),
              const SizedBox(width: 8),
              _statChip('Orders', '$orders', AppTheme.primaryBlue),
              if (_viewFilter != _ViewFilter.attendance &&
                  _viewFilter != _ViewFilter.orders) ...[
                const SizedBox(width: 8),
                _statChip('Collect', '$collections', AppTheme.warning),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _statChip(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: color,
                fontSize: 16,
              ),
            ),
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: AppTheme.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _reports.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null && _reports.isEmpty) {
      return ErrorStateWidget(message: _errorMessage!, onRetry: _loadLogs);
    }
    if (_reports.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text(
              'No activity found',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              'No login, logout, orders or collections for $_periodLabel',
              style: const TextStyle(color: AppTheme.grey),
              textAlign: TextAlign.center,
            ),
            if (_period == _Period.today) ...[
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => _setPeriod(_Period.month),
                child: const Text('View this month'),
              ),
            ],
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadLogs,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        itemCount: _reports.length,
        itemBuilder: (context, index) => _buildSalesmanCard(_reports[index]),
      ),
    );
  }

  Widget _buildSalesmanCard(SalesmanActivityReport report) {
    final fullCount = _allLogs
        .where((l) => l.salesmanId == report.salesmanId)
        .where((l) => l.type == ActivityLogType.collection)
        .length;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        title: Text(
          report.salesmanName,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          [
            if (report.mobile != null && report.mobile!.isNotEmpty)
              report.mobile!,
            '${report.loginCount} login',
            '${report.orderCount} orders',
            '$fullCount collections',
          ].join('  ·  '),
          style: const TextStyle(color: AppTheme.grey, fontSize: 12),
        ),
        trailing: const Icon(Icons.chevron_right, color: AppTheme.grey),
        onTap: () => _openSalesmanDetails(report),
      ),
    );
  }
}
