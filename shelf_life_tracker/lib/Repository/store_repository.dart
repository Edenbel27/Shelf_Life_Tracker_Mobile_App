import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Shared models for store data used across pages.
@immutable
class InventoryItem {
  final String id;
  final String name;
  final String category;
  final int quantity;
  final int expiresInDays;
  final int alertThresholdDays;
  final double purchasePrice;
  final double sellingPrice;
  const InventoryItem({
    required this.id,
    required this.name,
    required this.category,
    required this.quantity,
    required this.expiresInDays,
    required this.alertThresholdDays,
    required this.purchasePrice,
    required this.sellingPrice,
  });

  InventoryItem copyWith({
    String? id,
    String? name,
    String? category,
    int? quantity,
    int? expiresInDays,
    int? alertThresholdDays,
    double? purchasePrice,
    double? sellingPrice,
  }) {
    return InventoryItem(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      quantity: quantity ?? this.quantity,
      expiresInDays: expiresInDays ?? this.expiresInDays,
      alertThresholdDays: alertThresholdDays ?? this.alertThresholdDays,
      purchasePrice: purchasePrice ?? this.purchasePrice,
      sellingPrice: sellingPrice ?? this.sellingPrice,
    );
  }
}

/// Simple user/role/approval models
enum UserRole { owner, staff }

@immutable
class AppUser {
  final String email;
  final String firstName;
  final String lastName;
  final String phone;
  final UserRole role;
  final String password; // demo only; do not store plain text in production
  final bool approved;

  const AppUser({
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.phone,
    required this.role,
    required this.password,
    required this.approved,
  });

  String get displayName => '$firstName $lastName'.trim();

  AppUser copyWith({
    String? email,
    String? firstName,
    String? lastName,
    String? phone,
    UserRole? role,
    String? password,
    bool? approved,
  }) {
    return AppUser(
      email: email ?? this.email,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      phone: phone ?? this.phone,
      role: role ?? this.role,
      password: password ?? this.password,
      approved: approved ?? this.approved,
    );
  }
}

@immutable
class TransactionHistoryEntry {
  final String name;
  final String type; // 'sale' or 'purchase'
  final int qty;
  final double amount;
  final String dateTime;
  const TransactionHistoryEntry({
    required this.name,
    required this.type,
    required this.qty,
    required this.amount,
    required this.dateTime,
  });
}

/// Simple in-memory repository to share state across pages.
class StoreRepository {
  StoreRepository._();
  static final StoreRepository instance = StoreRepository._();
  static const _usersKey = 'users';
  static const _currentUserKey = 'currentUserEmail';

  // --- Users (in-memory demo store) ---
  List<AppUser> _users = [];
  AppUser? _currentUser;

  AppUser? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_usersKey);
    if (raw == null) {
      // seed owner (growable list)
      _users = [
        const AppUser(
          email: 'owner@store.com',
          firstName: 'Store',
          lastName: 'Owner',
          phone: '+0000000000',
          role: UserRole.owner,
          password: 'owner123',
          approved: true,
        ),
      ];
      await _saveUsers();
    } else {
      final list = (jsonDecode(raw) as List)
          .map((e) => e as Map<String, dynamic>)
          .toList(growable: true);
      _users = list.map(_userFromMap).toList(growable: true);
    }

    final email = prefs.getString(_currentUserKey);
    if (email != null) {
      _currentUser = findUserByEmail(email);
    }
  }

  Future<void> _saveUsers() async {
    final prefs = await SharedPreferences.getInstance();
    final data = jsonEncode(_users.map(_userToMap).toList());
    await prefs.setString(_usersKey, data);
  }

  Future<void> _saveCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    if (_currentUser == null) {
      await prefs.remove(_currentUserKey);
    } else {
      await prefs.setString(_currentUserKey, _currentUser!.email);
    }
  }

  Map<String, dynamic> _userToMap(AppUser u) => {
        'email': u.email,
        'firstName': u.firstName,
        'lastName': u.lastName,
      'phone': u.phone,
        'role': u.role.name,
        'password': u.password,
        'approved': u.approved,
      };

  AppUser _userFromMap(Map<String, dynamic> m) => AppUser(
        email: m['email'] as String,
        firstName: m['firstName'] as String,
        lastName: m['lastName'] as String,
      phone: (m['phone'] ?? '') as String,
        role: (m['role'] as String) == 'owner' ? UserRole.owner : UserRole.staff,
        password: m['password'] as String,
        approved: m['approved'] as bool,
      );

  List<AppUser> get users => List.unmodifiable(_users);
  List<AppUser> get staff => _users.where((u) => u.role == UserRole.staff && u.approved).toList(growable: false);
  List<AppUser> get pendingUsers =>
      _users.where((u) => u.role == UserRole.staff && !u.approved).toList(growable: false);

  AppUser? findUserByEmail(String email) {
    final lower = email.trim().toLowerCase();
    for (final u in _users) {
      if (u.email.toLowerCase() == lower) return u;
    }
    return null;
  }

  Future<void> registerStaff({
    required String firstName,
    required String lastName,
    required String phone,
    required String email,
    required String password,
  }) {
    final existing = findUserByEmail(email);
    if (existing != null) {
      throw StateError('Email already registered');
    }
    _users.add(AppUser(
      email: email.trim(),
      firstName: firstName.trim(),
      lastName: lastName.trim(),
      phone: phone.trim(),
      role: UserRole.staff,
      password: password,
      approved: false,
    ));
    return _saveUsers();
  }

  Future<AppUser> approveUser(String email) async {
    final idx = _users.indexWhere((u) => u.email.toLowerCase() == email.toLowerCase());
    if (idx == -1) {
      throw StateError('User not found');
    }
    final updated = _users[idx].copyWith(approved: true);
    _users[idx] = updated;
    await _saveUsers();
    return updated;
  }

  Future<void> rejectUser(String email) async {
    _users.removeWhere((u) => u.email.toLowerCase() == email.toLowerCase() && u.role == UserRole.staff);
    await _saveUsers();
  }

  Future<void> deleteStaff(String email) async {
    // Remove staff from local list
    _users.removeWhere((u) => u.email.toLowerCase() == email.toLowerCase() && u.role == UserRole.staff);
    await _saveUsers();

    // Remove staff from Firebase Firestore
    try {
      final firestore = FirebaseFirestore.instance;
      await firestore.collection('staff').doc(email).delete();
    } catch (e) {
      debugPrint('Error deleting staff from Firebase: $e');
    }
  }

  /// Returns the logged-in user on success; throws on failure.
  AppUser login({required String email, required String password}) {
    final user = findUserByEmail(email);
    if (user == null) {
      throw StateError('No account found for this email');
    }
    if (user.password != password) {
      throw StateError('Invalid credentials');
    }
    if (user.role == UserRole.staff && !user.approved) {
      throw StateError('Your account is awaiting store owner approval');
    }
    _currentUser = user;
    _saveCurrentUser();
    return user;
  }

  Future<void> logout() async {
    _currentUser = null;
    await _saveCurrentUser();
  }

  // --- Profile updates ---
  Future<AppUser> updateCurrentUserProfile({required String firstName, required String lastName, required String phone}) async {
    if (_currentUser == null) {
      throw StateError('Not logged in');
    }
    final idx = _users.indexWhere((u) => u.email.toLowerCase() == _currentUser!.email.toLowerCase());
    if (idx == -1) {
      throw StateError('User not found');
    }
    final updated = _users[idx].copyWith(firstName: firstName.trim(), lastName: lastName.trim(), phone: phone.trim());
    _users[idx] = updated;
    _currentUser = updated;
    await _saveUsers();
    await _saveCurrentUser();
    return updated;
  }

  Future<AppUser> updateCurrentUserName({required String firstName, required String lastName}) async {
    if (_currentUser == null) {
      throw StateError('Not logged in');
    }
    final idx = _users.indexWhere((u) => u.email.toLowerCase() == _currentUser!.email.toLowerCase());
    if (idx == -1) {
      throw StateError('User not found');
    }
    final updated = _users[idx].copyWith(firstName: firstName.trim(), lastName: lastName.trim());
    _users[idx] = updated;
    _currentUser = updated;
    await _saveUsers();
    await _saveCurrentUser();
    return updated;
  }

  Future<void> updateCurrentUserPassword({required String oldPassword, required String newPassword}) async {
    if (_currentUser == null) {
      throw StateError('Not logged in');
    }
    if (_currentUser!.password != oldPassword) {
      throw StateError('Old password does not match');
    }
    if (newPassword.isEmpty) {
      throw StateError('New password cannot be empty');
    }
    final idx = _users.indexWhere((u) => u.email.toLowerCase() == _currentUser!.email.toLowerCase());
    if (idx == -1) {
      throw StateError('User not found');
    }
    final updated = _users[idx].copyWith(password: newPassword);
    _users[idx] = updated;
    _currentUser = updated;
    await _saveUsers();
    await _saveCurrentUser();
  }

  final List<InventoryItem> _items = [
    const InventoryItem(id: 'milk-1l', name: 'Milk 1L', category: 'Dairy', quantity: 45, expiresInDays: 4, alertThresholdDays: 3, purchasePrice: 2.50, sellingPrice: 3.99),
    const InventoryItem(id: 'bread-loaf', name: 'Bread Loaf', category: 'Bakery', quantity: 18, expiresInDays: 5, alertThresholdDays: 3, purchasePrice: 1.20, sellingPrice: 2.49),
    const InventoryItem(id: 'eggs-12', name: 'Eggs 12 Pack', category: 'Dairy', quantity: 8, expiresInDays: 7, alertThresholdDays: 3, purchasePrice: 3.00, sellingPrice: 4.99),
    const InventoryItem(id: 'oj-1l', name: 'Orange Juice 1L', category: 'Beverages', quantity: 12, expiresInDays: 28, alertThresholdDays: 5, purchasePrice: 1.50, sellingPrice: 2.99),
    const InventoryItem(id: 'yogurt-cup', name: 'Yogurt Cup', category: 'Dairy', quantity: 12, expiresInDays: 6, alertThresholdDays: 3, purchasePrice: 0.80, sellingPrice: 1.49),
  ];

  final List<TransactionHistoryEntry> _history = [
    const TransactionHistoryEntry(name: 'Milk 1L', type: 'sale', qty: 2, amount: 19.95, dateTime: '2025-12-18 10:30 AM'),
    const TransactionHistoryEntry(name: 'Bread Loaf', type: 'purchase', qty: 20, amount: 400.00, dateTime: '2025-12-18 09:15 AM'),
    const TransactionHistoryEntry(name: 'Orange Juice 1L', type: 'sale', qty: 3, amount: 13.47, dateTime: '2025-12-17 04:20 PM'),
    const TransactionHistoryEntry(name: 'Eggs 12 Pack', type: 'sale', qty: 2, amount: 9.98, dateTime: '2025-12-17 01:40 PM'),
    const TransactionHistoryEntry(name: 'Yogurt Cup', type: 'purchase', qty: 32, amount: 240.00, dateTime: '2025-12-17 11:30 AM'),
  ];

  List<InventoryItem> get items => List.unmodifiable(_items);
  List<TransactionHistoryEntry> get history => List.unmodifiable(_history);

  InventoryItem? findById(String id) {
    for (final item in _items) {
      if (item.id == id) return item;
    }
    return null;
  }

  InventoryItem? findByName(String name) {
    final lower = name.toLowerCase();
    for (final item in _items) {
      if (item.name.toLowerCase() == lower) return item;
    }
    return null;
  }

  void _appendHistory({required String name, required String type, required int qty, required double amount}) {
    final now = DateTime.now();
    final hour12 = (now.hour % 12 == 0) ? 12 : now.hour % 12;
    final stamp = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${hour12.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} ${now.hour >= 12 ? 'PM' : 'AM'}';
    _history.insert(0, TransactionHistoryEntry(name: name, type: type, qty: qty, amount: amount, dateTime: stamp));
  }

  InventoryItem recordSale(String itemId, int qty, {double? priceOverride}) {
    final idx = _items.indexWhere((i) => i.id == itemId);
    if (idx == -1) {
      throw ArgumentError('Item not found: $itemId');
    }
    final current = _items[idx];
    if (qty > current.quantity) {
      throw ArgumentError('Insufficient stock');
    }
    final unitPrice = priceOverride != null && priceOverride > 0 ? priceOverride : current.sellingPrice;
    final updated = current.copyWith(quantity: current.quantity - qty, sellingPrice: unitPrice);
    _items[idx] = updated;
    _appendHistory(name: updated.name, type: 'sale', qty: qty, amount: unitPrice * qty);
    return updated;
  }

  InventoryItem recordPurchase(String itemId, int qty, {double? purchasePrice, double? sellingPrice}) {
    final idx = _items.indexWhere((i) => i.id == itemId);
    if (idx == -1) {
      throw ArgumentError('Item not found: $itemId');
    }
    final current = _items[idx];
    final newPurchase = purchasePrice != null && purchasePrice > 0 ? purchasePrice : current.purchasePrice;
    final newSelling = sellingPrice != null && sellingPrice > 0 ? sellingPrice : current.sellingPrice;
    final updated = current.copyWith(
      quantity: current.quantity + qty,
      purchasePrice: newPurchase,
      sellingPrice: newSelling,
    );
    _items[idx] = updated;
    _appendHistory(name: updated.name, type: 'purchase', qty: qty, amount: newPurchase * qty);
    return updated;
  }

  InventoryItem updateItem(
    String itemId, {
    String? name,
    String? category,
    int? quantity,
    int? expiresInDays,
    int? alertThresholdDays,
    double? purchasePrice,
    double? sellingPrice,
  }) {
    final idx = _items.indexWhere((i) => i.id == itemId);
    if (idx == -1) {
      throw ArgumentError('Item not found: $itemId');
    }
    final current = _items[idx];
    final updated = current.copyWith(
      name: name?.trim().isEmpty == true ? current.name : name?.trim(),
      category: category?.trim().isEmpty == true ? current.category : category?.trim(),
      quantity: quantity != null && quantity >= 0 ? quantity : current.quantity,
      expiresInDays: expiresInDays != null && expiresInDays >= 0 ? expiresInDays : current.expiresInDays,
      alertThresholdDays: alertThresholdDays != null && alertThresholdDays >= 0 ? alertThresholdDays : current.alertThresholdDays,
      purchasePrice: purchasePrice != null && purchasePrice >= 0 ? purchasePrice : current.purchasePrice,
      sellingPrice: sellingPrice != null && sellingPrice >= 0 ? sellingPrice : current.sellingPrice,
    );
    _items[idx] = updated;
    return updated;
  }

  void deleteItem(String itemId) {
    _items.removeWhere((i) => i.id == itemId);
  }

  InventoryItem addManualItem({
    required String name,
    required String category,
    required int qty,
    required double purchasePrice,
    required double sellingPrice,
    int expiresInDays = 30,
    int alertThresholdDays = 3,
  }) {
    final existingIdx = _items.indexWhere((i) => i.name.toLowerCase() == name.toLowerCase());
    if (existingIdx != -1) {
      return recordPurchase(_items[existingIdx].id, qty, purchasePrice: purchasePrice, sellingPrice: sellingPrice);
    }
    final newItem = InventoryItem(
      id: name.toLowerCase().replaceAll(' ', '-'),
      name: name,
      category: category,
      quantity: qty,
      expiresInDays: expiresInDays,
      alertThresholdDays: alertThresholdDays,
      purchasePrice: purchasePrice,
      sellingPrice: sellingPrice,
    );
    _items.add(newItem);
    _appendHistory(name: newItem.name, type: 'purchase', qty: qty, amount: purchasePrice * qty);
    return newItem;
  }
}
