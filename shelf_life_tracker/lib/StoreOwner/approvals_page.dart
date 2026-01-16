import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../widgets/app_header.dart';

class ApprovalsPage extends StatefulWidget {
  const ApprovalsPage({super.key});

  @override
  State<ApprovalsPage> createState() => _ApprovalsPageState();
}

class _ApprovalsPageState extends State<ApprovalsPage> {
  @override
  Widget build(BuildContext context) {
    final pendingStaffStream = FirebaseFirestore.instance
      .collection('users')
      .where('approved', isEqualTo: false)
      .snapshots();

    return Scaffold(
      appBar: buildAppBarWithLogoutAndNotifications(
        context: context,
        title: 'Shelf Life Tracker',
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Approvals', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: pendingStaffStream,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(child: Text('Error loading pending staff: ${snapshot.error}'));
                  }
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return const Center(child: Text('No pending staff requests.'));
                  }
                  final pending = snapshot.data!.docs;
                  return ListView.separated(
                    itemCount: pending.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final u = pending[index].data() as Map<String, dynamic>;
                      final docId = pending[index].id;
                      return Card(
                        child: ListTile(
                          title: Text('${u['firstName'] ?? ''} ${u['lastName'] ?? ''}'.trim().isEmpty
                              ? 'Pending user'
                              : '${u['firstName'] ?? ''} ${u['lastName'] ?? ''}'.trim()),
                          subtitle: Text('${u['email'] ?? ''}${u['phone'] != null && (u['phone'] as String).isNotEmpty ? ' • ${u['phone'] as String}' : ''}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.check, color: Colors.green),
                                tooltip: 'Approve',
                                onPressed: () async {
                                  await FirebaseFirestore.instance.collection('users').doc(docId).update({'approved': true});
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, color: Colors.red),
                                tooltip: 'Reject',
                                onPressed: () async {
                                  await FirebaseFirestore.instance.collection('users').doc(docId).delete();
                                },
                              ),
                            ],
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
