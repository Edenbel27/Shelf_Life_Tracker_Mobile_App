import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../Repository/store_repository.dart' show UserRole;
import '../navigation.dart';
import '../StoreOwner/report_page.dart' as report_page;
import 'inventory_page.dart' as inventory_page;
import 'transaction_page.dart' as transaction_page;
import '../notifications_page.dart';
import '../login_page.dart' as login_page;
import 'purchase_page.dart' as purchase_page;
import '../Settings/settings_page.dart' as settings_page;

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.role = UserRole.owner});

  final UserRole role;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _showAllExpiring = false;

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
  Widget build(BuildContext context) {
    final canViewReports = widget.role == UserRole.owner;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Shelf Life Tracker'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (!context.mounted) return;
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const login_page.LoginPage()),
                (route) => false,
              );
            },
          ),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .where('approved', isEqualTo: false)
                .snapshots(),
            builder: (context, snapshot) {
              final hasPending = canViewReports && snapshot.hasData && snapshot.data!.docs.isNotEmpty;
              return Stack(
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications_none),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => NotificationsPage(role: widget.role)),
                      ).then((_) {
                        if (mounted) setState(() {});
                      });
                    },
                  ),
                  if (hasPending)
                    Positioned(
                      right: 12,
                      top: 12,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
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
          final nearExpiry = items.where((i) => i.expiresInDays <= i.alertThresholdDays && i.quantity > 0).length;
          final lowStock = items.where((i) => i.quantity < 5 && i.quantity > 0).length;
          final expired = items.where((i) => i.expiresInDays <= 0).length;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  ' Welcome Back!',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                const Text("Here's what's happening in your store today"),
                const SizedBox(height: 16),

                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  children: [
                    _StatCard('Total Items', totalItems.toString(), Icons.inventory, Colors.blue),
                    _StatCard('Near Expiry', nearExpiry.toString(), Icons.timer, Colors.orange),
                    _StatCard('Low Stock', lowStock.toString(), Icons.warning, Colors.amber),
                    _StatCard('Expired', expired.toString(), Icons.close, Colors.red),
                  ],
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
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
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
                            ElevatedButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (context) => const report_page.StoreOwnerReportsPage()),
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.green,
                              ),
                              child: const Text('View Details'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
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
                    TextButton(
                      onPressed: () => setState(() => _showAllExpiring = !_showAllExpiring),
                      child: Text(_showAllExpiring ? 'Show 3' : 'View All'),
                    ),
                  ],
                ),

                const SizedBox(height: 12),
                ...items
                    .where((i) => i.expiresInDays <= i.alertThresholdDays && i.quantity > 0)
                    .toList()
                    .asMap()
                    .entries
                    .where((e) => _showAllExpiring || e.key < 3)
                    .map((e) => e.value)
                    .map((i) => _ExpiryItem(
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const Spacer(),
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          Text(title),
        ],
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
