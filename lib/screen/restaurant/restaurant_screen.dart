import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cravy/screen/restaurant/inventory/inventory_screen.dart';
import 'package:cravy/screen/restaurant/kitchen/kitchen_screen.dart';
import 'package:cravy/screen/restaurant/orders/orders_screen.dart';
import 'package:cravy/screen/restaurant/reports/reports_screen.dart';
import 'package:cravy/screen/restaurant/suppliers/suppliers_screen.dart'; // Import the new screen
import 'package:cravy/screen/restaurant/tables_and_reservations/tables_and_reservations_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';

import 'billing_setup/billing_setup_and_coupons.dart';
import 'menu/menu_screen.dart';
import 'reports/payment_history_screen.dart';


class Restaurant {
  final String id;
  final String name;
  final String address;
  final DateTime createdAt;

  Restaurant({
    required this.id,
    required this.name,
    required this.address,
    required this.createdAt,
  });

  factory Restaurant.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return Restaurant(
      id: doc.id,
      name: data['name'] ?? 'Unnamed Restaurant',
      address: data['address'] ?? 'No address provided',
      createdAt: (data['createdAt'] as Timestamp? ?? Timestamp.now()).toDate(),
    );
  }
}


class DashboardItem {
  final String title;
  final IconData icon;
  final Widget screen;
  final Stream<bool>? alertStream;

  DashboardItem({
    required this.title,
    required this.icon,
    required this.screen,
    this.alertStream,
  });
}


const double _desktopBreakpoint = 1000.0;


class RestaurantDashboardScreen extends StatefulWidget {
  final Restaurant restaurant;
  const RestaurantDashboardScreen({super.key, required this.restaurant});

  @override
  State<RestaurantDashboardScreen> createState() =>
      _RestaurantDashboardScreenState();
}

class _RestaurantDashboardScreenState extends State<RestaurantDashboardScreen> {
  late List<DashboardItem> _dashboardItems;
  List<DashboardItem> _filteredItems = [];
  final TextEditingController _searchController = TextEditingController();
  int _selectedSidebarIndex = 3;

  @override
  void initState() {
    super.initState();
    _dashboardItems = _getDashboardItems();
    _filteredItems = _dashboardItems;
    _searchController.addListener(_filterDashboard);
  }

  @override
  void dispose() {
    _searchController.removeListener(_filterDashboard);
    _searchController.dispose();
    super.dispose();
  }

  void _filterDashboard() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredItems = _dashboardItems.where((item) {
        return item.title.toLowerCase().contains(query);
      }).toList();
    });
  }

  void _navigateTo(Widget screen, int index) {
    setState(() {
      _selectedSidebarIndex = index;
    });
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => screen,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  List<DashboardItem> _getDashboardItems() {
    final lowStockStream = FirebaseFirestore.instance
        .collection('restaurants')
        .doc(widget.restaurant.id)
        .collection('inventory')
        .snapshots()
        .map((snapshot) {
      if (snapshot.docs.isEmpty) return false;
      return snapshot.docs.any((doc) {
        final item = InventoryItem.fromFirestore(doc);
        return item.quantity <= item.lowStockThreshold;
      });
    });

    return [
      DashboardItem(title: 'Tables & Reservations', icon: Icons.table_restaurant_outlined, screen: TablesAndReservationsScreen(restaurantId: widget.restaurant.id)),
      DashboardItem(title: 'Orders & Billing', icon: Icons.receipt_long_outlined, screen: OrdersScreen(restaurantId: widget.restaurant.id,)),
      DashboardItem(title: 'Menu', icon: Icons.menu_book_outlined, screen: MenuScreen(restaurantId: widget.restaurant.id)),
      DashboardItem(title: 'Kitchen', icon: Icons.kitchen_outlined, screen: KitchenScreen(restaurantId: widget.restaurant.id)),
      DashboardItem(
        title: 'Inventory',
        icon: Icons.inventory_2_outlined,
        screen: InventoryScreen(restaurantId: widget.restaurant.id),
        alertStream: lowStockStream,
      ),
      DashboardItem(title: 'Billing Setup & Coupons', icon: Icons.folder_outlined, screen: BillingSetupAndCouponsScreen(restaurantId: widget.restaurant.id)),
      DashboardItem(title: 'Payment History', icon: Icons.history_outlined, screen: PaymentHistoryScreen(restaurantId: widget.restaurant.id)),
      DashboardItem(title: 'Staff & Roles', icon: Icons.people_alt_outlined, screen: const PlaceholderScreen(tabName: 'Staff / Roles')),
      DashboardItem(title: 'Customers', icon: Icons.people_outline, screen: const PlaceholderScreen(tabName: 'Customer Details')),
      DashboardItem(title: 'Suppliers', icon: Icons.local_shipping_outlined, screen: SuppliersScreen(restaurantId: widget.restaurant.id)), // Add the new screen here
      DashboardItem(title: 'Reports', icon: Icons.bar_chart_outlined, screen: ReportsScreen(restaurantId: widget.restaurant.id)),
      DashboardItem(title: 'Activity Log', icon: Icons.history_outlined, screen: const PlaceholderScreen(tabName: 'Activity Log')),
      DashboardItem(title: 'Settings', icon: Icons.settings_outlined, screen: const PlaceholderScreen(tabName: 'Settings')),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading:
        MediaQuery.of(context).size.width < _desktopBreakpoint ? null : Container(),
      ),
      body: Stack(
        children: [
          const _StaticBackground(),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < _desktopBreakpoint) {
                  return _buildMobileLayout();
                } else {
                  return _buildDesktopLayout();
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLayout() {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
            child: _Header(
                restaurant: widget.restaurant,
                searchController: _searchController)),
        _DashboardGrid(
          items: _filteredItems,
          allItems: _dashboardItems,
          onItemTap: (screen, index) => _navigateTo(screen, index),
        ),
      ],
    );
  }

  Widget _buildDesktopLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SidebarNav(
          restaurant: widget.restaurant,
          items: _dashboardItems,
          onItemTap: (screen, index) => _navigateTo(screen, index),
          selectedIndex: _selectedSidebarIndex,
        ),
        const VerticalDivider(width: 1, thickness: 1),
        Expanded(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: _Header(
                  restaurant: widget.restaurant,
                  searchController: _searchController,
                  isDesktop: true,
                ),
              ),
              _DashboardGrid(
                items: _filteredItems,
                allItems: _dashboardItems,
                onItemTap: (screen, index) => _navigateTo(screen, index),
              ),
            ],
          ),
        ),
      ],
    );
  }
}



class _SidebarNav extends StatelessWidget {
  final Restaurant restaurant;
  final List<DashboardItem> items;
  final Function(Widget, int) onItemTap;
  final int selectedIndex;

  const _SidebarNav({
    required this.restaurant,
    required this.items,
    required this.onItemTap,
    required this.selectedIndex,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 280,
      color: theme.colorScheme.surface.withOpacity(0.2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                child: Row(
                  children: [
                    Icon(Icons.arrow_back,
                        color: theme.textTheme.bodyLarge?.color),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        "Back to Home",
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return _SidebarNavItem(
                  title: item.title,
                  icon: item.icon,
                  isSelected: selectedIndex == index,
                  onTap: () => onItemTap(item.screen, index),
                  alertStream: item.alertStream,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarNavItem extends StatefulWidget {
  final String title;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;
  final Stream<bool>? alertStream;

  const _SidebarNavItem({
    required this.title,
    required this.icon,
    required this.isSelected,
    required this.onTap,
    this.alertStream,
  });

  @override
  State<_SidebarNavItem> createState() => _SidebarNavItemState();
}

class _SidebarNavItemState extends State<_SidebarNavItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color textColor = widget.isSelected
        ? theme.primaryColor
        : theme.textTheme.bodyLarge!.color!;
    final Color bgColor = widget.isSelected
        ? theme.primaryColor.withOpacity(0.1)
        : (_isHovered
        ? theme.textTheme.bodyLarge!.color!.withOpacity(0.05)
        : Colors.transparent);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(widget.icon, color: textColor.withOpacity(0.8), size: 22),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  widget.title,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: textColor,
                    fontWeight:
                    widget.isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
              if (widget.alertStream != null)
                StreamBuilder<bool>(
                  stream: widget.alertStream,
                  builder: (context, snapshot) {
                    if (snapshot.hasData && snapshot.data == true) {
                      return Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.error,
                          shape: BoxShape.circle,
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final Restaurant restaurant;
  final TextEditingController searchController;
  final bool isDesktop;

  const _Header({
    required this.restaurant,
    required this.searchController,
    this.isDesktop = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isDesktop) ...[
            Text(
              restaurant.name,
              style: theme.textTheme.displaySmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              restaurant.address,
              style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.textTheme.bodyLarge?.color?.withOpacity(0.7)),
            ),
            const SizedBox(height: 24),
          ],
          TextField(
            controller: searchController,
            decoration: InputDecoration(
              hintText: 'Search features...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: theme.colorScheme.surface.withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardGrid extends StatelessWidget {
  final List<DashboardItem> items;
  final List<DashboardItem> allItems;
  final Function(Widget, int) onItemTap;

  const _DashboardGrid({
    required this.items,
    required this.allItems,
    required this.onItemTap,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const SliverFillRemaining(
        child: Center(
          child: Text('No features match your search.'),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.all(24.0),
      sliver: AnimationLimiter(
        child: SliverGrid.builder(
          itemCount: items.length,
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 220,
            mainAxisSpacing: 20.0,
            crossAxisSpacing: 20.0,
            childAspectRatio: 1.1,
          ),
          itemBuilder: (context, index) {
            final item = items[index];
            final originalIndex = _getOriginalIndex(item);
            return AnimationConfiguration.staggeredGrid(
              position: index,
              duration: const Duration(milliseconds: 375),
              columnCount: 4,
              child: ScaleAnimation(
                child: FadeInAnimation(
                  child: DashboardCard(
                    item: item,
                    onTap: () => onItemTap(item.screen, originalIndex),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  int _getOriginalIndex(DashboardItem item) {
    return allItems.indexWhere((dashboardItem) => dashboardItem.title == item.title);
  }
}

class DashboardCard extends StatefulWidget {
  final DashboardItem item;
  final VoidCallback onTap;

  const DashboardCard({
    super.key,
    required this.item,
    required this.onTap,
  });

  @override
  State<DashboardCard> createState() => _DashboardCardState();
}

class _DashboardCardState extends State<DashboardCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            splashColor: theme.primaryColor.withOpacity(0.1),
            highlightColor: theme.primaryColor.withOpacity(0.05),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: _isHovered
                      ? theme.primaryColor.withOpacity(0.5)
                      : Colors.white.withOpacity(0.2),
                  width: 1.5,
                ),
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.surface.withOpacity(0.3),
                    theme.colorScheme.surface.withOpacity(0.1),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Icon(widget.item.icon, size: 32, color: theme.primaryColor),
                      if (widget.item.alertStream != null)
                        StreamBuilder<bool>(
                          stream: widget.item.alertStream,
                          builder: (context, snapshot) {
                            if (snapshot.hasData && snapshot.data == true) {
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.error,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  'Alert',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onError,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              );
                            }
                            return const SizedBox.shrink();
                          },
                        ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    widget.item.title,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
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
            top: -120,
            left: -180,
            child: _buildShape(
                theme.primaryColor.withOpacity(isDark ? 0.3 : 0.1), 400),
          ),
          Positioned(
            bottom: -150,
            right: -150,
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
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class PlaceholderScreen extends StatelessWidget {
  final String tabName;
  const PlaceholderScreen({super.key, required this.tabName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tabName),
      ),
      body: Center(
        child: Text(
          '$tabName Feature',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
      ),
    );
  }
}