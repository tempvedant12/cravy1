import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cravy/models/supplier_model.dart';
import 'package:cravy/screen/restaurant/suppliers/add_edit_purchase_order_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:intl/intl.dart';

class PurchaseOrdersScreen extends StatefulWidget {
  final String restaurantId;

  const PurchaseOrdersScreen({super.key, required this.restaurantId});

  @override
  State<PurchaseOrdersScreen> createState() => _PurchaseOrdersScreenState();
}

class _PurchaseOrdersScreenState extends State<PurchaseOrdersScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Purchase Orders'),
      ),
      body: Stack(
        children: [
          const _StaticBackground(),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('restaurants')
                .doc(widget.restaurantId)
                .collection('purchaseOrders')
                .orderBy('orderDate', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const Center(child: Text('No purchase orders found.'));
              }

              final purchaseOrders = snapshot.data!.docs
                  .map((doc) => PurchaseOrder.fromFirestore(doc))
                  .toList();

              return AnimationLimiter(
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 80, top: 16),
                  itemCount: purchaseOrders.length,
                  itemBuilder: (context, index) {
                    final po = purchaseOrders[index];
                    return AnimationConfiguration.staggeredList(
                      position: index,
                      duration: const Duration(milliseconds: 375),
                      child: SlideAnimation(
                        verticalOffset: 50.0,
                        child: FadeInAnimation(
                          child: Card(
                            margin: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            child: ListTile(
                              title: Text(
                                  'PO #${po.id.substring(0, 6).toUpperCase()}'),
                              subtitle: Text(
                                  '${po.supplierName} - ${DateFormat.yMMMd().format(po.orderDate)}'),
                              trailing: Chip(
                                label: Text(po.status),
                                backgroundColor: po.status == 'Completed'
                                    ? Colors.green.withOpacity(0.2)
                                    : po.status == 'Cancelled'
                                    ? Colors.red.withOpacity(0.2)
                                    : Colors.orange.withOpacity(0.2),
                              ),
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        AddEditPurchaseOrderScreen(
                                          restaurantId: widget.restaurantId,
                                          purchaseOrder: po,
                                        ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) =>
                  AddEditPurchaseOrderScreen(restaurantId: widget.restaurantId),
            ),
          );
        },
        child: const Icon(Icons.add),
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
                theme.colorScheme.surface.withOpacity(isDark ? 0.3 : 0.2), 450),
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