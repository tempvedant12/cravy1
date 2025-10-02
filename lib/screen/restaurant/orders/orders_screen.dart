import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cravy/screen/restaurant/orders/create_order_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:intl/intl.dart';

import '../tables_and_reservations/tables_and_reservations_screen.dart';
import 'order_session_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _setupFloorListener();
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

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
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
                  .orderBy('createdAt', descending: true)
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
                  final newCounts =
                  <String, int>{'All': allGroupedOrders.length};
                  for (var floor in _floors) {
                    newCounts[floor.name] = allGroupedOrders.keys
                        .where((key) => key.contains(floor.name))
                        .length;
                  }
                  _sessionCounts.value = newCounts;
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
          )
        ],
      ),
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

class _SessionList extends StatelessWidget {
  final String restaurantId;
  final Map<String, List<DocumentSnapshot>> groupedOrders;

  const _SessionList({required this.restaurantId, required this.groupedOrders});

  Future<void> _deleteSession(
      BuildContext context, List<DocumentSnapshot> sessionOrders) async {
    final bool? confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Session?'),
        content: const Text(
            'Are you sure you want to delete this session and all its orders? This action cannot be undone.'),
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

    if (confirm == true) {
      final batch = FirebaseFirestore.instance.batch();
      for (final order in sessionOrders) {
        batch.delete(order.reference);
      }
      await batch.commit();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (groupedOrders.isEmpty) {
      return const Center(child: Text('No active sessions on this floor.'));
    }

    final sessionKeys = groupedOrders.keys.toList();

    return AnimationLimiter(
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
        itemCount: sessionKeys.length,
        itemBuilder: (context, index) {
          final sessionKey = sessionKeys[index];
          final sessionOrders = groupedOrders[sessionKey]!;

          // --- Calculation for Payment Status ---
          double totalAmount = 0;
          double totalPaidAmount = 0;
          bool isFullyPaid = true;

          for (var doc in sessionOrders) {
            final data = doc.data() as Map<String, dynamic>;
            final orderTotal = (data['totalAmount'] ?? 0.0).toDouble();
            final isOrderPaid = (data['isPaid'] ?? false);

            totalAmount += orderTotal;

            if (isOrderPaid) {
              final billingDetails = data['billingDetails'] as Map<String, dynamic>?;
              // Use finalTotal if available, otherwise assume orderTotal was paid
              totalPaidAmount += (billingDetails?['finalTotal'] ?? orderTotal).toDouble();
            } else {
              isFullyPaid = false;
            }
          }
          final remainingPayable = totalAmount - totalPaidAmount;
          // --------------------------------------

          return AnimationConfiguration.staggeredList(
            position: index,
            duration: const Duration(milliseconds: 375),
            child: SlideAnimation(
              verticalOffset: 50.0,
              child: FadeInAnimation(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: _OrderSessionCard(
                    sessionKey: sessionKey,
                    sessionOrders: sessionOrders,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => OrderSessionScreen(
                            restaurantId: restaurantId,
                            sessionKey: sessionKey,
                            initialOrders: sessionOrders,
                          ),
                        ),
                      );
                    },
                    onDelete: () => _deleteSession(context, sessionOrders),
                    isFullyPaid: isFullyPaid,              // <--- PASSED
                    remainingPayable: remainingPayable,    // <--- PASSED
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}


class _OrderSessionCard extends StatelessWidget {
  final String sessionKey;
  final List<DocumentSnapshot> sessionOrders;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final bool isFullyPaid;       // <--- ADDED
  final double remainingPayable; // <--- ADDED

  const _OrderSessionCard({
    required this.sessionKey,
    required this.sessionOrders,
    required this.onTap,
    required this.onDelete,
    required this.isFullyPaid,      // <--- ADDED
    required this.remainingPayable, // <--- ADDED
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final formatter = NumberFormat.currency(locale: 'en_IN', symbol: '₹'); // ADDED formatter

    final double totalAmount = sessionOrders.fold(
        0.0,
            (sum, doc) =>
        sum + ((doc.data() as Map<String, dynamic>)['totalAmount'] ?? 0.0));

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
      } else if (allItems
          .every((item) => (item['status'] ?? 'Pending') == 'Completed')) {
        latestStatus = 'Completed';
        statusColor = Colors.green;
      }
    }

    final Timestamp? firstOrderTimestamp =
    (sessionOrders.last.data() as Map<String, dynamic>)['createdAt'];


    String title = sessionKey;
    String? subtitle;
    if (sessionKey.contains(' - ')) {
      final parts = sessionKey.split(' - ');
      subtitle = parts[0];
      title = parts.sublist(1).join(' - ');
    }

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onDelete,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: theme.textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      Text(
                        formatter.format(totalAmount),
                        style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.primaryColor),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.circle, color: statusColor, size: 10),
                            const SizedBox(width: 6),
                            Text(
                              latestStatus,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: statusColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // --- START MODIFIED DISPLAY LOGIC ---
                      if (isFullyPaid)
                        Chip(
                          label: const Text('PAID'),
                          backgroundColor: Colors.green,
                          labelStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          visualDensity: VisualDensity.compact,
                        )
                      else // Always show PAYABLE if not fully paid
                        Chip(
                          label: Text(
                            // Display the exact remaining amount, including negative/zero.
                            'PAYABLE: ${formatter.format(remainingPayable)}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onError),
                          ),
                          backgroundColor: theme.colorScheme.error, // Red background
                          visualDensity: VisualDensity.compact,
                        )
                      // --- END MODIFIED DISPLAY LOGIC ---
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (firstOrderTimestamp != null)
                        Row(
                          children: [
                            Icon(Icons.timer_outlined,
                                size: 16,
                                color: theme.textTheme.bodySmall?.color),
                            const SizedBox(width: 4),
                            Text(
                              'Started: ${DateFormat.jm().format(firstOrderTimestamp.toDate())}',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        )
                    ],
                  )
                ],
              ),
            ),
            if (subtitle != null) ...[
              const Divider(height: 1),
              Container(
                color: theme.colorScheme.surface.withOpacity(0.3),
                padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.layers_outlined,
                        size: 16, color: theme.textTheme.bodySmall?.color),
                    const SizedBox(width: 8),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              )
            ]
          ],
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