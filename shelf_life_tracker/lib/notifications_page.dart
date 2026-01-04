import 'package:flutter/material.dart';
import 'Repository/store_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

const int _nearExpiryWindowDays = 7;

int _lowStockThreshold(InventoryItem item) => item.alertThresholdDays > 0 ? item.alertThresholdDays : 5;
bool _isExpired(InventoryItem item) => item.expiresInDays <= 0;
bool _isNearExpiry(InventoryItem item) => item.expiresInDays > 0 && item.expiresInDays <= _nearExpiryWindowDays;
bool _isLowStock(InventoryItem item) => item.quantity <= _lowStockThreshold(item);

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key, this.role = UserRole.owner});
  final UserRole role;

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  Stream<List<InventoryItem>> _inventoryStream() {
    return FirebaseFirestore.instance
        .collection('inventory')
        .orderBy('nameLower')
        .snapshots()
        .map((snap) => snap.docs.map(_inventoryFromDoc).toList());
  }

  @override
  Widget build(BuildContext context) {
    final isOwner = widget.role == UserRole.owner;
    final pendingStaffStream = FirebaseFirestore.instance
      .collection('users')
      .where('approved', isEqualTo: false)
      .snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text('Shelf Life Tracker')),
      body: StreamBuilder<List<InventoryItem>>(
        stream: _inventoryStream(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error loading inventory: ${snapshot.error}'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final items = snapshot.data ?? const <InventoryItem>[];
          final expired = items.where(_isExpired).toList();
          final nearExpiry = items.where(_isNearExpiry).toList();
          final lowStock = items.where(_isLowStock).toList();

          return SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Notifications', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                if (isOwner) ...[
                  const Text('Pending Approvals', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  StreamBuilder<QuerySnapshot>(
                    stream: pendingStaffStream,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return _EmptyRow('Error loading pending staff: ${snapshot.error}');
                      }
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return _EmptyRow('No pending staff requests.');
                      }
                      final pendingDocs = snapshot.data!.docs;
                      return _ApprovalsList(
                        pending: pendingDocs,
                        onApprove: (docId) async {
                          await FirebaseFirestore.instance
                              .collection('users')
                              .doc(docId)
                              .update({'approved': true});
                        },
                        onReject: (docId) async {
                          await FirebaseFirestore.instance
                              .collection('users')
                              .doc(docId)
                              .delete();
                        },
                      );
                    },
                  ),
                  const Divider(height: 24),
                ],

                const Text('Expired Items', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                if (expired.isEmpty) _EmptyRow('No expired items') else _ItemList(items: expired, color: Colors.red),
                const SizedBox(height: 16),

                const Text('Near Expiry (next 7 days)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                if (nearExpiry.isEmpty) _EmptyRow('No items near expiry') else _ItemList(items: nearExpiry, color: Colors.orange),
                const SizedBox(height: 16),

                const Text('Low Stock', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                if (lowStock.isEmpty) _EmptyRow('No low stock items') else _ItemList(items: lowStock, color: Colors.amber),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _EmptyRow extends StatelessWidget {
  final String text;
  const _EmptyRow(this.text);
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Colors.grey),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _ItemList extends StatelessWidget {
  final List<InventoryItem> items;
  final Color color;
  const _ItemList({required this.items, required this.color});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final it = items[i];
        String subtitle = '${it.category} • Qty: ${it.quantity}';
        return Card(
          child: ListTile(
            leading: CircleAvatar(backgroundColor: color.withOpacity(0.15), child: Icon(Icons.notifications, color: color)),
            title: Text(it.name),
            subtitle: Text(subtitle),
            trailing: _StatusPill(item: it),
          ),
        );
      },
    );
  }
}

class _StatusPill extends StatelessWidget {
  final InventoryItem item;
  const _StatusPill({required this.item});
  @override
  Widget build(BuildContext context) {
    String label;
    Color bg;
    Color fg;
    if (_isExpired(item)) {
      label = 'Expired';
      bg = Colors.red.shade100;
      fg = Colors.red.shade800;
    } else if (_isNearExpiry(item)) {
      label = 'Near Expiry';
      bg = Colors.orange.shade100;
      fg = Colors.orange.shade800;
    } else if (_isLowStock(item)) {
      label = 'Low Stock';
      bg = Colors.amber.shade100;
      fg = Colors.amber.shade800;
    } else {
      label = 'OK';
      bg = Colors.green.shade50;
      fg = Colors.green.shade700;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Text(label, style: TextStyle(color: fg)),
    );
  }
}

InventoryItem _inventoryFromDoc(DocumentSnapshot doc) {
  final data = doc.data() as Map<String, dynamic>? ?? {};
  return InventoryItem(
    id: doc.id,
    name: (data['name'] ?? '') as String,
    category: (data['category'] ?? '') as String,
    quantity: ((data['quantity'] ?? 0) as num).toInt(),
    expiresInDays: ((data['expiresInDays'] ?? 0) as num).toInt(),
    alertThresholdDays: ((data['alertThresholdDays'] ?? 5) as num).toInt(),
    purchasePrice: (data['purchasePrice'] ?? 0).toDouble(),
    sellingPrice: (data['sellingPrice'] ?? 0).toDouble(),
  );
}

class _ApprovalsList extends StatelessWidget {
  final List<QueryDocumentSnapshot> pending;
  final Future<void> Function(String docId) onApprove;
  final Future<void> Function(String docId) onReject;
  const _ApprovalsList({required this.pending, required this.onApprove, required this.onReject});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: pending.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final data = pending[index].data() as Map<String, dynamic>;
        final docId = pending[index].id;
        final displayName = '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'.trim();
        final email = (data['email'] ?? '') as String;
        final phone = (data['phone'] ?? '') as String;
        return Card(
          child: ListTile(
            title: Text(displayName.isEmpty ? 'Unnamed user' : displayName),
            subtitle: Text(phone.isNotEmpty ? '$email • $phone' : email),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.check, color: Colors.green),
                  tooltip: 'Approve',
                  onPressed: () => onApprove(docId),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.red),
                  tooltip: 'Reject',
                  onPressed: () => onReject(docId),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
