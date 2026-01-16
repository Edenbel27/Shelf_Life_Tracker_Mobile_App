import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../Repository/store_repository.dart';
import '../StoreOwner/report_page.dart' as report_page;
import '../Settings/settings_page.dart' as settings_page;
import '../navigation.dart';
import '../widgets/app_header.dart';
import 'inventory_page.dart' as inventory_page;
import 'purchase_page.dart' as purchase_page;
import 'transaction_page.dart' as transaction_page;

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.role = UserRole.owner});

  final UserRole role;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _showGreeting = false;
  static const int _nearExpiryWindowDays = 7;

  int _lowStockThreshold(_InventoryItem item) => item.alertThresholdDays > 0 ? item.alertThresholdDays : 5;
  bool _isExpired(_InventoryItem item) => item.expiresInDays <= 0;
  bool _isNearExpiry(_InventoryItem item) => item.expiresInDays > 0 && item.expiresInDays <= _nearExpiryWindowDays;
  bool _isLowStock(_InventoryItem item) => item.quantity <= _lowStockThreshold(item);

  Stream<_TodayTotals> _todayProfitStream() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));

    return FirebaseFirestore.instance
        .collection('transactions')
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('timestamp', isLessThan: Timestamp.fromDate(end))
        .snapshots()
        .map((snap) {
      double sales = 0;
      double purchases = 0;
      for (final doc in snap.docs) {
        final data = doc.data() as Map<String, dynamic>? ?? {};
        final type = (data['type'] ?? 'sale') as String;
        final qty = ((data['qty'] ?? 0) as num).toInt();
        final amount = (data['amount'] ?? 0).toDouble();
        final purchasePrice = (data['purchasePrice'] ?? 0).toDouble();
        final sellingPrice = (data['sellingPrice'] ?? 0).toDouble();

        final effectiveAmount = amount != 0
            ? amount
            : (type == 'purchase' ? purchasePrice * qty : sellingPrice * qty);

        if (type == 'sale') {
          sales += effectiveAmount;
        } else {
          purchases += effectiveAmount;
        }
      }
      return _TodayTotals(sales: sales, purchases: purchases);
    });
  }

  Stream<List<_InventoryItem>> _inventoryStream() {
    return FirebaseFirestore.instance
        .collection('inventory')
        .snapshots()
        .map((snap) => snap.docs.map((d) => _InventoryItem.fromDoc(d)).toList());
  }

  @override
  void initState() {
    super.initState();
    // Trigger a light intro motion for the greeting on first build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() => _showGreeting = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final canViewReports = widget.role == UserRole.owner;
    final currentUser = StoreRepository.instance.currentUser;
    final firstName = (currentUser?.firstName ?? '').trim();
    final greeting = firstName.isEmpty ? 'Welcome!' : 'Welcome, $firstName!';

    return Scaffold(
      appBar: buildAppBarWithLogoutAndNotifications(
        context: context,
        title: 'Shelf Life Tracker',
        role: widget.role,
      ),
      body: StreamBuilder<List<_InventoryItem>>(
        stream: _inventoryStream(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error loading inventory: ${snapshot.error}'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final items = snapshot.data ?? [];
          final totalItems = items.length;
          final nearExpiry = items.where(_isNearExpiry).length;
          final lowStock = items.where(_isLowStock).length;
          final expired = items.where(_isExpired).length;
          final expiringSoonItems = items
              .where((i) => _isNearExpiry(i) && i.quantity > 0)
              .toList()
            ..sort((a, b) => a.expiresInDays.compareTo(b.expiresInDays));

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: _showGreeting ? 1 : 0),
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOut,
                  builder: (context, value, child) {
                    return Opacity(
                      opacity: value,
                      child: Transform.translate(
                        offset: Offset(0, (1 - value) * 12),
                        child: child,
                      ),
                    );
                  },
                  child: Text(
                    greeting,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 4),
                const Text("Here's what's happening in your store today"),
                const SizedBox(height: 16),

                // Remove the unified container and add horizontally scrollable cards
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _StatCard('Total Items', totalItems.toString(), Icons.inventory, Colors.blue),
                      const SizedBox(width: 12),
                      _StatCard('Near Expiry', nearExpiry.toString(), Icons.timer, Colors.orange),
                      const SizedBox(width: 12),
                      _StatCard('Low Stock', lowStock.toString(), Icons.warning, Colors.amber),
                      const SizedBox(width: 12),
                      _StatCard('Expired', expired.toString(), Icons.close, Colors.red),
                    ],
                  ),
                ),

                if (canViewReports) ...[
                  const SizedBox(height: 16),
                  StreamBuilder<_TodayTotals>(
                    stream: _todayProfitStream(),
                    builder: (context, snap) {
                      final totals = snap.data ?? const _TodayTotals(sales: 0, purchases: 0);
                      final profit = totals.sales - totals.purchases;
                      final loading = snap.connectionState == ConnectionState.waiting;

                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Today\'s Profit', style: TextStyle(color: Colors.white)),
                                  const SizedBox(height: 4),
                                  Text(
                                    loading ? '...' : 'Birr ${profit.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    loading
                                        ? ''
                                        : 'Sales:  ${totals.sales.toStringAsFixed(2)}  •  Purchases:  ${totals.purchases.toStringAsFixed(2)}',
                                    style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              fit: FlexFit.loose,
                              child: ElevatedButton(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (context) => const report_page.StoreOwnerReportsPage()),
                                  );
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: Colors.green,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                ),
                                child: const Text('View Details'),
                              ),
                            ),
                          ],
                        ),
                      );
                      }
                  )
                    
                ],

                const SizedBox(height: 20),
                const Text(
                  'Quick Actions',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                if (canViewReports)
                  Row(
                    children: [
                      Expanded(
                        child: _ActionButton(
                          icon: Icons.add,
                          label: 'Add Item/ Purchase',
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const purchase_page.PurchasePage()),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _ActionButton(
                          icon: Icons.attach_money,
                          label: 'Record Sale',
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => transaction_page.TransactionsPage(role: widget.role)),
                            );
                          },
                        ),
                      ),
                    ],
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: _ActionButton(
                          icon: Icons.attach_money,
                          label: 'Record Sale',
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => transaction_page.TransactionsPage(role: widget.role)),
                            );
                          },
                        ),
                      ),
                    ],
                  ),

                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Expiring Soon',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),

                const SizedBox(height: 12),
                ...expiringSoonItems.map((i) => _ExpiryItem(
                      name: i.name,
                      subtitle: '${i.category} • Qty: ${i.quantity}',
                      daysLeft: i.expiresInDays <= 0 ? 'Expired' : '${i.expiresInDays} days',
                    )),
              ],
            ),
          );
        },
      ),

      bottomNavigationBar: buildBottomNav(
        context: context,
        role: widget.role,
        activeTab: AppTab.home,
        destinationBuilder: (tab) {
          switch (tab) {
            case AppTab.home:
              return HomePage(role: widget.role);
            case AppTab.inventory:
              return inventory_page.InventoryPage(role: widget.role);
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
}

class StoreOwnerHomePage extends StatelessWidget {
  const StoreOwnerHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const HomePage(role: UserRole.owner);
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard(this.title, this.value, this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Container(
        width: 140,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 18),
            Text(
              value,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(title, style: const TextStyle(fontSize: 15)),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, size: 30),
            const SizedBox(height: 8),
            Text(label),
          ],
        ),
      ),
    );
  }
}

class _InventoryItem {
  final String id;
  final String name;
  final String category;
  final int quantity;
  final int expiresInDays;
  final int alertThresholdDays;

  _InventoryItem({
    required this.id,
    required this.name,
    required this.category,
    required this.quantity,
    required this.expiresInDays,
    required this.alertThresholdDays,
  });

  factory _InventoryItem.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return _InventoryItem(
      id: doc.id,
      name: (data['name'] ?? '') as String,
      category: (data['category'] ?? '') as String,
      quantity: ((data['quantity'] ?? 0) as num).toInt(),
      expiresInDays: ((data['expiresInDays'] ?? 0) as num).toInt(),
      alertThresholdDays: ((data['alertThresholdDays'] ?? 3) as num).toInt(),
    );
  }
}

class _TodayTotals {
  const _TodayTotals({required this.sales, required this.purchases});

  final double sales;
  final double purchases;
}

class _ExpiryItem extends StatelessWidget {
  final String name;
  final String subtitle;
  final String daysLeft;

  const _ExpiryItem({
    required this.name,
    required this.subtitle,
    required this.daysLeft,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(name),
        subtitle: Text(subtitle),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.red.shade100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            daysLeft,
            style: const TextStyle(color: Colors.red),
          ),
        ),
      ),
    );
  }
}
