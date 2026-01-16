import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../Repository/store_repository.dart';
import '../login_page.dart' as login_page;
import '../pages/home_page.dart' as home_page;
import '../pages/inventory_page.dart' as inventory_page;
import '../pages/transaction_page.dart' as transaction_page;
import '../StoreOwner/report_page.dart' as report_page;
import '../StoreOwner/staff_management_page.dart' as staff_management;
import '../navigation.dart';
import '../widgets/app_header.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, this.role = UserRole.owner});

  final UserRole role;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _loadingProfile = false;
  bool _savingProfile = false;
  String? _profileError;
  String _emailDisplay = '';

  late final TextEditingController _firstNameCtrl;
  late final TextEditingController _lastNameCtrl;
  late final TextEditingController _phoneCtrl;
  final _oldPasswordCtrl = TextEditingController();
  final _newPasswordCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final repoUser = StoreRepository.instance.currentUser;
    _firstNameCtrl = TextEditingController(text: repoUser?.firstName ?? '');
    _lastNameCtrl = TextEditingController(text: repoUser?.lastName ?? '');
    _phoneCtrl = TextEditingController(text: repoUser?.phone ?? '');
    _emailDisplay = repoUser?.email ?? FirebaseAuth.instance.currentUser?.email ?? '';
    _initProfile();
  }

  Future<void> _initProfile() async {
    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null) {
      return;
    }

    setState(() {
      _loadingProfile = true;
      _profileError = null;
    });

    try {
      final snap = await FirebaseFirestore.instance.collection('users').doc(authUser.uid).get();
      if (!snap.exists) {
        setState(() {
          _profileError = 'Profile not found for this account.';
        });
        return;
      }
      final data = snap.data() ?? {};
      _emailDisplay = data['email'] as String? ?? authUser.email ?? _emailDisplay;
      _firstNameCtrl.text = data['firstName'] as String? ?? _firstNameCtrl.text;
      _lastNameCtrl.text = data['lastName'] as String? ?? _lastNameCtrl.text;
      _phoneCtrl.text = data['phone'] as String? ?? _phoneCtrl.text;
    } catch (e) {
      setState(() {
        _profileError = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingProfile = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _phoneCtrl.dispose();
    _oldPasswordCtrl.dispose();
    _newPasswordCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    final first = _firstNameCtrl.text.trim();
    final last = _lastNameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    if (first.isEmpty || last.isEmpty || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter first name, last name and phone')));
      return;
    }
    try {
      setState(() {
        _savingProfile = true;
      });

      // Update local demo store if present
      if (StoreRepository.instance.currentUser != null) {
        await StoreRepository.instance.updateCurrentUserProfile(firstName: first, lastName: last, phone: phone);
      }

      // Update Firestore profile for authenticated users
      final authUser = FirebaseAuth.instance.currentUser;
      if (authUser != null) {
        await FirebaseFirestore.instance.collection('users').doc(authUser.uid).set({
          'firstName': first,
          'lastName': last,
          'phone': phone,
        }, SetOptions(merge: true));
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated')));
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) {
        setState(() {
          _savingProfile = false;
        });
      }
    }
  }

  Future<void> _changePassword() async {
    final oldPwd = _oldPasswordCtrl.text;
    final newPwd = _newPasswordCtrl.text;
    if (oldPwd.isEmpty || newPwd.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill both password fields')));
      return;
    }
    bool isStrongPassword(String value) {
      if (value.length < 8) return false;
      final hasUpper = RegExp(r'[A-Z]').hasMatch(value);
      final hasLower = RegExp(r'[a-z]').hasMatch(value);
      final hasDigit = RegExp(r'\d').hasMatch(value);
      final hasSymbol = RegExp(r'[!@#\$%^&*(),.?":{}|<>\-_=+]').hasMatch(value);
      return hasUpper && hasLower && hasDigit && hasSymbol;
    }

    if (!isStrongPassword(newPwd)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('New password must be 8+ chars with upper, lower, number, and symbol')),
      );
      return;
    }
    try {
      // Update FirebaseAuth password with re-authentication
      final authUser = FirebaseAuth.instance.currentUser;
      if (authUser == null) {
        throw Exception('You must be logged in to change password.');
      }

      final email = authUser.email ?? _emailDisplay;
      if (email.isEmpty) {
        throw Exception('No email associated with this account.');
      }

      final credential = EmailAuthProvider.credential(email: email, password: oldPwd);
      await authUser.reauthenticateWithCredential(credential);
      await authUser.updatePassword(newPwd);

      // Update local repository user if present
      if (StoreRepository.instance.currentUser != null) {
        await StoreRepository.instance.updateCurrentUserPassword(oldPassword: oldPwd, newPassword: newPwd);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password updated')));
      _oldPasswordCtrl.clear();
      _newPasswordCtrl.clear();
    } catch (e) {
      if (!mounted) return;
      String msg = e.toString();
      if (msg.contains('wrong-password')) {
        msg = 'Old password is incorrect.';
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final repoUser = StoreRepository.instance.currentUser;
    final authUser = FirebaseAuth.instance.currentUser;
    final isLoggedIn = repoUser != null || authUser != null;

    if (!isLoggedIn) {
      return Scaffold(
        appBar: buildAppBarWithLogoutAndNotifications(
          context: context,
          title: 'Settings',
          role: widget.role,
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('You are not logged in.'),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const login_page.LoginPage()),
                  );
                },
                child: const Text('Go to Login'),
              ),
            ],
          ),
        ),
      );
    }

    final email = _emailDisplay.isNotEmpty ? _emailDisplay : (repoUser?.email ?? authUser?.email ?? '');

    return Scaffold(
      appBar: buildAppBarWithLogoutAndNotifications(
        context: context,
        title: 'Shelf Life Tracker',
        role: widget.role,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Settings', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (widget.role == UserRole.owner) ...[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const staff_management.StaffManagementPage()),
                    );
                  },
                  icon: const Icon(Icons.group_remove),
                  label: const Text('Manage Staff Access'),
                ),
              ),
              const SizedBox(height: 12),
            ],
            const Text('Profile', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Email: $email'),
            if (_profileError != null) ...[
              const SizedBox(height: 6),
              Text(_profileError!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _firstNameCtrl,
              decoration: const InputDecoration(labelText: 'First Name', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _lastNameCtrl,
              decoration: const InputDecoration(labelText: 'Last Name', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone Number', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _loadingProfile || _savingProfile ? null : _saveProfile,
                icon: const Icon(Icons.save),
                label: _savingProfile
                    ? const Text('Saving...')
                    : const Text('Save Profile'),
              ),
            ),
            const Divider(height: 32),
            const Text('Change Password', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _oldPasswordCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Old Password', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _newPasswordCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'New Password', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _changePassword,
                icon: const Icon(Icons.lock_reset),
                label: const Text('Update Password'),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: buildBottomNav(
        context: context,
        role: widget.role,
        activeTab: AppTab.settings,
        destinationBuilder: (tab) {
          switch (tab) {
            case AppTab.home:
              return home_page.HomePage(role: widget.role);
            case AppTab.inventory:
              return inventory_page.InventoryPage(role: widget.role);
            case AppTab.transactions:
              return transaction_page.TransactionsPage(role: widget.role);
            case AppTab.reports:
              return const report_page.StoreOwnerReportsPage();
            case AppTab.settings:
              return SettingsPage(role: widget.role);
          }
        },
      ),
    );
  }
}
