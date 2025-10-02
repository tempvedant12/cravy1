// lib/screen/restaurant/orders/order_session_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cravy/models/order_models.dart';
import 'package:cravy/screen/restaurant/menu/menu_screen.dart';
import 'package:cravy/screen/restaurant/orders/create_order_screen.dart';
import 'package:cravy/screen/restaurant/orders/order_details_screen.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'billing_screen.dart';
import '../tables_and_reservations/tables_and_reservations_screen.dart';
import 'assign_table_screen.dart';
import 'create_order_screen.dart';

class OrderSessionScreen extends StatefulWidget {
  final String restaurantId;
  final String sessionKey;
  final List<DocumentSnapshot> initialOrders;

  const OrderSessionScreen({super.key, required this.restaurantId, required this.sessionKey, required this.initialOrders});

  @override
  State<OrderSessionScreen> createState() => _OrderSessionScreenState();
}

class _OrderSessionScreenState extends State<OrderSessionScreen> {
  List<MenuItem> _allMenuItems = [];

  @override
  void initState() {
    super.initState();
    _fetchAllMenuItems();
  }

  Future<void> _fetchAllMenuItems() async {
    // FIX: Iterate through all menus to fetch all items
    final menusSnapshot = await FirebaseFirestore.instance
        .collection('restaurants')
        .doc(widget.restaurantId)
        .collection('menus')
        .get();

    final List<MenuItem> allItems = [];

    for (var menuDoc in menusSnapshot.docs) {
      // Query the 'items' subcollection for each menu
      final itemsSnapshot = await menuDoc.reference.collection('items').get();
      allItems.addAll(itemsSnapshot.docs.map((doc) => MenuItem.fromFirestore(doc)));
    }
    // END FIX

    if (mounted) {
      setState(() {
        _allMenuItems = allItems;
      });
    }
  }

  Future<void> _orderMore(List<DocumentSnapshot> sessionOrders) async {
    if (sessionOrders.isEmpty) return;

    final firstOrderData = sessionOrders.first.data() as Map<String, dynamic>;

    OrderAssignment? initialAssignment;
    final assignmentData =
    firstOrderData['assignment'] as Map<String, dynamic>?;
    if (assignmentData != null) {
      final tableIds = assignmentData.keys.toList();
      final tableDocs = await FirebaseFirestore.instance
          .collection('restaurants')
          .doc(widget.restaurantId)
          .collection('tables')
          .where(FieldPath.documentId, whereIn: tableIds)
          .get();

      final tableLabels = <String, String>{};
      final tableFloorNames = <String, String>{};
      final tableCapacities = <String, int>{};

      for (var doc in tableDocs.docs) {
        final table = TableModel.fromFirestore(doc);
        tableLabels[table.id] = table.label;
        tableCapacities[table.id] = table.capacity;
        final sessionParts = widget.sessionKey.split(' - ');
        if (sessionParts.length > 1) {
          tableFloorNames[table.id] = sessionParts[0];
        }
      }

      initialAssignment = OrderAssignment(
        selections: assignmentData
            .map((key, value) => MapEntry(key, Set<int>.from(value))),
        tableLabels: tableLabels,
        tableFloorNames: tableFloorNames,
        tableCapacities: tableCapacities,
      );
    }

    final List<CustomerInfo> initialCustomers =
    (firstOrderData['customers'] as List<dynamic>? ?? [])
        .map((data) =>
        CustomerInfo(id: data['id'], name: data['name'], phone: data['phone']))
        .toList();

    if (mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => CreateOrderScreen(
            restaurantId: widget.restaurantId,
            initialAssignment: initialAssignment,
            initialCustomers: initialCustomers,
          ),
        ),
      );
    }
  }

  // --- NEW: Function to mark a specific order as unpaid and reset billing details ---
  Future<void> _markOrderAsUnpaid(String orderId) async {
    final bool? confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Payment?'),
        content: const Text(
            'Are you sure you want to mark this order as UNPAID? This action will clear billing details and revert the order for re-billing.'),
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

    if (confirm != true) return;

    try {
      await FirebaseFirestore.instance
          .collection('restaurants')
          .doc(widget.restaurantId)
          .collection('orders')
          .doc(orderId)
          .update({
        'isPaid': false,
        'billingDetails': FieldValue.delete(), // Clear billing details
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Order payment successfully reset!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error resetting payment: ${e.toString()}')),
        );
      }
    }
  }

  // --- ADDED: Function to delete a specific order ---
  Future<void> _deleteOrder(DocumentSnapshot orderDoc) async {
    final bool? confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Order?'),
        content: const Text(
            'Are you sure you want to delete this specific order? This action cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Delete',
                style:
                TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await orderDoc.reference.delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Order deleted successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting order: ${e.toString()}')),
        );
      }
    }
  }
  // --------------------------------------------------

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

    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session closed successfully!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Session: ${widget.sessionKey}')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('restaurants').doc(widget.restaurantId).collection('orders').where('sessionKey', isEqualTo: widget.sessionKey).where('isSessionActive', isEqualTo: true).orderBy('createdAt', descending: false).snapshots(),
        builder: (context, snapshot) {
          // Check for menu items and order data
          if (!snapshot.hasData || _allMenuItems.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          final sessionOrders = snapshot.data!.docs;
          if (sessionOrders.isEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) Navigator.of(context).pop();
            });
            return const Center(child: Text('This session has no orders.'));
          }

          double totalAmount = 0;
          double totalPaidAmount = 0;
          double unpaidOrdersValue = 0;
          bool allPaid = true;

          final Set<Timestamp> processedTransactions = {};

          for (var doc in sessionOrders) {
            final data = doc.data() as Map<String, dynamic>;
            final orderTotal = (data['totalAmount'] ?? 0.0).toDouble();
            final isOrderPaid = (data['isPaid'] ?? false);

            totalAmount += orderTotal; // Sums up the total amount of all active orders in the session.

            if (isOrderPaid) {
              final billingDetails = data['billingDetails'] as Map<String, dynamic>?;
              final billedAt = billingDetails?['billedAt'] as Timestamp?;
              // Use finalTotal if available, otherwise assume orderTotal was paid
              final finalTotal = (billingDetails?['finalTotal'] ?? orderTotal).toDouble();

              // Only count the final billed total once per unique billing transaction (identified by billedAt)
              if (billedAt != null && !processedTransactions.contains(billedAt)) {
                totalPaidAmount += finalTotal;
                processedTransactions.add(billedAt);
              }
            } else {
              // ADDED LOGIC: Sum up the value of all orders that are NOT paid
              unpaidOrdersValue += orderTotal;
              // If ANY order is not paid, the session is not all paid.
              allPaid = false;
            }
          }

          // MODIFIED: Remaining payable is the sum of the original total amount of all UNPAID orders.
          final remainingPayable = unpaidOrdersValue;

          return Column(
            children: [
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: sessionOrders.length,
                  itemBuilder: (context, index) {
                    final orderDoc = sessionOrders[index];
                    return _OrderCard(
                      restaurantId: widget.restaurantId,
                      order: orderDoc,
                      orderNumber: index + 1,
                      allMenuItems: _allMenuItems,
                      onMarkUnpaid: () => _markOrderAsUnpaid(orderDoc.id),
                      onDeleteOrder: () => _deleteOrder(orderDoc), // <--- PASSED DELETE CALLBACK
                    );
                  },
                ),
              ),
              _buildBottomPanel(
                  totalAmount,
                  totalPaidAmount,
                  remainingPayable, // PASS THE CORRECT VALUE
                  allPaid,
                      () => _orderMore(sessionOrders),
                      () => _closeSession(sessionOrders),
                      () {
                    Navigator.of(context).push(MaterialPageRoute(builder: (context) => BillingScreen(restaurantId: widget.restaurantId, sessionKey: widget.sessionKey)));
                  }
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBottomPanel(
      double total,
      double totalPaid,
      double unpaidAmount, // NEW PARAMETER
      bool allPaid,
      VoidCallback onOrderMore,
      VoidCallback onClose,
      VoidCallback onBilling
      ) {
    final theme = Theme.of(context);
    // REMOVED: final remainingPayable = total - totalPaid;
    final formatter = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

    return Material(
      elevation: 8,
      child: Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Session Total:', style: theme.textTheme.headlineSmall),
                Text(formatter.format(total), style: theme.textTheme.headlineSmall!.copyWith(color: theme.primaryColor)),
              ],
            ),
            // MODIFIED Remaining Payable Row to use unpaidAmount
            if (unpaidAmount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Remaining Payable:', style: theme.textTheme.titleMedium),
                    Text(formatter.format(unpaidAmount), style: theme.textTheme.titleMedium!.copyWith(color: theme.colorScheme.error)),
                  ],
                ),
              ),

            // ------------------------------------
            if (allPaid)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text('This session is fully paid.', style: theme.textTheme.titleMedium?.copyWith(color: Colors.green)),
              ),
            const Divider(height: 24),
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 500;

                Widget billingButton = ElevatedButton(
                  onPressed: onBilling,
                  child: Text(allPaid ? 'View Bill' : 'Go to Billing'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                );

                Widget orderMoreButton = OutlinedButton.icon(
                  onPressed: onOrderMore,
                  icon: const Icon(Icons.add),
                  label: const Text('Add Items'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                );

                Widget closeSessionButton = TextButton.icon(
                  onPressed: onClose,
                  icon: const Icon(Icons.close),
                  label: const Text('Close Session'),
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                );

                if (isWide) {
                  return Row(
                    children: [
                      Expanded(flex: 2, child: billingButton),
                      const SizedBox(width: 16),
                      Expanded(flex: 2, child: orderMoreButton),
                      const SizedBox(width: 16),
                      Expanded(flex: 1, child: closeSessionButton),
                    ],
                  );
                } else {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      billingButton,
                      const SizedBox(height: 12),
                      orderMoreButton,
                      const SizedBox(height: 12),
                      closeSessionButton,
                    ],
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final String restaurantId;
  final DocumentSnapshot order;
  final int orderNumber;
  final List<MenuItem> allMenuItems;
  final VoidCallback? onMarkUnpaid;
  final VoidCallback? onDeleteOrder; // <--- ADDED CALLBACK

  const _OrderCard({required this.restaurantId, required this.order, required this.orderNumber, required this.allMenuItems, this.onMarkUnpaid, this.onDeleteOrder}); // <--- UPDATED CONSTRUCTOR

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final orderData = order.data() as Map<String, dynamic>;
    final items = (orderData['items'] as List<dynamic>? ?? []).map((itemData) => OrderItem.fromMap(itemData, allMenuItems)).toList();
    final totalAmount = (orderData['totalAmount'] ?? 0.0).toDouble();
    final timestamp = (orderData['createdAt'] as Timestamp?)?.toDate();
    final isPaid = orderData['isPaid'] ?? false; // <--- NEW: Get isPaid status

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => OrderDetailsScreen(restaurantId: restaurantId, orderId: order.id))),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('Order #$orderNumber', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                // --- MODIFIED: Show Paid Label and PopupMenuButton ---
                Row(
                  children: [
                    if (isPaid)
                      ...[
                        Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: Chip(
                            label: const Text('PAID'),
                            backgroundColor: Colors.green.withOpacity(0.1),
                            labelStyle: TextStyle(color: Colors.green),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                          ),
                        ),
                        PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'mark_unpaid') {
                              onMarkUnpaid?.call();
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'mark_unpaid',
                              child: Text('Mark as Unpaid / Reset Payment'),
                            ),
                          ],
                          icon: const Icon(Icons.more_vert, size: 20),
                        ),
                      ],
                    if (timestamp != null && !isPaid) // Show timestamp if not paid (since paid orders have the menu button)
                      Text(DateFormat.jm().format(timestamp), style: theme.textTheme.bodySmall),

                    // 4. Dedicated Delete Button (Always visible)
                    IconButton( // <--- ADDED DEDICATED DELETE BUTTON
                      icon: Icon(Icons.delete_outline, color: theme.colorScheme.error, size: 22),
                      onPressed: onDeleteOrder,
                      tooltip: 'Delete Order',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                    ),
                  ],
                ),
                // -----------------------------------------------------
              ]),
              Text('ID: ${order.id.substring(0, 8)}', style: theme.textTheme.bodySmall),
              const Divider(height: 20),
              if (items.isEmpty) const Text('No items in this order.') else ...items.map((item) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('${item.quantity}x', style: theme.textTheme.bodyMedium),
                          const SizedBox(width: 8),
                          Expanded(child: Text(item.menuItem.name, style: theme.textTheme.bodyMedium)),
                          Text('₹${(item.singleItemPrice * item.quantity).toStringAsFixed(2)}', style: theme.textTheme.bodyMedium),
                        ],
                      ),
                      if (item.selectedOptions.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(left: 24.0, top: 4.0),
                          child: Text(
                            item.selectedOptions.map((o) => o.optionName).join(', '),
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.textTheme.bodySmall?.color?.withOpacity(0.8)),
                          ),
                        )
                    ],
                  ),
                );
              }),
              const Divider(height: 20),
              Align(
                alignment: Alignment.centerRight,
                child: Text('Order Total: ₹${totalAmount.toStringAsFixed(2)}', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}