import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cravy/models/order_models.dart';
import 'package:cravy/screen/restaurant/billing_setup/bill_design_screen.dart';
import 'package:cravy/screen/restaurant/billing_setup/manage_coupon_screen.dart';
import 'package:cravy/screen/restaurant/menu/menu_screen.dart';
import 'package:cravy/screen/restaurant/orders/bill_template_screen.dart';
import 'package:cravy/screen/restaurant/orders/create_order_screen.dart';
import 'package:cravy/screen/restaurant/orders/select_menu_items_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:intl/intl.dart';

import '../../../services/table_service.dart';
import '../tables_and_reservations/tables_and_reservations_screen.dart';
import 'order_details_screen.dart';

class OrdersScreen extends StatefulWidget {
  final String restaurantId;
  const OrdersScreen({super.key, required this.restaurantId});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen>
    with TickerProviderStateMixin {
  TabController? _tabController;
  StreamSubscription? _floorSubscription;
  List<FloorModel> _floors = [];
  final ValueNotifier<Map<String, int>> _sessionCounts =
  ValueNotifier<Map<String, int>>({'All': 0});

  List<MenuItem> _allMenuItems = [];

  @override
  void initState() {
    super.initState();
    _setupFloorListener();
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

  void _setupFloorListener() {
    _floorSubscription = FirebaseFirestore.instance
        .collection('restaurants')
        .doc(widget.restaurantId)
        .collection('floors')
        .orderBy('order')
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      final newFloors =
      snapshot.docs.map((doc) => FloorModel.fromFirestore(doc)).toList();

      if (newFloors.length != _floors.length ||
          !newFloors.every((f) => _floors.any((of) => of.id == f.id))) {
        setState(() {
          _floors = newFloors;
          _tabController?.dispose();
          _tabController =
              TabController(length: _floors.length + 1, vsync: this);
        });
      }
    });
  }

  @override
  void dispose() {
    _floorSubscription?.cancel();
    _tabController?.dispose();
    _sessionCounts.dispose();
    super.dispose();
  }

  String _getGroupKey(DocumentSnapshot order) {
    final data = order.data() as Map<String, dynamic>;
    return data['sessionKey'] as String? ?? 'Other Orders';
  }

  @override
  Widget build(BuildContext context) {
    if (_tabController == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final tabs = ['All', ..._floors.map((f) => f.name)];

    // ✨ FIX: Wrap the Scaffold in a Stack and add the background
    return Stack(
      children: [
        const _StaticBackground(),
        Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: const Text('Active Orders'),
            backgroundColor:
            Theme.of(context).scaffoldBackgroundColor.withOpacity(0.85),
            elevation: 0,
            bottom: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabs: tabs.map((name) {
                return ValueListenableBuilder<Map<String, int>>(
                  valueListenable: _sessionCounts,
                  builder: (context, counts, child) {
                    final count = counts[name] ?? 0;
                    return Tab(text: '$name ($count)');
                  },
                );
              }).toList(),
            ),
          ),
          body: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('restaurants')
                .doc(widget.restaurantId)
                .collection('orders')
                .where('isSessionActive', isEqualTo: true)
                .orderBy('createdAt', descending: false)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return _buildEmptyState();
              }

              final allOrders = snapshot.data!.docs;
              final allGroupedOrders = <String, List<DocumentSnapshot>>{};
              for (final order in allOrders) {
                final key = _getGroupKey(order);
                allGroupedOrders.putIfAbsent(key, () => []).add(order);
              }

              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                final newCounts = <String, int>{'All': allGroupedOrders.length};
                for (var floor in _floors) {
                  newCounts[floor.name] = allGroupedOrders.keys
                      .where((key) => key.contains(floor.name))
                      .length;
                }
                if (_sessionCounts.value.toString() != newCounts.toString()) {
                  _sessionCounts.value = newCounts;
                }
              });

              return TabBarView(
                controller: _tabController,
                children: tabs.map((tabName) {
                  final Map<String, List<DocumentSnapshot>> filteredGroups;
                  if (tabName == 'All') {
                    filteredGroups = allGroupedOrders;
                  } else {
                    filteredGroups = Map.fromEntries(
                      allGroupedOrders.entries.where(
                            (entry) => entry.key.contains(tabName),
                      ),
                    );
                  }
                  return _SessionList(
                    restaurantId: widget.restaurantId,
                    groupedOrders: filteredGroups,
                    allMenuItems: _allMenuItems,
                  );
                }).toList(),
              );
            },
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) =>
                      CreateOrderScreen(restaurantId: widget.restaurantId),
                ),
              );
            },
            tooltip: 'Create New Order',
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long_outlined,
              size: 80, color: Theme.of(context).dividerColor),
          const SizedBox(height: 16),
          Text('No active orders found.',
              style: Theme.of(context).textTheme.headlineSmall),
        ],
      ),
    );
  }
}

class _SessionList extends StatefulWidget {
  final String restaurantId;
  final Map<String, List<DocumentSnapshot>> groupedOrders;
  final List<MenuItem> allMenuItems;

  const _SessionList(
      {required this.restaurantId,
        required this.groupedOrders,
        required this.allMenuItems,});

  @override
  State<_SessionList> createState() => _SessionListState();
}

class _SessionListState extends State<_SessionList> {
  String? _selectedSessionKey;
  void _selectSession(String sessionKey) {
    setState(() {
      if (_selectedSessionKey == sessionKey) {
        _selectedSessionKey = null;
      } else {
        _selectedSessionKey = sessionKey;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.groupedOrders.isEmpty) {
      return const Center(child: Text('No active sessions on this floor.'));
    }

    final sessionKeys = widget.groupedOrders.keys.toList();

    // ✨ FIX: Use LayoutBuilder to switch between ListView and GridView
    return LayoutBuilder(
      builder: (context, constraints) {
        const double breakpoint = 800.0;
        final bool isWide = constraints.maxWidth > breakpoint;

        if (isWide) {
          // --- DESKTOP/WEB: GRID VIEW ---
          final crossAxisCount = (constraints.maxWidth / 420).floor().clamp(2, 4);
          return AnimationLimiter(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
              itemCount: sessionKeys.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 16.0,
                mainAxisSpacing: 16.0,
                childAspectRatio: 0.9,
              ),
              itemBuilder: (context, index) {
                final sessionKey = sessionKeys[index];
                final sessionOrders = widget.groupedOrders[sessionKey]!;
                return AnimationConfiguration.staggeredGrid(
                  position: index,
                  duration: const Duration(milliseconds: 375),
                  columnCount: crossAxisCount,
                  child: ScaleAnimation(
                    child: FadeInAnimation(
                      child: _OrderSessionCard(
                        key: ValueKey(sessionKey),
                        restaurantId: widget.restaurantId,
                        sessionKey: sessionKey,
                        sessionOrders: sessionOrders,
                        isSelected: true,
                        onTap: () {}, // Dummy onTap, interaction is disabled in child
                        allMenuItems: widget.allMenuItems,
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        } else {
          // --- MOBILE: LIST VIEW ---
          return AnimationLimiter(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
              itemCount: sessionKeys.length,
              itemBuilder: (context, index) {
                final sessionKey = sessionKeys[index];
                final sessionOrders = widget.groupedOrders[sessionKey]!;
                return AnimationConfiguration.staggeredList(
                  position: index,
                  duration: const Duration(milliseconds: 375),
                  child: SlideAnimation(
                    verticalOffset: 50.0,
                    child: FadeInAnimation(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 12.0),
                        child: _OrderSessionCard(
                          key: ValueKey(sessionKey),
                          restaurantId: widget.restaurantId,
                          sessionKey: sessionKey,
                          sessionOrders: sessionOrders,
                          isSelected: _selectedSessionKey == sessionKey,
                          onTap: () => _selectSession(sessionKey),
                          allMenuItems: widget.allMenuItems,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        }
      },
    );
  }
}


class _OrderSessionCard extends StatefulWidget {
  final String restaurantId;
  final String sessionKey;
  final List<DocumentSnapshot> sessionOrders;
  final VoidCallback onTap;
  final bool isSelected;
  final List<MenuItem> allMenuItems;

  const _OrderSessionCard({
    super.key,
    required this.restaurantId,
    required this.sessionKey,
    required this.sessionOrders,
    required this.onTap,
    this.isSelected = false,
    required this.allMenuItems,
  });

  @override
  State<_OrderSessionCard> createState() => _OrderSessionCardState();
}

class _OrderSessionCardState extends State<_OrderSessionCard> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final TextEditingController _discountController = TextEditingController();
  final TextEditingController _couponController = TextEditingController();
  final TextEditingController _adHocChargeController = TextEditingController();
  final TextEditingController _adHocChargeLabelController = TextEditingController();

  String _adHocChargeType = 'percentage';
  double _discountPercentage = 0.0;
  CouponModel? _appliedCoupon;
  String? _couponError;
  BillConfiguration? _billConfig;
  bool _showDiscounts = false;

  @override
  void initState() {
    super.initState();
    _loadBillConfiguration();
    _discountController.addListener(_onDiscountChanged);
    _adHocChargeController.addListener(_recalculateBill);
    _adHocChargeLabelController.addListener(_recalculateBill);
  }

  @override
  void dispose() {
    _discountController.dispose();
    _couponController.dispose();
    _adHocChargeController.dispose();
    _adHocChargeLabelController.dispose();
    super.dispose();
  }

  void _recalculateBill() {
    if (mounted) setState(() {});
  }

  Future<void> _loadBillConfiguration() async {
    final restaurantRef = FirebaseFirestore.instance
        .collection('restaurants')
        .doc(widget.restaurantId);
    final restaurantDoc = await restaurantRef.get();
    final defaultBillConfigId = restaurantDoc.data()?['defaultBillConfigId'];

    if (defaultBillConfigId != null) {
      final configDoc = await restaurantRef
          .collection('billConfigurations')
          .doc(defaultBillConfigId)
          .get();
      if (configDoc.exists && mounted) {
        setState(() {
          _billConfig = BillConfiguration.fromFirestore(configDoc);
        });
      }
    }
  }

  void _onDiscountChanged() {
    final value = double.tryParse(_discountController.text) ?? 0.0;
    if (value >= 0 && value <= 100) {
      setState(() {
        _discountPercentage = value / 100.0;
      });
    }
  }

  Future<void> _applyCoupon(double subtotal) async {
    final code = _couponController.text.trim().toUpperCase();
    if (code.isEmpty) {
      setState(() {
        _appliedCoupon = null;
        _couponError = null;
      });
      return;
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('restaurants')
          .doc(widget.restaurantId)
          .collection('coupons')
          .where('code', isEqualTo: code)
          .get();

      if (snapshot.docs.isEmpty) {
        setState(() {
          _appliedCoupon = null;
          _couponError = 'Invalid Coupon Code';
        });
        return;
      }

      final coupon = CouponModel.fromFirestore(snapshot.docs.first);

      if (subtotal * (1 - _discountPercentage) < coupon.minOrderAmount) {
        setState(() {
          _appliedCoupon = null;
          _couponError =
          'Min order amount of ₹${coupon.minOrderAmount.toStringAsFixed(2)} not met after staff discount.';
        });
        return;
      }

      setState(() {
        _appliedCoupon = coupon;
        _couponError = null;
      });
    } catch (e) {
      setState(() {
        _appliedCoupon = null;
        _couponError = 'Error applying coupon.';
      });
    }
  }

  double _calculateCouponDiscount(double subtotal) {
    if (_appliedCoupon == null) return 0.0;
    final discountedSubtotal = subtotal * (1 - _discountPercentage);

    if (discountedSubtotal < _appliedCoupon!.minOrderAmount) return 0.0;

    if (_appliedCoupon!.type == 'percentage') {
      return discountedSubtotal * (_appliedCoupon!.value / 100.0);
    } else {
      return _appliedCoupon!.value;
    }
  }

  MapEntry<String, double> _calculateAdHocCharge(
      double subtotalAfterDiscounts) {
    final input = _adHocChargeController.text.trim();
    final value = double.tryParse(input) ?? 0.0;
    final userLabel = _adHocChargeLabelController.text.trim();
    String finalLabel = userLabel.isNotEmpty ? userLabel : 'Ad-Hoc Charge';

    if (value <= 0) return MapEntry(finalLabel, 0.0);

    if (_adHocChargeType == 'percentage') {
      final amount = subtotalAfterDiscounts * (value / 100.0);
      finalLabel = '$finalLabel (${input}%)';
      return MapEntry(finalLabel, amount);
    } else {
      finalLabel = '$finalLabel (Fixed)';
      return MapEntry(finalLabel, value);
    }
  }

  List<OrderItem> _aggregateItems(List<DocumentSnapshot> sessionOrders) {
    final aggregatedItems = <String, OrderItem>{};
    for (var orderDoc in sessionOrders) {
      final orderData = orderDoc.data() as Map<String, dynamic>;
      final items = (orderData['items'] as List<dynamic>? ?? [])
          .map((itemData) => OrderItem.fromMap(itemData, widget.allMenuItems))
          .toList();

      for (var item in items) {
        if (aggregatedItems.containsKey(item.uniqueId)) {
          aggregatedItems[item.uniqueId]!.quantity += item.quantity;
        } else {
          aggregatedItems[item.uniqueId] = item;
        }
      }
    }
    return aggregatedItems.values.toList();
  }

  Future<void> _removeItemFromOrder(OrderItem itemToRemove, List<DocumentSnapshot> sessionOrders) async {
    DocumentSnapshot? targetOrderDoc;
    Map<String, dynamic>? targetOrderData;
    int itemIndexInOrder = -1;

    for (var orderDoc in sessionOrders) {
      var orderData = orderDoc.data() as Map<String, dynamic>;
      var items = List<Map<String, dynamic>>.from(orderData['items'] ?? []);
      var foundIndex = items.indexWhere((itemMap) {
        final orderItem = OrderItem.fromMap(itemMap, widget.allMenuItems);
        return orderItem.uniqueId == itemToRemove.uniqueId;
      });

      if (foundIndex != -1) {
        targetOrderDoc = orderDoc;
        targetOrderData = orderData;
        itemIndexInOrder = foundIndex;
        break;
      }
    }

    if (targetOrderDoc == null || targetOrderData == null) {
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not find the item to remove.')),
        );
      }
      return;
    }

    final orderRef = targetOrderDoc.reference;
    var items = List<Map<String, dynamic>>.from(targetOrderData['items']);
    var itemInOrder = items[itemIndexInOrder];
    int currentQuantity = itemInOrder['quantity'];

    if (currentQuantity > 1) {
      items[itemIndexInOrder]['quantity'] = currentQuantity - 1;
      final newTotal = items.fold<double>(0.0, (sum, item) => sum + (item['price'] as num) * (item['quantity'] as int));
      await orderRef.update({'items': items, 'totalAmount': newTotal});
    } else {
      items.removeAt(itemIndexInOrder);
      if (items.isEmpty) {
        await orderRef.delete();
      } else {
        final newTotal = items.fold<double>(0.0, (sum, item) => sum + (item['price'] as num) * (item['quantity'] as int));
        await orderRef.update({'items': items, 'totalAmount': newTotal});
      }
    }
  }

  void _showPaymentDialog(
      BuildContext context,
      double grandTotal,
      double couponDiscount,
      Map<String, double> finalCharges,
      List<DocumentSnapshot> sessionOrders,
      ) {
    // Capture the Navigator and ScaffoldMessenger BEFORE showing the dialog.
    // This ensures they are still valid even if this widget gets disposed.
    final navigator = Navigator.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    showDialog(
      context: context,
      builder: (dialogContext) => _PaymentMethodDialog(
        grandTotal: grandTotal,
        onConfirm: (paymentMethod) async {
          // 1. Pop the payment selection dialog first. Use the captured navigator.
          navigator.pop();

          // 2. Show a loading indicator. It's safe to use the navigator's context
          //    because the navigator's state persists.
          showDialog(
            context: navigator.context,
            barrierDismissible: false,
            builder: (BuildContext context) {
              return const Center(child: CircularProgressIndicator());
            },
          );

          try {
            // 3. Perform the asynchronous database operation.
            await _markOrderAsPaid(
              _discountPercentage,
              _appliedCoupon?.code,
              couponDiscount,
              paymentMethod,
              grandTotal,
              finalCharges,
              sessionOrders,
            );

            // 4. Pop the loading dialog using the captured navigator.
            navigator.pop();

            // 5. Push the new screen using the captured navigator.

                await showPrintedBill(
                context: navigator.context,
                restaurantId: widget.restaurantId,
                sessionKey: widget.sessionKey,
                paymentMethod: paymentMethod,

            );
          } catch (e) {
            // 6. If an error occurs, pop the loading dialog.
            navigator.pop();

            // 7. Show a SnackBar using the captured scaffoldMessenger.
            scaffoldMessenger.showSnackBar(
              SnackBar(content: Text('Payment failed: ${e.toString()}')),
            );
          }
        },
      ),
    );
  }





  Future<void> _markOrderAsPaid(
      double discountPercentage,
      String? couponCode,
      double couponDiscount,
      String paymentMethod,
      double finalTotal,
      Map<String, double> finalCharges,
      List<DocumentSnapshot> sessionOrders,
      ) async {

    final restaurantRef = FirebaseFirestore.instance.collection('restaurants').doc(widget.restaurantId);

    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final restaurantDoc = await transaction.get(restaurantRef);
      final restaurantData = restaurantDoc.data() as Map<String, dynamic>?;

      int currentBillCount;

      // ✨ FIX: Check if the counter field exists.
      if (restaurantData != null && restaurantData.containsKey('totalBillCount')) {
        // If it exists, use it.
        currentBillCount = restaurantData['totalBillCount'];
      } else {
        // If not, this is the first time. Count all previous paid orders to initialize.
        final paidOrdersSnapshot = await restaurantRef
            .collection('orders')
            .where('isPaid', isEqualTo: true)
            .get();
        currentBillCount = paidOrdersSnapshot.docs.length;
      }

      final newBillNumber = (currentBillCount + 1).toString().padLeft(4, '0');

      // Increment the counter for the next order.
      // FieldValue.increment(1) will create the field if it doesn't exist, starting from 1.
      // But we set it explicitly to be safe and clear.
      transaction.update(restaurantRef, {
        'totalBillCount': currentBillCount + 1,
      });

      // Update all unpaid orders with the new bill number.
      final List<Map<String, dynamic>> chargesList = finalCharges.entries
          .map((e) => {'label': e.key, 'amount': e.value})
          .toList();

      final unpaidOrders = sessionOrders
          .where((doc) => (doc.data() as Map<String, dynamic>)['isPaid'] != true)
          .toList();

      for (var orderDoc in unpaidOrders) {
        transaction.update(orderDoc.reference, {
          'isPaid': true,
          'billingDetails': {
            'billNumber': newBillNumber,
            'discount': discountPercentage,
            'couponCode': couponCode,
            'couponDiscount': couponDiscount,
            'finalTotal': finalTotal,
            'paymentMethod': paymentMethod,
            'billedAt': FieldValue.serverTimestamp(),
            'appliedCharges': chargesList,
          }
        });
      }
    });
  }

  // ✨ NEW: Mark a single paid order as unpaid
  Future<void> _markSingleOrderAsUnpaid(DocumentSnapshot orderToUpdate) async {
    final bool? confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark as Unpaid?'),
        content: const Text(
            'This will mark this specific order as unpaid and clear its billing details. Are you sure?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Mark Unpaid',
                style:
                TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await orderToUpdate.reference.update({
        'isPaid': false,
        'billingDetails': FieldValue.delete(),
      });
    }
  }


  Future<void> _closeSession(List<DocumentSnapshot> sessionOrders) async {
    final bool? confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Close Session?'),
        content: const Text(
            'This will finalize the bill, release the tables, and close the session. This action cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Confirm & Close',
                style:
                TextStyle(color: Theme.of(context).colorScheme.primary)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final batch = FirebaseFirestore.instance.batch();
    final tableAssignments = <String, Set<int>>{};

    for (final orderDoc in sessionOrders) {
      final data = orderDoc.data() as Map<String, dynamic>;
      final assignmentMap = data['assignment'] as Map<String, dynamic>?;

      if (assignmentMap != null) {
        assignmentMap.forEach((tableId, seatsList) {
          tableAssignments
              .putIfAbsent(tableId, () => {})
              .addAll(Set<int>.from(seatsList));
        });
      }

      batch.update(orderDoc.reference, {'isSessionActive': false});
    }

    await batch.commit();

    if (tableAssignments.isNotEmpty) {
      await updateTableSessionStatus(
        widget.restaurantId,
        tableAssignments,
        widget.sessionKey,
        closeSession: true,
      );
    }
    if(mounted){
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session closed successfully!')),
      );
    }
  }

  void _showAddItemsSheet(List<DocumentSnapshot> sessionOrders) async {
    final List<OrderItem>? result = await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.9,
        maxChildSize: 0.9,
        builder: (_, controller) =>
            SelectMenuItemsScreen(restaurantId: widget.restaurantId),
      ),
    );

    if (result != null) {
      _addItemsToSession(sessionOrders, result);
    }
  }

  Future<void> _addItemsToSession(List<DocumentSnapshot> sessionOrders, List<OrderItem> newItems) async {
    if (newItems.isEmpty) {
      return;
    }

    final itemsForFirestore = newItems.map((item) {
      return {
        'menuItemId': item.menuItem.id,
        'name': item.menuItem.name,
        'price': item.menuItem.price,
        'quantity': item.quantity,
        'status': 'Pending', // Default status
        'selectedOptions': item.selectedOptions.map((o) => o.toMap()).toList(),
      };
    }).toList();

    final totalAmount =
    newItems.fold(0.0, (sum, item) => sum + item.totalPrice);

    final firstOrderData = sessionOrders.first.data() as Map<String, dynamic>;

    await FirebaseFirestore.instance
        .collection('restaurants')
        .doc(widget.restaurantId)
        .collection('orders')
        .add({
      'orderType': firstOrderData['orderType'],
      'sessionKey': widget.sessionKey,
      'assignment': firstOrderData['assignment'],
      'assignmentLabel': firstOrderData['assignmentLabel'],
      'tableIds': firstOrderData['tableIds'],
      'items': itemsForFirestore,
      'totalAmount': totalAmount,
      'status': 'Pending',
      'createdAt': FieldValue.serverTimestamp(),
      'customers': firstOrderData['customers'],
      'deliveryAddress': firstOrderData['deliveryAddress'],
      'notes': '', // New order, new notes
      'isSessionActive': true,
      'isPaid': false, // Ensure new orders are marked as unpaid
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final sessionOrders = widget.sessionOrders;
    if (sessionOrders.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final formatter =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹');

    final bool isWide = MediaQuery.of(context).size.width > 800.0;

    final unpaidOrders = sessionOrders.where((doc) => (doc.data() as Map<String, dynamic>)['isPaid'] != true).toList();
    final paidOrders = sessionOrders.where((doc) => (doc.data() as Map<String, dynamic>)['isPaid'] == true).toList();

    double totalAmount = sessionOrders.fold(0.0, (sum, doc) => sum + ((doc.data() as Map<String, dynamic>)['totalAmount'] ?? 0.0));
    final bool isFullyPaid = unpaidOrders.isEmpty;

    final aggregatedUnpaidItems = _aggregateItems(unpaidOrders);
    final aggregatedPaidItems = _aggregateItems(paidOrders);

    final subtotal = aggregatedUnpaidItems.fold(0.0, (sum, item) => sum + item.totalPrice);
    final discountAmount = subtotal * _discountPercentage;
    final couponDiscount = _calculateCouponDiscount(subtotal);

    double runningTotal = subtotal - discountAmount - couponDiscount;
    final Map<String, double> finalCharges = {};

    if (_billConfig != null) {
      for (var charge in _billConfig!.customCharges) {
        if (charge.isMandatory) {
          final chargeAmount = runningTotal * (charge.rate / 100.0);
          finalCharges['${charge.label} (${charge.rate.toStringAsFixed(1)}%)'] = chargeAmount;
          runningTotal += chargeAmount;
        }
      }
    }

    final adHocCharge = _calculateAdHocCharge(runningTotal);
    if (adHocCharge.value > 0) {
      finalCharges[adHocCharge.key] = adHocCharge.value;
      runningTotal += adHocCharge.value;
    }
    final grandTotal = runningTotal;

    final allItems = sessionOrders
        .expand((doc) => List<Map<String, dynamic>>.from(
        (doc.data() as Map<String, dynamic>)['items'] ?? []))
        .toList();

    String latestStatus = 'Pending';
    Color statusColor = Colors.grey;
    if (allItems.isNotEmpty) {
      if (allItems.any((item) => (item['status'] ?? 'Pending') == 'Making')) {
        latestStatus = 'Making';
        statusColor = Colors.orange;
      } else if (allItems.every((item) => (item['status'] ?? 'Pending') == 'Completed')) {
        latestStatus = 'Completed';
        statusColor = Colors.green;
      }
    }

    final sortedOrders = List<DocumentSnapshot>.from(sessionOrders)
      ..sort((a, b) {
        final aTimestamp = (a.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
        final bTimestamp = (b.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
        if (aTimestamp == null) return 1;
        if (bTimestamp == null) return -1;
        return aTimestamp.compareTo(bTimestamp);
      });

    final Timestamp? firstOrderTimestamp = (sortedOrders.first.data()
    as Map<String, dynamic>)['createdAt'];

    String title = widget.sessionKey;
    String? subtitle;
    if (widget.sessionKey.contains(' - ')) {
      final parts = widget.sessionKey.split(' - ');
      subtitle = parts[0];
      title = parts.sublist(1).join(' - ');
    }

    // ✨ MAJOR FIX: Use a different layout for wide screens to prevent crashes.
    // Instead of a single complex ExpansionTile, we now have two distinct layouts.
    if (isWide) {
      // --- WIDE LAYOUT (Desktop/Web) ---
      // Uses Column + Expanded + SingleChildScrollView for a scrollable content area
      // inside a fixed-size card. This solves the "unbounded height" error.
      return Card(
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 5,
              child: Container(color: statusColor),
            ),
            Column(
              children: [
                // --- Card Header ---
                ListTile(
                  title: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Text(
                      '${subtitle ?? ''}${subtitle != null && firstOrderTimestamp != null ? ' • ' : ''}${firstOrderTimestamp != null ? DateFormat.jm().format(firstOrderTimestamp.toDate()) : ''}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        formatter.format(totalAmount),
                        style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold, color: theme.primaryColor),
                      ),
                      const SizedBox(height: 4),
                      isFullyPaid
                          ? Text('Paid', style: theme.textTheme.bodySmall?.copyWith(color: Colors.green))
                          : Text('Payable', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
                    ],
                  ),
                ),
                // --- Scrollable Card Body ---
                Expanded(
                  child: Container(
                    color: theme.colorScheme.surface.withOpacity(0.2),
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: _buildCardContent(theme, formatter, aggregatedPaidItems, paidOrders, aggregatedUnpaidItems, unpaidOrders, subtotal, discountAmount, couponDiscount, finalCharges, grandTotal, isFullyPaid, sessionOrders),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    } else {
      // --- NARROW LAYOUT (Mobile) ---
      // Keeps the original ExpansionTile behavior.
      return Card(
        elevation: widget.isSelected ? 4 : 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 5,
              child: Container(color: statusColor),
            ),
            ExpansionTile(
              childrenPadding: EdgeInsets.zero,
              shape: const Border(),
              collapsedShape: const Border(),
              initiallyExpanded: widget.isSelected,
              onExpansionChanged: (isExpanding) => widget.onTap(),
              title: Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Text(
                      '${subtitle ?? ''}${subtitle != null && firstOrderTimestamp != null ? ' • ' : ''}${firstOrderTimestamp != null ? DateFormat.jm().format(firstOrderTimestamp.toDate()) : ''}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  if (!widget.isSelected)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Wrap(
                        spacing: 4.0,
                        runSpacing: 4.0,
                        children: _aggregateItems(sessionOrders).map((item) {
                          return Chip(
                            label: Text('${item.quantity}x ${item.menuItem.name}'),
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                          );
                        }).toList(),
                      ),
                    ),
                ],
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatter.format(totalAmount),
                    style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold, color: theme.primaryColor),
                  ),
                  const SizedBox(height: 4),
                  isFullyPaid
                      ? Text('Paid', style: theme.textTheme.bodySmall?.copyWith(color: Colors.green))
                      : Text('Payable', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
                ],
              ),
              children: [
                Container(
                  color: theme.colorScheme.surface.withOpacity(0.2),
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _buildCardContent(theme, formatter, aggregatedPaidItems, paidOrders, aggregatedUnpaidItems, unpaidOrders, subtotal, discountAmount, couponDiscount, finalCharges, grandTotal, isFullyPaid, sessionOrders),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }
  }
  List<Widget> _buildCardContent(
      ThemeData theme,
      NumberFormat formatter,
      List<OrderItem> aggregatedPaidItems,
      List<DocumentSnapshot> paidOrders,
      List<OrderItem> aggregatedUnpaidItems,
      List<DocumentSnapshot> unpaidOrders,
      double subtotal,
      double discountAmount,
      double couponDiscount,
      Map<String, double> finalCharges,
      double grandTotal,
      bool isFullyPaid,
      List<DocumentSnapshot> sessionOrders,
      ) {
    final String orderType = (sessionOrders.first.data() as Map<String, dynamic>)['orderType'] ?? 'Dine-In';
    return [
      if (aggregatedPaidItems.isNotEmpty) ...[
        Text('Already Paid', style: theme.textTheme.titleSmall?.copyWith(color: Colors.green)),
        const Divider(height: 12),
        ...paidOrders.map((order) {
          final itemsInOrder = _aggregateItems([order]);
          return Opacity(
            opacity: 0.7,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(itemsInOrder.map((e) => '${e.quantity}x ${e.menuItem.name}').join(', ')),
              trailing: PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 20),
                onSelected: (value) {
                  if (value == 'mark_unpaid') {
                    _markSingleOrderAsUnpaid(order);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'mark_unpaid',
                    child: Text('Mark as Unpaid'),
                  ),
                ],
              ),
            ),
          );
        }),
        const Divider(height: 24),
      ],

      if (aggregatedUnpaidItems.isNotEmpty) ...[
        Text('Items to Bill', style: theme.textTheme.titleSmall),
        const Divider(height: 12),
        ...aggregatedUnpaidItems.map((item) => ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text('${item.quantity}x ${item.menuItem.name}'),
          subtitle: item.selectedOptions.isNotEmpty
              ? Text(item.selectedOptions.map((o) => o.optionName).join(', '))
              : null,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(formatter.format(item.totalPrice)),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: () => _removeItemFromOrder(item, unpaidOrders),
                color: theme.colorScheme.error,
              )
            ],
          ),
        )),
      ] else
        const Center(child: Padding(
          padding: EdgeInsets.symmetric(vertical: 8.0),
          child: Text('All items in this session are paid.'),
        )),

      const Divider(height: 16),

      InkWell(
        onTap: () => setState(() => _showDiscounts = !_showDiscounts),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Discounts & Charges', style: theme.textTheme.titleSmall),
              Icon(_showDiscounts ? Icons.expand_less : Icons.expand_more, size: 20),
            ],
          ),
        ),
      ),
      AnimatedSize(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        child: _showDiscounts
            ? _buildDiscountAndChargesSection(subtotal)
            : const SizedBox.shrink(),
      ),
      const Divider(height: 16),
      Text('Final Bill (for unpaid items)', style: theme.textTheme.titleSmall),
      const SizedBox(height: 8),
      _buildSummaryRow('Subtotal', subtotal, theme, isTotal: true),
      if (discountAmount > 0)
        _buildSummaryRow('Staff Discount', -discountAmount, theme),
      if (_appliedCoupon != null)
        _buildSummaryRow('Coupon: ${_appliedCoupon!.code}', -couponDiscount, theme),
      if (finalCharges.isNotEmpty) ...[
        const Divider(height: 12, thickness: 0.5),
        ...finalCharges.entries.map((entry) {
          return _buildSummaryRow(entry.key, entry.value, theme);
        }).toList(),
      ],
      const Divider(height: 16),
      _buildSummaryRow('Grand Total', grandTotal, theme, isGrandTotal: true),
      const SizedBox(height: 20),

      if (!isFullyPaid)
        ElevatedButton.icon(
          onPressed: ()=>_showPaymentDialog(context,grandTotal, couponDiscount, finalCharges, unpaidOrders),
          icon: const Icon(Icons.payment),
          label: Text('Pay ${formatter.format(grandTotal)}'),
          style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16)),
        )
      else
        const Center(child: Text("✅ Session Fully Paid")),

      const SizedBox(height: 8),
      Wrap(
        alignment: WrapAlignment.spaceAround, // This distributes the buttons nicely
        spacing: 8.0, // Horizontal space between buttons
        runSpacing: 4.0, // Vertical space if they wrap
        children: [
          TextButton.icon(
            icon: const Icon(Icons.add_shopping_cart, size: 18),
            label: const Text('Add Item'),
            onPressed: () => _showAddItemsSheet(sessionOrders),
          ),
          if (orderType == 'Dine-In')
            TextButton.icon(
              icon: const Icon(Icons.open_with, size: 18),
              label: const Text('Shift Table'),
              onPressed: () => shiftTableSession(context, widget.restaurantId, sessionOrders),
            ),
          if (isFullyPaid)
            TextButton.icon(
              icon: const Icon(Icons.print_outlined, size: 18),
              label: const Text('Print Bill'),
              onPressed: () => showPrintedBill(
                context: context,
                restaurantId: widget.restaurantId,
                sessionKey: widget.sessionKey,
              ),
            ),
          TextButton.icon(
            icon: Icon(Icons.close, size: 18, color: theme.colorScheme.error),
            // I also shortened "Close Session" to "Close" to help save space
            label: Text('Close', style: TextStyle(color: theme.colorScheme.error)),
            onPressed: () => _closeSession(sessionOrders),
          ),
        ],
      )
    ];
  }


  Widget _buildDiscountAndChargesSection(double subtotal) {
    return Column(
      children: [
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: TextFormField(
                // ✨ FIX: Add a unique key
                key: ValueKey('${widget.sessionKey}_discount'),
                controller: _discountController,
                decoration: const InputDecoration(
                  labelText: 'Staff Discount (%)',
                  hintText: 'e.g., 10',
                  suffixText: '%',
                  isDense: true,
                ),
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
                onPressed: () => _discountController.clear(),
                child: const Text('Clear'))
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                // ✨ FIX: Add a unique key
                key: ValueKey('${widget.sessionKey}_coupon'),
                controller: _couponController,
                decoration: InputDecoration(
                    labelText: 'Coupon Code',
                    hintText: 'e.g., SAVE20',
                    errorText: _couponError,
                    isDense: true),
                textCapitalization: TextCapitalization.characters,
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
                onPressed: () => _applyCoupon(subtotal),
                child: const Text('Apply')),
          ],
        ),
        const Divider(height: 24),
        Text('Ad-Hoc Charges (Optional)',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        _buildAdHocChargeInput(),
      ],
    );
  }


  Widget _buildAdHocChargeInput() {
    return Column(
      children: [
        TextFormField(
          // ✨ FIX: Add a unique key
          key: ValueKey('${widget.sessionKey}_adhoc_label'),
          controller: _adHocChargeLabelController,
          decoration: const InputDecoration(
              labelText: 'Charge Label',
              hintText: 'e.g., Delivery Fee',
              isDense: true),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextFormField(
                // ✨ FIX: Add a unique key
                key: ValueKey('${widget.sessionKey}_adhoc_value'),
                controller: _adHocChargeController,
                decoration: InputDecoration(
                    labelText: _adHocChargeType == 'percentage'
                        ? 'Rate (%)'
                        : 'Amount (₹)',
                    hintText: 'e.g., 5 or 50.00',
                    isDense: true,
                    suffixText: _adHocChargeType == 'percentage' ? '%' : '₹'),
                keyboardType: TextInputType.number,
                validator: (val) => (val != null &&
                    val.isNotEmpty &&
                    double.tryParse(val) == null)
                    ? 'Invalid number'
                    : null,
              ),
            ),
            const SizedBox(width: 8),
            DropdownButton<String>(
              value: _adHocChargeType,
              items: const [
                DropdownMenuItem(value: 'percentage', child: Text('Percent')),
                DropdownMenuItem(value: 'fixed', child: Text('Fixed')),
              ],
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _adHocChargeType = val;
                  });
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.clear, size: 20),
              onPressed: () {
                _adHocChargeController.clear();
                _adHocChargeLabelController.clear();
              },
            )
          ],
        ),
      ],
    );
  }
  Widget _buildSummaryRow(String label, double amount, ThemeData theme,
      {bool isTotal = false, bool isGrandTotal = false}) {
    final formatter = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
    TextStyle style = theme.textTheme.bodyLarge!;
    if (isGrandTotal) {
      style =
          theme.textTheme.titleLarge!.copyWith(color: theme.primaryColor, fontWeight: FontWeight.bold);
    } else if (isTotal) {
      style = theme.textTheme.titleMedium!.copyWith(fontWeight: FontWeight.bold);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(formatter.format(amount), style: style),
        ],
      ),
    );
  }
}

class _PaymentMethodDialog extends StatelessWidget {
  final double grandTotal;
  final Function(String paymentMethod) onConfirm;

  const _PaymentMethodDialog(
      {required this.grandTotal, required this.onConfirm});

  void _showOtherPaymentDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Other Payment Method'),
        content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'e.g., Gift Card')),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.of(dialogContext).pop(controller.text.trim());
              }
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    ).then((value) {
      if (value != null && value is String) onConfirm(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Select Payment Method'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Amount Due: ${formatter.format(grandTotal)}',
              style: theme.textTheme.titleLarge?.copyWith(
                  color: theme.primaryColor, fontWeight: FontWeight.bold)),
          const Divider(),
          _buildPaymentOption(
              context, 'Cash', Icons.money, () => onConfirm('Cash')),
          _buildPaymentOption(context, 'Card / POS', Icons.credit_card,
                  () => onConfirm('Card')),
          _buildPaymentOption(
              context, 'UPI / QR', Icons.qr_code, () => onConfirm('UPI')),
          _buildPaymentOption(context, 'Other', Icons.more_horiz,
                  () => _showOtherPaymentDialog(context)),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'))
      ],
    );
  }

  Widget _buildPaymentOption(
      BuildContext context, String title, IconData icon, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: Theme.of(context).primaryColor),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
// ✨ FIX: Add the background widget to this file
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