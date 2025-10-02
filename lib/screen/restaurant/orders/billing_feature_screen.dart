

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cravy/screen/restaurant/orders/billing_screen.dart';
import 'package:flutter/material.dart';
import '../billing_setup/manage_bill_designs_screen.dart';
import '../billing_setup/manage_coupon_screen.dart';
import '../tables_and_reservations/tables_and_reservations_screen.dart';
import '../reports/payment_history_screen.dart';

class BillingFeatureScreen extends StatefulWidget {
  final String restaurantId;
  const BillingFeatureScreen({super.key, required this.restaurantId});

  @override
  State<BillingFeatureScreen> createState() => _BillingFeatureScreenState();
}

class _BillingFeatureScreenState extends State<BillingFeatureScreen>
    with TickerProviderStateMixin {
  TabController? _tabController;

  String _getGroupKey(DocumentSnapshot order) {
    final data = order.data() as Map<String, dynamic>;
    return data['sessionKey'] as String? ?? 'Other Orders';
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
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

              
              _tabController ??=
                  TabController(length: tabs.length, vsync: this);

              return Scaffold(
                backgroundColor: Colors.transparent,
                appBar: AppBar(
                  title: const Text('Billing'),
                  backgroundColor: Theme.of(context)
                      .scaffoldBackgroundColor
                      .withOpacity(0.85),
                  elevation: 0,
                  actions: [
                    
                    PopupMenuButton<String>(
                      onSelected: (value) {
                        switch (value) {
                          case 'history':
                            Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => PaymentHistoryScreen(
                                  restaurantId: widget.restaurantId),
                            ));
                            break;
                          case 'setup':
                            Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => ManageBillDesignsScreen(
                                  restaurantId: widget.restaurantId),
                            ));
                            break;
                          case 'coupons':
                            Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => ManageCouponScreen(
                                  restaurantId: widget.restaurantId),
                            ));
                            break;
                        }
                      },
                      itemBuilder: (BuildContext context) =>
                      <PopupMenuEntry<String>>[
                        const PopupMenuItem<String>(
                          value: 'history',
                          child: ListTile(
                            leading: Icon(Icons.history_outlined),
                            title: Text('Payment History'),
                          ),
                        ),
                        const PopupMenuItem<String>(
                          value: 'setup',
                          child: ListTile(
                            leading: Icon(Icons.settings_outlined),
                            title: Text('Bill Setup'),
                          ),
                        ),
                        const PopupMenuItem<String>(
                          value: 'coupons',
                          child: ListTile(
                            leading: Icon(Icons.local_offer_outlined),
                            title: Text('Manage Coupons'),
                          ),
                        ),
                      ],
                    ),
                  ],
                  bottom: TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    tabs: tabs.map((name) => Tab(text: name)).toList(),
                  ),
                ),
                body: TabBarView(
                  controller: _tabController,
                  children: tabs.map((tabName) {
                    return _buildSessionList(
                        floorName: tabName == 'All' ? null : tabName);
                  }).toList(),
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
          .where('isPaid', isEqualTo: false) 
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(
              child: Text('No active orders ready for billing.'));
        }

        final orders = snapshot.data!.docs;
        final groupedOrders = <String, List<DocumentSnapshot>>{};

        for (final order in orders) {
          final key = _getGroupKey(order);
          final sessionKey =
              (order.data() as Map<String, dynamic>)['sessionKey']
                  ?.toString() ??
                  '';
          if (floorName == null || sessionKey.contains(floorName)) {
            groupedOrders.putIfAbsent(key, () => []).add(order);
          }
        }

        if (groupedOrders.isEmpty) {
          return Center(child: Text('No active sessions on "$floorName".'));
        }

        final sessionKeys = groupedOrders.keys.toList();

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
          itemCount: sessionKeys.length,
          itemBuilder: (context, index) {
            final sessionKey = sessionKeys[index];
            final sessionOrders = groupedOrders[sessionKey]!;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: _BillingSessionCard(
                sessionKey: sessionKey,
                sessionOrders: sessionOrders,
                onBill: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => BillingScreen(
                        restaurantId: widget.restaurantId,
                        sessionKey: sessionKey,
                      ),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}

class _BillingSessionCard extends StatelessWidget {
  final String sessionKey;
  final List<DocumentSnapshot> sessionOrders;
  final VoidCallback onBill;

  const _BillingSessionCard({
    required this.sessionKey,
    required this.sessionOrders,
    required this.onBill,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
        latestStatus = 'In Progress';
        statusColor = Colors.orange;
      } else if (allItems
          .every((item) => (item['status'] ?? 'Pending') == 'Completed')) {
        latestStatus = 'Ready to Bill';
        statusColor = Colors.green;
      }
    }

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onBill,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      sessionKey,
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  Text(
                    '${sessionOrders.length} Orders',
                    style: theme.textTheme.bodyLarge,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      latestStatus,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Text(
                    'Total: ₹${totalAmount.toStringAsFixed(2)}',
                    style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.primaryColor),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onBill,
                  icon: const Icon(Icons.receipt_long),
                  label: const Text('Generate Bill'),
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