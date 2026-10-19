import 'package:Orderx/core/theme/app_theme.dart';
import 'package:Orderx/models/collection_model.dart';
import 'package:Orderx/models/customer_model.dart';
import 'package:Orderx/providers/auth_provider.dart';
import 'package:Orderx/screens/salesman/customer_selection_screen.dart';
import 'package:Orderx/services/collection_service.dart';
import 'package:Orderx/utils/location_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class AddCollectionScreen extends StatefulWidget {
  const AddCollectionScreen({super.key});

  @override
  State<AddCollectionScreen> createState() => _AddCollectionScreenState();
}

class _AddCollectionScreenState extends State<AddCollectionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _collectionService = CollectionService();

  CustomerModel? _customer;
  String? _paymentMethod;
  DateTime _collectionDate = DateTime.now();
  DateTime? _instrumentDate;

  final _amountController = TextEditingController();
  final _remarksController = TextEditingController();
  final _referenceController = TextEditingController();
  final _receivedFromController = TextEditingController();
  final _instrumentNumberController = TextEditingController();
  final _bankNameController = TextEditingController();
  final _bankBranchController = TextEditingController();
  final _ifscController = TextEditingController();
  final _drawerNameController = TextEditingController();
  final _accountLast4Controller = TextEditingController();
  final _transactionIdController = TextEditingController();
  final _upiIdController = TextEditingController();
  final _cardLast4Controller = TextEditingController();
  final _approvalCodeController = TextEditingController();
  final _gatewayController = TextEditingController();
  final _walletController = TextEditingController();
  final _otherDetailController = TextEditingController();

  String? _cardType;
  bool _saving = false;

  @override
  void dispose() {
    _amountController.dispose();
    _remarksController.dispose();
    _referenceController.dispose();
    _receivedFromController.dispose();
    _instrumentNumberController.dispose();
    _bankNameController.dispose();
    _bankBranchController.dispose();
    _ifscController.dispose();
    _drawerNameController.dispose();
    _accountLast4Controller.dispose();
    _transactionIdController.dispose();
    _upiIdController.dispose();
    _cardLast4Controller.dispose();
    _approvalCodeController.dispose();
    _gatewayController.dispose();
    _walletController.dispose();
    _otherDetailController.dispose();
    super.dispose();
  }

  Future<void> _pickCustomer() async {
    final selected = await Navigator.push<CustomerModel>(
      context,
      MaterialPageRoute(builder: (_) => const CustomerSelectionScreen()),
    );
    if (selected != null && mounted) {
      setState(() => _customer = selected);
    }
  }

  Future<void> _pickDate({required bool instrument}) async {
    final initial = instrument
        ? (_instrumentDate ?? DateTime.now())
        : _collectionDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      setState(() {
        if (instrument) {
          _instrumentDate = picked;
        } else {
          _collectionDate = picked;
        }
      });
    }
  }

  String? _requiredWhen(bool when, String? value, String label) {
    if (!when) return null;
    if (value == null || value.trim().isEmpty) return 'Enter $label';
    return null;
  }

  Future<void> _save() async {
    if (_customer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select a customer'),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }
    if (_paymentMethod == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select a payment method'),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final isCheque = _paymentMethod == PaymentMethod.cheque;
    final isDd = _paymentMethod == PaymentMethod.demandDraft;
    if ((isCheque || isDd) && _instrumentDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isCheque
              ? 'Select cheque date'
              : 'Select demand draft date'),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    final auth = context.read<AuthProvider>();
    final user = auth.currentUser;
    final companyId = auth.selectedCompanyId ?? user?.companyId;
    if (user == null || companyId == null || companyId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Company not selected. Cannot save collection.'),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    final amount = double.tryParse(
          _amountController.text.trim().replaceAll(',', ''),
        ) ??
        0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a valid amount'),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final location = await _captureLocation();
      await _collectionService.createCollection(
        companyId: companyId,
        salesmanId: user.id,
        salesmanName: user.name,
        customerId: _customer!.id,
        customerName: _customer!.customerName,
        amount: amount,
        collectionDate: _collectionDate,
        paymentMethod: _paymentMethod!,
        referenceNumber: _emptyToNull(_referenceController.text),
        remarks: _emptyToNull(_remarksController.text),
        receivedFrom: _emptyToNull(_receivedFromController.text),
        instrumentNumber: _emptyToNull(_instrumentNumberController.text),
        instrumentDate: _instrumentDate,
        bankName: _emptyToNull(_bankNameController.text),
        bankBranch: _emptyToNull(_bankBranchController.text),
        ifscCode: _emptyToNull(_ifscController.text),
        drawerName: _emptyToNull(_drawerNameController.text),
        transferMode: _isBankTransfer ? _paymentMethod : null,
        accountLast4: _emptyToNull(_accountLast4Controller.text),
        transactionId: _emptyToNull(_transactionIdController.text),
        upiId: _emptyToNull(_upiIdController.text),
        cardLast4: _emptyToNull(_cardLast4Controller.text),
        cardType: _cardType,
        approvalCode: _emptyToNull(_approvalCodeController.text),
        gatewayName: _emptyToNull(_gatewayController.text),
        walletName: _emptyToNull(_walletController.text),
        otherMethodDetail: _emptyToNull(_otherDetailController.text),
        latitude: location.$1,
        longitude: location.$2,
        locationAddress: location.$3,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Collection saved'),
          backgroundColor: AppTheme.success,
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save collection: $e'),
          backgroundColor: AppTheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<(double?, double?, String?)> _captureLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return (null, null, null);
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final address = await reverseGeocodeAddress(
        position.latitude,
        position.longitude,
      );
      return (position.latitude, position.longitude, address);
    } catch (_) {
      return (null, null, null);
    }
  }

  String? _emptyToNull(String value) {
    final t = value.trim();
    return t.isEmpty ? null : t;
  }

  bool get _isBankTransfer =>
      _paymentMethod == PaymentMethod.neft ||
      _paymentMethod == PaymentMethod.rtgs ||
      _paymentMethod == PaymentMethod.imps;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Add Collection'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _sectionCard(
              title: 'Customer',
              child: InkWell(
                onTap: _pickCustomer,
                borderRadius: BorderRadius.circular(12),
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Customer name',
                    prefixIcon: const Icon(Icons.person_outline),
                    suffixIcon: const Icon(Icons.chevron_right),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    _customer?.customerName ?? 'Tap to select customer',
                    style: TextStyle(
                      color: _customer == null
                          ? AppTheme.grey
                          : AppTheme.darkGrey,
                      fontWeight: _customer == null
                          ? FontWeight.normal
                          : FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _sectionCard(
              title: 'Payment',
              child: Column(
                children: [
                  TextFormField(
                    controller: _amountController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    decoration: InputDecoration(
                      labelText: 'Amount',
                      prefixText: '₹ ',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    validator: (value) {
                      final amount = double.tryParse(
                            (value ?? '').trim().replaceAll(',', ''),
                          ) ??
                          0;
                      if (amount <= 0) return 'Enter amount';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () => _pickDate(instrument: false),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Collection date',
                        prefixIcon: const Icon(Icons.calendar_today_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        DateFormat('dd MMM yyyy').format(_collectionDate),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _paymentMethod,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Payment method',
                      prefixIcon: const Icon(Icons.payments_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    items: PaymentMethod.all
                        .map(
                          (method) => DropdownMenuItem(
                            value: method,
                            child: Text(method),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      setState(() {
                        _paymentMethod = value;
                        if (value != PaymentMethod.cheque &&
                            value != PaymentMethod.demandDraft) {
                          _instrumentDate = null;
                        }
                      });
                    },
                    validator: (value) =>
                        value == null ? 'Select payment method' : null,
                  ),
                ],
              ),
            ),
            if (_paymentMethod != null) ...[
              const SizedBox(height: 16),
              _sectionCard(
                title: '$_paymentMethod details',
                child: _buildMethodFields(),
              ),
            ],
            const SizedBox(height: 16),
            _sectionCard(
              title: 'Notes',
              child: TextFormField(
                controller: _remarksController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Remarks',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(_saving ? 'Saving...' : 'Save Collection'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMethodFields() {
    switch (_paymentMethod) {
      case PaymentMethod.cash:
        return Column(
          children: [
            _field(_receivedFromController, 'Received from', Icons.badge_outlined),
            const SizedBox(height: 12),
            _field(_referenceController, 'Receipt / reference no.', Icons.tag),
          ],
        );
      case PaymentMethod.cheque:
        return Column(
          children: [
            _field(
              _instrumentNumberController,
              'Cheque number',
              Icons.confirmation_number_outlined,
              required: true,
            ),
            const SizedBox(height: 12),
            _dateField('Cheque date', _instrumentDate, () => _pickDate(instrument: true)),
            const SizedBox(height: 12),
            _field(_bankNameController, 'Bank name', Icons.account_balance_outlined, required: true),
            const SizedBox(height: 12),
            _field(_bankBranchController, 'Branch', Icons.location_city_outlined),
            const SizedBox(height: 12),
            _field(_ifscController, 'IFSC', Icons.pin_outlined),
            const SizedBox(height: 12),
            _field(_drawerNameController, 'Drawer / account name', Icons.person_outline),
          ],
        );
      case PaymentMethod.demandDraft:
        return Column(
          children: [
            _field(
              _instrumentNumberController,
              'DD number',
              Icons.confirmation_number_outlined,
              required: true,
            ),
            const SizedBox(height: 12),
            _dateField('DD date', _instrumentDate, () => _pickDate(instrument: true)),
            const SizedBox(height: 12),
            _field(_bankNameController, 'Issuing bank', Icons.account_balance_outlined, required: true),
            const SizedBox(height: 12),
            _field(_bankBranchController, 'Branch', Icons.location_city_outlined),
          ],
        );
      case PaymentMethod.neft:
      case PaymentMethod.rtgs:
      case PaymentMethod.imps:
        return Column(
          children: [
            _field(_transactionIdController, 'UTR / transaction ID', Icons.tag, required: true),
            const SizedBox(height: 12),
            _field(_bankNameController, 'Bank name', Icons.account_balance_outlined),
            const SizedBox(height: 12),
            _field(_ifscController, 'IFSC', Icons.pin_outlined),
            const SizedBox(height: 12),
            _field(
              _accountLast4Controller,
              'Account last 4 digits',
              Icons.credit_card_outlined,
              keyboard: TextInputType.number,
              maxLength: 4,
            ),
            const SizedBox(height: 12),
            _field(_referenceController, 'Reference', Icons.notes_outlined),
          ],
        );
      case PaymentMethod.upi:
        return Column(
          children: [
            _field(_upiIdController, 'UPI ID', Icons.qr_code, required: true),
            const SizedBox(height: 12),
            _field(_transactionIdController, 'UPI transaction / UTR', Icons.tag, required: true),
            const SizedBox(height: 12),
            _field(_referenceController, 'Reference', Icons.notes_outlined),
          ],
        );
      case PaymentMethod.creditCard:
      case PaymentMethod.debitCard:
        return Column(
          children: [
            DropdownButtonFormField<String>(
              value: _cardType,
              decoration: InputDecoration(
                labelText: 'Card network',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              items: const ['Visa', 'Mastercard', 'RuPay', 'Amex', 'Other']
                  .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                  .toList(),
              onChanged: (v) => setState(() => _cardType = v),
            ),
            const SizedBox(height: 12),
            _field(
              _cardLast4Controller,
              'Card last 4 digits',
              Icons.credit_card,
              keyboard: TextInputType.number,
              maxLength: 4,
              required: true,
            ),
            const SizedBox(height: 12),
            _field(_approvalCodeController, 'Approval / auth code', Icons.verified_outlined),
            const SizedBox(height: 12),
            _field(_transactionIdController, 'Transaction ID', Icons.tag),
          ],
        );
      case PaymentMethod.online:
        return Column(
          children: [
            _field(_gatewayController, 'Payment gateway / portal', Icons.language, required: true),
            const SizedBox(height: 12),
            _field(_transactionIdController, 'Transaction ID', Icons.tag, required: true),
            const SizedBox(height: 12),
            _field(_referenceController, 'Reference / order ID', Icons.notes_outlined),
          ],
        );
      case PaymentMethod.wallet:
        return Column(
          children: [
            _field(_walletController, 'Wallet name (Paytm, PhonePe...)', Icons.account_balance_wallet_outlined, required: true),
            const SizedBox(height: 12),
            _field(_transactionIdController, 'Transaction ID', Icons.tag, required: true),
            const SizedBox(height: 12),
            _field(_referenceController, 'Reference', Icons.notes_outlined),
          ],
        );
      case PaymentMethod.other:
        return Column(
          children: [
            _field(
              _otherDetailController,
              'Specify payment method',
              Icons.more_horiz,
              required: true,
            ),
            const SizedBox(height: 12),
            _field(_transactionIdController, 'Transaction / reference ID', Icons.tag),
            const SizedBox(height: 12),
            _field(_referenceController, 'Reference', Icons.notes_outlined),
          ],
        );
      default:
        return _field(_referenceController, 'Reference', Icons.tag);
    }
  }

  Widget _sectionCard({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 15,
              color: AppTheme.darkBlue,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    IconData icon, {
    bool required = false,
    TextInputType? keyboard,
    int? maxLength,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboard,
      maxLength: maxLength,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        counterText: '',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      validator: (value) => _requiredWhen(required, value, label),
    );
  }

  Widget _dateField(String label, DateTime? value, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.event_outlined),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(
          value != null
              ? DateFormat('dd MMM yyyy').format(value)
              : 'Tap to select date',
          style: TextStyle(
            color: value == null ? AppTheme.grey : AppTheme.darkGrey,
          ),
        ),
      ),
    );
  }
}
