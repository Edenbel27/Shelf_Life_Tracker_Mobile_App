import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'dart:async';

import '../Repository/store_repository.dart' show UserRole;
import '../Settings/settings_page.dart' as settings_page;
import '../StoreOwner/report_page.dart' as report_page;
import '../navigation.dart';
import '../widgets/app_header.dart';
import 'home_page.dart' as home_page;
import 'inventory_page.dart' as inventory_page;
import 'purchase_page.dart' as purchase_page;

class TransactionsPage extends StatefulWidget {
  const TransactionsPage({super.key, this.role = UserRole.owner});

  final UserRole role;

  @override
  State<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends State<TransactionsPage> with TickerProviderStateMixin {
  bool _showHistory = false;
  String _mode = 'sale';
  String _historyFilter = 'all';
  String _search = '';
  bool _manualMode = false;
  InventoryItem? _selectedItem;

  bool get _canPurchase => widget.role == UserRole.owner;

  final List<String> _categories = const ['Dairy', 'Bakery', 'Beverages', 'Produce', 'Household', 'Other'];
  String _selectedCategory = 'Dairy';

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _categoryController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _qtyController = TextEditingController(text: '1');
  final FocusNode _qtyFocusNode = FocusNode();
  final ScrollController _formScrollController = ScrollController();
  final GlobalKey _qtySelectedKey = GlobalKey();
  final GlobalKey _qtyManualKey = GlobalKey();
  final TextEditingController _barcodeController = TextEditingController();
  final TextEditingController _supplierController = TextEditingController();
  final TextEditingController _minStockController = TextEditingController(text: '0');
  final TextEditingController _expiryController = TextEditingController();
  final TextEditingController _purchasePriceController = TextEditingController();
  final TextEditingController _sellingPriceController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _qtyFocusNode.addListener(() {
      if (!_qtyFocusNode.hasFocus && mounted) {
        setState(() {});
      }
    });
  }
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Enforce sale-only mode for non-owners without mutating in build()
    if (!_canPurchase && _mode != 'sale') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _mode = 'sale';
          _manualMode = false;
        });
      });
    }
    }

  @override
  void dispose() {
    _nameController.dispose();
    _categoryController.dispose();
    _priceController.dispose();
    _qtyController.dispose();
    _qtyFocusNode.dispose();
    _formScrollController.dispose();
    _barcodeController.dispose();
    _supplierController.dispose();
    _minStockController.dispose();
    _expiryController.dispose();
    _purchasePriceController.dispose();
    _sellingPriceController.dispose();
    _notesController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  bool get _selectionValid => !_manualMode && _selectedItem != null && _qtyController.text.trim().isNotEmpty;
  bool get _manualValid {
    return _manualMode && _canPurchase && _mode == 'purchase' &&
        _nameController.text.trim().isNotEmpty &&
        _purchasePriceController.text.trim().isNotEmpty &&
        _sellingPriceController.text.trim().isNotEmpty &&
        _qtyController.text.trim().isNotEmpty;
  }

  DateTime get _cutoff24h => DateTime.now().subtract(const Duration(hours: 24));
  bool _isRecent(DateTime? ts) => ts == null || ts.isAfter(_cutoff24h);

  Stream<List<InventoryItem>> _inventoryStream() {
    return FirebaseFirestore.instance
        .collection('inventory')
        .orderBy('nameLower')
        .snapshots()
        .map((snap) => snap.docs.map(InventoryItem.fromDoc).toList());
  }

  Stream<List<TransactionRecord>> _transactionsStream() {
    return FirebaseFirestore.instance
        .collection('transactions')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(TransactionRecord.fromDoc).toList());
  }

  void _updateSearch(String value) {
    if (!mounted) return;
    setState(() {
      _search = value.trim();
    });
    _searchFocusNode.requestFocus();
  }

  List<InventoryItem> _filteredItems(List<InventoryItem> items) {
    // Exclude expired items everywhere; additionally exclude zero-stock in sale mode
    final base = items
        .where((it) => it.expiresInDays > 0)
        .where((it) => _mode != 'sale' || it.quantity > 0)
        .toList();

    if (_search.isEmpty) return base;
    final q = _search.toLowerCase();
    return base.where((it) => it.name.toLowerCase().contains(q)).toList();
  }

  List<TransactionRecord> _filteredHistory(List<TransactionRecord> history) {
    return history.where((h) {
      final tsOk = _isRecent(h.timestamp);
      final typeMatch = _historyFilter == 'all' || h.type == _historyFilter;
      final searchMatch = _search.isEmpty || h.name.toLowerCase().contains(_search.toLowerCase());
      return tsOk && typeMatch && searchMatch;
    }).toList();
  }

  void _selectItem(InventoryItem item) {
    setState(() {
      _manualMode = false;
      _selectedItem = item;
      _nameController.text = item.name;
      _categoryController.text = item.category;
      final selectedPrice = _mode == 'sale' ? item.sellingPrice : item.purchasePrice;
      _priceController.text = selectedPrice.toStringAsFixed(2);
      if (_qtyController.text.trim().isEmpty) {
        _qtyController.text = '1';
      }
    });
  }

  void _startManualEntry() {
    setState(() {
      _manualMode = true;
      _selectedItem = null;
      _nameController.clear();
      _selectedCategory = _categories.first;
      _priceController.clear();
      _barcodeController.clear();
      _supplierController.clear();
      _minStockController.text = '0';
      _expiryController.clear();
      _purchasePriceController.clear();
      _sellingPriceController.clear();
      _notesController.clear();
      if (_qtyController.text.trim().isEmpty) {
        _qtyController.text = '1';
      }
    });
  }

  Future<void> _submitTransaction() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    if (!(_selectionValid || _manualValid)) {
      setState(() => _isSaving = false);
      return;
    }
    if (!_canPurchase && _mode != 'sale') {
      setState(() => _isSaving = false);
      setState(() {
        _mode = 'sale';
        _manualMode = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Only owners can record purchases.')));
      return;
    }
    final qty = int.tryParse(_qtyController.text.trim()) ?? 0;
    if (qty <= 0) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Quantity must be greater than zero.')));
      return;
    }
    try {
      if (_mode == 'sale') {
        if (_selectedItem == null) {
          setState(() => _isSaving = false);
          return;
        }
        final unitPrice = double.tryParse(_priceController.text.trim());
        await _recordSale(_selectedItem!, qty, priceOverride: unitPrice);
        setState(() {
          _selectedItem = null;
          _qtyController.clear();
          _priceController.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sale recorded.')));
        setState(() => _isSaving = false);
        return;
      }
      if (_manualMode) {
        await _recordManualPurchase(qty);
        setState(() {
          _selectedItem = null;
          _manualMode = false;
          _qtyController.clear();
          _priceController.clear();
          _selectedCategory = _categories.first;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Purchase recorded.')));
        setState(() => _isSaving = false);
        return;
      }
      if (_selectedItem == null) {
        setState(() => _isSaving = false);
        return;
      }
      final price = double.tryParse(_priceController.text.trim());
      await _recordPurchase(_selectedItem!, qty, price, price);
      setState(() {
        _selectedItem = null;
        _manualMode = false;
        _qtyController.clear();
        _priceController.clear();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Purchase recorded.')));
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _recordSale(InventoryItem item, int qty, {double? priceOverride}) async {
    final invRef = FirebaseFirestore.instance.collection('inventory').doc(item.id);
    final txRef = FirebaseFirestore.instance.collection('transactions').doc();

    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(invRef);
      if (!snap.exists) {
        throw Exception('Item not found');
      }
      final data = snap.data() ?? {};
      final currentQty = ((data['quantity'] ?? 0) as num).toInt();
      if (qty > currentQty) {
        throw Exception('Insufficient stock');
      }
      final purchasePrice = (data['purchasePrice'] ?? 0).toDouble();
      final sellingPrice = priceOverride != null && priceOverride > 0
          ? priceOverride
          : (data['sellingPrice'] ?? 0).toDouble();

      tx.update(invRef, {
        'quantity': currentQty - qty,
        'sellingPrice': sellingPrice,
      });

      tx.set(txRef, {
        'itemId': snap.id,
        'name': data['name'] ?? '',
        'category': data['category'] ?? '',
        'type': 'sale',
        'qty': qty,
        'amount': sellingPrice * qty,
        'purchasePrice': purchasePrice,
        'sellingPrice': sellingPrice,
        'timestamp': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> _recordPurchase(InventoryItem item, int qty, double? purchasePrice, double? sellingPrice) async {
    final invRef = FirebaseFirestore.instance.collection('inventory').doc(item.id);
    final txRef = FirebaseFirestore.instance.collection('transactions').doc();

    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(invRef);
      if (!snap.exists) {
        throw Exception('Item not found');
      }
      final data = snap.data() ?? {};
      final currentQty = ((data['quantity'] ?? 0) as num).toInt();
      final newPurchase = purchasePrice != null && purchasePrice > 0 ? purchasePrice : (data['purchasePrice'] ?? 0).toDouble();
      final newSelling = sellingPrice != null && sellingPrice > 0 ? sellingPrice : (data['sellingPrice'] ?? 0).toDouble();

      tx.update(invRef, {
        'quantity': currentQty + qty,
        'purchasePrice': newPurchase,
        'sellingPrice': newSelling,
      });

      tx.set(txRef, {
        'itemId': snap.id,
        'name': data['name'] ?? '',
        'category': data['category'] ?? '',
        'type': 'purchase',
        'qty': qty,
        'amount': newPurchase * qty,
        'purchasePrice': newPurchase,
        'sellingPrice': newSelling,
        'timestamp': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> _recordManualPurchase(int qty) async {
    final name = _nameController.text.trim();
    final purchasePrice = double.tryParse(_purchasePriceController.text.trim()) ?? 0;
    final sellingPrice = double.tryParse(_sellingPriceController.text.trim()) ?? 0;
    final nameLower = name.toLowerCase();

    final invColl = FirebaseFirestore.instance.collection('inventory');
    final existing = await invColl.where('nameLower', isEqualTo: nameLower).limit(1).get();

    if (existing.docs.isNotEmpty) {
      final doc = existing.docs.first;
      final item = InventoryItem.fromDoc(doc);
      await _recordPurchase(item, qty, purchasePrice, sellingPrice);
      return;
    }

    final expiresInDays = _computeExpiresInDays();
    final alertThreshold = int.tryParse(_minStockController.text.trim()) ?? 3;
    final newRef = invColl.doc();
    final txRef = FirebaseFirestore.instance.collection('transactions').doc();

    await FirebaseFirestore.instance.runTransaction((tx) async {
      tx.set(newRef, {
        'name': name,
        'nameLower': nameLower,
        'category': _selectedCategory,
        'quantity': qty,
        'expiresInDays': expiresInDays,
        'alertThresholdDays': alertThreshold,
        'purchasePrice': purchasePrice,
        'sellingPrice': sellingPrice,
      });

      tx.set(txRef, {
        'itemId': newRef.id,
        'name': name,
        'category': _selectedCategory,
        'type': 'purchase',
        'qty': qty,
        'amount': purchasePrice * qty,
        'purchasePrice': purchasePrice,
        'sellingPrice': sellingPrice,
        'timestamp': FieldValue.serverTimestamp(),
      });
    });
  }

  int _computeExpiresInDays() {
    if (_expiryController.text.isEmpty) return 30;
    try {
      final parsed = DateTime.tryParse(_expiryController.text);
      if (parsed == null) return 30;
      final diff = parsed.difference(DateTime.now()).inDays;
      return diff > 0 ? diff : 0;
    } catch (_) {
      return 30;
    }
  }

  void _bumpQty(int delta) {
    final current = int.tryParse(_qtyController.text.trim()) ?? 0;
    final next = (current + delta).clamp(1, 999999);
    _qtyController.value = TextEditingValue(
      text: next.toString(),
      selection: TextSelection.collapsed(offset: next.toString().length),
    );
    setState(() {});
    _qtyFocusNode.requestFocus();
    _scrollQtyIntoView();
  }

  Future<void> _scrollQtyIntoView({GlobalKey? fieldKey}) async {
    final key = fieldKey ?? _qtySelectedKey;
    await Future.delayed(const Duration(milliseconds: 30));
    final ctx = key.currentContext;
    if (ctx == null) return;
    await Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 180),
      alignment: 0.3,
      curve: Curves.easeOut,
    );
  }

  Widget _buildQtyStepper({bool compact = false, String label = 'Quantity', GlobalKey? fieldKey}) {
    final labelStyle = TextStyle(fontWeight: FontWeight.w600, color: Colors.grey.shade800);
    final borderColor = Colors.grey.shade300;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: labelStyle),
        const SizedBox(height: 6),
        Container(
          key: fieldKey,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: () => _bumpQty(-1),
              ),
              Expanded(
                child: TextField(
                  focusNode: _qtyFocusNode,
                  controller: _qtyController,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    isDense: compact,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    border: InputBorder.none,
                    hintText: '1',
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                onPressed: () => _bumpQty(1),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildModeBadge(bool isSale) {
    final Color accent = isSale ? const Color(0xFF2EAD68) : const Color(0xFF3B82F6);
    final icon = isSale ? Icons.attach_money : Icons.inventory_2_outlined;
    final title = isSale ? 'Sale' : 'Purchase';
    final subtitle = isSale ? 'Record outgoing items' : 'Restock inventory';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Container(
            height: 42,
            width: 42,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: accent.withOpacity(0.25)),
            ),
            child: Icon(icon, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: accent, fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(color: Colors.grey.shade700)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeSwitch(bool isSale, bool canPurchase) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 3)),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _ModeSegment(
              selected: isSale,
              title: 'Sale',
              icon: Icons.sell,
              color: const Color(0xFF2EAD68),
              onTap: () => setState(() {
                _mode = 'sale';
                _manualMode = false;
                _selectedItem = null;
                if (_qtyController.text.trim().isEmpty) {
                  _qtyController.text = '1';
                }
                _priceController.clear();
              }),
          ), 
          ),
          Expanded(
            child: _ModeSegment(
              selected: !isSale,
              title: 'Purchase',
              icon: Icons.inventory,
              color: const Color(0xFF3B82F6),
              disabled: !canPurchase,
              onTap: () {
                if (!canPurchase) return;
                setState(() {
                  _mode = 'purchase';
                  _manualMode = false;
                  _selectedItem = null;
                  if (_qtyController.text.trim().isEmpty) {
                    _qtyController.text = '1';
                  }
                  _priceController.clear();
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickExpiryDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 5)),
    );
    if (picked != null) {
      final formatted = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      setState(() => _expiryController.text = formatted);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSale = _mode == 'sale';
    return Scaffold(
      appBar: buildAppBarWithLogoutAndNotifications(
        context: context,
        title: 'Shelf Life Tracker',
        role: widget.role,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: StreamBuilder<List<InventoryItem>>(
        stream: _inventoryStream(),
        builder: (context, invSnap) {
          if (invSnap.hasError) {
            return Center(child: Text('Error loading items: ${invSnap.error}'));
          }
          if (invSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final items = invSnap.data ?? [];
          if (_selectedItem != null && !items.any((i) => i.id == _selectedItem!.id)) {
            _selectedItem = null;
          }

          return Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Transactions', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _showHistory ? Colors.grey.shade200 : Colors.blue,
                          foregroundColor: _showHistory ? Colors.black87 : Colors.white,
                        ),
                        onPressed: () => setState(() => _showHistory = false),
                        child: const Text('New Transaction'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _showHistory ? Colors.blue : Colors.grey.shade200,
                          foregroundColor: _showHistory ? Colors.white : Colors.black87,
                        ),
                        onPressed: () => setState(() => _showHistory = true),
                        child: const Text('History'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 150),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    child: _showHistory
                        ? SizedBox.expand(
                            key: const ValueKey('history'),
                            child: _buildHistoryView(),
                          )
                        : SizedBox.expand(
                            key: const ValueKey('new'),
                            child: _buildNewTransactionView(items, isSale),
                          ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: buildBottomNav(
        context: context,
        role: widget.role,
        activeTab: AppTab.transactions,
        destinationBuilder: (tab) {
          switch (tab) {
            case AppTab.home:
              return home_page.HomePage(role: widget.role);
            case AppTab.inventory:
              return inventory_page.InventoryPage(role: widget.role);
            case AppTab.transactions:
              return TransactionsPage(role: widget.role);
            case AppTab.reports:
              return const report_page.StoreOwnerReportsPage();
            case AppTab.settings:
              return settings_page.SettingsPage(role: widget.role);
          }
        },
      ),
    );
  }

  Widget _buildNewTransactionView(List<InventoryItem> items, bool isSale) {
    final canPurchase = _canPurchase;
    final filteredItems = _filteredItems(items);

    // Keep the primary action anchored in view so it is not hidden behind the
    // keyboard or device safe areas on smaller phones.
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            controller: _formScrollController,
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Transaction Type', style: TextStyle(color: Colors.grey.shade700)),
                const SizedBox(height: 6),
                _buildModeSwitch(isSale, canPurchase),
                const SizedBox(height: 12),
                _buildModeBadge(isSale),
                const SizedBox(height: 14),
                Text('Select Item', style: TextStyle(color: Colors.grey.shade700)),
                const SizedBox(height: 6),
                TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  key: const ValueKey('item-search'),
                  decoration: InputDecoration(
                    hintText: 'Search items...',
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    border: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey.shade300)),
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey.shade300)),
                    focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.blue, width: 1.5)),
                    fillColor: Colors.grey.shade100,
                    filled: true,
                  ),
                  textInputAction: TextInputAction.search,
                  onSubmitted: _updateSearch,
                  onChanged: (value) {
                    if (value.isEmpty) {
                      _updateSearch('');
                    }
                  },
                ),
                const SizedBox(height: 10),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 150),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  child: _buildModeContent(
                    isSale: isSale,
                    filteredItems: filteredItems,
                    canPurchase: canPurchase,
                  ),
                ),
              ],
            ),
          ),
        ),
        SafeArea(
          minimum: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isSaving ? null : _submitTransaction,
              icon: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.save),
              label: Text(_isSaving ? 'Saving...' : (_mode == 'sale' ? 'Save Sale' : 'Save Purchase')),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildModeContent({required bool isSale, required List<InventoryItem> filteredItems, required bool canPurchase}) {
    if (_manualMode) {
      return Column(
        key: const ValueKey('manual'),
        children: [
          _buildManualBackButton(),
          const SizedBox(height: 8),
          _buildManualForm(),
        ],
      );
    }

    if (isSale) {
      return Container(
        key: const ValueKey('sale'),
        child: _buildSaleList(filteredItems),
      );
    }

    return Column(
      key: const ValueKey('purchase'),
      children: [
        _buildPurchaseList(filteredItems),
        const SizedBox(height: 12),
        if (canPurchase) _buildManualEntryCallout(),
      ],
    );
  }

  Widget _buildManualForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Manual Entry (purchase only)', style: TextStyle(color: Colors.grey.shade700)),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Item Details', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                TextField(
                  controller: _nameController,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Item name *', hintText: 'e.g., Milk 1L'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: _selectedCategory,
                  items: _categories.map((c) => DropdownMenuItem<String>(value: c, child: Text(c))).toList(),
                  onChanged: (val) => setState(() => _selectedCategory = val ?? _selectedCategory),
                  decoration: const InputDecoration(labelText: 'Category *'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _barcodeController,
                  decoration: const InputDecoration(labelText: 'Barcode / SKU', hintText: 'Optional'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _supplierController,
                  decoration: const InputDecoration(labelText: 'Supplier', hintText: 'Optional'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Stock Information', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                _buildQtyStepper(label: 'Quantity *', fieldKey: _qtyManualKey),
                const SizedBox(height: 10),
                TextField(
                  controller: _minStockController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Minimum stock alert level',
                    hintText: 'e.g., 10',
                    helperText: "You'll be notified when stock falls below this level",
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _expiryController,
                  readOnly: true,
                  decoration: InputDecoration(
                    labelText: 'Expiry date',
                    hintText: 'yyyy-mm-dd',
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.calendar_today_outlined),
                      onPressed: _pickExpiryDate,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Pricing Information', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                TextField(
                  controller: _purchasePriceController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Purchase price (per unit) *', hintText: 'Birr 0.00'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _sellingPriceController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Selling price (per unit) *', hintText: 'Birr 0.00'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Additional Notes', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                TextField(
                  controller: _notesController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Notes',
                    hintText: 'Any additional information...',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSaleList(List<InventoryItem> items) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Select an item to sell', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          SizedBox(
            height: 340,
            child: ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = items[index];
                final isSelected = _selectedItem?.id == item.id;
                return Container(
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.blue.shade50 : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isSelected ? Colors.blue.shade200 : Colors.grey.shade300),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.03),
                        blurRadius: 6,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      ListTile(
                        onTap: () {
                          if (isSelected) {
                            setState(() {
                              _selectedItem = null;
                              _manualMode = false;
                            });
                          } else {
                            _selectItem(item);
                            _scrollQtyIntoView(fieldKey: _qtySelectedKey);
                          }
                        },
                        title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text('${item.category} · Stock: ${item.quantity}', style: TextStyle(color: Colors.grey.shade700)),
                        trailing: Icon(isSelected ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down),
                      ),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 150),
                        curve: Curves.easeOut,
                        child: isSelected
                            ? Padding(
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Quantity', style: TextStyle(color: Colors.grey.shade800, fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 6),
                                    TextField(
                                      key: _qtySelectedKey,
                                      controller: _qtyController,
                                      focusNode: _qtyFocusNode,
                                      keyboardType: TextInputType.number,
                                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                      onChanged: (_) {},
                                      decoration: const InputDecoration(
                                        hintText: 'Enter quantity',
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Text('Unit Price', style: TextStyle(color: Colors.grey.shade800, fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 6),
                                    TextField(
                                      controller: _priceController,
                                      readOnly: true,
                                      decoration: InputDecoration(
                                        hintText: 'Birr ${item.sellingPrice.toStringAsFixed(2)}',
                                        border: const OutlineInputBorder(),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPurchaseList(List<InventoryItem> items) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Select an item to purchase', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          SizedBox(
            height: 340,
            child: ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = items[index];
                final isSelected = _selectedItem?.id == item.id;
                return Container(
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.blue.shade50 : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isSelected ? Colors.blue.shade200 : Colors.grey.shade300),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.03),
                        blurRadius: 6,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      ListTile(
                        onTap: () {
                          if (isSelected) {
                            setState(() {
                              _selectedItem = null;
                              _manualMode = false;
                            });
                          } else {
                            _selectItem(item);
                            _scrollQtyIntoView(fieldKey: _qtySelectedKey);
                          }
                        },
                        title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text('${item.category} · Stock: ${item.quantity}', style: TextStyle(color: Colors.grey.shade700)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Birr ${item.sellingPrice.toStringAsFixed(2)}'),
                            const SizedBox(width: 6),
                            IconButton(
                              icon: Icon(isSelected ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down),
                              onPressed: () {
                                if (isSelected) {
                                  setState(() {
                                    _selectedItem = null;
                                    _manualMode = false;
                                  });
                                } else {
                                  _selectItem(item);
                                  _scrollQtyIntoView(fieldKey: _qtySelectedKey);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 150),
                        curve: Curves.easeOut,
                        child: isSelected
                            ? Padding(
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Quantity', style: TextStyle(color: Colors.grey.shade800, fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 6),
                                    TextField(
                                      key: _qtySelectedKey,
                                      controller: _qtyController,
                                      focusNode: _qtyFocusNode,
                                      keyboardType: TextInputType.number,
                                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                      onChanged: (_) {},
                                      decoration: const InputDecoration(
                                        hintText: 'Enter quantity',
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Text('Purchase Price', style: TextStyle(color: Colors.grey.shade800, fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 6),
                                    TextField(
                                      controller: _priceController,
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      onChanged: (_) {},
                                      decoration: InputDecoration(
                                        hintText: 'Birr ${item.purchasePrice.toStringAsFixed(2)}',
                                        border: const OutlineInputBorder(),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildManualEntryCallout() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Row(
        children: [
          const Icon(Icons.playlist_add, color: Colors.blue),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              "Can't find the item? Go to Add/Purchase",
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const purchase_page.PurchasePage()),
              ).then((_) {
                if (mounted) setState(() {});
              });
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
            child: const Text('Go'),
          ),
        ],
      ),
    );
  }

  Widget _buildManualBackButton() {
    return OutlinedButton.icon(
      onPressed: () => setState(() => _manualMode = false),
      icon: const Icon(Icons.arrow_back),
      label: const Text('Back to item list'),
    );
  }

  Widget _buildHistoryView() {
    return StreamBuilder<List<TransactionRecord>>(
      stream: _transactionsStream(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('Error loading history: ${snap.error}'));
        }
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final history = snap.data ?? [];
        final filtered = _filteredHistory(history);
        final totalSales = history.where((h) => h.type == 'sale').fold<double>(0, (sum, h) => sum + h.amount);
        final totalPurchases = history.where((h) => h.type == 'purchase').fold<double>(0, (sum, h) => sum + h.amount);

        return Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _SummaryCard(
                    title: 'Total Sales',
                    value: 'Birr ${totalSales.toStringAsFixed(2)}',
                    color: Colors.green,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _SummaryCard(
                    title: 'Total Purchases',
                    value: 'Birr ${totalPurchases.toStringAsFixed(2)}',
                    color: Colors.blue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _HistoryChip(label: 'All', selected: _historyFilter == 'all', onTap: () => setState(() => _historyFilter = 'all')),
                const SizedBox(width: 6),
                _HistoryChip(label: 'Sales', selected: _historyFilter == 'sale', onTap: () => setState(() => _historyFilter = 'sale')),
                const SizedBox(width: 6),
                _HistoryChip(label: 'Purchases', selected: _historyFilter == 'purchase', onTap: () => setState(() => _historyFilter = 'purchase')),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              decoration: InputDecoration(
                hintText: 'Search history...',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey.shade300)),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey.shade300)),
                focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.blue, width: 1.5)),
                fillColor: Colors.grey.shade100,
                filled: true,
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: _updateSearch,
              onChanged: (value) {
                if (value.isEmpty) {
                  _updateSearch('');
                }
              },
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.separated(
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final h = filtered[i];
                  final isSaleType = h.type == 'sale';
                  final tagColor = isSaleType ? Colors.green.shade50 : Colors.blue.shade50;
                  final tagTextColor = isSaleType ? Colors.green.shade800 : Colors.blue.shade800;
                  return ListTile(
                    title: Row(
                      children: [
                        Expanded(child: Text(h.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: tagColor, borderRadius: BorderRadius.circular(12)),
                          child: Text(isSaleType ? 'sale' : 'purchase', style: TextStyle(color: tagTextColor, fontSize: 12)),
                        ),
                      ],
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_formatTimestamp(h.timestamp), style: TextStyle(color: Colors.grey.shade600)),
                        Text('Qty: ${h.qty}', style: TextStyle(color: Colors.grey.shade600)),
                      ],
                    ),
                    trailing: Text('Birr ${h.amount.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  String _formatTimestamp(DateTime? ts) {
    if (ts == null) return '';
    return DateFormat('yyyy-MM-dd hh:mm a').format(ts);
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.title, required this.value, required this.color});

  final String title;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: Colors.grey.shade700)),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(color: color.withOpacity(0.9), fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _HistoryChip extends StatelessWidget {
  const _HistoryChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
    );
  }
}

class _ModeSegment extends StatelessWidget {
  const _ModeSegment({
    required this.selected,
    required this.title,
    required this.icon,
    required this.color,
    required this.onTap,
    this.disabled = false,
  });

  final bool selected;
  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final base = disabled ? Colors.grey : color;
    final textColor = selected
        ? (base is MaterialColor ? base.shade700 : base.withOpacity(0.85))
        : Colors.grey.shade800;
    return InkWell(
      onTap: disabled ? null : onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? base.withOpacity(0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? base.withOpacity(0.35) : Colors.transparent),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: selected ? base : Colors.grey.shade700),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
            if (disabled) ...[
              const SizedBox(width: 6),
              Icon(Icons.lock_outline, size: 14, color: Colors.grey.shade500),
            ],
          ],
        ),
      ),
    );
  }
}

class InventoryItem {
  const InventoryItem({
    required this.id,
    required this.name,
    required this.category,
    required this.quantity,
    required this.expiresInDays,
    required this.alertThresholdDays,
    required this.purchasePrice,
    required this.sellingPrice,
  });

  final String id;
  final String name;
  final String category;
  final int quantity;
  final int expiresInDays;
  final int alertThresholdDays;
  final double purchasePrice;
  final double sellingPrice;

  factory InventoryItem.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return InventoryItem(
      id: doc.id,
      name: (data['name'] ?? '') as String,
      category: (data['category'] ?? '') as String,
      quantity: ((data['quantity'] ?? 0) as num).toInt(),
      expiresInDays: ((data['expiresInDays'] ?? 0) as num).toInt(),
      alertThresholdDays: ((data['alertThresholdDays'] ?? 3) as num).toInt(),
      purchasePrice: (data['purchasePrice'] ?? 0).toDouble(),
      sellingPrice: (data['sellingPrice'] ?? 0).toDouble(),
    );
  }
}

class TransactionRecord {
  const TransactionRecord({
    required this.id,
    required this.name,
    required this.type,
    required this.qty,
    required this.amount,
    required this.timestamp,
    required this.category,
    required this.purchasePrice,
    required this.sellingPrice,
  });

  final String id;
  final String name;
  final String type;
  final int qty;
  final double amount;
  final DateTime? timestamp;
  final String category;
  final double purchasePrice;
  final double sellingPrice;

  factory TransactionRecord.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final ts = data['timestamp'];
    return TransactionRecord(
      id: doc.id,
      name: (data['name'] ?? '') as String,
      type: (data['type'] ?? 'sale') as String,
      qty: ((data['qty'] ?? 0) as num).toInt(),
      amount: (data['amount'] ?? 0).toDouble(),
      timestamp: ts is Timestamp ? ts.toDate() : null,
      category: (data['category'] ?? '') as String,
      purchasePrice: (data['purchasePrice'] ?? 0).toDouble(),
      sellingPrice: (data['sellingPrice'] ?? 0).toDouble(),
    );
  }
}
