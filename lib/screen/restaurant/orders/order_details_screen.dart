

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cravy/models/order_models.dart';
import 'package:cravy/screen/restaurant/menu/menu_screen.dart';
import 'package:cravy/screen/restaurant/orders/select_menu_items_screen.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:ui';

class OrderDetailsScreen extends StatefulWidget {
  final String restaurantId;
  final String orderId;

  const OrderDetailsScreen({super.key, required this.restaurantId, required this.orderId});

  @override
  State<OrderDetailsScreen> createState() => _OrderDetailsScreenState();
}

class _OrderDetailsScreenState extends State<OrderDetailsScreen> {
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
      final itemsSnapshot = await menuDoc.reference.collection('items').get();
      allItems.addAll(itemsSnapshot.docs.map((doc) => MenuItem.fromFirestore(doc)));
    }

    if (mounted) {
      setState(() {
        _allMenuItems = allItems;
      });
    }
  }




  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(title: Text('Order #${widget.orderId.substring(0, 8)}'), backgroundColor: Colors.transparent, elevation: 0),
      body: Stack(
        children: [
          const _StaticBackground(),
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance.collection('restaurants').doc(widget.restaurantId).collection('orders').doc(widget.orderId).snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting || _allMenuItems.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }
              if (!snapshot.hasData || !snapshot.data!.exists) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) Navigator.of(context).pop();
                });
                return const Center(child: Text('Order not found.'));
              }

              final orderData = snapshot.data!.data() as Map<String, dynamic>;
              final items = (orderData['items'] as List<dynamic>? ?? []).map((itemData) => OrderItem.fromMap(itemData, _allMenuItems)).toList();
              final totalAmount = (orderData['totalAmount'] ?? 0.0).toDouble();

              return Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 100, 16, 120),
                      children: [
                        _buildSectionCard(child: _buildOrderSummary(context, orderData, totalAmount)),
                        const SizedBox(height: 20),
                        _buildSectionCard(child: _buildItemsList(context, items)),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
          
        ],
      ),
    );
  }

  Widget _buildItemsList(BuildContext context, List<OrderItem> items) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Items (${items.length})', style: theme.textTheme.titleLarge),
        const Divider(height: 24),
        if (items.isEmpty) const Center(child: Padding(padding: EdgeInsets.all(16.0), child: Text('No items in this order.')))
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return Card(
                elevation: 0,
                color: theme.colorScheme.surface.withOpacity(0.5),
                margin: const EdgeInsets.symmetric(vertical: 4),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('${item.quantity}x', style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(width: 12),
                          Expanded(child: Text(item.menuItem.name, style: theme.textTheme.titleMedium)),
                          Text('₹${(item.singleItemPrice * item.quantity).toStringAsFixed(2)}', style: theme.textTheme.titleMedium),
                        ],
                      ),
                      if (item.selectedOptions.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(left: 36.0, top: 6.0),
                          child: Text(
                            item.selectedOptions.map((o) => o.optionName).join(', '),
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.textTheme.bodySmall?.color?.withOpacity(0.8)),
                          ),
                        )
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  
  Widget _buildOrderSummary(BuildContext context, Map<String, dynamic> orderData, double totalAmount) {
    final theme = Theme.of(context);
    final timestamp = (orderData['createdAt'] as Timestamp?)?.toDate();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Summary', style: theme.textTheme.titleLarge),
        const Divider(height: 24),
        _buildSummaryRow('Total Price:', '₹${totalAmount.toStringAsFixed(2)}', theme),
        const SizedBox(height: 8),
        _buildSummaryRow('Status:', orderData['status'] ?? 'N/A', theme),
        const SizedBox(height: 8),
        if (timestamp != null)
          _buildSummaryRow('Time:', DateFormat.jm().format(timestamp), theme),
        const SizedBox(height: 8),
        _buildSummaryRow('Assigned to:', orderData['assignmentLabel'] ?? 'Not assigned', theme),
      ],
    );
  }

  Widget _buildSummaryRow(String label, String value, ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: theme.textTheme.bodyLarge),
        Text(value, style: theme.textTheme.titleMedium),
      ],
    );
  }

  Widget _buildSectionCard({required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.2)),
          gradient: LinearGradient(
            colors: [
              Theme.of(context).colorScheme.surface.withOpacity(0.3),
              Theme.of(context).colorScheme.surface.withOpacity(0.1),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: child,
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