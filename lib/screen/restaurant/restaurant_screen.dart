import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cravy/screen/restaurant/inventory/inventory_screen.dart';
import 'package:cravy/screen/restaurant/kitchen/kitchen_screen.dart';
import 'package:cravy/screen/restaurant/orders/orders_screen.dart';
import 'package:cravy/screen/restaurant/quick_bill/quick_bill_screen.dart';
import 'package:cravy/screen/restaurant/reports/reports_screen.dart';
import 'package:cravy/screen/restaurant/staff/staff_and_roles_screen.dart';
import 'package:cravy/screen/restaurant/suppliers/suppliers_screen.dart'; // Import the new screen
import 'package:cravy/screen/restaurant/tables_and_reservations/tables_and_reservations_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';

import 'EditRestaurantScreen.dart';
import 'billing_setup/billing_setup_and_coupons.dart';
import 'customers/customers_screen.dart';
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

  final FocusNode _focusNode = FocusNode();
  final FocusNode _searchFocusNode = FocusNode();

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
    _focusNode.dispose();
    _searchFocusNode.dispose();
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
      DashboardItem(title: 'Quick Bill', icon: Icons.flash_on, screen: QuickBillScreen(restaurantId: widget.restaurant.id)),
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
      DashboardItem(title: 'Staff & Roles', icon: Icons.people_alt_outlined, screen: StaffAndRolesScreen(restaurantId: widget.restaurant.id)),
      DashboardItem(title: 'Customers', icon: Icons.people_outline, screen: CustomersScreen(restaurantId: widget.restaurant.id)),
      DashboardItem(title: 'Suppliers', icon: Icons.local_shipping_outlined, screen: SuppliersScreen(restaurantId: widget.restaurant.id)), // Add the new screen here
      DashboardItem(title: 'Reports', icon: Icons.bar_chart_outlined, screen: ReportsScreen(restaurantId: widget.restaurant.id)),
      DashboardItem(title: 'Activity Log', icon: Icons.history_outlined, screen: const PlaceholderScreen(tabName: 'Activity Log')),
      DashboardItem(
        title: 'Settings',
        icon: Icons.settings_outlined,
        screen: EditRestaurantScreen(restaurant: widget.restaurant),
      ),
    ];
  }

  int _getOriginalIndex(DashboardItem item) {
    // This finds the index of the item from the *original* unfiltered list,
    // which matches the index used by the _SidebarNav
    return _dashboardItems.indexWhere((dashboardItem) => dashboardItem.title == item.title);
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
                return Focus(
                  focusNode: _focusNode,
                  autofocus: true,
                  onKey: (FocusNode node, RawKeyEvent event) {
                    if (event is! RawKeyDownEvent) return KeyEventResult.ignored;

                    // Handle Back/Esc
                    if (event.logicalKey == LogicalKeyboardKey.escape ||
                        event.logicalKey == LogicalKeyboardKey.backspace) {
                      if (_searchFocusNode.hasFocus) {
                        _searchFocusNode.unfocus(); // First, unfocus search
                        return KeyEventResult.handled;
                      }
                      Navigator.of(context).pop(); // Then, pop screen
                      return KeyEventResult.handled;
                    }

                    // --- NEW NAVIGATION LOGIC ---

                    // Check if the search bar is the one with focus
                    if (_searchFocusNode.hasFocus) {
                      // If user presses ArrowDown FROM search bar, move to grid
                      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                        node.focusInDirection(TraversalDirection.down);
                        return KeyEventResult.handled;
                      }
                      // If user presses Enter in search, just unfocus
                      if (event.logicalKey == LogicalKeyboardKey.enter ||
                          event.logicalKey == LogicalKeyboardKey.numpadEnter) {
                        _searchFocusNode.unfocus();
                        return KeyEventResult.handled;
                      }
                      // For any other key (like left/right/up), let the TextField control the cursor
                      return KeyEventResult.ignored;
                    }

                    // If search is NOT focused, control the grid/sidebar
                    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                      node.focusInDirection(TraversalDirection.down);
                      return KeyEventResult.handled;
                    }
                    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                      node.focusInDirection(TraversalDirection.up);
                      return KeyEventResult.handled;
                    }
                    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                      node.focusInDirection(TraversalDirection.left);
                      return KeyEventResult.handled;
                    }
                    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                      node.focusInDirection(TraversalDirection.right);
                      return KeyEventResult.handled;
                    }
                    // --- END NEW LOGIC ---

                    // Let child 'Focus' widgets (like on the cards) handle Enter
                    return KeyEventResult.ignored;
                  },                  child: constraints.maxWidth < _desktopBreakpoint
                    ? _buildMobileLayout() // <-- No longer pass index
                    : _buildDesktopLayout(), // <-- No longer pass index
                );
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
              searchController: _searchController,
              searchFocusNode: _searchFocusNode, // Pass search node
            )),
        _DashboardGrid(
          items: _filteredItems,
          allItems: _dashboardItems,
          onItemTap: (screen, index) => _navigateTo(screen, index),
          // --- REMOVED focusedIndex & crossAxisCount ---
        ),
      ],
    );
  }

  Widget _buildDesktopLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FocusTraversalGroup( // <-- WRAP Sidebar in FocusTraversalGroup
          child: _SidebarNav(
            restaurant: widget.restaurant,
            items: _dashboardItems,
            onItemTap: (screen, index) => _navigateTo(screen, index),
            selectedIndex: _selectedSidebarIndex,
          ),
        ),
        const VerticalDivider(width: 1, thickness: 1),
        Expanded(
          child: FocusTraversalGroup( // <-- WRAP Main Content in FocusTraversalGroup
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: _Header(
                    restaurant: widget.restaurant,
                    searchController: _searchController,
                    isDesktop: true,
                    searchFocusNode: _searchFocusNode, // Pass search node
                  ),
                ),
                _DashboardGrid(
                  items: _filteredItems,
                  allItems: _dashboardItems,
                  onItemTap: (screen, index) => _navigateTo(screen, index),
                  // --- REMOVED focusedIndex & crossAxisCount ---
                ),
              ],
            ),
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

  // --- 1. ADD FocusNode ---
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // --- 2. ADD Listener ---
    _focusNode.addListener(() {
      if (mounted) {
        setState(() {}); // Just trigger a rebuild to check hasFocus
      }
    });
  }

  @override
  void dispose() {
    // --- 3. DISPOSE Node ---
    _focusNode.dispose();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // --- 4. UPDATE Highlight Logic ---
    final bool isHighlighted = _isHovered || _focusNode.hasFocus || widget.isSelected;

    final Color textColor = isHighlighted // <-- Use new logic
        ? theme.primaryColor
        : theme.textTheme.bodyLarge!.color!;
    final Color bgColor = isHighlighted // <-- Use new logic
        ? theme.primaryColor.withOpacity(0.1)
        : (_isHovered
        ? theme.textTheme.bodyLarge!.color!.withOpacity(0.05)
        : Colors.transparent);

    // --- 5. WRAP in Focus to handle Enter ---
    return Focus(
      focusNode: _focusNode, // Assign the node here
      onKey: (FocusNode node, RawKeyEvent event) {
        if (event is RawKeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.numpadEnter)) {
          widget.onTap(); // Call the onTap function
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: SystemMouseCursors.click,
        // --- 6. CHANGE to InkWell ---
        child: InkWell(
          onTap: widget.onTap,
          onFocusChange: (hasFocus) { // --- 7. ADD onFocusChange ---
            setState(() {}); // Trigger rebuild
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: bgColor, // <-- Use new logic
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
                      color: textColor, // <-- Use new logic
                      fontWeight:
                      isHighlighted ? FontWeight.bold : FontWeight.normal, // <-- Use new logic
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
            ),          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final Restaurant restaurant;
  final TextEditingController searchController;
  final bool isDesktop;
  final FocusNode searchFocusNode;

  const _Header({
    required this.restaurant,
    required this.searchController,
    this.isDesktop = false,
    required this.searchFocusNode,
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
            focusNode: searchFocusNode,
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

    final double maxCardWidth = 220.0;
    final double spacing = 20.0;
    final double contentWidth = MediaQuery.of(context).size.width;
    // This is a simplified calculation, but good enough
    final int crossAxisCount = (contentWidth / (maxCardWidth + spacing)).floor().clamp(1, 6);

    return SliverPadding(
      padding: const EdgeInsets.all(24.0),
      sliver: SliverGrid.builder(
        itemCount: items.length,
        // --- 3. USE FixedCrossAxisCount to match logic ---
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
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
            columnCount: crossAxisCount, // <-- Pass calculated count
            child: ScaleAnimation(
              child: FadeInAnimation(
                child: DashboardCard(
                  item: item,
                  // --- REMOVED isFocused ---
                  onTap: () => onItemTap(item.screen, originalIndex),
                ),
              ),
            ),
          );
        },
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

  final FocusNode _cardFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _cardFocusNode.addListener(() {
      if(mounted) {
        setState(() {}); // Just trigger rebuild
      }
    });
  }

  @override
  void dispose() {
    _cardFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // --- UPDATED Highlight Logic ---
    final bool isHighlighted = _isHovered || _cardFocusNode.hasFocus;

    // --- 1. WRAP in Focus to handle Enter ---
    return Focus(
      onKey: (FocusNode node, RawKeyEvent event) {
        if (event is RawKeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.numpadEnter)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: SystemMouseCursors.click,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onTap,
              focusNode: _cardFocusNode, // <-- 2. ASSIGN node
              onFocusChange: (hasFocus) { // <-- 3. ADD onFocusChange
                setState(() {});
              },
              splashColor: theme.primaryColor.withOpacity(0.1),
              highlightColor: theme.primaryColor.withOpacity(0.05),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: isHighlighted // <-- 4. USE new logic
                        ? theme.primaryColor.withOpacity(0.5)
                        : Colors.white.withOpacity(0.2),
                    width: isHighlighted ? 2.5 : 1.5,
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