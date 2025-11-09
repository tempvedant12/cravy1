import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'dart:async';

import '../tables_and_reservations/tables_and_reservations_screen.dart';

// --- ADDED KitchenItem class from detail screen ---
class KitchenItem {
  final String orderId;
  final String menuItemId;
  final String name;
  final int quantity;
  String status;
  final String orderType;

  KitchenItem({
    required this.orderId,
    required this.menuItemId,
    required this.name,
    required this.quantity,
    required this.status,
    required this.orderType,
  });
}
// ------------------------------------------------

class KitchenScreen extends StatefulWidget {
  final String restaurantId;
  const KitchenScreen({super.key, required this.restaurantId});

  @override
  State<KitchenScreen> createState() => _KitchenScreenState();
}

class _KitchenScreenState extends State<KitchenScreen> {
  String _getGroupKey(DocumentSnapshot order) {
    final data = order.data() as Map<String, dynamic>;
    return data['sessionKey'] as String? ?? 'Other Orders';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          const _StaticBackground(),
          StreamBuilder<QuerySnapshot>(
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
              final tabs = ['All', ...floors.map((f) => f.name)];

              return DefaultTabController(
                length: tabs.length,
                child: Scaffold(
                  backgroundColor: Colors.transparent,
                  appBar: AppBar(
                    title: const Text('Kitchen Sessions'),
                    backgroundColor: Theme.of(context).scaffoldBackgroundColor.withOpacity(0.85),
                    elevation: 0,
                    bottom: TabBar(
                      isScrollable: true,
                      tabs: tabs.map((name) => Tab(text: name)).toList(),
                    ),
                  ),
                  body: TabBarView(
                    children: tabs.map((tabName) {
                      return _buildSessionList(
                          floorName: tabName == 'All' ? null : tabName);
                    }).toList(),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSessionList({String? floorName}) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('restaurants')
          .doc(widget.restaurantId)
          .collection('orders')
          .where('isSessionActive', isEqualTo: true)
          .orderBy('createdAt')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(
              child: Text('No active orders in the kitchen.'));
        }

        final orders = snapshot.data!.docs;
        final groupedOrders = <String, List<DocumentSnapshot>>{};
        for (final order in orders) {
          final key = _getGroupKey(order);
          final sessionKey = (order.data() as Map<String, dynamic>)['sessionKey']?.toString() ?? '';

          if (floorName == null || sessionKey.contains(floorName)) {
            groupedOrders.putIfAbsent(key, () => []).add(order);
          }
        }

        if (groupedOrders.isEmpty) {
          return Center(
            child: Text('No active orders for "$floorName".'),
          );
        }

        final sessionKeys = groupedOrders.keys.toList();

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: sessionKeys.length,
          itemBuilder: (context, index) {
            final sessionKey = sessionKeys[index];
            final sessionOrders = groupedOrders[sessionKey]!;
            return Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              // --- MODIFIED CARD ---
              child: _KitchenSessionCard(
                restaurantId: widget.restaurantId, // Pass restaurantId
                sessionOrders: sessionOrders,
                // No onTap needed anymore
              ),
              // ---------------------
            );
          },
        );
      },
    );
  }
}

// --- WIDGET REBUILT AS STATEFUL ---
class _KitchenSessionCard extends StatefulWidget {
  final List<DocumentSnapshot> sessionOrders;
  final String restaurantId;

  const _KitchenSessionCard({
    required this.sessionOrders,
    required this.restaurantId,
  });

  @override
  State<_KitchenSessionCard> createState() => _KitchenSessionCardState();
}

class _KitchenSessionCardState extends State<_KitchenSessionCard> {
  // --- Logic moved from KitchenSessionDetailScreen ---

  Future<void> _updateItemStatus(
      String orderId, String menuItemId, String newStatus) async {
    final orderRef = FirebaseFirestore.instance
        .collection('restaurants')
        .doc(widget.restaurantId)
        .collection('orders')
        .doc(orderId);

    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final snapshot = await transaction.get(orderRef);
      if (!snapshot.exists) return;

      final data = snapshot.data() as Map<String, dynamic>;
      final items = List<Map<String, dynamic>>.from(data['items']);
      final itemIndex =
      items.indexWhere((item) => item['menuItemId'] == menuItemId);

      if (itemIndex != -1) {
        items[itemIndex]['status'] = newStatus;

        final allItemsCompleted =
        items.every((item) => item['status'] == 'Completed');
        final newOrderStatus = allItemsCompleted ? 'Completed' : 'Pending';

        transaction.update(orderRef, {'items': items, 'status': newOrderStatus});
      }
    });
  }

  Widget _buildActionButton(KitchenItem item, {bool isCompleted = false}) {
    // 1. Item is DONE (Completed)
    // Show a simple "Revert" button
    if (isCompleted) {
      return GestureDetector(
        onTap: () =>
            _updateItemStatus(item.orderId, item.menuItemId, 'Pending'), // Revert straight to Pending
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.grey[600], // A neutral color for revert
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text('Revert', style: TextStyle(color: Colors.white)),
        ),
      );
    }

    // 2. Item is NOT STARTED (Pending)
    // Show the "Start" button
    if (item.status == 'Pending') {
      return GestureDetector(
        onTap: () =>
            _updateItemStatus(item.orderId, item.menuItemId, 'Making'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.orange,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text('Start', style: TextStyle(color: Colors.white)),
        ),
      );
    }

    // 3. Item is BEING MADE (Making)
    // Show the "Done" button
    if (item.status == 'Making') {
      return GestureDetector(
        onTap: () =>
            _updateItemStatus(item.orderId, item.menuItemId, 'Completed'), // Go straight to Completed
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.green,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text('Done', style: TextStyle(color: Colors.white)),
        ),
      );
    }

    // Fallback for any other unknown status
    return const SizedBox.shrink();
  }

  Widget _buildItemTile(KitchenItem item, {bool isCompleted = false}) {
    return ListTile(
      title: Text('${item.quantity}x ${item.name}'),
      trailing: _buildActionButton(item, isCompleted: isCompleted),
      dense: true,
      contentPadding: EdgeInsets.zero,
    );
  }

  // --- End of logic from KitchenSessionDetailScreen ---

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = widget.sessionOrders.first.data() as Map<String, dynamic>;
    final sessionKey = data['sessionKey'] as String? ?? 'N/A';

    // --- Processing logic from detail screen's builder ---
    final allItems = <KitchenItem>[];
    for (var doc in widget.sessionOrders) {
      final docData = doc.data() as Map<String, dynamic>;
      final itemsList =
      List<Map<String, dynamic>>.from(docData['items'] ?? []);
      for (var itemData in itemsList) {
        allItems.add(KitchenItem(
          orderId: doc.id,
          menuItemId: itemData['menuItemId'],
          name: itemData['name'],
          quantity: itemData['quantity'],
          status: itemData['status'] ?? 'Pending',
          orderType: docData['orderType'] ?? 'Dine-In',
        ));
      }
    }

    final todoItems = allItems
        .where((item) => item.status == 'Pending' || item.status == 'Making')
        .toList();
    final completedItems =
    allItems.where((item) => item.status == 'Completed').toList();

    final pendingCount = allItems.where((i) => i.status == 'Pending').length;
    final makingCount = allItems.where((i) => i.status == 'Making').length;

    Color cardColor = theme.cardColor;
    if (makingCount > 0) {
      cardColor = Colors.orange.withOpacity(0.1);
    } else if (pendingCount > 0) {
      cardColor = theme.colorScheme.error.withOpacity(0.1);
    }
    // --- End of processing logic ---

    return Card(
      elevation: 4,
      color: cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // --- NEW HEADER ---
            Column(
              crossAxisAlignment: CrossAxisAlignment.start, // Align text to the left
              children: [
                // --- Row 1: Session Key (will wrap) ---
                Text(
                  sessionKey,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                  // No overflow property, so it will wrap by default
                ),
                const SizedBox(height: 8), // Vertical space between text and chips

                // --- Row 2: Chips ---
                Row(
                  mainAxisAlignment: MainAxisAlignment.start, // Align chips to the left
                  children: [
                    if (makingCount > 0)
                      Padding(
                        padding: const EdgeInsets.only(right: 8.0), // Use right padding
                        child: Chip(
                          label: Text('Making: $makingCount'),
                          labelStyle: theme.textTheme.bodySmall?.copyWith(fontSize: 10),
                          padding: const EdgeInsets.symmetric(horizontal: 4.0),
                          backgroundColor: Colors.orange.withOpacity(0.2),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    if (pendingCount > 0)
                      Padding(
                        padding: const EdgeInsets.only(right: 8.0), // Use right padding
                        child: Chip(
                          label: Text('Pending: $pendingCount'),
                          labelStyle: theme.textTheme.bodySmall?.copyWith(fontSize: 10),
                          padding: const EdgeInsets.symmetric(horizontal: 4.0),
                          backgroundColor: theme.colorScheme.error.withOpacity(0.2),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                  ],
                ),
              ],
            ),
            // --- END NEW HEADER ---

            const Divider(height: 16),

            // --- NEW: In-line "To Do" list ---
            if (todoItems.isNotEmpty)
              Text("To Do", style: theme.textTheme.titleMedium),
            if (todoItems.isEmpty && completedItems.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Center(
                    child: Text("All items completed!",
                        style: theme.textTheme.titleMedium)),
              ),
            if (todoItems.isEmpty && completedItems.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Center(
                    child: Text("No items in this session.",
                        style: theme.textTheme.titleMedium)),
              ),
            ...todoItems.map((item) => _buildItemTile(item, isCompleted: false)),
            // ---------------------------------

            // --- NEW: In-line "Completed" list ---
            if (completedItems.isNotEmpty) ...[
              const Divider(height: 20),
              Text("Completed", style: theme.textTheme.titleMedium),
              ...completedItems
                  .map((item) => _buildItemTile(item, isCompleted: true)),
            ],
            // -----------------------------------
          ],
        ),
      ),
    );
  }
}
// -----------------------------------


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