import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'Repository/store_repository.dart';
import 'widgets/app_header.dart';

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
      appBar: buildAppBarWithLogoutAndNotifications(
        context: context,
        title: 'Shelf Life Tracker',
        role: widget.role,
      ),
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
                if (expired.isEmpty) _EmptyRow('No expired items') else _ItemList(items: expired, color: Colors.red, forcedStatus: _Status.expired),
                const SizedBox(height: 16),

                const Text('Near Expiry', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                if (nearExpiry.isEmpty) _EmptyRow('No items near expiry') else _ItemList(items: nearExpiry, color: Colors.orange, forcedStatus: _Status.nearExpiry),
                const SizedBox(height: 16),

                const Text('Low Stock', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                if (lowStock.isEmpty) _EmptyRow('No low stock items') else _ItemList(items: lowStock, color: Colors.amber, forcedStatus: _Status.lowStock),
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
  final _Status? forcedStatus;
  const _ItemList({required this.items, required this.color, this.forcedStatus});

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
            trailing: _StatusPill(item: it, forcedStatus: forcedStatus),
          ),
        );
      },
    );
  }
}

class _StatusPill extends StatelessWidget {
  final InventoryItem item;
  final _Status? forcedStatus;
  const _StatusPill({required this.item, this.forcedStatus});

  @override
  Widget build(BuildContext context) {
    final statuses = _statusesForItem(item, forcedStatus: forcedStatus);
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: statuses.map((s) {
        final colors = _statusColors(s);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: colors.bg, borderRadius: BorderRadius.circular(12)),
          child: Text(_statusLabel(s), style: TextStyle(color: colors.fg)),
        );
      }).toList(),
    );
  }
}

enum _Status { expired, nearExpiry, lowStock, ok }

_Status _statusForItem(InventoryItem item) {
  if (_isExpired(item)) return _Status.expired;
  if (_isNearExpiry(item)) return _Status.nearExpiry;
  if (_isLowStock(item)) return _Status.lowStock;
  return _Status.ok;
}

List<_Status> _statusesForItem(InventoryItem item, {_Status? forcedStatus}) {
  final list = <_Status>[];
  if (forcedStatus != null) list.add(forcedStatus);
  if (_isExpired(item) && !list.contains(_Status.expired)) list.add(_Status.expired);
  if (_isNearExpiry(item) && !list.contains(_Status.nearExpiry)) list.add(_Status.nearExpiry);
  if (_isLowStock(item) && !list.contains(_Status.lowStock)) list.add(_Status.lowStock);
  if (list.isEmpty) list.add(_Status.ok);

  list.sort((a, b) => _statusPriority(a).compareTo(_statusPriority(b)));
  return list;
}

int _statusPriority(_Status status) {
  switch (status) {
    case _Status.expired:
      return 0;
    case _Status.nearExpiry:
      return 1;
    case _Status.lowStock:
      return 2;
    case _Status.ok:
      return 3;
  }
}

class _StatusColors {
  const _StatusColors({required this.bg, required this.fg});
  final Color bg;
  final Color fg;
}

_StatusColors _statusColors(_Status status) {
  switch (status) {
    case _Status.expired:
      return _StatusColors(bg: Colors.red.shade100, fg: Colors.red.shade800);
    case _Status.nearExpiry:
      return _StatusColors(bg: Colors.orange.shade100, fg: Colors.orange.shade800);
    case _Status.lowStock:
      return _StatusColors(bg: Colors.amber.shade100, fg: Colors.amber.shade800);
    case _Status.ok:
      return _StatusColors(bg: Colors.green.shade50, fg: Colors.green.shade700);
  }
}

String _statusLabel(_Status status) {
  switch (status) {
    case _Status.expired:
      return 'Expired';
    case _Status.nearExpiry:
      return 'Near Expiry';
    case _Status.lowStock:
      return 'Low Stock';
    case _Status.ok:
      return 'OK';
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
