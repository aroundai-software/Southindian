import 'package:Orderx/core/theme/app_theme.dart';
import 'package:Orderx/models/collection_model.dart';
import 'package:Orderx/models/salesman.dart';
import 'package:Orderx/providers/auth_provider.dart';
import 'package:Orderx/screens/salesman/collection_details_screen.dart';
import 'package:Orderx/services/collection_pdf_service.dart';
import 'package:Orderx/services/collection_service.dart';
import 'package:Orderx/services/company_selection_service.dart';
import 'package:Orderx/services/salesman_service.dart';
import 'package:Orderx/utils/error_handler.dart';
import 'package:Orderx/widgets/error_state_widget.dart';
import 'package:Orderx/widgets/location_address_widget.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class AdminCollectionsScreen extends StatefulWidget {
  const AdminCollectionsScreen({super.key});

  @override
  State<AdminCollectionsScreen> createState() => _AdminCollectionsScreenState();
}

class _AdminCollectionsScreenState extends State<AdminCollectionsScreen> {
  final _collectionService = CollectionService();
  final _salesmanService = SalesmanService();
  final _searchController = TextEditingController();
  final _money = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

  List<CollectionModel> _all = [];
  List<CollectionModel> _filtered = [];
  List<Salesman> _salesmen = [];
  bool _isLoading = true;
  String? _errorMessage;

  String? _salesmanId;
  String? _customerName;
  DateTimeRange? _dateRange;
  DateTime? _month;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_applyFilters);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _searchController.removeListener(_applyFilters);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final auth = context.read<AuthProvider>();
      final companyId = auth.selectedCompanyId;
      final effectiveCompany =
          (companyId == null || companyId == 'ALL') ? null : companyId;

      final results = await Future.wait([
        _collectionService.getCollections(companyId: effectiveCompany),
        if (effectiveCompany != null)
          _salesmanService.getSalesmen(companyId: effectiveCompany)
        else
          Future.value(<Salesman>[]),
      ]);

      if (!mounted) return;
      setState(() {
        _all = results[0] as List<CollectionModel>;
        _salesmen = results[1] as List<Salesman>;
        _isLoading = false;
      });
      _applyFilters();
    } catch (e) {
      if (!mounted) return;
      final raw = e.toString();
      final missingTable = raw.contains('payment_collections') ||
          raw.contains('PGRST205') ||
          raw.contains('42P01') ||
          raw.contains('schema cache');
      setState(() {
        _isLoading = false;
        _errorMessage = missingTable
            ? 'Collections table is missing. Run 016_create_payment_collections.sql in the Supabase SQL Editor, then tap Retry.'
            : ErrorHandler.getFriendlyErrorMessage(e);
      });
    }
  }

  List<String> get _customerOptions {
    final names = _all
        .map((e) => e.customerName.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return names;
  }

  Map<String, String> get _salesmanOptions {
    final map = <String, String>{};
    for (final s in _salesmen) {
      map[s.id] = s.name;
    }
    for (final row in _all) {
      map.putIfAbsent(
        row.salesmanId,
        () => (row.salesmanName?.trim().isNotEmpty == true)
            ? row.salesmanName!
            : 'Salesman',
      );
    }
    return map;
  }

  void _applyFilters() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      _filtered = _all.where((item) {
        if (_salesmanId != null && item.salesmanId != _salesmanId) {
          return false;
        }
        if (_customerName != null && item.customerName != _customerName) {
          return false;
        }
        final day = DateTime(
          item.collectionDate.year,
          item.collectionDate.month,
          item.collectionDate.day,
        );
        if (_month != null) {
          if (day.year != _month!.year || day.month != _month!.month) {
            return false;
          }
        }
        if (_dateRange != null) {
          final start = DateTime(
            _dateRange!.start.year,
            _dateRange!.start.month,
            _dateRange!.start.day,
          );
          final end = DateTime(
            _dateRange!.end.year,
            _dateRange!.end.month,
            _dateRange!.end.day,
          );
          if (day.isBefore(start) || day.isAfter(end)) return false;
        }
        return item.matchesQuery(query);
      }).toList();
    });
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _dateRange,
    );
    if (picked != null && mounted) {
      setState(() {
        _dateRange = picked;
        _month = null;
      });
      _applyFilters();
    }
  }

  Future<void> _pickMonth() async {
    final initial = _month ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      helpText: 'Select a month',
    );
    if (picked != null && mounted) {
      setState(() {
        _month = DateTime(picked.year, picked.month);
        _dateRange = null;
      });
      _applyFilters();
    }
  }

  void _clearFilters() {
    setState(() {
      _salesmanId = null;
      _customerName = null;
      _dateRange = null;
      _month = null;
      _searchController.clear();
    });
    _applyFilters();
  }

  bool get _hasFilters =>
      _salesmanId != null ||
      _customerName != null ||
      _dateRange != null ||
      _month != null ||
      _searchController.text.trim().isNotEmpty;

  Future<void> _openDetails(CollectionModel item) async {
    final deleted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CollectionDetailsScreen(collection: item),
      ),
    );
    if (deleted == true && mounted) _load();
  }

  Future<void> _confirmDelete(CollectionModel item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete collection?'),
        content: Text(
          'This will permanently delete the collection from ${item.customerName}.',
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
    if (confirmed != true || !mounted) return;
    try {
      await _collectionService.deleteCollection(item.id);
      if (!mounted) return;
      setState(() {
        _all.removeWhere((e) => e.id == item.id);
      });
      _applyFilters();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Collection deleted')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ErrorHandler.getFriendlyErrorMessage(e)),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  String _filterSummary() {
    final parts = <String>[];
    if (_salesmanId != null) {
      parts.add('Salesman: ${_salesmanOptions[_salesmanId] ?? _salesmanId}');
    }
    if (_customerName != null) parts.add('Customer: $_customerName');
    if (_dateRange != null) {
      parts.add(
        'Date: ${DateFormat('dd MMM yyyy').format(_dateRange!.start)} - ${DateFormat('dd MMM yyyy').format(_dateRange!.end)}',
      );
    }
    if (_month != null) {
      parts.add('Month: ${DateFormat('MMM yyyy').format(_month!)}');
    }
    final search = _searchController.text.trim();
    if (search.isNotEmpty) parts.add('Search: $search');
    return parts.isEmpty ? 'None (all collections)' : parts.join(' | ');
  }

  Future<void> _sharePdf() async {
    if (_filtered.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No collections to share')),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Preparing PDF...'), duration: Duration(seconds: 1)),
    );
    try {
      String? companyName;
      final companyId = context.read<AuthProvider>().selectedCompanyId;
      if (companyId != null && companyId != 'ALL') {
        final company =
            await CompanySelectionService().getCompanyById(companyId);
        companyName = company?['company_name'] as String?;
      } else if (companyId == 'ALL') {
        companyName = 'All Companies';
      }
      await CollectionPdfService().share(
        collections: List<CollectionModel>.from(_filtered),
        companyName: companyName,
        filterSummary: _filterSummary(),
      );
    } catch (e) {
      if (!mounted) return;
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
    final total = _filtered.fold<double>(0, (sum, e) => sum + e.amount);
    final salesmen = _salesmanOptions;
    final salesmanIds = salesmen.keys.toList()
      ..sort((a, b) => salesmen[a]!.toLowerCase().compareTo(salesmen[b]!.toLowerCase()));

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Collections'),
        actions: [
          IconButton(
            tooltip: 'Share PDF',
            icon: const Icon(Icons.share),
            onPressed: _isLoading ? null : _sharePdf,
          ),
          if (_hasFilters)
            TextButton(
              onPressed: _clearFilters,
              child: const Text('Clear', style: TextStyle(color: Colors.white)),
            ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText:
                    'Search salesman, customer, cheque, UPI, bank, amount...',
                hintStyle: const TextStyle(color: AppTheme.grey, fontSize: 14),
                prefixIcon:
                    const Icon(Icons.search, color: AppTheme.primaryBlue),
                suffixIcon: _searchController.text.trim().isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: _searchController.clear,
                      )
                    : null,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _filterChip(
                  icon: Icons.person_outline,
                  label: _salesmanId == null
                      ? 'Salesman: All'
                      : 'Salesman: ${salesmen[_salesmanId] ?? 'Selected'}',
                  selected: _salesmanId != null,
                  onTap: () => _pickFromList(
                    title: 'Filter by salesman',
                    options: [
                      'All',
                      ...salesmanIds.map((id) => salesmen[id]!),
                    ],
                    selected: _salesmanId == null
                        ? 'All'
                        : salesmen[_salesmanId],
                    onPicked: (label) {
                      setState(() {
                        if (label == 'All') {
                          _salesmanId = null;
                        } else {
                          _salesmanId = salesmanIds.firstWhere(
                            (id) => salesmen[id] == label,
                            orElse: () => _salesmanId ?? '',
                          );
                          if (_salesmanId != null && _salesmanId!.isEmpty) {
                            _salesmanId = null;
                          }
                        }
                      });
                      _applyFilters();
                    },
                  ),
                ),
                _filterChip(
                  icon: Icons.storefront_outlined,
                  label: _customerName == null
                      ? 'Customer: All'
                      : 'Customer: $_customerName',
                  selected: _customerName != null,
                  onTap: () => _pickFromList(
                    title: 'Filter by customer',
                    options: ['All', ..._customerOptions],
                    selected: _customerName ?? 'All',
                    onPicked: (label) {
                      setState(() {
                        _customerName = label == 'All' ? null : label;
                      });
                      _applyFilters();
                    },
                  ),
                ),
                _filterChip(
                  icon: Icons.date_range,
                  label: _dateRange == null
                      ? 'Date'
                      : '${DateFormat('dd MMM').format(_dateRange!.start)} - ${DateFormat('dd MMM').format(_dateRange!.end)}',
                  selected: _dateRange != null,
                  onTap: _pickDateRange,
                ),
                _filterChip(
                  icon: Icons.calendar_month,
                  label: _month == null
                      ? 'Month'
                      : DateFormat('MMM yyyy').format(_month!),
                  selected: _month != null,
                  onTap: _pickMonth,
                ),
              ],
            ),
          ),
          if (!_isLoading && _errorMessage == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Text(
                    '${_filtered.length} collection${_filtered.length == 1 ? '' : 's'}',
                    style: const TextStyle(color: AppTheme.grey, fontSize: 13),
                  ),
                  const Spacer(),
                  Text(
                    _money.format(total),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.success,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? ErrorStateWidget(message: _errorMessage!, onRetry: _load)
                    : _filtered.isEmpty
                        ? const Center(
                            child: Text(
                              'No collections match these filters',
                              style: TextStyle(color: AppTheme.grey),
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                              itemCount: _filtered.length,
                              itemBuilder: (context, index) {
                                final item = _filtered[index];
                                final summary = item.detailsSummary;
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: InkWell(
                                    onTap: () => _openDetails(item),
                                    borderRadius: BorderRadius.circular(16),
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 44,
                                            height: 44,
                                            decoration: BoxDecoration(
                                              color: AppTheme.success
                                                  .withValues(alpha: 0.12),
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(
                                              Icons.payments,
                                              color: AppTheme.success,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  item.customerName,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 15,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  '${item.salesmanName ?? 'Salesman'} · ${item.paymentMethod} · ${DateFormat('dd MMM yyyy').format(item.collectionDate)}',
                                                  style: const TextStyle(
                                                    color: AppTheme.grey,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Row(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Icon(
                                                      Icons.location_on,
                                                      size: 14,
                                                      color: item.hasLocation
                                                          ? AppTheme.error
                                                          : AppTheme.grey,
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Expanded(
                                                      child: item.latitude !=
                                                                  null &&
                                                              item.longitude !=
                                                                  null
                                                          ? LocationAddressWidget(
                                                              latitude: item
                                                                  .latitude!,
                                                              longitude: item
                                                                  .longitude!,
                                                              storedAddress: item
                                                                  .locationAddress,
                                                              showIcon: false,
                                                            )
                                                          : Text(
                                                              item.locationDisplay ??
                                                                  'Location not recorded',
                                                              maxLines: 2,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                              style: const TextStyle(
                                                                color: AppTheme
                                                                    .grey,
                                                                fontSize: 12,
                                                              ),
                                                            ),
                                                    ),
                                                  ],
                                                ),
                                                if (summary.isNotEmpty) ...[
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    summary,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      color: AppTheme.darkGrey,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
                                            children: [
                                              Text(
                                                _money.format(item.amount),
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  color: AppTheme.success,
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              IconButton(
                                                tooltip: 'Delete collection',
                                                icon: const Icon(
                                                  Icons.delete_outline,
                                                  color: AppTheme.error,
                                                ),
                                                visualDensity:
                                                    VisualDensity.compact,
                                                onPressed: () =>
                                                    _confirmDelete(item),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return ActionChip(
      avatar: Icon(
        icon,
        size: 16,
        color: selected ? AppTheme.primaryBlue : AppTheme.darkGrey,
      ),
      label: Text(
        label,
        overflow: TextOverflow.ellipsis,
      ),
      onPressed: onTap,
      backgroundColor:
          selected ? AppTheme.primaryBlue.withValues(alpha: 0.12) : Colors.white,
      labelStyle: TextStyle(
        color: selected ? AppTheme.primaryBlue : AppTheme.darkGrey,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        fontSize: 13,
      ),
    );
  }

  Future<void> _pickFromList({
    required String title,
    required List<String> options,
    required String? selected,
    required ValueChanged<String> onPicked,
  }) async {
    final controller = TextEditingController();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        var query = '';
        return StatefulBuilder(
          builder: (context, setModal) {
            final filtered = options
                .where((o) => o.toLowerCase().contains(query.toLowerCase()))
                .toList();
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: SizedBox(
                height: MediaQuery.sizeOf(context).height * 0.65,
                child: Column(
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        controller: controller,
                        onChanged: (v) => setModal(() => query = v),
                        decoration: InputDecoration(
                          hintText: 'Search',
                          prefixIcon: const Icon(Icons.search),
                          filled: true,
                          fillColor: Colors.grey[100],
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final option = filtered[index];
                          final isSelected = option == selected;
                          return ListTile(
                            title: Text(option),
                            trailing: isSelected
                                ? const Icon(Icons.check,
                                    color: AppTheme.primaryBlue)
                                : null,
                            onTap: () {
                              Navigator.pop(context);
                              onPicked(option);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    controller.dispose();
  }
}
