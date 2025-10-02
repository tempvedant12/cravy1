import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';


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

class KitchenSessionDetailScreen extends StatefulWidget {
  final String restaurantId;
  final String sessionKey;

  const KitchenSessionDetailScreen({
    super.key,
    required this.restaurantId,
    required this.sessionKey,
  });

  @override
  State<KitchenSessionDetailScreen> createState() =>
      _KitchenSessionDetailScreenState();
}

class _KitchenSessionDetailScreenState
    extends State<KitchenSessionDetailScreen> {
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

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      
      stream: FirebaseFirestore.instance
          .collection('restaurants')
          .doc(widget.restaurantId)
          .collection('orders')
          .where('sessionKey', isEqualTo: widget.sessionKey)
          .where('isSessionActive', isEqualTo: true) 
          .snapshots(),
      
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.data!.docs.isEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.of(context).pop();
          });
          return Container();
        }

        final allItems = <KitchenItem>[];
        for (var doc in snapshot.data!.docs) {
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

        return DefaultTabController(
          length: 2,
          child: Scaffold(
            extendBodyBehindAppBar: true,
            body: Stack(
              children: [
                const _StaticBackground(),
                Scaffold(
                  backgroundColor: Colors.transparent,
                  appBar: AppBar(
                    title: Text(widget.sessionKey),
                    backgroundColor: Theme.of(context)
                        .scaffoldBackgroundColor
                        .withOpacity(0.85),
                    elevation: 0,
                    bottom: TabBar(
                      tabs: [
                        Tab(text: 'To Do (${todoItems.length})'),
                        Tab(text: 'Completed (${completedItems.length})'),
                      ],
                    ),
                  ),
                  body: TabBarView(
                    children: [
                      _buildItemList(todoItems),
                      _buildItemList(completedItems, isCompleted: true),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildItemList(List<KitchenItem> items, {bool isCompleted = false}) {
    if (items.isEmpty) {
      return Center(
          child: Text(isCompleted
              ? 'No items completed yet.'
              : 'All items are completed!'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return Card(
          color: isCompleted
              ? Colors.green.withOpacity(0.1)
              : (item.status == 'Making'
              ? Colors.orange.withOpacity(0.1)
              : null),
          child: ListTile(
            title: Text('${item.quantity}x ${item.name}'),
            trailing: _buildActionButton(item, isCompleted: isCompleted),
          ),
        );
      },
    );
  }

  Widget _buildActionButton(KitchenItem item, {bool isCompleted = false}) {
    if (isCompleted) {
      return PopupMenuButton<String>(
        onSelected: (value) {
          _updateItemStatus(item.orderId, item.menuItemId, value);
        },
        itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
          const PopupMenuItem<String>(
            value: 'Pending',
            child: Text('Remake Item'),
          ),
          const PopupMenuItem<String>(
            value: 'Making',
            child: Text('Revert to Making'),
          ),
        ],
        child: const Icon(Icons.check_circle, color: Colors.green),
      );
    }

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
    if (item.status == 'Making') {
      String completeActionText;
      switch (item.orderType) {
        case 'Takeaway':
          completeActionText = 'Ready for Pickup';
          break;
        case 'Delivery':
          completeActionText = 'Out for Delivery';
          break;
        default: 
          completeActionText = 'Send to Table';
      }

      return PopupMenuButton<String>(
        onSelected: (value) {
          _updateItemStatus(item.orderId, item.menuItemId, value);
        },
        itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
          PopupMenuItem<String>(
            value: 'Completed',
            child: Text(completeActionText),
          ),
          const PopupMenuDivider(),
          const PopupMenuItem<String>(
            value: 'Pending',
            child: Text('Revert to Pending'),
          ),
        ],
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
    return const SizedBox.shrink();
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