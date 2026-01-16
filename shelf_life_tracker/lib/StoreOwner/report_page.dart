import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../Repository/store_repository.dart' show UserRole;
import '../Settings/settings_page.dart' as settings_page;
import '../navigation.dart';
import '../pages/home_page.dart' as home_page;
import '../pages/inventory_page.dart' as inventory_page;
import '../pages/transaction_page.dart' as transaction_page;
import '../widgets/app_header.dart';

class StoreOwnerReportsPage extends StatefulWidget {
  const StoreOwnerReportsPage({super.key});

  @override
  State<StoreOwnerReportsPage> createState() => _StoreOwnerReportsPageState();
}

class _StoreOwnerReportsPageState extends State<StoreOwnerReportsPage> {
  bool _savingSnapshot = false;
  bool _snapshotSavedToday = false;
  bool _purgingOld = false;

  @override
  void initState() {
    super.initState();
    _checkTodaySnapshot();
    _purgeOldData();
  }

  String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Stream<List<_TransactionRecord>> _transactionsStream() {
    return FirebaseFirestore.instance
        .collection('transactions')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(_TransactionRecord.fromDoc).toList());
  }

  _PastDaySummary _pastDayFromHistory(List<_TransactionRecord> history) {
    final now = DateTime.now();
    final yesterdayStart = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 1));
    final yesterdayEnd = DateTime(now.year, now.month, now.day);

    double sales = 0;
    double purchases = 0;
    int count = 0;

    for (final h in history) {
      if (h.timestamp == null || h.timestamp!.isBefore(yesterdayStart) || h.timestamp!.isAfter(yesterdayEnd)) {
        continue;
      }
      count++;
      final amt = h.effectiveAmount;
      if (h.type == 'sale') {
        sales += amt;
      } else {
        purchases += amt;
      }
    }

    return _PastDaySummary(
      totalSales: sales,
      totalPurchases: purchases,
      profit: sales - purchases,
      transactions: count,
    );
  }

  Future<void> _savePastDaySnapshot(_PastDaySummary summary) async {
    if (_savingSnapshot) return;
    setState(() => _savingSnapshot = true);
    final key = _todayKey();
    try {
      await FirebaseFirestore.instance.collection('daily_reports').doc(key).set({
        'date': key,
        'totalSales': summary.totalSales,
        'totalPurchases': summary.totalPurchases,
        'profit': summary.profit,
        'transactions': summary.transactions,
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        setState(() => _snapshotSavedToday = true);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Past-day snapshot saved')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _savingSnapshot = false);
    }
  }

  Future<void> _checkTodaySnapshot() async {
    final key = _todayKey();
    try {
      final doc = await FirebaseFirestore.instance.collection('daily_reports').doc(key).get();
      if (mounted && doc.exists) {
        setState(() => _snapshotSavedToday = true);
      }
    } catch (_) {
      // ignore; permission errors are handled on save
    }
  }

  Future<void> _purgeOldData() async {
    if (_purgingOld) return;
    setState(() => _purgingOld = true);
    final cutoff = DateTime.now().subtract(const Duration(hours: 24));
    final cutoffTs = Timestamp.fromDate(cutoff);
    try {
      await _deleteWhere('transactions', 'timestamp', cutoffTs);
      await _deleteWhere('daily_reports', 'createdAt', cutoffTs);
    } catch (_) {
      // ignore silently; saves are still guarded by rules
    } finally {
      if (mounted) setState(() => _purgingOld = false);
    }
  }

  Future<void> _deleteWhere(String collection, String field, Timestamp cutoffTs) async {
    const int batchSize = 20;
    while (true) {
      final snap = await FirebaseFirestore.instance
          .collection(collection)
          .where(field, isLessThan: cutoffTs)
          .limit(batchSize)
          .get();

      if (snap.docs.isEmpty) break;

      final batch = FirebaseFirestore.instance.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      if (snap.docs.length < batchSize) break;
    }
  }

  List<_SellingItem> _topSellingFromHistory(List<_TransactionRecord> history) {
    final Map<String, int> counts = {};
    final Map<String, double> totals = {};
    for (final h in history) {
      if (h.type != 'sale') continue;
      counts[h.name] = (counts[h.name] ?? 0) + h.qty;
      totals[h.name] = (totals[h.name] ?? 0) + h.effectiveAmount;
    }

    final entries = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return List.generate(entries.length, (i) {
      final name = entries[i].key;
      final qty = entries[i].value;
      final total = totals[name] ?? 0;
      return _SellingItem(
        rank: i + 1,
        name: name,
        detail: '$qty units sold',
        price: 'Birr ${total.toStringAsFixed(2)}',
      );
    }).take(3).toList();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<_TransactionRecord>>(
      stream: _transactionsStream(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Scaffold(
            appBar: buildAppBarWithLogoutAndNotifications(
              context: context,
              title: 'Shelf Life Tracker',
              role: UserRole.owner,
            ),
            body: Center(child: Text('Error loading reports: ${snap.error}')),
          );
        }
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        final history = snap.data ?? [];
        final cutoff = DateTime.now().subtract(const Duration(hours: 24));
        final recent = history.where((h) => h.timestamp == null || h.timestamp!.isAfter(cutoff)).toList();
        double totalSales = 0;
        double totalPurchases = 0;
        for (final h in recent) {
          final amt = h.effectiveAmount;
          if (h.type == 'sale') {
            totalSales += amt;
          } else {
            totalPurchases += amt;
          }
        }

        // final profit = totalSales - totalPurchases;
        // final txCount = recent.length;
        final topSelling = _topSellingFromHistory(recent);
        final pastDay = _pastDayFromHistory(recent);

        // Calculate today's sales and expenses for the cards
        final todayStart = DateTime.now();
        final todayRangeStart = DateTime(todayStart.year, todayStart.month, todayStart.day);
        final todayRangeEnd = todayRangeStart.add(const Duration(days: 1));
        final todayTransactions = history.where((h) =>
          h.timestamp != null &&
          h.timestamp!.isAfter(todayRangeStart) &&
          h.timestamp!.isBefore(todayRangeEnd)
        ).toList();
        double todaySales = 0;
        double todayPurchases = 0;
        for (final h in todayTransactions) {
          final amt = h.effectiveAmount;
          if (h.type == 'sale') {
            todaySales += amt;
          } else {
            todayPurchases += amt;
          }
        }
        final todayProfit = todaySales - todayPurchases;
        final todayTxCount = todayTransactions.length;

        return Scaffold(
          appBar: buildAppBarWithLogoutAndNotifications(
            context: context,
            title: 'Shelf Life Tracker',
            role: UserRole.owner,
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Column(
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Reports', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 8),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F9D58),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Today\'s Profit', style: TextStyle(color: Colors.white.withOpacity(0.8))),
                      const SizedBox(height: 6),
                      Text(
                        'Birr ${todayProfit.toStringAsFixed(2)}',
                        style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: _MiniMetric(label: 'Transactions', value: todayTxCount.toString()),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                _SectionCard(
                  title: 'Yesterday\'s Summary',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: _MiniMetric(label: 'Sales', value: 'Birr ${pastDay.totalSales.toStringAsFixed(2)}', color: Colors.black87)),
                          Expanded(child: _MiniMetric(label: 'Purchases', value: 'Birr ${pastDay.totalPurchases.toStringAsFixed(2)}', color: Colors.black87)),
                          Expanded(child: _MiniMetric(label: 'Profit', value: 'Birr ${pastDay.profit.toStringAsFixed(2)}', color: Colors.black87)),
                          Expanded(child: _MiniMetric(label: 'Transactions', value: pastDay.transactions.toString(), color: Colors.black87)),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                Row(
                  children: [
                    Expanded(
                      child: _StatTile(
                        title: 'Total Sales',
                        value: 'Birr ${todaySales.toStringAsFixed(2)}',
                        change: '',
                        changePositive: true,
                        accent: Colors.blue,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StatTile(
                        title: 'Total Expenses',
                        value: 'Birr ${todayPurchases.toStringAsFixed(2)}',
                        change: '',
                        changePositive: false,
                        accent: const Color(0xFFFF7043),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                _SectionCard(
                  title: 'Top Selling Items',
                  child: Column(
                    children: topSelling.isEmpty
                        ? [const Padding(padding: EdgeInsets.all(8), child: Text('No sales yet'))]
                        : topSelling
                            .map((item) => Column(
                                  children: [
                                    ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: Colors.blue.shade50,
                                        child: Text('${item.rank}', style: const TextStyle(color: Colors.blue)),
                                      ),
                                      title: Text(item.name),
                                      subtitle: Text(item.detail),
                                      trailing: Text(item.price, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.green)),
                                    ),
                                    if (item != topSelling.last) const Divider(height: 1, color: Colors.grey),
                                  ],
                                ))
                            .toList(),
                  ),
                ),
              ],
            ),
          ),

          bottomNavigationBar: buildBottomNav(
            context: context,
            role: UserRole.owner,
            activeTab: AppTab.reports,
            destinationBuilder: (tab) {
              switch (tab) {
                case AppTab.home:
                  return home_page.HomePage(role: UserRole.owner);
                case AppTab.inventory:
                  return inventory_page.InventoryPage(role: UserRole.owner);
                case AppTab.transactions:
                  return const transaction_page.TransactionsPage(role: UserRole.owner);
                case AppTab.reports:
                  return const StoreOwnerReportsPage();
                case AppTab.settings:
                  return const settings_page.SettingsPage(role: UserRole.owner);
              }
            },
          ),
        );
      },
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.title,
    required this.value,
    required this.change,
    required this.changePositive,
    required this.accent,
  });

  final String title;
  final String value;
  final String change;
  final bool changePositive;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final changeColor = changePositive ? Colors.green : Colors.red;
    final changeIcon = changePositive ? Icons.arrow_upward : Icons.arrow_downward;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withOpacity(0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: Colors.grey.shade700)),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(changeIcon, size: 16, color: changeColor),
              const SizedBox(width: 4),
              Text(change, style: TextStyle(color: changeColor, fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final textColor = color ?? Colors.white;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: textColor.withOpacity(0.85))),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

class _PastDaySummary {
  const _PastDaySummary({
    required this.totalSales,
    required this.totalPurchases,
    required this.profit,
    required this.transactions,
  });

  final double totalSales;
  final double totalPurchases;
  final double profit;
  final int transactions;
}

class _SellingItem {
  const _SellingItem({required this.rank, required this.name, required this.detail, required this.price});

  final int rank;
  final String name;
  final String detail;
  final String price;
}

class _TransactionRecord {
  const _TransactionRecord({
    required this.id,
    required this.name,
    required this.type,
    required this.qty,
    required this.amount,
    required this.purchasePrice,
    required this.sellingPrice,
    required this.timestamp,
  });

  final String id;
  final String name;
  final String type;
  final int qty;
  final double amount;
  final double purchasePrice;
  final double sellingPrice;
  final DateTime? timestamp;

  double get effectiveAmount {
    if (amount != 0) return amount;
    if (type == 'purchase') {
      return purchasePrice * qty;
    }
    return sellingPrice * qty;
  }

  factory _TransactionRecord.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final ts = data['timestamp'];
    return _TransactionRecord(
      id: doc.id,
      name: (data['name'] ?? '') as String,
      type: (data['type'] ?? 'sale') as String,
      qty: ((data['qty'] ?? 0) as num).toInt(),
      amount: (data['amount'] ?? 0).toDouble(),
      purchasePrice: (data['purchasePrice'] ?? 0).toDouble(),
      sellingPrice: (data['sellingPrice'] ?? 0).toDouble(),
      timestamp: ts is Timestamp ? ts.toDate() : null,
    );
  }
}