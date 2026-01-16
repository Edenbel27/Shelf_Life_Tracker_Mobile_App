import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../Repository/store_repository.dart';
import '../login_page.dart' as login_page;
import '../notifications_page.dart';

PreferredSizeWidget buildAppBarWithLogoutAndNotifications({
  required BuildContext context,
  required String title,
  UserRole role = UserRole.owner,
  List<Widget> extraActions = const [],
  Widget? leading,
}) {
  return AppBar(
    title: Text(title),
    leading: leading,
    actions: [
      ...extraActions,
      IconButton(
        icon: const Icon(Icons.logout),
        tooltip: 'Logout',
        onPressed: () => _handleLogout(context),
      ),
      _NotificationsButton(role: role),
    ],
  );
}

Future<void> _handleLogout(BuildContext context) async {
  await FirebaseAuth.instance.signOut();
  if (!context.mounted) return;
  Navigator.pushAndRemoveUntil(
    context,
    MaterialPageRoute(builder: (_) => const login_page.LoginPage()),
    (route) => false,
  );
}

class _NotificationsButton extends StatelessWidget {
  const _NotificationsButton({required this.role});

  final UserRole role;

  @override
  Widget build(BuildContext context) {
    final pendingStream = FirebaseFirestore.instance
        .collection('users')
        .where('approved', isEqualTo: false)
        .snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: role == UserRole.owner ? pendingStream : null,
      builder: (context, snapshot) {
        final hasPending = role == UserRole.owner && snapshot.hasData && snapshot.data!.docs.isNotEmpty;
        return Stack(
          children: [
            IconButton(
              icon: const Icon(Icons.notifications_none_outlined),
              tooltip: 'Notifications',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => NotificationsPage(role: role)),
                );
              },
            ),
            if (hasPending)
              Positioned(
                right: 12,
                top: 12,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                ),
              ),
          ],
        );
      },
    );
  }
}
