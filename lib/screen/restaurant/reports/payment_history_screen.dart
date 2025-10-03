import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cravy/models/order_models.dart';
import 'package:cravy/screen/restaurant/billing_setup/bill_design_screen.dart';
import 'package:cravy/screen/restaurant/menu/menu_screen.dart';
import 'package:cravy/screen/restaurant/orders/bill_template_screen.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:ui';

import '../billing_setup/manage_coupon_screen.dart';
import '../tables_and_reservations/tables_and_reservations_screen.dart';
import '../../../models/supplier_model.dart'; // Import PurchaseOrder model

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
      });
    }
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  // New state setter to handle session selection from any list
  void _updateSelectedSession(String key, List<DocumentSnapshot>? orders) {
    setState(() {
      _selectedSessionKey = key;
      _selectedSessionOrders = orders;
    });
  }

  @override
  Widget build(BuildContext context) {
    _tabController ??= TabController(length: 3, vsync: this); // 3 main tabs

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
                isScrollable: false,
                tabs: const [
                  Tab(text: 'All'),
                  Tab(text: 'Restaurant Payments'),
                  Tab(text: 'Supplier Payments'),
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

  // Helper to build the wide-screen detail panel content
  Widget _buildDetailPanel({required bool isWide}) {
    if (_selectedSessionKey == null) {
      return const Center(
          child: Text('Select a transaction to see the details.'));
    }

    if (_selectedSessionOrders != null) {
      // Restaurant Payment Selected (sessionOrders is non-null)
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: _FullBillPreview(
          restaurantId: widget.restaurantId,
          sessionKey: _selectedSessionKey!,
          sessionOrders: _selectedSessionOrders!,
          allMenuItems: _allMenuItems,
        ),
      );
    } else {
      // Supplier Payment Selected (sessionOrders is null)
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
    }
  }
}

// --- 1. ALL TRANSACTIONS VIEW ---

class _AllTransactionsView extends StatelessWidget {
  final String restaurantId;
  final DateTimeRange? selectedDateRange;
  final String? selectedPaymentMethod;
  final List<MenuItem> allMenuItems;
  final Function(String, List<DocumentSnapshot>?) onSelectSession;

  const _AllTransactionsView({
    required this.restaurantId,
    this.selectedDateRange,
    this.selectedPaymentMethod,
    required this.allMenuItems,
    required this.onSelectSession,
  });

  Future<List<Map<String, dynamic>>> _fetchCombinedTransactions() async {
    // 1. Fetch Restaurant Orders
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
      restaurantTransactions.add({
        'type': 'restaurant',
        'key': key,
        'date': (billingDetails['billedAt'] as Timestamp?)?.toDate() ??
            DateTime.fromMillisecondsSinceEpoch(0),
        'amount': billingDetails['finalTotal'] ?? 0.0,
        'method': billingDetails['paymentMethod'] ?? 'N/A',
        'orders': orders,
      });
    });

    // 2. Fetch Supplier Payments
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

    // 3. Combine and Sort
    final allTransactions = [...restaurantTransactions, ...supplierTransactions];
    allTransactions.sort(
            (a, b) => (b['date'] as DateTime).compareTo(a['date'] as DateTime));
    return allTransactions;
  }

  @override
  Widget build(BuildContext context) {
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
        final isWide = MediaQuery.of(context).size.width > 800;

        return GridView.builder(
          padding: const EdgeInsets.all(16.0),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: isWide ? 2 : 1,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: isWide ? 1.5 : 1.2,
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
                onTap: () {
                  onSelectSession(transaction['key'], sessionOrders);
                  if (!isWide) {
                    _showBillPreviewSheet(
                        context, transaction['key'], sessionOrders);
                  }
                },
              );
            } else {
              final po = transaction['purchaseOrder'] as PurchaseOrder;
              return _SupplierTransactionGridCard(
                purchaseOrder: po,
                onTap: () {
                  onSelectSession(po.id, null);
                  if (!isWide) {
                    _showSupplierPreviewSheet(context, po);
                  }
                },
              );
            }
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
            return SingleChildScrollView(
              controller: scrollController,
              child: _FullBillPreview(
                restaurantId: restaurantId,
                sessionKey: sessionKey,
                sessionOrders: sessionOrders,
                allMenuItems: allMenuItems,
              ),
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
}

// --- 2. RESTAURANT PAYMENTS VIEW (re-using old logic) ---

class _RestaurantPaymentsView extends StatefulWidget {
  final String restaurantId;
  final DateTimeRange? selectedDateRange;
  final String? selectedPaymentMethod;
  final List<MenuItem> allMenuItems;
  final Function(String, List<DocumentSnapshot>?) onSelectSession;

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

  // This is the core logic for querying and displaying restaurant payments
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
            groupedSessions.putIfAbsent(sessionKey, () => []).add(order);
          }
        }

        if (groupedSessions.isEmpty) {
          return Center(
              child: Text('No history found for floor: "$floorName".'));
        }

        final sessionKeys = groupedSessions.keys.toList();
        final isWide = MediaQuery.of(context).size.width > 800;

        return GridView.builder(
          padding: const EdgeInsets.all(16.0),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: isWide ? 2 : 1,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: isWide ? 1.5 : 1.2,
          ),
          itemCount: sessionKeys.length,
          itemBuilder: (context, index) {
            final key = sessionKeys[index];
            final sessionOrders = groupedSessions[key]!;
            return _TransactionGridCard(
              restaurantId: widget.restaurantId,
              sessionKey: key,
              sessionOrders: sessionOrders,
              allMenuItems: widget.allMenuItems,
              onTap: () {
                widget.onSelectSession(key, sessionOrders);
                if (!isWide) {
                  _showBillPreviewSheet(context, key, sessionOrders);
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
            return SingleChildScrollView(
              controller: scrollController,
              child: _FullBillPreview(
                restaurantId: widget.restaurantId,
                sessionKey: sessionKey,
                sessionOrders: sessionOrders,
                allMenuItems: widget.allMenuItems,
              ),
            );
          },
        );
      },
    );
  }
}

// --- 3. SUPPLIER PAYMENTS VIEW ---

class _SupplierPaymentsView extends StatelessWidget {
  final String restaurantId;
  final DateTimeRange? selectedDateRange;
  final String? selectedPaymentMethod;
  final Function(String, List<DocumentSnapshot>?) onSelectSession;

  const _SupplierPaymentsView({
    required this.restaurantId,
    this.selectedDateRange,
    this.selectedPaymentMethod,
    required this.onSelectSession,
  });

  @override
  Widget build(BuildContext context) {
    Query query = FirebaseFirestore.instance
        .collection('restaurants')
        .doc(restaurantId)
        .collection('purchaseOrders')
        .where('paymentStatus', isEqualTo: 'Paid') // Only paid orders
        .where('totalAmount', isGreaterThan: 0) // Exclude zero-value orders
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

        final isWide = MediaQuery.of(context).size.width > 800;

        return GridView.builder(
          padding: const EdgeInsets.all(16.0),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: isWide ? 2 : 1,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: isWide ? 1.5 : 1.2,
          ),
          itemCount: paidPurchaseOrders.length,
          itemBuilder: (context, index) {
            final po = paidPurchaseOrders[index];
            return _SupplierTransactionGridCard(
              purchaseOrder: po,
              onTap: () {
                // Pass null for orders as a PurchaseOrder is a single document
                onSelectSession(po.id, null);
                if (!isWide) {
                  _showSupplierPreviewSheet(context, po);
                }
              },
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
              child: _SupplierOrderPreview(po: po), // New Preview Widget
            );
          },
        );
      },
    );
  }
}

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
                  Text(
                    po.supplierName,
                    style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold, color: Colors.lightBlue),
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
                            style: theme.textTheme.bodyMedium,
                          ),
                          Text(
                            'Ordered',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                      Text(
                        formatter.format(po.totalAmount),
                        style: theme.textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const Divider(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.payment,
                              size: 18,
                              color: theme.textTheme.bodyMedium?.color),
                          const SizedBox(width: 8),
                          Text(
                            'Paid with ${po.paymentMethod}',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      ),
                      Chip(
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

  final List<String> _paymentMethods = ['Cash', 'Card', 'UPI', 'Other'];

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

  const _TransactionGridCard(
      {required this.sessionKey,
        required this.sessionOrders,
        required this.onTap,
        required this.restaurantId,
        required this.allMenuItems});

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

    final billNumber =
    widget.sessionOrders.first.id.substring(0, 8).toUpperCase();

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
                  Text(
                    widget.sessionKey,
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
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
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (billedAt != null)
                            Text(
                              DateFormat.yMMMd().format(billedAt),
                              style: theme.textTheme.bodyMedium,
                            ),
                          if (billedAt != null)
                            Text(
                              DateFormat.jm().format(billedAt),
                              style: theme.textTheme.bodySmall,
                            ),
                        ],
                      ),
                      Text(
                        formatter.format(total),
                        style: theme.textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const Divider(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.payment,
                              size: 18,
                              color: theme.textTheme.bodyMedium?.color),
                          const SizedBox(width: 8),
                          Text(
                            'Paid with $paymentMethod',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Icon(Icons.shopping_cart_checkout,
                              size: 18,
                              color: theme.textTheme.bodyMedium?.color),
                          const SizedBox(width: 8),
                          Text(
                            '$totalItems Items',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
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

class _FullBillPreview extends StatefulWidget {
  final String restaurantId;

  final String sessionKey;

  final List<DocumentSnapshot> sessionOrders;

  final List<MenuItem> allMenuItems;

  const _FullBillPreview({
    required this.restaurantId,
    required this.sessionKey,
    required this.sessionOrders,
    required this.allMenuItems,
  });

  @override
  State<_FullBillPreview> createState() => _FullBillPreviewState();
}

class _FullBillPreviewState extends State<_FullBillPreview> {
  Future<Map<String, dynamic>>? _billDetailsFuture;

  @override
  void initState() {
    super.initState();

    _billDetailsFuture = _fetchBillDetails();
  }

  Future<Map<String, dynamic>> _fetchBillDetails() async {
    final restaurantRef = FirebaseFirestore.instance
        .collection('restaurants')
        .doc(widget.restaurantId);

    final restaurantDoc = await restaurantRef.get();

    final restaurantData = restaurantDoc.data() ?? {};

    final defaultBillConfigId = restaurantData['defaultBillConfigId'];

    BillConfiguration? billConfig;

    if (defaultBillConfigId != null) {
      final configDoc = await restaurantRef
          .collection('billConfigurations')
          .doc(defaultBillConfigId)
          .get();

      if (configDoc.exists) {
        billConfig = BillConfiguration.fromFirestore(configDoc);
      }
    }

    CouponModel? appliedCoupon;

    if (widget.sessionOrders.isNotEmpty) {
      final finalTransaction =
      widget.sessionOrders.first.data() as Map<String, dynamic>;

      final billingDetails =
          finalTransaction['billingDetails'] as Map<String, dynamic>? ?? {};

      final couponCode = billingDetails['couponCode'] as String?;

      if (couponCode != null && couponCode.isNotEmpty) {
        final couponSnapshot = await restaurantRef
            .collection('coupons')
            .where('code', isEqualTo: couponCode)
            .get();

        if (couponSnapshot.docs.isNotEmpty) {
          appliedCoupon =
              CouponModel.fromFirestore(couponSnapshot.docs.first);
        }
      }
    }

    return {
      'restaurantName': restaurantData['name'] ?? 'N/A',
      'restaurantAddress': restaurantData['address'] ?? 'N/A',
      'billConfig': billConfig,
    };
  }

  Map<String, OrderItem> _aggregateOrders() {
    final aggregatedItems = <String, OrderItem>{};

    for (var orderDoc in widget.sessionOrders) {
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
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: FutureBuilder<Map<String, dynamic>>(
        future: _billDetailsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
                heightFactor: 5, child: CircularProgressIndicator());
          }

          if (!snapshot.hasData) {
            return const Center(child: Text('Could not load bill details.'));
          }

          final details = snapshot.data!;

          final billConfig = details['billConfig'] as BillConfiguration?;

          final finalTransaction =
          widget.sessionOrders.first.data() as Map<String, dynamic>;

          final billingDetails =
              finalTransaction['billingDetails'] as Map<String, dynamic>? ??
                  {};

          final aggregatedItems = _aggregateOrders().values.toList();

          final subtotal =
          aggregatedItems.fold(0.0, (sum, item) => sum + item.totalPrice);

          final discountPercentage = (billingDetails['discount'] ?? 0.0);

          final staffDiscountAmount = subtotal * discountPercentage;

          double totalAfterStaffDiscount = subtotal - staffDiscountAmount;

          final CouponModel? appliedCoupon = details['coupon'] as CouponModel?;

          double couponDiscountAmount = 0.0;

          if (appliedCoupon != null) {
            if (appliedCoupon.type == 'percentage') {
              couponDiscountAmount =
                  totalAfterStaffDiscount * (appliedCoupon.value / 100.0);
            } else {
              couponDiscountAmount = appliedCoupon.value;
            }
          }

          totalAfterStaffDiscount -= couponDiscountAmount;

          final Map<String, double> calculatedCharges = {};

          if (billConfig != null) {
            for (var charge in billConfig.customCharges) {
              if (charge.isMandatory) {
                final chargeAmount =
                    totalAfterStaffDiscount * (charge.rate / 100.0);
                calculatedCharges[
                '${charge.label} (${charge.rate.toStringAsFixed(1)}%)'] =
                    chargeAmount;
              }
            }
          }

          final billItems = aggregatedItems.map((item) {
            return {
              'name': item.menuItem.name,
              'qty': item.quantity,
              'price': item.singleItemPrice,
              'options':
              item.selectedOptions.map((o) => o.optionName).join(', '),
            };
          }).toList();

          return BillTemplate(
            restaurantName: details['restaurantName'],
            restaurantAddress: details['restaurantAddress'],
            phone: billConfig?.contactPhone ?? 'N/A',
            gst: billConfig?.gstNumber ?? 'N/A',
            footer: billConfig?.footerNote ?? 'Thank you!',
            notes: billConfig?.billNotes ?? '',
            billItems: billItems.cast<Map<String, Object>>(),
            subtotal: subtotal,
            staffDiscount: staffDiscountAmount,
            couponDiscount: couponDiscountAmount,
            calculatedCharges: calculatedCharges,
            total: billingDetails['finalTotal'] ?? 0.0,
            billNumber:
            widget.sessionOrders.first.id.substring(0, 8).toUpperCase(),
            sessionKey: widget.sessionKey,
            paymentMethod: billingDetails['paymentMethod'],
          );
        },
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

// Placeholder for BillTheme
class BillTheme {
  static getThemeByName(String name) {
    return null;
  }
}

// Placeholder for BillTemplate
class BillTemplate extends StatelessWidget {
  final String restaurantName;
  final String restaurantAddress;
  final String phone;
  final String gst;
  final String footer;
  final String notes;
  final List<Map<String, Object>> billItems;
  final double subtotal;
  final double staffDiscount;
  final double couponDiscount;
  final Map<String, double> calculatedCharges;
  final double total;
  final String billNumber;
  final String sessionKey;
  final String paymentMethod;
  final dynamic theme;

  const BillTemplate({
    super.key,
    required this.restaurantName,
    required this.restaurantAddress,
    required this.phone,
    required this.gst,
    required this.footer,
    required this.notes,
    required this.billItems,
    required this.subtotal,
    required this.staffDiscount,
    required this.couponDiscount,
    required this.calculatedCharges,
    required this.total,
    required this.billNumber,
    required this.sessionKey,
    required this.paymentMethod,
    this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(restaurantName,
              style:
              const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          Text(restaurantAddress),
          Text('Phone: $phone'),
          Text('GST: $gst'),
          const Divider(),
          Text('Bill #: $billNumber'),
          Text('Session: $sessionKey'),
          const Divider(),
          for (var item in billItems)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${item['qty']}x ${item['name']}'),
                Text('₹${(item['price'] as double) * (item['qty'] as int)}'),
              ],
            ),
          const Divider(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Subtotal'),
              Text('₹$subtotal'),
            ],
          ),
          if (staffDiscount > 0)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Staff Discount'),
                Text('-₹$staffDiscount'),
              ],
            ),
          if (couponDiscount > 0)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Coupon Discount'),
                Text('-₹$couponDiscount'),
              ],
            ),
          for (var charge in calculatedCharges.entries)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(charge.key),
                Text('₹${charge.value}'),
              ],
            ),
          const Divider(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Text('₹$total',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          const Divider(),
          Text('Paid by: $paymentMethod'),
          const Divider(),
          Text(footer),
        ],
      ),
    );
  }
}