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
                    ),
                    _RestaurantPaymentsView(
                      restaurantId: widget.restaurantId,
                      selectedDateRange: _selectedDateRange,
                      selectedPaymentMethod: _selectedPaymentMethod,
                      allMenuItems: _allMenuItems,
                      onSelectSession: _updateSelectedSession,
                    ),
                    _SupplierPaymentsView(
                      restaurantId: widget.restaurantId,
                      selectedDateRange: _selectedDateRange,
                      selectedPaymentMethod: _selectedPaymentMethod,
                      onSelectSession: _updateSelectedSession,
                    ),
                    // --- NEW TAB VIEW ---
                    _StaffPaymentsView(
                      restaurantId: widget.restaurantId,
                      selectedDateRange: _selectedDateRange,
                      selectedPaymentMethod: _selectedPaymentMethod,
                      onSelectSession: _updateSelectedSession,
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
      // Restaurant bill selected
      return _BillPreviewPanel(
        key: ValueKey(_selectedSessionKey),
        restaurantId: widget.restaurantId,
        sessionKey: _selectedSessionKey!,
        sessionOrders: _selectedSessionOrders!,
        allMenuItems: _allMenuItems,
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
            child: _SupplierOrderPreview(po: po),
          );
        },
      );
    } else if (_selectedTransactionType == 'staff') {
      // Staff Payment Selected
      return FutureBuilder<DocumentSnapshot>(
        future: FirebaseFirestore.instance
            .collection('restaurants')
            .doc(widget.restaurantId)
            .collection('staff')
            .doc(_selectedStaffId) // Use the stored staffId
            .collection('payments')
            .doc(_selectedSessionKey) // Use the paymentId
            .get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return Center(
                child: Text('Staff Payment #$_selectedSessionKey not found.'));
          }
          // We need the staff name, which isn't on the payment doc.
          // We can fetch it, or just show "Staff Payment".
          // Let's create the model which requires re-fetching staff (or passing it)
          // To simplify, we'll just pass the data to a new preview widget
          final paymentData = snapshot.data!.data() as Map<String, dynamic>;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: _StaffPaymentPreview(
              paymentData: paymentData,
              staffId: _selectedStaffId!,
              restaurantId: widget.restaurantId,
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

  const _AllTransactionsView({
    required this.restaurantId,
    this.selectedDateRange,
    this.selectedPaymentMethod,
    required this.allMenuItems,
    required this.onSelectSession,
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
      final sessionKey =
          (doc.data() as Map<String, dynamic>)['sessionKey'] as String? ??
              'Unknown';
      groupedSessions.putIfAbsent(sessionKey, () => []).add(doc);
    }
    final List<Map<String, dynamic>> restaurantTransactions = [];
    groupedSessions.forEach((key, orders) {
      final finalOrder = orders.first.data() as Map<String, dynamic>;
      final billingDetails =
          finalOrder['billingDetails'] as Map<String, dynamic>? ?? {};
      final orderType = finalOrder['orderType'] as String? ?? 'Dine-In';
      restaurantTransactions.add({
        'type': 'restaurant',
        'key': key,
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
                        _showBillPreviewSheet(
                            context, transaction['key'], sessionOrders);
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
                        _showSupplierPreviewSheet(context, po);
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
                        _showStaffPreviewSheet(
                            context, payment.staffId, payment.id);
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

  void _showBillPreviewSheet(BuildContext context, String sessionKey,
      List<DocumentSnapshot> sessionOrders) {
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
            );
          },
        );
      },
    );
  }

  void _showSupplierPreviewSheet(BuildContext context, PurchaseOrder po) {
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
              child: _SupplierOrderPreview(po: po),
            );
          },
        );
      },
    );
  }

  // --- NEW: Show Staff Payment Sheet ---
  void _showStaffPreviewSheet(
      BuildContext context, String staffId, String paymentId) {
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
  onSelectSession; // <-- MODIFIED SIGNATURE

  const _RestaurantPaymentsView({
    required this.restaurantId,
    this.selectedDateRange,
    this.selectedPaymentMethod,
    required this.allMenuItems,
    required this.onSelectSession,
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
    // (Same as before)
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
    // (Query logic is same as before)
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
            groupedSessions.putIfAbsent(sessionKey, () => []).add(order);
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
              final key = sessionKeys[index];
              final sessionOrders = groupedSessions[key]!;
              final finalOrder =
              sessionOrders.first.data() as Map<String, dynamic>;
              final orderType =
                  finalOrder['orderType'] as String? ?? 'Dine-In';
              return _TransactionGridCard(
                restaurantId: widget.restaurantId,
                sessionKey: key,
                sessionOrders: sessionOrders,
                allMenuItems: widget.allMenuItems,
                orderType: orderType,
                onTap: () {
                  widget.onSelectSession(key, sessionOrders,
                      'restaurant'); // <-- Pass type
                  if (!isWide) {
                    _showBillPreviewSheet(context, key, sessionOrders);
                  }
                },
              );
            },
          );
        });
      },
    );
  }

  void _showBillPreviewSheet(BuildContext context, String sessionKey,
      List<DocumentSnapshot> sessionOrders) {
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
  onSelectSession; // <-- MODIFIED SIGNATURE

  const _SupplierPaymentsView({
    required this.restaurantId,
    this.selectedDateRange,
    this.selectedPaymentMethod,
    required this.onSelectSession,
  });

  @override
  Widget build(BuildContext context) {
    // (Query logic is same as before)
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
                  // --- FIX: Accessing property on stateless widget ---
                  onSelectSession(po.id, null, 'supplier'); // <-- Pass type
                  // ----------------------------------------------------
                  if (!isWide) {
                    _showSupplierPreviewSheet(context, po);
                  }
                },
              );
            },
          );
        });
      },
    );
  }

  void _showSupplierPreviewSheet(BuildContext context, PurchaseOrder po) {
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
              child: _SupplierOrderPreview(po: po),
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

  const _StaffPaymentsView({
    required this.restaurantId,
    this.selectedDateRange,
    this.selectedPaymentMethod,
    required this.onSelectSession,
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
                    _showStaffPreviewSheet(context, payment.staffId, payment.id);
                  }
                },
              );
            },
          );
        },
      );
    });
  }

  void _showStaffPreviewSheet(
      BuildContext context, String staffId, String paymentId) {
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
// (This widget is unchanged)
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
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final po = widget.purchaseOrder;
    final formatter = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedScale(
        scale: _isHovered ? 1.05 : 1.0,
        duration: const Duration(milliseconds: 200),
        child: GestureDetector(
          onTap: widget.onTap,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _isHovered
                      ? theme.primaryColor.withOpacity(0.5)
                      : theme.dividerColor.withOpacity(0.2),
                  width: 1.5,
                ),
                gradient: LinearGradient(
                  colors: [
                    Colors.lightBlue
                        .withOpacity(0.1), // Distinct color for supplier
                    Colors.lightBlue.withOpacity(0.05),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      po.supplierName,
                      style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold, color: Colors.lightBlue),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'PO #${po.id.substring(0, 6).toUpperCase()}',
                    style: theme.textTheme.bodySmall,
                  ),
                  const Divider(height: 16),
                  Expanded(
                    child: ListView(
                      children: [
                        ...po.items.map((item) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2.0),
                            child: Row(
                              children: [
                                Text('${item.quantity} ${item.unit} x',
                                    style: theme.textTheme.bodySmall),
                                const SizedBox(width: 8),
                                Expanded(
                                    child: Text(item.name,
                                        style: theme.textTheme.bodySmall)),
                              ],
                            ),
                          );
                        }).toList(),
                      ],
                    ),
                  ),
                  const Divider(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            DateFormat.yMMMd().format(po.orderDate),
                            style: theme.textTheme.bodySmall,
                          ),
                          Text(
                            'Ordered',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          formatter.format(po.totalAmount),
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Icon(Icons.payment,
                                size: 18,
                                color: theme.textTheme.bodyMedium?.color),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Paid with ${po.paymentMethod}',
                                style: theme.textTheme.bodySmall,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Chip(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        visualDensity: VisualDensity.compact,
                        label: Text(po.status),
                        backgroundColor: po.status == 'Completed'
                            ? Colors.green.withOpacity(0.2)
                            : Colors.orange.withOpacity(0.2),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SupplierOrderPreview extends StatelessWidget {
  final PurchaseOrder po;

  const _SupplierOrderPreview({required this.po});

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
              theme, 'Order Date:', DateFormat.yMMMd().format(po.orderDate)),
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
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final payment = widget.payment;
    final formatter = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedScale(
        scale: _isHovered ? 1.05 : 1.0,
        duration: const Duration(milliseconds: 200),
        child: GestureDetector(
          onTap: widget.onTap,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _isHovered
                      ? theme.primaryColor.withOpacity(0.5)
                      : theme.dividerColor.withOpacity(0.2),
                  width: 1.5,
                ),
                gradient: LinearGradient(
                  colors: [
                    Colors.green.withOpacity(0.1), // Distinct color for staff
                    Colors.green.withOpacity(0.05),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      payment.staffName,
                      style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold, color: Colors.green),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Payment ID: #${payment.id.substring(0, 6).toUpperCase()}',
                    style: theme.textTheme.bodySmall,
                  ),
                  const Divider(height: 16),
                  Expanded(
                    child: ListView(
                      children: [
                        Text(
                          'Notes: ${payment.notes.isEmpty ? 'N/A' : payment.notes}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            DateFormat.yMMMd().format(payment.paidAt),
                            style: theme.textTheme.bodySmall,
                          ),
                          Text(
                            DateFormat.jm().format(payment.paidAt),
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          formatter.format(payment.amount),
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Icon(Icons.payment,
                                size: 18,
                                color: theme.textTheme.bodyMedium?.color),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Type: ${payment.paymentType}',
                                style: theme.textTheme.bodySmall,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Chip(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        visualDensity: VisualDensity.compact,
                        label: const Text('Paid'),
                        backgroundColor: Colors.green.withOpacity(0.2),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// --- NEW: STAFF PAYMENT PREVIEW ---
class _StaffPaymentPreview extends StatelessWidget {
  final Map<String, dynamic> paymentData;
  final String staffId;
  final String restaurantId;

  const _StaffPaymentPreview({
    required this.paymentData,
    required this.staffId,
    required this.restaurantId,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final formatter = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

    final amount = (paymentData['amount'] as num?)?.toDouble() ?? 0.0;
    final paidAt = (paymentData['paidAt'] as Timestamp?)?.toDate();
    final notes = paymentData['notes'] as String? ?? '';
    final paymentType = paymentData['paymentType'] as String? ?? 'N/A';
    final payRate = (paymentData['payRate'] as num?)?.toDouble() ?? 0.0;

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Staff Payment Details', style: theme.textTheme.headlineSmall),
          const Divider(height: 24),
          // Fetch staff name for context
          FutureBuilder<DocumentSnapshot>(
            future: FirebaseFirestore.instance
                .collection('restaurants')
                .doc(restaurantId)
                .collection('staff')
                .doc(staffId)
                .get(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const SizedBox.shrink();
              final staffName =
                  (snapshot.data!.data() as Map<String, dynamic>)['name'] ??
                      'Unknown Staff';
              return _buildDetailRow(theme, 'Staff Member:', staffName);
            },
          ),
          _buildDetailRow(
              theme,
              'Payment Date:',
              paidAt != null
                  ? DateFormat.yMMMd().add_jm().format(paidAt)
                  : 'N/A'),
          _buildDetailRow(theme, 'Amount Paid:', formatter.format(amount)),
          _buildDetailRow(theme, 'Payment Type:', paymentType),
          _buildDetailRow(
              theme, 'Pay Rate at Time:', formatter.format(payRate)),
          _buildDetailRow(theme, 'Notes:', notes.isEmpty ? 'N/A' : notes),
          const Divider(height: 24),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.bodyLarge),
          const SizedBox(width: 16),
          Expanded(
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

  // --- MODIFIED: Added Pay Later ---
  final List<String> _paymentMethods = [
    'Cash',
    'Card',
    'UPI',
    'Other',
    'Pay Later'
  ];
  // ---------------------------------

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

    if (picked != null && picked != _dateRange) {
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
            leading: const Icon(Icons.date_range),
            title: const Text('Date Range'),
            subtitle: Text(_dateRange == null
                ? 'Any'
                : '${DateFormat.yMMMd().format(_dateRange!.start)} - ${DateFormat.yMMMd().format(_dateRange!.end)}'),
            onTap: _selectDateRange,
            trailing: _dateRange != null
                ? IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () => setState(() => _dateRange = null))
                : null,
          ),
          DropdownButtonFormField<String>(
            value: _paymentMethod,
            decoration: const InputDecoration(
              labelText: 'Payment Method',
              prefixIcon: Icon(Icons.payment),
            ),
            items: _paymentMethods.map((String value) {
              return DropdownMenuItem<String>(
                value: value,
                child: Text(value),
              );
            }).toList(),
            onChanged: (String? newValue) {
              setState(() {
                _paymentMethod = newValue;
              });
            },
          ),
        ],
      ),
      actions: [
        if (_paymentMethod != null || _dateRange != null)
          TextButton(
            onPressed: () => setState(() {
              _paymentMethod = null;

              _dateRange = null;
            }),
            child: const Text('Clear Filters'),
          ),
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
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
  final VoidCallback onTap;
  final String orderType; // <-- ADDED: Receive orderType

  const _TransactionGridCard(
      {required this.sessionKey,
        required this.sessionOrders,
        required this.onTap,
        required this.restaurantId,
        required this.allMenuItems,
        required this.orderType, // <-- ADDED: Receive orderType
      });

  @override
  State<_TransactionGridCard> createState() => _TransactionGridCardState();
}

class _TransactionGridCardState extends State<_TransactionGridCard> {
  bool _isHovered = false;

  Map<String, OrderItem> _aggregateOrders(List<DocumentSnapshot> orders) {
    final aggregatedItems = <String, OrderItem>{};

    for (var orderDoc in orders) {
      final orderData = orderDoc.data() as Map<String, dynamic>;

      final items = List<Map<String, dynamic>>.from(orderData['items'] ?? []);

      for (var itemMap in items) {
        final item = OrderItem.fromMap(itemMap, widget.allMenuItems);

        if (aggregatedItems.containsKey(item.uniqueId)) {
          aggregatedItems[item.uniqueId]!.quantity += item.quantity;
        } else {
          aggregatedItems[item.uniqueId] = item;
        }
      }
    }

    return aggregatedItems;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final finalTransaction =
    widget.sessionOrders.first.data() as Map<String, dynamic>;

    final billingDetails =
        finalTransaction['billingDetails'] as Map<String, dynamic>? ?? {};

    final billedAt = (billingDetails['billedAt'] as Timestamp?)?.toDate();

    final formatter = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

    final total = billingDetails['finalTotal'] ?? 0.0;

    final paymentMethod = billingDetails['paymentMethod'] ?? 'N/A';

    // --- FIX: Use billNumber from billingDetails if available ---
    final billNumber = billingDetails['billNumber']?.toString() ??
        widget.sessionOrders.first.id.substring(0, 8).toUpperCase();
    // -----------------------------------------------------------

    final aggregatedItems = _aggregateOrders(widget.sessionOrders);

    final totalItems =
    aggregatedItems.values.fold(0, (sum, item) => sum + item.quantity);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedScale(
        scale: _isHovered ? 1.05 : 1.0,
        duration: const Duration(milliseconds: 200),
        child: GestureDetector(
          onTap: widget.onTap,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _isHovered
                      ? theme.primaryColor.withOpacity(0.5)
                      : theme.dividerColor.withOpacity(0.2),
                  width: 1.5,
                ),
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.surface.withOpacity(0.5),
                    theme.colorScheme.surface.withOpacity(0.2),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          widget.sessionKey,
                          style: theme.textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Chip(
                        label: Text(widget.orderType),
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        labelStyle: theme.textTheme.bodySmall,
                        backgroundColor: theme.primaryColor.withOpacity(0.1),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Bill #$billNumber',
                    style: theme.textTheme.bodySmall,
                  ),
                  const Divider(height: 16),
                  Expanded(
                    child: ListView(
                      children: [
                        ...aggregatedItems.values.map((item) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2.0),
                            child: Row(
                              children: [
                                Text('${item.quantity}x',
                                    style: theme.textTheme.bodySmall),
                                const SizedBox(width: 8),
                                Expanded(
                                    child: Text(item.menuItem.name,
                                        style: theme.textTheme.bodySmall)),
                              ],
                            ),
                          );
                        }).toList(),
                      ],
                    ),
                  ),
                  const Divider(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (billedAt != null)
                              Text(
                                DateFormat.yMMMd().format(billedAt),
                                style: theme.textTheme.bodySmall,
                                overflow: TextOverflow.ellipsis,
                              ),
                            if (billedAt != null)
                              Text(
                                DateFormat.jm().format(billedAt),
                                style: theme.textTheme.bodySmall,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          formatter.format(total),
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Icon(Icons.payment,
                                size: 16,
                                color: theme.textTheme.bodySmall?.color),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Paid with $paymentMethod',
                                style: theme.textTheme.bodySmall,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Row(
                          children: [
                            Icon(Icons.shopping_cart_checkout,
                                size: 16,
                                color: theme.textTheme.bodySmall?.color),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '$totalItems Items',
                                style: theme.textTheme.bodySmall,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
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

  const _BillPreviewPanel({
    super.key, // Use super.key
    required this.restaurantId,
    required this.sessionKey,
    required this.sessionOrders,
    required this.allMenuItems,
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

  @override
  Widget build(BuildContext context) {
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
              child: ElevatedButton.icon(
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
                ),
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