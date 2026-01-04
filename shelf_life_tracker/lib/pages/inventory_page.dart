import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../Repository/store_repository.dart' show UserRole;
import '../Settings/settings_page.dart' as settings_page;
import '../StoreOwner/report_page.dart' as report_page;
import '../navigation.dart';
import 'home_page.dart' as home_page;
import 'purchase_page.dart' as purchase_page;
import 'transaction_page.dart' as transaction_page;

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key, this.role = UserRole.owner});

  final UserRole role;

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  String _search = '';
  String _selectedCategory = 'All';

  bool get _isOwner => widget.role == UserRole.owner;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Shelf Life Tracker'),
        actions: [
          if (_isOwner)
            TextButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const purchase_page.PurchasePage()),
              ),
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text('Add / Purchase', style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
      body: StreamBuilder<List<InventoryItem>>(
        stream: _itemsStream(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error loading inventory: ${snapshot.error}'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final items = snapshot.data ?? [];
          final categories = _categoriesFrom(items);
          final filtered = _filteredItems(items);
          final expiringSoon = _expiringSoonItems(items);
          final lowStock = _lowStockItems(items);

          return Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Inventory', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.grey.shade800)),
                ),
                const SizedBox(height: 8),
                TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search items...',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (value) => setState(() => _search = value.trim()),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 40,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: categories.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, i) {
                      final cat = categories[i];
                      final selected = cat == _selectedCategory;
                      return ChoiceChip(
                        label: Text(cat),
                        selected: selected,
                        selectedColor: Colors.blue.shade100,
                        onSelected: (_) => setState(() => _selectedCategory = cat),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _SmallCard(title: 'Total Items', value: items.length.toString()),
                    _SmallCard(title: 'Low Stock', value: lowStock.length.toString()),
                    _SmallCard(title: 'Near Expiry', value: expiringSoon.length.toString()),
                    _SmallCard(title: 'Expired', value: items.where((i) => i.expiresInDays <= 0).length.toString()),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: filtered.isEmpty
                      ? const Center(child: Text('No items found'))
                      : ListView.separated(
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, idx) {
                            final item = filtered[idx];
                            final status = _statusLabel(item);
                            final bg = _statusColor(item);
                            final potentialProfit = (item.sellingPrice - item.purchasePrice).toStringAsFixed(2);
                            return Card(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                              ),
                                              const SizedBox(width: 6),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: bg,
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                child: Text(status, style: const TextStyle(fontSize: 12)),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          Text(item.category, style: TextStyle(color: Colors.grey.shade700)),
                                          const SizedBox(height: 8),
                                          Text('Quantity: ${item.quantity}'),
                                          const SizedBox(height: 4),
                                          Text('Expires: ${item.expiresInDays} days (alert <= ${item.alertThresholdDays})'),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text('Birr ${item.sellingPrice.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                        const SizedBox(height: 6),
                                        Text('Profit: Birr ${potentialProfit}', style: const TextStyle(color: Colors.green)),
                                        if (_isOwner) ...[
                                          const SizedBox(height: 8),
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              IconButton(
                                                onPressed: () => _editItem(item),
                                                icon: const Icon(Icons.edit, size: 18),
                                              ),
                                              IconButton(
                                                onPressed: () => _deleteItem(item),
                                                icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                                              ),
                                            ],
                                          )
                                        ],
                                      ],
                                    )
                                  ],
                                ),
                              ),
                            );
                          },
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
        activeTab: AppTab.inventory,
        destinationBuilder: (tab) {
          switch (tab) {
            case AppTab.home:
              return home_page.HomePage(role: widget.role);
            case AppTab.inventory:
              return InventoryPage(role: widget.role);
            case AppTab.transactions:
              return transaction_page.TransactionsPage(role: widget.role);
            case AppTab.reports:
              return const report_page.StoreOwnerReportsPage();
            case AppTab.settings:
              return settings_page.SettingsPage(role: widget.role);
          }
        },
      ),
    );
  }

  Stream<List<InventoryItem>> _itemsStream() {
    return FirebaseFirestore.instance
        .collection('inventory')
        .orderBy('nameLower')
        .snapshots()
        .map((snap) => snap.docs.map(InventoryItem.fromDoc).toList());
  }

  List<String> _categoriesFrom(List<InventoryItem> items) {
    final others = <String>[];
    for (final item in items) {
      if (item.category.isNotEmpty) {
        others.add(item.category);
      }
    }
    others.sort();
    return ['All', ...{
      // deduplicate while preserving sorted order for the rest
      for (final c in others) c,
    }];
  }

  List<InventoryItem> _filteredItems(List<InventoryItem> items) {
    final query = _search.toLowerCase();
    return items.where((item) {
      final matchesSearch = query.isEmpty || item.name.toLowerCase().contains(query);
      final matchesCategory = _selectedCategory == 'All' || item.category == _selectedCategory;
      return matchesSearch && matchesCategory;
    }).toList();
  }

  List<InventoryItem> _expiringSoonItems(List<InventoryItem> items) {
    return items.where((i) => i.expiresInDays > 0 && i.expiresInDays <= i.alertThresholdDays).toList();
  }

  List<InventoryItem> _lowStockItems(List<InventoryItem> items) {
    return items.where((i) => i.quantity <= 5).toList();
  }

  String _statusLabel(InventoryItem item) {
    if (item.expiresInDays <= 0) return 'Expired';
    if (item.expiresInDays <= item.alertThresholdDays) return 'Expiring';
    return 'Fresh';
  }

  Color _statusColor(InventoryItem item) {
    if (item.expiresInDays <= 0) return Colors.red.shade200;
    if (item.expiresInDays <= item.alertThresholdDays) return Colors.orange.shade200;
    return Colors.green.shade200;
  }

  Future<void> _editItem(InventoryItem item) async {
    final nameCtrl = TextEditingController(text: item.name);
    final categoryCtrl = TextEditingController(text: item.category);
    final quantityCtrl = TextEditingController(text: item.quantity.toString());
    final expiresCtrl = TextEditingController(text: item.expiresInDays.toString());
    final alertCtrl = TextEditingController(text: item.alertThresholdDays.toString());
    final purchaseCtrl = TextEditingController(text: item.purchasePrice.toStringAsFixed(2));
    final sellingCtrl = TextEditingController(text: item.sellingPrice.toStringAsFixed(2));

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Edit Item'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
                TextField(controller: categoryCtrl, decoration: const InputDecoration(labelText: 'Category')),
                TextField(controller: quantityCtrl, decoration: const InputDecoration(labelText: 'Quantity'), keyboardType: TextInputType.number),
                TextField(controller: expiresCtrl, decoration: const InputDecoration(labelText: 'Expires in days'), keyboardType: TextInputType.number),
                TextField(controller: alertCtrl, decoration: const InputDecoration(labelText: 'Alert threshold days'), keyboardType: TextInputType.number),
                TextField(controller: purchaseCtrl, decoration: const InputDecoration(labelText: 'Purchase price'), keyboardType: TextInputType.number),
                TextField(controller: sellingCtrl, decoration: const InputDecoration(labelText: 'Selling price'), keyboardType: TextInputType.number),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        );
      },
    );

    if (result != true) return;

    await FirebaseFirestore.instance.collection('inventory').doc(item.id).update({
      'name': nameCtrl.text.trim(),
      'nameLower': nameCtrl.text.trim().toLowerCase(),
      'category': categoryCtrl.text.trim(),
      'quantity': int.tryParse(quantityCtrl.text) ?? item.quantity,
      'expiresInDays': int.tryParse(expiresCtrl.text) ?? item.expiresInDays,
      'alertThresholdDays': int.tryParse(alertCtrl.text) ?? item.alertThresholdDays,
      'purchasePrice': double.tryParse(purchaseCtrl.text) ?? item.purchasePrice,
      'sellingPrice': double.tryParse(sellingCtrl.text) ?? item.sellingPrice,
    });
  }

  Future<void> _deleteItem(InventoryItem item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete item?'),
        content: Text('Remove ${item.name} from inventory?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseFirestore.instance.collection('inventory').doc(item.id).delete();
    }
  }
}

class _SmallCard extends StatelessWidget {
  const _SmallCard({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          children: [
            Text(title, style: const TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 6),
            Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
      ),
    );
  }
}

class InventoryItem {
  InventoryItem({
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
