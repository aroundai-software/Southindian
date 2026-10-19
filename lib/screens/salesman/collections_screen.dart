import 'package:Orderx/core/theme/app_theme.dart';
import 'package:Orderx/models/collection_model.dart';
import 'package:Orderx/providers/auth_provider.dart';
import 'package:Orderx/screens/salesman/add_collection_screen.dart';
import 'package:Orderx/screens/salesman/collection_details_screen.dart';
import 'package:Orderx/services/collection_pdf_service.dart';
import 'package:Orderx/services/collection_service.dart';
import 'package:Orderx/utils/error_handler.dart';
import 'package:Orderx/widgets/error_state_widget.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class CollectionsScreen extends StatefulWidget {
  const CollectionsScreen({super.key});

  @override
  State<CollectionsScreen> createState() => _CollectionsScreenState();
}

class _CollectionsScreenState extends State<CollectionsScreen> {
  final CollectionService _collectionService = CollectionService();
  final TextEditingController _searchController = TextEditingController();

  List<CollectionModel> _all = [];
  List<CollectionModel> _filtered = [];
  bool _isLoading = true;
  String? _errorMessage;
  String _methodFilter = 'All';
  DateTimeRange? _dateRange;

  final _money = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

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
      final user = auth.currentUser;
      if (user == null) {
        setState(() {
          _all = [];
          _filtered = [];
          _isLoading = false;
        });
        return;
      }
      final rows = await _collectionService.getCollections(
        salesmanId: user.id,
        companyId: auth.selectedCompanyId ?? user.companyId,
      );
      if (!mounted) return;
      setState(() {
        _all = rows;
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

  void _applyFilters() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      _filtered = _all.where((item) {
        if (!PaymentMethod.matchesFilter(item.paymentMethod, _methodFilter)) {
          return false;
        }
        if (_dateRange != null) {
          final day = DateTime(
            item.collectionDate.year,
            item.collectionDate.month,
            item.collectionDate.day,
          );
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
      setState(() => _dateRange = picked);
      _applyFilters();
    }
  }

  Future<void> _openAdd() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AddCollectionScreen()),
    );
    if (saved == true && mounted) {
      await _load();
    }
  }

  void _openDetails(CollectionModel item) async {
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
      final parts = <String>[];
      if (_methodFilter != 'All') parts.add('Method: $_methodFilter');
      if (_dateRange != null) {
        parts.add(
          'Date: ${DateFormat('dd MMM yyyy').format(_dateRange!.start)} - ${DateFormat('dd MMM yyyy').format(_dateRange!.end)}',
        );
      }
      final search = _searchController.text.trim();
      if (search.isNotEmpty) parts.add('Search: $search');
      await CollectionPdfService().share(
        collections: List<CollectionModel>.from(_filtered),
        filterSummary: parts.isEmpty ? 'None (all collections)' : parts.join(' | '),
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
          IconButton(
            tooltip: 'Filter by date',
            icon: Icon(
              _dateRange != null ? Icons.filter_alt : Icons.filter_alt_outlined,
            ),
            onPressed: _pickDateRange,
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAdd,
        backgroundColor: AppTheme.success,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add Collection', style: TextStyle(color: Colors.white)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search customer, cheque, UPI, txn, bank...',
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
          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: PaymentMethod.filterGroups.map((filter) {
                final selected = _methodFilter == filter;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: FilterChip(
                    label: Text(filter),
                    selected: selected,
                    onSelected: (_) {
                      setState(() => _methodFilter = filter);
                      _applyFilters();
                    },
                    selectedColor: AppTheme.primaryBlue.withOpacity(0.15),
                    checkmarkColor: AppTheme.primaryBlue,
                    labelStyle: TextStyle(
                      color: selected ? AppTheme.primaryBlue : AppTheme.darkGrey,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          if (_dateRange != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  const Icon(Icons.date_range, size: 16, color: AppTheme.primaryBlue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${DateFormat('dd MMM yyyy').format(_dateRange!.start)} - ${DateFormat('dd MMM yyyy').format(_dateRange!.end)}',
                      style: const TextStyle(
                        color: AppTheme.primaryBlue,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() => _dateRange = null);
                      _applyFilters();
                    },
                    child: const Text('Clear date'),
                  ),
                ],
              ),
            ),
          if (!_isLoading && _errorMessage == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
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
                        ? _emptyState()
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                              itemCount: _filtered.length,
                              itemBuilder: (context, index) {
                                final item = _filtered[index];
                                return _CollectionCard(
                                  item: item,
                                  money: _money,
                                  onTap: () => _openDetails(item),
                                  onDelete: () => _confirmDelete(item),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.payments_outlined, size: 56, color: Colors.grey[400]),
            const SizedBox(height: 12),
            const Text(
              'No collections yet',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
            const SizedBox(height: 6),
            const Text(
              'Tap Add Collection to record cash, cheque, UPI or bank payments.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.grey),
            ),
          ],
        ),
      ),
    );
  }
}

class _CollectionCard extends StatelessWidget {
  final CollectionModel item;
  final NumberFormat money;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _CollectionCard({
    required this.item,
    required this.money,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final summary = item.detailsSummary;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.success.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.payments, color: AppTheme.success),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                      '${item.paymentMethod} · ${DateFormat('dd MMM yyyy').format(item.collectionDate)}',
                      style: const TextStyle(color: AppTheme.grey, fontSize: 12),
                    ),
                    if (summary.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        summary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppTheme.darkGrey, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
              Text(
                money.format(item.amount),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.success,
                ),
              ),
              IconButton(
                tooltip: 'Delete collection',
                icon: const Icon(Icons.delete_outline, color: AppTheme.error),
                visualDensity: VisualDensity.compact,
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
