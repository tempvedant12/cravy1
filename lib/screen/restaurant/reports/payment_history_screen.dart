// lib/screen/restaurant/reports/payment_history_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cravy/models/order_models.dart';
import 'package:cravy/screen/restaurant/billing_setup/bill_design_screen.dart';
import 'package:cravy/screen/restaurant/menu/menu_screen.dart';
// --- ADDED IMPORTS ---
import 'package:cravy/screen/restaurant/orders/bill_template_screen.dart';
import 'package:cravy/screen/restaurant/orders/create_order_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
// ---------------------
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:ui';

import '../billing_setup/manage_coupon_screen.dart';
// --- ADDED IMPORT FOR STAFF MODEL ---
import '../staff/staff_and_roles_screen.dart';
import '../tables_and_reservations/tables_and_reservations_screen.dart';
import '../../../models/supplier_model.dart'; // Import PurchaseOrder model

// --- NEW MODEL FOR STAFF PAYMENTS ---
class StaffPaymentModel {
  final String id; // payment doc id
  final String staffId;
  final String staffName;
  final double amount;
  final DateTime paidAt;
  final String notes;
  final String paymentType;
  final double payRate;

  StaffPaymentModel({
    required this.id,
    required this.staffId,
    required this.staffName,
    required this.amount,
    required this.paidAt,
    required this.notes,
    required this.paymentType,
    required this.payRate,
  });

  factory StaffPaymentModel.fromFirestore(
      DocumentSnapshot doc, String staffId, String staffName) {
    final data = doc.data() as Map<String, dynamic>;
    return StaffPaymentModel(
      id: doc.id,
      staffId: staffId,
      staffName: staffName,
      amount: (data['amount'] as num?)?.toDouble() ?? 0.0,
      paidAt: (data['paidAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      notes: data['notes'] as String? ?? '',
      paymentType: data['paymentType'] as String? ?? '',
      payRate: (data['payRate'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
// -------------------------------------

class PaymentHistoryScreen extends StatefulWidget {
  final String restaurantId;
  const PaymentHistoryScreen({super.key, required this.restaurantId});

  @override
  State<PaymentHistoryScreen> createState() => _PaymentHistoryScreenState();
}

class _PaymentHistoryScreenState extends State<PaymentHistoryScreen>
    with TickerProviderStateMixin {
  TabController? _tabController;
  DateTimeRange? _selectedDateRange;
  String? _selectedPaymentMethod;
  List<DocumentSnapshot>? _selectedSessionOrders;
  String? _selectedSessionKey;
  List<MenuItem> _allMenuItems = [];
  // --- NEW STATE VARIABLES ---
  String? _selectedTransactionType;
  String? _selectedStaffId;
  // ---------------------------

  @override
  void initState() {
    super.initState();
    _fetchAllMenuItems();
  }

  Future<void> _fetchAllMenuItems() async {
    final menusSnapshot = await FirebaseFirestore.instance
        .collection('restaurants')
        .doc(widget.restaurantId)
        .collection('menus')
        .get();

    final List<MenuItem> allItems = [];

    for (var menuDoc in menusSnapshot.docs) {
      final itemsSnapshot = await menuDoc.reference.collection('items').get();
      allItems.addAll(
          itemsSnapshot.docs.map((doc) => MenuItem.fromFirestore(doc)));
    }

    if (mounted) {
      setState(() {
        _allMenuItems = allItems;
      });
    }
  }

  Future<void> _showFilterDialog() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _FilterDialog(
        initialDateRange: _selectedDateRange,
        initialPaymentMethod: _selectedPaymentMethod,
      ),
    );

    if (result != null) {
      setState(() {
        _selectedDateRange = result['dateRange'];
        _selectedPaymentMethod = result['paymentMethod'];
        // Reset selected session when filter changes
        _selectedSessionKey = null;
        _selectedSessionOrders = null;
        _selectedTransactionType = null;
        _selectedStaffId = null;
      });
    }
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  // --- NEW: Handler for Editing Restaurant Payment Time ---
  Future<void> _editRestaurantPayment(
      String sessionKey, Timestamp billedAt, DateTime newDateTime) async {
    try {
      final query = await FirebaseFirestore.instance
          .collection('restaurants')
          .doc(widget.restaurantId)
          .collection('orders')
          .where('sessionKey', isEqualTo: sessionKey)
          .where('billingDetails.billedAt', isEqualTo: billedAt)
          .get();

      if (query.docs.isEmpty) {
        throw Exception('No matching orders found for this bill.');
      }

      final batch = FirebaseFirestore.instance.batch();
      for (final doc in query.docs) {
        // We must read the existing billingDetails map and only update the 'billedAt' field
        final data = doc.data() as Map<String, dynamic>;
        final billingDetails =
            data['billingDetails'] as Map<String, dynamic>? ?? {};

        // Update the timestamp
        billingDetails['billedAt'] = Timestamp.fromDate(newDateTime);

        // Write the modified map back
        batch.update(doc.reference, {'billingDetails': billingDetails});
      }
      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Restaurant payment date updated.'),
              backgroundColor: Colors.green),
        );
      }
      setState(() {}); // Refresh view
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating: ${e.toString()}')),
        );
      }
    }
  }

  // --- NEW: Handler for "Deleting" (Marking as Unpaid) Restaurant Payment ---
  Future<void> _deleteRestaurantPayment(String sessionKey, Timestamp billedAt) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirm Revert Payment'),
        content: const Text(
            'Are you sure you want to revert this payment? This will mark all orders in this bill as "Unpaid" and move them back to Active Orders. It will NOT delete the orders.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Revert Payment',
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final query = await FirebaseFirestore.instance
            .collection('restaurants')
            .doc(widget.restaurantId)
            .collection('orders')
            .where('sessionKey', isEqualTo: sessionKey)
            .where('billingDetails.billedAt', isEqualTo: billedAt)
            .get();

        if (query.docs.isEmpty) {
          throw Exception('No matching orders found for this bill.');
        }

        final batch = FirebaseFirestore.instance.batch();
        for (final doc in query.docs) {
          batch.update(doc.reference, {
            'isPaid': false,
            'billingDetails': FieldValue.delete(),
          });
        }
        await batch.commit();

        setState(() {
          _selectedSessionKey = null;
          _selectedSessionOrders = null;
          _selectedTransactionType = null;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Payment reverted. Orders are now active and unpaid.'),
                backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error reverting: ${e.toString()}')),
          );
        }
      }
    }
  }

  // --- NEW: Handler for Editing Supplier Payment Time ---
  Future<void> _editSupplierPayment(String purchaseOrderId, DateTime newDateTime) async {
    try {
      await FirebaseFirestore.instance
          .collection('restaurants')
          .doc(widget.restaurantId)
          .collection('purchaseOrders')
          .doc(purchaseOrderId)
          .update({'orderDate': Timestamp.fromDate(newDateTime)});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Supplier payment date updated.'),
              backgroundColor: Colors.green),
        );
      }
      setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating: ${e.toString()}')),
        );
      }
    }
  }

  // --- NEW: Handler for Deleting Supplier Payment ---
  Future<void> _deleteSupplierPayment(String purchaseOrderId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirm Delete'),
        content: const Text(
            'Are you sure you want to delete this purchase order? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Delete',
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await FirebaseFirestore.instance
            .collection('restaurants')
            .doc(widget.restaurantId)
            .collection('purchaseOrders')
            .doc(purchaseOrderId)
            .delete();

        setState(() {
          _selectedSessionKey = null;
          _selectedTransactionType = null;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Supplier payment deleted.'),
                backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting: ${e.toString()}')),
          );
        }
      }
    }
  }

  // --- EXISTING STAFF HANDLERS (Unchanged) ---
  Future<void> _editStaffPayment(String staffId, String paymentId, DateTime newDateTime) async {
    try {
      await FirebaseFirestore.instance
          .collection('restaurants')
          .doc(widget.restaurantId)
          .collection('staff')
          .doc(staffId)
          .collection('payments')
          .doc(paymentId)
          .update({'paidAt': Timestamp.fromDate(newDateTime)});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Payment date updated.'),
              backgroundColor: Colors.green),
        );
      }
      // Refresh the FutureBuilder by triggering a rebuild
      setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _deleteStaffPayment(String staffId, String paymentId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirm Delete'),
        content: const Text(
            'Are you sure you want to delete this payment? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Delete',
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await FirebaseFirestore.instance
            .collection('restaurants')
            .doc(widget.restaurantId)
            .collection('staff')
            .doc(staffId)
            .collection('payments')
            .doc(paymentId)
            .delete();

        // Deselect the item to close the panel
        setState(() {
          _selectedSessionKey = null;
          _selectedStaffId = null;
          _selectedTransactionType = null;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Payment deleted.'),
                backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting: ${e.toString()}')),
          );
        }
      }
    }
  }


  // --- MODIFIED: Handle new transaction types and staff ID ---
  void _updateSelectedSession(
      String key,
      List<DocumentSnapshot>? orders,
      String type, {
        String? staffId,
      }) {
    setState(() {
      _selectedSessionKey = key;
      _selectedSessionOrders = orders;
      _selectedTransactionType = type;
      _selectedStaffId = staffId; // Will be null unless type is 'staff'
    });
  }
  // ---------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    _tabController ??= TabController(length: 4, vsync: this); // <-- CHANGED to 4

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          const _StaticBackground(),
          Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              title: const Text('Payment History'),
              backgroundColor:
              Theme.of(context).scaffoldBackgroundColor.withOpacity(0.85),
              elevation: 0,
              actions: [
                IconButton(
                  icon: const Icon(Icons.filter_list),
                  onPressed: _showFilterDialog,
                  tooltip: 'Filter History',
                ),
              ],
              bottom: TabBar(
                controller: _tabController,
                isScrollable: true, // <-- CHANGED to true to fit all tabs
                tabs: const [
                  Tab(text: 'All'),
                  Tab(text: 'Restaurant Payments'),
                  Tab(text: 'Supplier Payments'),
                  Tab(text: 'Staff Payments'), // <-- NEW TAB
                ],
              ),
            ),
            body: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 800;

                // Tab content is placed directly in the main scaffold body,
                // and wrapped in LayoutBuilder to handle the split view.
                final tabContent = TabBarView(
                  controller: _tabController,
                  children: [
                    _AllTransactionsView(
                      restaurantId: widget.restaurantId,
                      selectedDateRange: _selectedDateRange,
                      selectedPaymentMethod: _selectedPaymentMethod,
                      allMenuItems: _allMenuItems,
                      onSelectSession: _updateSelectedSession,
                      // --- PASS ALL HANDLERS ---
                      onDeleteRestaurantPayment: _deleteRestaurantPayment,
                      onEditRestaurantPayment: _editRestaurantPayment,
                      onDeleteSupplierPayment: _deleteSupplierPayment,
                      onEditSupplierPayment: _editSupplierPayment,
                      onDeletePayment: _deleteStaffPayment,
                      onEditPayment: _editStaffPayment,
                    ),
                    _RestaurantPaymentsView(
                      restaurantId: widget.restaurantId,
                      selectedDateRange: _selectedDateRange,
                      selectedPaymentMethod: _selectedPaymentMethod,
                      allMenuItems: _allMenuItems,
                      onSelectSession: _updateSelectedSession,
                      // --- PASS RESTAURANT HANDLERS ---
                      onDeleteRestaurantPayment: _deleteRestaurantPayment,
                      onEditRestaurantPayment: _editRestaurantPayment,
                    ),
                    _SupplierPaymentsView(
                      restaurantId: widget.restaurantId,
                      selectedDateRange: _selectedDateRange,
                      selectedPaymentMethod: _selectedPaymentMethod,
                      onSelectSession: _updateSelectedSession,
                      // --- PASS SUPPLIER HANDLERS ---
                      onDeleteSupplierPayment: _deleteSupplierPayment,
                      onEditSupplierPayment: _editSupplierPayment,
                    ),
                    // --- NEW TAB VIEW ---
                    _StaffPaymentsView(
                      restaurantId: widget.restaurantId,
                      selectedDateRange: _selectedDateRange,
                      selectedPaymentMethod: _selectedPaymentMethod,
                      onSelectSession: _updateSelectedSession,
                      // --- PASS STAFF HANDLERS ---
                      onDeletePayment: _deleteStaffPayment,
                      onEditPayment: _editStaffPayment,
                    ),
                    // ---------------------
                  ],
                );

                if (isWide) {
                  return Row(
                    children: [
                      SizedBox(
                        width: 400,
                        child: tabContent,
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: _buildDetailPanel(isWide: true),
                      ),
                    ],
                  );
                } else {
                  return tabContent;
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  // --- MODIFIED: Handle all 3 transaction types ---
  Widget _buildDetailPanel({required bool isWide}) {
    if (_selectedSessionKey == null || _selectedTransactionType == null) {
      return const Center(
          child: Text('Select a transaction to see the details.'));
    }

    if (_selectedTransactionType == 'restaurant') {
      // --- FIND THE UNIQUE BILLEDAT TIMESTAMP ---
      final billingDetails = (_selectedSessionOrders!.first.data()
      as Map<String, dynamic>)['billingDetails']
      as Map<String, dynamic>? ??
          {};
      final billedAt = (billingDetails['billedAt'] as Timestamp?);

      if (billedAt == null) {
        return const Center(child: Text('Error: Bill timestamp not found.'));
      }

      return _BillPreviewPanel(
        key: ValueKey(_selectedSessionKey),
        restaurantId: widget.restaurantId,
        sessionKey: _selectedSessionKey!,
        sessionOrders: _selectedSessionOrders!,
        allMenuItems: _allMenuItems,
        // --- PASS HANDLERS ---
        onDelete: () => _deleteRestaurantPayment(_selectedSessionKey!, billedAt),
        onEdit: (newDate) =>
            _editRestaurantPayment(_selectedSessionKey!, billedAt, newDate),
        billedAt: billedAt.toDate(), // Pass the date for the edit dialog
      );
    } else if (_selectedTransactionType == 'supplier') {
      // Supplier Payment Selected
      return FutureBuilder<DocumentSnapshot>(
        future: FirebaseFirestore.instance
            .collection('restaurants')
            .doc(widget.restaurantId)
            .collection('purchaseOrders')
            .doc(_selectedSessionKey)
            .get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return Center(
                child: Text('Supplier Order #$_selectedSessionKey not found.'));
          }
          final po = PurchaseOrder.fromFirestore(snapshot.data!);
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: _SupplierOrderPreview(
              po: po,
              // --- PASS HANDLERS ---
              onDelete: () => _deleteSupplierPayment(po.id),
              onEdit: (newDate) => _editSupplierPayment(po.id, newDate),
            ),
          );
        },
      );
    } else if (_selectedTransactionType == 'staff') {
      // Staff Payment Selected
      final String paymentId = _selectedSessionKey!; // <-- Get the ID
      final String staffId = _selectedStaffId!;   // <-- Get the ID

      return FutureBuilder<DocumentSnapshot>(
        future: FirebaseFirestore.instance
            .collection('restaurants')
            .doc(widget.restaurantId)
            .collection('staff')
            .doc(staffId) // Use the stored staffId
            .collection('payments')
            .doc(paymentId) // Use the paymentId
            .get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return Center(
                child: Text('Staff Payment #$paymentId not found.'));
          }

          final paymentData = snapshot.data!.data() as Map<String, dynamic>;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: _StaffPaymentPreview(
              paymentData: paymentData,
              staffId: staffId,
              restaurantId: widget.restaurantId,
              paymentId: paymentId, // <-- PASS THE ID
              onDelete: () => _deleteStaffPayment(staffId, paymentId), // <-- PASS DELETE CALLBACK
              onEdit: (DateTime newDate) => _editStaffPayment(staffId, paymentId, newDate), // <-- PASS EDIT CALLBACK
            ),
          );
        },
      );
    } else {
      // Fallback
      return const Center(
          child: Text('Select a transaction to see the details.'));
    }
  }
}

// --- NEW HELPER FUNCTION to fetch all staff payments ---
Future<List<StaffPaymentModel>> _fetchStaffTransactions(
    String restaurantId) async {
  final List<StaffPaymentModel> staffTransactions = [];

  final staffSnapshot = await FirebaseFirestore.instance
      .collection('restaurants')
      .doc(restaurantId)
      .collection('staff')
      .get();

  for (final staffDoc in staffSnapshot.docs) {
    final staff = Staff.fromFirestore(staffDoc);
    final paymentsSnapshot =
    await staffDoc.reference.collection('payments').get();
    for (final paymentDoc in paymentsSnapshot.docs) {
      staffTransactions.add(StaffPaymentModel.fromFirestore(
          paymentDoc, staff.id, staff.name));
    }
  }
  return staffTransactions;
}

// --- 1. ALL TRANSACTIONS VIEW (MODIFIED) ---

class _AllTransactionsView extends StatelessWidget {
  final String restaurantId;
  final DateTimeRange? selectedDateRange;
  final String? selectedPaymentMethod;
  final List<MenuItem> allMenuItems;
  final Function(String, List<DocumentSnapshot>?, String, {String? staffId})
  onSelectSession;
  // --- ADD ALL HANDLERS ---
  final Function(String, Timestamp, DateTime) onEditRestaurantPayment;
  final Function(String, Timestamp) onDeleteRestaurantPayment;
  final Function(String, DateTime) onEditSupplierPayment;
  final Function(String) onDeleteSupplierPayment;
  final Function(String, String) onDeletePayment; // Staff
  final Function(String, String, DateTime) onEditPayment; // Staff
  // -----------------------

  const _AllTransactionsView({
    required this.restaurantId,
    this.selectedDateRange,
    this.selectedPaymentMethod,
    required this.allMenuItems,
    required this.onSelectSession,
    // --- ADD ALL HANDLERS ---
    required this.onEditRestaurantPayment,
    required this.onDeleteRestaurantPayment,
    required this.onEditSupplierPayment,
    required this.onDeleteSupplierPayment,
    required this.onDeletePayment,
    required this.onEditPayment,
    // -----------------------
  });

  Future<List<Map<String, dynamic>>> _fetchCombinedTransactions() async {
    // 1. Fetch Restaurant Orders (Same as before)
    Query ordersQuery = FirebaseFirestore.instance
        .collection('restaurants')
        .doc(restaurantId)
        .collection('orders')
        .where('isPaid', isEqualTo: true)
        .orderBy('billingDetails.billedAt', descending: true);
    if (selectedDateRange != null) {
      ordersQuery = ordersQuery
          .where('billingDetails.billedAt',
          isGreaterThanOrEqualTo: selectedDateRange!.start)
          .where('billingDetails.billedAt',
          isLessThanOrEqualTo:
          selectedDateRange!.end.add(const Duration(days: 1)));
    }
    if (selectedPaymentMethod != null) {
      ordersQuery = ordersQuery.where('billingDetails.paymentMethod',
          isEqualTo: selectedPaymentMethod);
    }
    final ordersSnapshot = await ordersQuery.get();
    final groupedSessions = <String, List<DocumentSnapshot>>{};
    for (final doc in ordersSnapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final sessionKey = data['sessionKey'] as String? ?? 'Unknown';

      // --- FIX: Create a compound key ---
      final billingDetails = data['billingDetails'] as Map<String, dynamic>? ?? {};
      // Use the timestamp's millisecond value as a unique ID, or the doc.id as a fallback
      final billedAt = (billingDetails['billedAt'] as Timestamp?)?.millisecondsSinceEpoch ?? doc.id;
      final compoundKey = '$sessionKey-$billedAt';
      // ----------------------------------

      groupedSessions.putIfAbsent(compoundKey, () => []).add(doc);
    }
    final List<Map<String, dynamic>> restaurantTransactions = [];
    groupedSessions.forEach((compoundKey, orders) { // Renamed 'key' to 'compoundKey'
      final finalOrder = orders.first.data() as Map<String, dynamic>;
      final billingDetails =
          finalOrder['billingDetails'] as Map<String, dynamic>? ?? {};
      final orderType = finalOrder['orderType'] as String? ?? 'Dine-In';
      final sessionKey = finalOrder['sessionKey'] as String? ?? 'Unknown'; // <-- ADD this line

      restaurantTransactions.add({
        'type': 'restaurant',
        'key': sessionKey, // <-- FIX: Pass the original sessionKey here
        'date': (billingDetails['billedAt'] as Timestamp?)?.toDate() ??
            DateTime.fromMillisecondsSinceEpoch(0),
        'amount': billingDetails['finalTotal'] ?? 0.0,
        'method': billingDetails['paymentMethod'] ?? 'N/A',
        'orders': orders,
        'orderType': orderType,
      });
    });

    // 2. Fetch Supplier Payments (Same as before)
    Query poQuery = FirebaseFirestore.instance
        .collection('restaurants')
        .doc(restaurantId)
        .collection('purchaseOrders')
        .where('paymentStatus', isEqualTo: 'Paid')
        .where('totalAmount', isGreaterThan: 0)
        .orderBy('orderDate', descending: true);
    if (selectedDateRange != null) {
      poQuery = poQuery
          .where('orderDate',
          isGreaterThanOrEqualTo: selectedDateRange!.start)
          .where('orderDate',
          isLessThanOrEqualTo:
          selectedDateRange!.end.add(const Duration(days: 1)));
    }
    if (selectedPaymentMethod != null && selectedPaymentMethod != 'Pay Later') {
      poQuery =
          poQuery.where('paymentMethod', isEqualTo: selectedPaymentMethod);
    }
    final poSnapshot = await poQuery.get();
    final List<Map<String, dynamic>> supplierTransactions =
    poSnapshot.docs.map((doc) {
      final po = PurchaseOrder.fromFirestore(doc);
      return {
        'type': 'supplier',
        'key': po.id,
        'date': po.orderDate,
        'amount': po.totalAmount,
        'method': po.paymentMethod,
        'purchaseOrder': po,
      };
    }).toList();

    // --- 3. NEW: Fetch Staff Payments ---
    final allStaffPayments = await _fetchStaffTransactions(restaurantId);
    final List<Map<String, dynamic>> staffTransactions = [];
    for (final payment in allStaffPayments) {
      // Apply date range filter
      if (selectedDateRange != null &&
          (payment.paidAt.isBefore(selectedDateRange!.start) ||
              payment.paidAt.isAfter(
                  selectedDateRange!.end.add(const Duration(days: 1))))) {
        continue;
      }
      // Note: We don't filter staff payments by payment method as it's not stored
      staffTransactions.add({
        'type': 'staff',
        'key': payment.id, // Payment document ID
        'date': payment.paidAt,
        'amount': payment.amount,
        'method': 'Salary/Payout', // Generic method
        'staffPayment': payment, // Pass the full model
      });
    }
    // ------------------------------------

    // 4. Combine and Sort
    final allTransactions = [
      ...restaurantTransactions,
      ...supplierTransactions,
      ...staffTransactions
    ];
    allTransactions.sort(
            (a, b) => (b['date'] as DateTime).compareTo(a['date'] as DateTime));
    return allTransactions;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 800;

        return FutureBuilder<List<Map<String, dynamic>>>(
          future: _fetchCombinedTransactions(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return const Center(child: Text('No transactions found.'));
            }

            final allTransactions = snapshot.data!;

            return GridView.builder(
              padding: const EdgeInsets.all(16.0),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: isWide ? 2 : 1,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: isWide ? 1.4 : 0.9,
              ),
              itemCount: allTransactions.length,
              itemBuilder: (context, index) {
                final transaction = allTransactions[index];
                final type = transaction['type'] as String;

                if (type == 'restaurant') {
                  final sessionOrders =
                  transaction['orders'] as List<DocumentSnapshot>;
                  return _TransactionGridCard(
                    restaurantId: restaurantId,
                    sessionKey: transaction['key'],
                    sessionOrders: sessionOrders,
                    allMenuItems: allMenuItems,
                    orderType: transaction['orderType'], // <-- Pass it
                    onTap: () {
                      onSelectSession(transaction['key'], sessionOrders,
                          'restaurant'); // <-- Pass type
                      if (!isWide) {
                        // --- PASS HANDLERS TO SHEET ---
                        final billingDetails = (sessionOrders.first.data() as Map<String, dynamic>)['billingDetails'] as Map<String, dynamic>? ?? {};
                        final billedAt = (billingDetails['billedAt'] as Timestamp?);
                        _showBillPreviewSheet(
                          context, transaction['key'], sessionOrders,
                          // --- PASS HANDLERS ---
                          billedAt: billedAt,
                          onDelete: billedAt == null ? null : () => onDeleteRestaurantPayment(transaction['key'], billedAt),
                          onEdit: billedAt == null ? null : (newDate) => onEditRestaurantPayment(transaction['key'], billedAt, newDate),
                        );
                      }
                    },
                  );
                } else if (type == 'supplier') {
                  final po = transaction['purchaseOrder'] as PurchaseOrder;
                  return _SupplierTransactionGridCard(
                    purchaseOrder: po,
                    onTap: () {
                      onSelectSession(
                          po.id, null, 'supplier'); // <-- Pass type
                      if (!isWide) {
                        // --- PASS HANDLERS TO SHEET ---
                        _showSupplierPreviewSheet(
                          context,
                          po,
                          onDelete: () => onDeleteSupplierPayment(po.id),
                          onEdit: (newDate) => onEditSupplierPayment(po.id, newDate),
                        );
                      }
                    },
                  );
                } else {
                  // --- NEW: Handle Staff Payment Card ---
                  final payment =
                  transaction['staffPayment'] as StaffPaymentModel;
                  return _StaffPaymentGridCard(
                    payment: payment,
                    onTap: () {
                      onSelectSession(payment.id, null, 'staff',
                          staffId: payment.staffId); // <-- Pass type and staffId
                      if (!isWide) {
                        // --- PASS HANDLERS TO SHEET ---
                        _showStaffPreviewSheet(
                          context,
                          payment.staffId,
                          payment.id,
                          onDelete: () => onDeletePayment(payment.staffId, payment.id),
                          onEdit: (newDate) => onEditPayment(payment.staffId, payment.id, newDate),
                        );
                      }
                    },
                  );
                  // ---------------------------------------
                }
              },
            );
          },
        );
      },
    );
  }

  // --- MODIFIED: Accept and pass handlers ---
  void _showBillPreviewSheet(BuildContext context, String sessionKey,
      List<DocumentSnapshot> sessionOrders, {
        Timestamp? billedAt,
        VoidCallback? onDelete,
        Function(DateTime)? onEdit,
      }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.8,
          maxChildSize: 0.9,
          minChildSize: 0.5,
          builder: (BuildContext context, ScrollController scrollController) {
            return _BillPreviewPanel(
              restaurantId: restaurantId,
              sessionKey: sessionKey,
              sessionOrders: sessionOrders,
              allMenuItems: allMenuItems,
              // --- PASS HANDLERS ---
              billedAt: billedAt?.toDate(),
              onDelete: onDelete ?? () {}, // Provide dummy if null
              onEdit: onEdit ?? (newDate) {}, // Provide dummy if null
            );
          },
        );
      },
    );
  }

  // --- MODIFIED: Accept and pass handlers ---
  void _showSupplierPreviewSheet(BuildContext context, PurchaseOrder po, {
    required VoidCallback onDelete,
    required Function(DateTime) onEdit,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.5,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          builder: (BuildContext context, ScrollController scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              child: _SupplierOrderPreview(
                po: po,
                // --- PASS HANDLERS ---
                onDelete: onDelete,
                onEdit: onEdit,
              ),
            );
          },
        );
      },
    );
  }

  // --- MODIFIED: Accept and pass handlers ---
  void _showStaffPreviewSheet(
      BuildContext context, String staffId, String paymentId, {
        required VoidCallback onDelete,
        required Function(DateTime) onEdit,
      }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.5,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          builder: (BuildContext context, ScrollController scrollController) {
            return FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance
                  .collection('restaurants')
                  .doc(restaurantId)
                  .collection('staff')
                  .doc(staffId)
                  .collection('payments')
                  .doc(paymentId)
                  .get(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || !snapshot.data!.exists) {
                  return const Center(child: Text('Payment not found.'));
                }
                final paymentData =
                snapshot.data!.data() as Map<String, dynamic>;
                return SingleChildScrollView(
                  controller: scrollController,
                  child: _StaffPaymentPreview(
                    paymentData: paymentData,
                    staffId: staffId,
                    restaurantId: restaurantId,
                    paymentId: paymentId,
                    onDelete: onDelete, // <-- PASS IT
                    onEdit: onEdit,     // <-- PASS IT
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

// --- 2. RESTAURANT PAYMENTS VIEW (MODIFIED) ---

class _RestaurantPaymentsView extends StatefulWidget {
  final String restaurantId;
  final DateTimeRange? selectedDateRange;
  final String? selectedPaymentMethod;
  final List<MenuItem> allMenuItems;
  final Function(String, List<DocumentSnapshot>?, String, {String? staffId})
  onSelectSession;
  // --- ADD HANDLERS ---
  final Function(String, Timestamp, DateTime) onEditRestaurantPayment;
  final Function(String, Timestamp) onDeleteRestaurantPayment;

  const _RestaurantPaymentsView({
    required this.restaurantId,
    this.selectedDateRange,
    this.selectedPaymentMethod,
    required this.allMenuItems,
    required this.onSelectSession,
    // --- ADD HANDLERS ---
    required this.onEditRestaurantPayment,
    required this.onDeleteRestaurantPayment,
  });

  @override
  State<_RestaurantPaymentsView> createState() =>
      _RestaurantPaymentsViewState();
}

class _RestaurantPaymentsViewState extends State<_RestaurantPaymentsView>
    with TickerProviderStateMixin {
  TabController? _floorTabController;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('restaurants')
          .doc(widget.restaurantId)
          .collection('floors')
          .orderBy('order')
          .snapshots(),
      builder: (context, floorSnapshot) {
        if (!floorSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final floors = floorSnapshot.data!.docs
            .map((doc) => FloorModel.fromFirestore(doc))
            .toList();
        final tabs = ['All Floors', ...floors.map((f) => f.name)];

        _floorTabController ??=
            TabController(length: tabs.length, vsync: this);

        return Column(
          children: [
            TabBar(
              controller: _floorTabController,
              isScrollable: true,
              tabs: tabs.map((name) => Tab(text: name)).toList(),
            ),
            Expanded(
              child: TabBarView(
                controller: _floorTabController,
                children: tabs.map((tabName) {
                  return _buildHistoryGrid(
                      floorName: tabName == 'All Floors' ? null : tabName);
                }).toList(),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHistoryGrid({String? floorName}) {
    Query query = FirebaseFirestore.instance
        .collection('restaurants')
        .doc(widget.restaurantId)
        .collection('orders')
        .where('isPaid', isEqualTo: true);
    if (widget.selectedDateRange != null) {
      query = query
          .where('billingDetails.billedAt',
          isGreaterThanOrEqualTo: widget.selectedDateRange!.start)
          .where('billingDetails.billedAt',
          isLessThanOrEqualTo:
          widget.selectedDateRange!.end.add(const Duration(days: 1)));
    }
    if (widget.selectedPaymentMethod != null) {
      query = query.where('billingDetails.paymentMethod',
          isEqualTo: widget.selectedPaymentMethod);
    }
    query =
        query.orderBy('billingDetails.billedAt', descending: true).limit(200);

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(
              child: Text(
                  'No restaurant payment history found for the selected filters.'));
        }

        final paidOrders = snapshot.data!.docs;
        final groupedSessions = <String, List<DocumentSnapshot>>{};
        for (final order in paidOrders) {
          final data = order.data() as Map<String, dynamic>;
          final sessionKey = data['sessionKey'] as String? ?? 'Unknown';
          if (floorName == null || sessionKey.contains(floorName)) {
            final billingDetails = data['billingDetails'] as Map<String, dynamic>? ?? {};
            final billedAt = (billingDetails['billedAt'] as Timestamp?)?.millisecondsSinceEpoch ?? order.id;
            final compoundKey = '$sessionKey-$billedAt';
            groupedSessions.putIfAbsent(compoundKey, () => []).add(order);
          }
        }

        if (groupedSessions.isEmpty) {
          return Center(
              child: Text('No history found for floor: "$floorName".'));
        }

        final sessionKeys = groupedSessions.keys.toList();

        return LayoutBuilder(builder: (context, constraints) {
          final isWide = constraints.maxWidth > 800;
          return GridView.builder(
            padding: const EdgeInsets.all(16.0),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: isWide ? 2 : 1,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: isWide ? 1.4 : 0.9,
            ),
            itemCount: sessionKeys.length,
            itemBuilder: (context, index) {
              final compoundKey = sessionKeys[index];
              final sessionOrders = groupedSessions[compoundKey]!;
              final finalOrder =
              sessionOrders.first.data() as Map<String, dynamic>;

              final originalSessionKey = finalOrder['sessionKey'] as String? ?? 'Unknown';
              final orderType =
                  finalOrder['orderType'] as String? ?? 'Dine-In';

              // --- GET BILLEDAT ---
              final billingDetails = (finalOrder['billingDetails'] as Map<String, dynamic>? ?? {});
              final billedAt = (billingDetails['billedAt'] as Timestamp?);

              return _TransactionGridCard(
                restaurantId: widget.restaurantId,
                sessionKey: originalSessionKey,
                sessionOrders: sessionOrders,
                allMenuItems: widget.allMenuItems,
                orderType: orderType,
                onTap: () {
                  widget.onSelectSession(originalSessionKey, sessionOrders,
                      'restaurant');
                  if (!isWide) {
                    // --- PASS HANDLERS TO SHEET ---
                    _showBillPreviewSheet(
                      context,
                      originalSessionKey,
                      sessionOrders,
                      billedAt: billedAt,
                      onDelete: billedAt == null ? null : () => widget.onDeleteRestaurantPayment(originalSessionKey, billedAt),
                      onEdit: billedAt == null ? null : (newDate) => widget.onEditRestaurantPayment(originalSessionKey, billedAt, newDate),
                    );
                  }
                },
              );
            },
          );
        });
      },
    );
  }

  // --- MODIFIED: Accept and pass handlers ---
  void _showBillPreviewSheet(BuildContext context, String sessionKey,
      List<DocumentSnapshot> sessionOrders, {
        Timestamp? billedAt,
        VoidCallback? onDelete,
        Function(DateTime)? onEdit,
      }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.8,
          maxChildSize: 0.9,
          minChildSize: 0.5,
          builder: (BuildContext context, ScrollController scrollController) {
            return _BillPreviewPanel(
              restaurantId: widget.restaurantId,
              sessionKey: sessionKey,
              sessionOrders: sessionOrders,
              allMenuItems: widget.allMenuItems,
              // --- PASS HANDLERS ---
              billedAt: billedAt?.toDate(),
              onDelete: onDelete ?? () {}, // Provide dummy if null
              onEdit: onEdit ?? (newDate) {}, // Provide dummy if null
            );
          },
        );
      },
    );
  }
}

// --- 3. SUPPLIER PAYMENTS VIEW (MODIFIED) ---

class _SupplierPaymentsView extends StatelessWidget {
  final String restaurantId;
  final DateTimeRange? selectedDateRange;
  final String? selectedPaymentMethod;
  final Function(String, List<DocumentSnapshot>?, String, {String? staffId})
  onSelectSession;
  // --- ADD HANDLERS ---
  final Function(String, DateTime) onEditSupplierPayment;
  final Function(String) onDeleteSupplierPayment;


  const _SupplierPaymentsView({
    required this.restaurantId,
    this.selectedDateRange,
    this.selectedPaymentMethod,
    required this.onSelectSession,
    // --- ADD HANDLERS ---
    required this.onEditSupplierPayment,
    required this.onDeleteSupplierPayment,
  });

  @override
  Widget build(BuildContext context) {
    Query query = FirebaseFirestore.instance
        .collection('restaurants')
        .doc(restaurantId)
        .collection('purchaseOrders')
        .where('paymentStatus', isEqualTo: 'Paid')
        .where('totalAmount', isGreaterThan: 0)
        .orderBy('orderDate', descending: true);
    if (selectedDateRange != null) {
      query = query
          .where('orderDate',
          isGreaterThanOrEqualTo: selectedDateRange!.start)
          .where('orderDate',
          isLessThanOrEqualTo:
          selectedDateRange!.end.add(const Duration(days: 1)));
    }
    if (selectedPaymentMethod != null && selectedPaymentMethod != 'Pay Later') {
      query = query.where('paymentMethod', isEqualTo: selectedPaymentMethod);
    }
    query = query.limit(200);

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(
              child: Text('No supplier payment history found.'));
        }

        final paidPurchaseOrders = snapshot.data!.docs
            .map((doc) => PurchaseOrder.fromFirestore(doc))
            .toList();

        return LayoutBuilder(builder: (context, constraints) {
          final isWide = constraints.maxWidth > 800;
          return GridView.builder(
            padding: const EdgeInsets.all(16.0),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: isWide ? 2 : 1,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: isWide ? 1.4 : 0.9,
            ),
            itemCount: paidPurchaseOrders.length,
            itemBuilder: (context, index) {
              final po = paidPurchaseOrders[index];
              return _SupplierTransactionGridCard(
                purchaseOrder: po,
                onTap: () {
                  onSelectSession(po.id, null, 'supplier');
                  if (!isWide) {
                    // --- PASS HANDLERS TO SHEET ---
                    _showSupplierPreviewSheet(
                      context,
                      po,
                      onDelete: () => onDeleteSupplierPayment(po.id),
                      onEdit: (newDate) => onEditSupplierPayment(po.id, newDate),
                    );
                  }
                },
              );
            },
          );
        });
      },
    );
  }

  // --- MODIFIED: Accept and pass handlers ---
  void _showSupplierPreviewSheet(BuildContext context, PurchaseOrder po, {
    required VoidCallback onDelete,
    required Function(DateTime) onEdit,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.5,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          builder: (BuildContext context, ScrollController scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              child: _SupplierOrderPreview(
                po: po,
                // --- PASS HANDLERS ---
                onDelete: onDelete,
                onEdit: onEdit,
              ),
            );
          },
        );
      },
    );
  }
}

// --- 4. NEW: STAFF PAYMENTS VIEW ---

class _StaffPaymentsView extends StatelessWidget {
  final String restaurantId;
  final DateTimeRange? selectedDateRange;
  final String? selectedPaymentMethod;
  final Function(String, List<DocumentSnapshot>?, String, {String? staffId})
  onSelectSession;

  final Function(String, String) onDeletePayment; // <-- ADD THIS
  final Function(String, String, DateTime) onEditPayment; // <-- ADD THIS

  const _StaffPaymentsView({
    required this.restaurantId,
    this.selectedDateRange,
    this.selectedPaymentMethod,
    required this.onSelectSession,
    required this.onDeletePayment, // <-- ADD THIS
    required this.onEditPayment,   // <-- ADD THIS
  });

  Future<List<StaffPaymentModel>> _fetchPayments() async {
    final payments = await _fetchStaffTransactions(restaurantId);
    // Apply filters
    return payments.where((payment) {
      // Date filter
      if (selectedDateRange != null &&
          (payment.paidAt.isBefore(selectedDateRange!.start) ||
              payment.paidAt.isAfter(
                  selectedDateRange!.end.add(const Duration(days: 1))))) {
        return false;
      }
      // We don't filter by payment method as it's not applicable
      return true;
    }).toList()
      ..sort((a, b) => b.paidAt.compareTo(a.paidAt)); // Sort descending
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final isWide = constraints.maxWidth > 800;
      return FutureBuilder<List<StaffPaymentModel>>(
        future: _fetchPayments(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No staff payments found.'));
          }

          final allPayments = snapshot.data!;

          return GridView.builder(
            padding: const EdgeInsets.all(16.0),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: isWide ? 2 : 1,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: isWide ? 1.4 : 0.9,
            ),
            itemCount: allPayments.length,
            itemBuilder: (context, index) {
              final payment = allPayments[index];
              return _StaffPaymentGridCard(
                payment: payment,
                onTap: () {
                  onSelectSession(payment.id, null, 'staff',
                      staffId: payment.staffId);
                  if (!isWide) {
                    _showStaffPreviewSheet(
                      context,
                      payment.staffId,
                      payment.id,
                      onDelete: () => onDeletePayment(payment.staffId, payment.id),
                      onEdit: (newDate) => onEditPayment(payment.staffId, payment.id, newDate),
                    );
                  }
                },
              );
            },
          );
        },
      );
    });
  }

  // --- MODIFIED: Accept and pass handlers ---
  void _showStaffPreviewSheet(
      BuildContext context, String staffId, String paymentId, {
        required VoidCallback onDelete,
        required Function(DateTime) onEdit,
      }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.5,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          builder: (BuildContext context, ScrollController scrollController) {
            return FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance
                  .collection('restaurants')
                  .doc(restaurantId)
                  .collection('staff')
                  .doc(staffId)
                  .collection('payments')
                  .doc(paymentId)
                  .get(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || !snapshot.data!.exists) {
                  return const Center(child: Text('Payment not found.'));
                }
                final paymentData =
                snapshot.data!.data() as Map<String, dynamic>;
                return SingleChildScrollView(
                  controller: scrollController,
                  child: _StaffPaymentPreview(
                    paymentData: paymentData,
                    staffId: staffId,
                    restaurantId: restaurantId,
                    paymentId: paymentId,
                    onDelete: onDelete, // <-- PASS IT
                    onEdit: onEdit,     // <-- PASS IT
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
// ------------------------------------

// --- NEW WIDGETS FOR SUPPLIER PO DISPLAY ---

class _SupplierTransactionGridCard extends StatefulWidget {
  final PurchaseOrder purchaseOrder;
  final VoidCallback onTap;

  const _SupplierTransactionGridCard({
    required this.purchaseOrder,
    required this.onTap,
  });

  @override
  State<_SupplierTransactionGridCard> createState() =>
      _SupplierTransactionGridCardState();
}

class _SupplierTransactionGridCardState
    extends State<_SupplierTransactionGridCard> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final po = widget.purchaseOrder;
    final formatter = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.local_shipping_outlined,
                      color: theme.primaryColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      po.supplierName,
                      style: theme.textTheme.titleLarge,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              Text('PO #${po.id.substring(0, 6).toUpperCase()}'),
              const Spacer(),
              const Divider(),
              _buildRow('Paid:', formatter.format(po.totalAmount)),
              _buildRow('Method:', po.paymentMethod),
              _buildRow('Time:', DateFormat.yMd().add_jm().format(po.orderDate)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          Text(value, style: Theme.of(context).textTheme.bodyLarge),
        ],
      ),
    );
  }
}

class _SupplierOrderPreview extends StatelessWidget {
  final PurchaseOrder po;
  // --- ADD HANDLERS ---
  final VoidCallback onDelete;
  final Function(DateTime) onEdit;

  const _SupplierOrderPreview({
    required this.po,
    required this.onDelete,
    required this.onEdit,
  });

  // --- NEW: Edit Function ---
  Future<void> _showEditDialog(BuildContext context) async {
    final currentPaidAt = po.orderDate;

    final DateTime? newDate = await showDatePicker(
      context: context,
      initialDate: currentPaidAt,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (newDate == null) return;
    if (!context.mounted) return;

    final TimeOfDay? newTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(currentPaidAt),
    );

    if (newTime == null) return;

    final newDateTime = DateTime(
      newDate.year,
      newDate.month,
      newDate.day,
      newTime.hour,
      newTime.minute,
    );

    onEdit(newDateTime);
  }
  // --------------------------


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final formatter = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Supplier Payment Details',
              style: theme.textTheme.headlineSmall),
          const Divider(height: 24),
          _buildDetailRow(theme, 'Supplier:', po.supplierName),
          _buildDetailRow(
              theme, 'PO Number:', po.id.substring(0, 6).toUpperCase()),
          _buildDetailRow(
              theme, 'Order Date:', DateFormat.yMMMd().add_jm().format(po.orderDate)),
          _buildDetailRow(
              theme, 'Total Amount:', formatter.format(po.totalAmount)),
          _buildDetailRow(
              theme, 'Amount Paid:', formatter.format(po.amountPaid)),
          _buildDetailRow(theme, 'Payment Method:', po.paymentMethod),
          _buildDetailRow(theme, 'Status:', po.status,
              color:
              po.status == 'Completed' ? Colors.green : Colors.orange),
          const Divider(height: 24),
          Text('Items Ordered', style: theme.textTheme.titleLarge),
          const Divider(height: 16),
          ...po.items
              .map((item) => ListTile(
            title: Text(item.name),
            subtitle: Text(
                '${item.quantity} ${item.unit} @ ${formatter.format(item.price)}'),
            trailing:
            Text(formatter.format(item.quantity * item.price)),
            dense: true,
          ))
              .toList(),
          // --- NEW: Add Edit/Delete buttons ---
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                icon: Icon(Icons.edit_calendar_outlined, size: 20, color: theme.colorScheme.primary),
                label: Text('Edit Date/Time', style: TextStyle(color: theme.colorScheme.primary)),
                onPressed: () => _showEditDialog(context),
              ),
              const SizedBox(width: 16),
              TextButton.icon(
                icon: Icon(Icons.delete_outline, size: 20, color: theme.colorScheme.error),
                label: Text('Delete', style: TextStyle(color: theme.colorScheme.error)),
                onPressed: onDelete,
              ),
            ],
          ),
          // ------------------------------------
        ],
      ),
    );
  }

  Widget _buildDetailRow(ThemeData theme, String label, String value,
      {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodyLarge),
          Text(value,
              style: theme.textTheme.titleMedium?.copyWith(color: color)),
        ],
      ),
    );
  }
}
// ------------------------------------

// --- NEW: STAFF PAYMENT CARD ---
class _StaffPaymentGridCard extends StatefulWidget {
  final StaffPaymentModel payment;
  final VoidCallback onTap;

  const _StaffPaymentGridCard({
    required this.payment,
    required this.onTap,
  });

  @override
  State<_StaffPaymentGridCard> createState() => _StaffPaymentGridCardState();
}

class _StaffPaymentGridCardState extends State<_StaffPaymentGridCard> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final payment = widget.payment;
    final formatter = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.person_outline, color: theme.primaryColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      payment.staffName,
                      style: theme.textTheme.titleLarge,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              Text('Payment ID: ${payment.id.substring(0, 6).toUpperCase()}'),
              const Spacer(),
              const Divider(),
              _buildRow('Paid:', formatter.format(payment.amount)),
              _buildRow('Notes:', payment.notes.isEmpty ? 'N/A' : payment.notes),
              _buildRow('Time:', DateFormat.yMd().add_jm().format(payment.paidAt)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          Flexible(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// --- NEW: STAFF PAYMENT PREVIEW ---
class _StaffPaymentPreview extends StatelessWidget {
  final Map<String, dynamic> paymentData;
  final String staffId;
  final String restaurantId;
  final String paymentId;
  final VoidCallback onDelete;
  final Function(DateTime) onEdit;

  const _StaffPaymentPreview({
    required this.paymentData,
    required this.staffId,
    required this.restaurantId,
    required this.paymentId,
    required this.onDelete,
    required this.onEdit,
  });

  Future<void> _showEditDialog(BuildContext context) async {
    final currentPaidAt =
        (paymentData['paidAt'] as Timestamp?)?.toDate() ?? DateTime.now();

    final DateTime? newDate = await showDatePicker(
      context: context,
      initialDate: currentPaidAt,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (newDate == null) return;
    if (!context.mounted) return;

    final TimeOfDay? newTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(currentPaidAt),
    );

    if (newTime == null) return;

    final newDateTime = DateTime(
      newDate.year,
      newDate.month,
      newDate.day,
      newTime.hour,
      newTime.minute,
    );

    onEdit(newDateTime);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final formatter = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
    final amount = (paymentData['amount'] as num?)?.toDouble() ?? 0.0;
    final paidAt = (paymentData['paidAt'] as Timestamp?)?.toDate();
    final notes = paymentData['notes'] as String? ?? '';
    final payRate = (paymentData['payRate'] as num?)?.toDouble() ?? 0.0;
    final paymentType = paymentData['paymentType'] as String? ?? 'N/A';

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Staff Payment Details', style: theme.textTheme.headlineSmall),
          const Divider(height: 24),
          _buildDetailRow(theme, 'Amount:', formatter.format(amount)),
          _buildDetailRow(
              theme,
              'Date:',
              paidAt != null
                  ? DateFormat.yMMMd().add_jm().format(paidAt)
                  : 'N/A'),
          _buildDetailRow(theme, 'Notes:', notes.isEmpty ? 'N/A' : notes),
          _buildDetailRow(
              theme, 'Payment Type:', paymentType.isEmpty ? 'N/A' : paymentType),
          _buildDetailRow(theme, 'Pay Rate at Time:',
              '${formatter.format(payRate)} / ${paymentType.toLowerCase()}'),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                icon: Icon(Icons.edit_calendar_outlined,
                    size: 20, color: theme.colorScheme.primary),
                label: Text('Edit Date/Time',
                    style: TextStyle(color: theme.colorScheme.primary)),
                onPressed: () => _showEditDialog(context),
              ),
              const SizedBox(width: 16),
              TextButton.icon(
                icon: Icon(Icons.delete_outline,
                    size: 20, color: theme.colorScheme.error),
                label: Text('Delete',
                    style: TextStyle(color: theme.colorScheme.error)),
                onPressed: onDelete,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(ThemeData theme, String label, String value,
      {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodyLarge),
          Flexible(
            child: Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(color: color),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}
// ------------------------------------

class _FilterDialog extends StatefulWidget {
  final DateTimeRange? initialDateRange;
  final String? initialPaymentMethod;

  const _FilterDialog({this.initialDateRange, this.initialPaymentMethod});

  @override
  State<_FilterDialog> createState() => _FilterDialogState();
}

class _FilterDialogState extends State<_FilterDialog> {
  DateTimeRange? _dateRange;
  String? _paymentMethod;
  final List<String> _paymentMethods = [
    'All',
    'Cash',
    'Card',
    'UPI',
    'Other',
    'Pay Later'
  ];

  @override
  void initState() {
    super.initState();
    _dateRange = widget.initialDateRange;
    _paymentMethod = widget.initialPaymentMethod;
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _dateRange,
    );
    if (picked != null) {
      setState(() {
        _dateRange = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Filter History'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: const Text('Date Range'),
            subtitle: Text(_dateRange == null
                ? 'Any Time'
                : '${DateFormat.yMd().format(_dateRange!.start)} - ${DateFormat.yMd().format(_dateRange!.end)}'),
            trailing: const Icon(Icons.calendar_today),
            onTap: _selectDateRange,
          ),
          DropdownButtonFormField<String>(
            value: _paymentMethod,
            decoration: const InputDecoration(labelText: 'Payment Method'),
            hint: const Text('All Methods'),
            items: _paymentMethods
                .map((method) =>
                DropdownMenuItem(value: method, child: Text(method)))
                .toList(),
            onChanged: (value) {
              setState(() {
                _paymentMethod = (value == 'All' ? null : value);
              });
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            // Clear filters
            Navigator.of(context).pop({
              'dateRange': null,
              'paymentMethod': null,
            });
          },
          child: const Text('Clear Filters'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.of(context).pop({
              'dateRange': _dateRange,
              'paymentMethod': _paymentMethod,
            });
          },
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

class _TransactionGridCard extends StatefulWidget {
  final String restaurantId;
  final String sessionKey;
  final List<DocumentSnapshot> sessionOrders;
  final List<MenuItem> allMenuItems;
  final String orderType;
  final VoidCallback onTap;

  const _TransactionGridCard({
    required this.restaurantId,
    required this.sessionKey,
    required this.sessionOrders,
    required this.allMenuItems,
    required this.orderType,
    required this.onTap,
  });

  @override
  State<_TransactionGridCard> createState() => _TransactionGridCardState();
}

class _TransactionGridCardState extends State<_TransactionGridCard> {
  // This state is just to show a simple aggregation. More complex logic can be added.
  double _totalAmount = 0.0;
  DateTime? _billedAt;
  String _paymentMethod = 'N/A';
  String _billNumber = '...';

  @override
  void initState() {
    super.initState();
    _aggregateData();
  }

  void _aggregateData() {
    if (widget.sessionOrders.isEmpty) return;

    final firstOrderData =
    widget.sessionOrders.first.data() as Map<String, dynamic>;
    final billingDetails =
        firstOrderData['billingDetails'] as Map<String, dynamic>? ?? {};

    _totalAmount = (billingDetails['finalTotal'] as num?)?.toDouble() ?? 0.0;
    _billedAt = (billingDetails['billedAt'] as Timestamp?)?.toDate();
    _paymentMethod = billingDetails['paymentMethod'] as String? ?? 'N/A';
    _billNumber = billingDetails['billNumber'] as String? ?? '...';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final formatter = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

    IconData icon;
    switch (widget.orderType) {
      case 'Takeaway':
        icon = Icons.takeout_dining_outlined;
        break;
      case 'Delivery':
        icon = Icons.delivery_dining_outlined;
        break;
      default:
        icon = Icons.restaurant_outlined;
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: theme.primaryColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.sessionKey,
                      style: theme.textTheme.titleLarge,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              Text('Bill #${_billNumber.padLeft(4, '0')}'),
              const Spacer(),
              const Divider(),
              _buildRow('Paid:', formatter.format(_totalAmount)),
              _buildRow('Method:', _paymentMethod),
              _buildRow(
                  'Time:',
                  _billedAt != null
                      ? DateFormat.yMd().add_jm().format(_billedAt!)
                      : 'N/A'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          Text(value, style: Theme.of(context).textTheme.bodyLarge),
        ],
      ),
    );
  }
}

class _StaticBackground extends StatelessWidget {
  const _StaticBackground();
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      color: theme.scaffoldBackgroundColor,
      child: Stack(
        children: [
          Positioned(
            top: -100,
            left: -150,
            child: _buildShape(
                theme.primaryColor.withOpacity(isDark ? 0.3 : 0.1), 350),
          ),
          Positioned(
            bottom: -150,
            right: -200,
            child: _buildShape(
                theme.colorScheme.surface.withOpacity(isDark ? 0.3 : 0.2),
                450),
          ),
        ],
      ),
    );
  }

  Widget _buildShape(Color color, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}

class _BillPreviewPanel extends StatefulWidget {
  final String restaurantId;
  final String sessionKey;
  final List<DocumentSnapshot> sessionOrders;
  final List<MenuItem> allMenuItems;
  // --- ADD HANDLERS ---
  final VoidCallback onDelete;
  final Function(DateTime) onEdit;
  final DateTime? billedAt; // To know the current date

  const _BillPreviewPanel({
    super.key, // Use super.key
    required this.restaurantId,
    required this.sessionKey,
    required this.sessionOrders,
    required this.allMenuItems,
    // --- ADD HANDLERS ---
    required this.onDelete,
    required this.onEdit,
    required this.billedAt,
  });

  @override
  State<_BillPreviewPanel> createState() => _BillPreviewPanelState();
}

class _BillPreviewPanelState extends State<_BillPreviewPanel> {
  Future<Map<String, dynamic>>? _billDetailsFuture;
  BillConfiguration? _selectedConfig;

  @override
  void initState() {
    super.initState();
    // Fetch all data needed for the PDF preview
    _billDetailsFuture = _historyFetchAndPrepareBillData(
      widget.restaurantId,
      widget.sessionKey,
      widget.sessionOrders,
      widget.allMenuItems,
    );
  }

  // --- NEW: Edit Function ---
  Future<void> _showEditDialog(BuildContext context) async {
    final currentPaidAt = widget.billedAt ?? DateTime.now();

    final DateTime? newDate = await showDatePicker(
      context: context,
      initialDate: currentPaidAt,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (newDate == null) return;
    if (!context.mounted) return;

    final TimeOfDay? newTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(currentPaidAt),
    );

    if (newTime == null) return;

    final newDateTime = DateTime(
      newDate.year,
      newDate.month,
      newDate.day,
      newTime.hour,
      newTime.minute,
    );

    widget.onEdit(newDateTime);
  }
  // --------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context); // Get theme

    return FutureBuilder<Map<String, dynamic>>(
      future: _billDetailsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError || !snapshot.hasData) {
          return Center(
              child: Text('Could not load bill details: ${snapshot.error}'));
        }

        final billData = snapshot.data!;
        _selectedConfig = billData['billConfig'] as BillConfiguration?;

        if (_selectedConfig == null) {
          return const Center(child: Text('No bill design configured.'));
        }

        return Column(
          children: [
            // --- 1. The PDF Preview ---
            Expanded(
              child: Container(
                color: Colors.grey[300], // Background for the PDF preview
                padding: const EdgeInsets.symmetric(
                    vertical: 24.0, horizontal: 16.0),
                child: Center(
                  child: AspectRatio(
                    aspectRatio:
                    _selectedConfig!.paperWidth / 150, // Use configured width
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 8,
                            offset: Offset(0, 4),
                          )
                        ],
                      ),
                      child: PdfPreview(
                        key: ValueKey(_selectedConfig!.id),
                        build: (format) =>
                            compute(generatePdfOnIsolate, billData),
                        useActions: false,
                        allowSharing: false,
                        allowPrinting: false,
                        canChangeOrientation: false,
                        canChangePageFormat: false,
                        canDebug: false,
                        pdfPreviewPageDecoration: const BoxDecoration(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // --- 2. The "Print Again" Button ---
            Container(
              padding: const EdgeInsets.all(16.0),
              width: double.infinity,
              decoration: BoxDecoration(
                  color: theme.scaffoldBackgroundColor,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, -4),
                    )
                  ]
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.print_outlined),
                    label: const Text('Print Again'),
                    onPressed: () {
                      // Use the public function from bill_template_screen.dart
                      showPrintedBill(
                        context: context,
                        restaurantId: widget.restaurantId,
                        sessionKey: widget.sessionKey,
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      minimumSize: const Size(double.infinity, 50), // Ensure it's full-width
                    ),
                  ),
                  const SizedBox(height: 12),
                  // --- NEW: Edit and Delete Buttons ---
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      TextButton.icon(
                        icon: Icon(Icons.edit_calendar_outlined, size: 20, color: theme.colorScheme.primary),
                        label: Text('Edit Date/Time', style: TextStyle(color: theme.colorScheme.primary)),
                        onPressed: () => _showEditDialog(context),
                      ),
                      TextButton.icon(
                        icon: Icon(Icons.undo_outlined, size: 20, color: theme.colorScheme.error),
                        label: Text('Revert Payment', style: TextStyle(color: theme.colorScheme.error)),
                        onPressed: widget.onDelete,
                      ),
                    ],
                  ),
                  // ------------------------------------
                ],
              ),
            )
          ],
        );
      },
    );
  }
}

// --- HELPER FUNCTIONS (COPIED FROM bill_template_screen.dart) ---
// These are needed to fetch the data for the PDF preview.

Future<Map<String, dynamic>> _historyFetchAndPrepareBillData(
    String restaurantId,
    String sessionKey,
    List<DocumentSnapshot> orderDocs,
    List<MenuItem> allMenuItems) async {
  final restaurantRef =
  FirebaseFirestore.instance.collection('restaurants').doc(restaurantId);

  final restaurantDoc = await restaurantRef.get();
  final configsSnapshot =
  await restaurantRef.collection('billConfigurations').get();

  final restaurantData = restaurantDoc.data() as Map<String, dynamic>? ?? {};
  final defaultBillConfigId = restaurantData['defaultBillConfigId'] as String?;

  final allConfigs = configsSnapshot.docs
      .map((doc) => BillConfiguration.fromFirestore(doc))
      .toList();

  BillConfiguration? selectedConfig;
  if (allConfigs.isNotEmpty) {
    selectedConfig = allConfigs.firstWhere((c) => c.id == defaultBillConfigId,
        orElse: () => allConfigs.first);
  } else {
    // Create a fallback config if none exist
    selectedConfig = BillConfiguration(
        id: 'fallback',
        gstNumber: 'N/A',
        contactPhone: 'N/A',
        footerNote: 'Thank you!',
        billNotes: '',
        customCharges: [],
        template: 'Standard');
  }

  final firstOrderData = orderDocs.first.data() as Map<String, dynamic>;
  final billingDetails =
  (firstOrderData['billingDetails'] as Map<String, dynamic>? ?? {});

  final aggregatedItems =
  _historyAggregateOrders(orderDocs, allMenuItems).values.toList();

  final billedAtTimestamp = (billingDetails['billedAt'] as Timestamp?);
  final DateTime billedAtDate = billedAtTimestamp?.toDate() ?? DateTime.now(); // Get the date

  final subtotal =
  aggregatedItems.fold(0.0, (sum, item) => sum + item.totalPrice);
  final discountPercentage = (billingDetails['discount'] ?? 0.0).toDouble();
  final staffDiscountAmount = subtotal * discountPercentage;
  final couponDiscountAmount =
  (billingDetails['couponDiscount'] ?? 0.0).toDouble();
  final appliedChargesList =
      billingDetails['appliedCharges'] as List<dynamic>? ?? [];
  final calculatedCharges = <String, double>{};
  for (var chargeMap in appliedChargesList) {
    if (chargeMap is Map<String, dynamic>) {
      final label = chargeMap['label'] as String? ?? 'Charge';
      final amount = (chargeMap['amount'] as num? ?? 0.0).toDouble();
      calculatedCharges[label] = amount;
    }
  }
  final billItems = aggregatedItems.map((item) {
    return {
      'name': item.menuItem.name,
      'qty': item.quantity,
      'price': item.singleItemPrice,
      'options': item.selectedOptions.map((o) => o.optionName).join(', '),
    };
  }).toList();

  return {
    'restaurantName': restaurantData['name'] ?? 'N/A',
    'restaurantAddress': restaurantData['address'] ?? 'N/A',
    'phone': selectedConfig.contactPhone,
    'gst': selectedConfig.gstNumber,
    'footer': selectedConfig.footerNote,
    'notes': selectedConfig.billNotes,
    'template': selectedConfig.template,
    'paperWidth': selectedConfig.paperWidth,
    'fontSize': selectedConfig.fontSize,
    'billConfig': selectedConfig, // Pass the config object
    'billItems': billItems,
    'subtotal': subtotal,
    'staffDiscount': staffDiscountAmount,
    'couponDiscount': couponDiscountAmount,
    'calculatedCharges': calculatedCharges,
    'total': billingDetails['finalTotal'] ?? 0.0,
    'billNumber': billingDetails['billNumber'] ?? 'N/A',
    'sessionKey': sessionKey,
    'paymentMethod': billingDetails['paymentMethod'] ?? 'N/A',
    'customers': (firstOrderData['customers'] as List<dynamic>? ?? [])
        .map((c) => CustomerInfo.fromMap(c as Map<String, dynamic>))
        .toList(),
    'orderType': firstOrderData['orderType'] ?? 'Dine-In',
    'billedAt': billedAtDate,
  };
}

Map<String, OrderItem> _historyAggregateOrders(
    List<DocumentSnapshot> orders, List<MenuItem> allMenuItems) {
  final aggregatedItems = <String, OrderItem>{};
  for (var orderDoc in orders) {
    final orderData = orderDoc.data() as Map<String, dynamic>;
    final items = List<Map<String, dynamic>>.from(orderData['items'] ?? []);
    for (var itemMap in items) {
      final item = OrderItem.fromMap(itemMap, allMenuItems);
      if (aggregatedItems.containsKey(item.uniqueId)) {
        aggregatedItems[item.uniqueId]!.quantity += item.quantity;
      } else {
        aggregatedItems[item.uniqueId] = item;
      }
    }
  }
  return aggregatedItems;
}