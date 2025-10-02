

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cravy/screen/restaurant/kitchen/kitchen_session_detail_screen.dart';
import 'package:flutter/material.dart';
import 'dart:async';

import '../tables_and_reservations/tables_and_reservations_screen.dart';

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
              child: _KitchenSessionCard(
                sessionOrders: sessionOrders,
                onTap: () {
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (context) => KitchenSessionDetailScreen(
                      restaurantId: widget.restaurantId,
                      sessionKey: sessionKey,
                    ),
                  ));
                },
              ),
            );
          },
        );
      },
    );
  }
}

class _KitchenSessionCard extends StatelessWidget {
  final List<DocumentSnapshot> sessionOrders;
  final VoidCallback onTap;

  const _KitchenSessionCard({required this.sessionOrders, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = sessionOrders.first.data() as Map<String, dynamic>;
    final sessionKey = data['sessionKey'] as String? ?? 'N/A';

    final allItems = sessionOrders
        .expand((doc) => List<Map<String, dynamic>>.from(
        (doc.data() as Map<String, dynamic>)['items'] ?? []))
        .toList();

    final pendingItems =
    allItems.where((i) => (i['status'] ?? 'Pending') == 'Pending').toList();
    final isMaking = allItems.any((i) => i['status'] == 'Making');

    Color cardColor =
    isMaking ? Colors.orange.withOpacity(0.1) : theme.cardColor;

    return Card(
      elevation: 4,
      color: cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                sessionKey,
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
              const Divider(height: 16),
              if (pendingItems.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                  child: Center(
                    child: Text(
                      isMaking
                          ? 'All items are being prepared...'
                          : 'No pending items.',
                      style: theme.textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              else
                ...pendingItems.map((item) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: Row(
                      children: [
                        Text('${item['quantity']}x',
                            style: theme.textTheme.bodyLarge
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text('${item['name']}',
                                style: theme.textTheme.bodyLarge)),
                      ],
                    ),
                  );
                }).toList(),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: onTap,
                  child: const Text('View Full Order'),
                ),
              ),
            ],
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