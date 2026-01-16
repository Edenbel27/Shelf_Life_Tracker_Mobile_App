import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../widgets/app_header.dart';

class PurchasePage extends StatefulWidget {
  const PurchasePage({super.key});

  @override
  State<PurchasePage> createState() => _PurchasePageState();
}

class _PurchasePageState extends State<PurchasePage> {
  final _nameCtrl = TextEditingController();
  final _categoryCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController();
  final _purchasePriceCtrl = TextEditingController();
  final _sellingPriceCtrl = TextEditingController();
  final _alertThresholdCtrl = TextEditingController(text: '3');
  DateTime? _expiryDate;
  bool _isSaving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _categoryCtrl.dispose();
    _qtyCtrl.dispose();
    _purchasePriceCtrl.dispose();
    _sellingPriceCtrl.dispose();
    _alertThresholdCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickExpiryDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _expiryDate ?? now.add(const Duration(days: 7)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 5)),
    );
    if (selected != null) {
      setState(() => _expiryDate = selected);
    }
  }

  Future<void> _submit() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    final name = _nameCtrl.text.trim();
    final category = _categoryCtrl.text.trim();
    final qty = int.tryParse(_qtyCtrl.text.trim());
    final purchasePrice = double.tryParse(_purchasePriceCtrl.text.trim());
    final sellingPrice = double.tryParse(_sellingPriceCtrl.text.trim());
    final alertThreshold = int.tryParse(_alertThresholdCtrl.text.trim());

    if (name.isEmpty || category.isEmpty || qty == null || purchasePrice == null || sellingPrice == null || _expiryDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields and pick an expiry date')),
      );
      setState(() => _isSaving = false);
      return;
    }

    final daysLeft = _expiryDate!.difference(DateTime.now()).inDays;
    final expiresInDays = daysLeft < 0 ? 0 : daysLeft;
    final threshold = alertThreshold != null && alertThreshold > 0 ? alertThreshold : 3;
    final amount = (purchasePrice ?? 0) * (qty ?? 0);

    try {
      final inv = FirebaseFirestore.instance.collection('inventory');
      final nameLower = name.toLowerCase();
      final existing = await inv.where('nameLower', isEqualTo: nameLower).limit(1).get();
      final batch = FirebaseFirestore.instance.batch();
      final transactions = FirebaseFirestore.instance.collection('transactions');

      if (existing.docs.isEmpty) {
        final invDoc = inv.doc();
        batch.set(invDoc, {
          'name': name,
          'nameLower': nameLower,
          'category': category,
          'quantity': qty,
          'purchasePrice': purchasePrice,
          'sellingPrice': sellingPrice,
          'alertThresholdDays': threshold,
          'expiresInDays': expiresInDays,
          'createdAt': FieldValue.serverTimestamp(),
        });

        final txDoc = transactions.doc();
        batch.set(txDoc, {
          'itemId': invDoc.id,
          'name': name,
          'category': category,
          'type': 'purchase',
          'qty': qty,
          'amount': amount,
          'purchasePrice': purchasePrice,
          'sellingPrice': sellingPrice,
          'timestamp': FieldValue.serverTimestamp(),
        });
      } else {
        final doc = existing.docs.first;
        final currentQty = ((doc.data()['quantity'] ?? 0) as num).toInt();
        batch.update(doc.reference, {
          'name': name,
          'nameLower': nameLower,
          'category': category,
          'quantity': currentQty + qty,
          'purchasePrice': purchasePrice,
          'sellingPrice': sellingPrice,
          'alertThresholdDays': threshold,
          'expiresInDays': expiresInDays,
        });

        final txDoc = transactions.doc();
        batch.set(txDoc, {
          'itemId': doc.id,
          'name': name,
          'category': category,
          'type': 'purchase',
          'qty': qty,
          'amount': amount,
          'purchasePrice': purchasePrice,
          'sellingPrice': sellingPrice,
          'timestamp': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Item saved')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildAppBarWithLogoutAndNotifications(
        context: context,
        title: 'Shelf Life Tracker',
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Add / Purchase Item', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Item Name', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _categoryCtrl,
              decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _qtyCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Quantity', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _purchasePriceCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Purchase Price', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _sellingPriceCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Sale Price', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _alertThresholdCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Alert when <= days', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _pickExpiryDate,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Expiry Date',
                  border: OutlineInputBorder(),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _expiryDate == null
                          ? 'Select date'
                          : '${_expiryDate!.year}-${_expiryDate!.month.toString().padLeft(2, '0')}-${_expiryDate!.day.toString().padLeft(2, '0')}',
                    ),
                    const Icon(Icons.calendar_today),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _submit,
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.save),
                label: Text(_isSaving ? 'Saving...' : 'Save Purchase'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
