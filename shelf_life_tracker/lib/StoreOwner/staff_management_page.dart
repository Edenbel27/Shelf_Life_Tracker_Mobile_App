import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../widgets/app_header.dart';

class StaffManagementPage extends StatefulWidget {
  const StaffManagementPage({super.key});

  @override
  State<StaffManagementPage> createState() => _StaffManagementPageState();
}

class _StaffManagementPageState extends State<StaffManagementPage> {
  Stream<List<_StaffMember>> _staffStream() {
    return FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'staff')
        .where('approved', isEqualTo: true)
        .snapshots()
        .map((snap) => snap.docs.map(_StaffMember.fromDoc).toList());
  }

  Future<void> _deleteStaff(_StaffMember user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Staff'),
        content: Text('Remove ${user.displayName} so they can no longer log in?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await FirebaseFirestore.instance.collection('users').doc(user.id).delete();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${user.displayName} removed')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to remove: ${e.toString()}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildAppBarWithLogoutAndNotifications(
        context: context,
        title: 'Staff Management',
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Approved Staff', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Remove staff to revoke their access. Pending requests stay in Approvals.'),
            const SizedBox(height: 12),
            Expanded(
              child: StreamBuilder<List<_StaffMember>>(
                stream: _staffStream(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(child: Text('Error loading staff: ${snapshot.error}'));
                  }
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final staff = snapshot.data ?? [];
                  if (staff.isEmpty) {
                    return const Center(child: Text('No staff members yet.'));
                  }

                  return ListView.separated(
                    itemCount: staff.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final user = staff[index];
                      return Card(
                        child: ListTile(
                          title: Text(user.displayName),
                          subtitle: Text(user.email + (user.phone.isNotEmpty ? ' • ${user.phone}' : '')),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _deleteStaff(user),
                            tooltip: 'Remove staff',
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StaffMember {
  const _StaffMember({required this.id, required this.firstName, required this.lastName, required this.email, required this.phone});

  final String id;
  final String firstName;
  final String lastName;
  final String email;
  final String phone;

  String get displayName {
    final name = ('$firstName $lastName').trim();
    return name.isEmpty ? email : name;
  }

  factory _StaffMember.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return _StaffMember(
      id: doc.id,
      firstName: (data['firstName'] ?? '') as String,
      lastName: (data['lastName'] ?? '') as String,
      email: (data['email'] ?? '') as String,
      phone: (data['phone'] ?? '') as String,
    );
  }
}
