import 'dart:async';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cravy/screen/theme/theme_screen.dart';
import 'package:cravy/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:intl/intl.dart';

import '../restaurant/EditRestaurantScreen.dart';
import '../restaurant/restaurant_screen.dart';
import 'create_restaurant_screen.dart';

// --- BREAKPOINT FOR RESPONSIVE LAYOUT ---
const double _desktopBreakpoint = 900.0;

// --- MAIN HOME SCREEN WIDGET ---
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AuthService _auth = AuthService();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  late final Stream<QuerySnapshot> _restaurantsStream;

  @override
  void initState() {
    super.initState();
    _restaurantsStream = _getRestaurantsStream();
    _searchController.addListener(() {
      if (mounted) {
        setState(() => _searchQuery = _searchController.text);
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _navigateTo(BuildContext context, Widget screen) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => screen,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      extendBodyBehindAppBar: true,
      drawer: const _AppDrawer(),
      body: Stack(
        children: [
          const _StaticBackground(),
          StreamBuilder<QuerySnapshot>(
            stream: _restaurantsStream,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }
              final allRestaurants = snapshot.data?.docs
                  .map((doc) => Restaurant.fromFirestore(doc))
                  .toList() ??
                  [];

              final filteredRestaurants = allRestaurants.where((restaurant) {
                return restaurant.name
                    .toLowerCase()
                    .contains(_searchQuery.toLowerCase());
              }).toList();

              return LayoutBuilder(builder: (context, constraints) {
                if (constraints.maxWidth < _desktopBreakpoint) {
                  return _buildMobileLayout(
                      context, filteredRestaurants, _scaffoldKey);
                } else {
                  return _buildDesktopLayout(
                      context, filteredRestaurants, _scaffoldKey);
                }
              });
            },
          ),
        ],
      ),
      floatingActionButton: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < _desktopBreakpoint) {
            return FloatingActionButton(
              onPressed: () =>
                  _navigateTo(context, const CreateRestaurantScreen()),
              child: const Icon(Icons.add),
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }

  /// The original layout, optimized for mobile screens.
  Widget _buildMobileLayout(BuildContext context, List<Restaurant> restaurants,
      GlobalKey<ScaffoldState> scaffoldKey) {
    return CustomScrollView(
      slivers: [
        _CustomSliverAppBar(scaffoldKey: scaffoldKey),
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.only(top: 24.0),
            child: BenefitsCarousel(),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
            child: _SearchField(controller: _searchController),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
            child: Text(
              "Your Restaurants",
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
        ),
        if (restaurants.isEmpty)
          const SliverFillRemaining(
              hasScrollBody: false, child: _EmptyState())
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            sliver: _RestaurantList(restaurants: restaurants),
          ),
      ],
    );
  }

  /// A new dashboard-style layout for web and desktop.
  Widget _buildDesktopLayout(BuildContext context, List<Restaurant> restaurants,
      GlobalKey<ScaffoldState> scaffoldKey) {
    return Row(
      children: [
        Expanded(
          child: CustomScrollView(
            slivers: [
              _CustomSliverAppBar(scaffoldKey: scaffoldKey),
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
              const SliverToBoxAdapter(child: _QuickActionsGrid()),
              SliverToBoxAdapter(
                child: _RestaurantSectionHeader(
                  searchController: _searchController,
                  onAdd: () =>
                      _navigateTo(context, const CreateRestaurantScreen()),
                ),
              ),
              if (restaurants.isEmpty)
                const SliverFillRemaining(
                    hasScrollBody: false, child: _EmptyState())
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 100),
                  sliver: _RestaurantGrid(
                    restaurants: restaurants,
                    crossAxisCount:
                    (MediaQuery.of(context).size.width / 420).floor(),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Stream<QuerySnapshot> _getRestaurantsStream() {
    final user = _auth.currentUser;
    if (user == null) return const Stream.empty();
    return FirebaseFirestore.instance
        .collection('restaurants')
        .where('ownerId', isEqualTo: user.uid)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }
}

// --- LAYOUT-SPECIFIC WIDGETS ---

class _QuickActionsGrid extends StatelessWidget {
  const _QuickActionsGrid();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 20,
        mainAxisSpacing: 20,
        childAspectRatio: 2.5,
        children: const [
          BenefitCard(
            icon: Icons.sync_alt_rounded,
            title: 'Streamline Operations',
            description: 'Manage tables, orders, and staff.',
          ),
          BenefitCard(
            icon: Icons.insights_rounded,
            title: 'Gain Valuable Insights',
            description: 'Track sales with detailed analytics.',
          ),
          BenefitCard(
            icon: Icons.favorite_border_rounded,
            title: 'Enhance Guest Experience',
            description: 'Faster service and smoother billing.',
          ),
        ],
      ),
    );
  }
}

class _RestaurantSectionHeader extends StatelessWidget {
  final TextEditingController searchController;
  final VoidCallback onAdd;

  const _RestaurantSectionHeader(
      {required this.searchController, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            "Your Restaurants",
            style:
            theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          SizedBox(
            width: 250,
            child: _SearchField(controller: searchController),
          ),
          const SizedBox(width: 16),
          ElevatedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Restaurant'),
            style: ElevatedButton.styleFrom(
              padding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RestaurantList extends StatelessWidget {
  final List<Restaurant> restaurants;
  const _RestaurantList({required this.restaurants});

  @override
  Widget build(BuildContext context) {
    return AnimationLimiter(
      child: SliverList.builder(
        itemCount: restaurants.length,
        itemBuilder: (context, index) => AnimationConfiguration.staggeredList(
          position: index,
          duration: const Duration(milliseconds: 500),
          child: SlideAnimation(
            verticalOffset: 50.0,
            child: FadeInAnimation(
              child: RestaurantCard(restaurant: restaurants[index]),
            ),
          ),
        ),
      ),
    );
  }
}

class _RestaurantGrid extends StatelessWidget {
  final List<Restaurant> restaurants;
  final int crossAxisCount;
  const _RestaurantGrid(
      {required this.restaurants, required this.crossAxisCount});

  @override
  Widget build(BuildContext context) {
    return AnimationLimiter(
      child: SliverGrid.builder(
        itemCount: restaurants.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          mainAxisSpacing: 20.0,
          crossAxisSpacing: 20.0,
          childAspectRatio: 1.8,
        ),
        itemBuilder: (context, index) {
          return AnimationConfiguration.staggeredGrid(
            position: index,
            duration: const Duration(milliseconds: 500),
            columnCount: crossAxisCount,
            child: ScaleAnimation(
              child: FadeInAnimation(
                child: RestaurantCard(restaurant: restaurants[index]),
              ),
            ),
          );
        },
      ),
    );
  }
}

// --- SHARED UI COMPONENTS ---

class _CustomSliverAppBar extends StatelessWidget {
  const _CustomSliverAppBar({required this.scaffoldKey});
  final GlobalKey<ScaffoldState> scaffoldKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = AuthService().currentUser;
    final String initial = user?.displayName?.isNotEmpty == true
        ? user!.displayName!.substring(0, 1).toUpperCase()
        : 'U';

    return SliverAppBar(
      pinned: true,
      floating: true,
      elevation: 0,
      backgroundColor: theme.scaffoldBackgroundColor.withOpacity(0.8),
      surfaceTintColor: Colors.transparent,
      flexibleSpace: ClipRect(
        child: Container(color: Colors.transparent),
      ),
      // --- CHANGES START HERE ---
      automaticallyImplyLeading: false,
      leading: IconButton(
        icon: CircleAvatar(
          backgroundColor: theme.dividerColor.withOpacity(0.5),
          child: Text(
            initial,
            style: TextStyle(
              color: theme.textTheme.bodyLarge?.color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        onPressed: () => scaffoldKey.currentState?.openDrawer(),
      ),
      centerTitle: true,
      title: Text(
        'DineFlow',
        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
      ),
      // --- CHANGES END HERE ---
      actions: [
        IconButton(
          icon: Icon(
            Icons.notifications_none_outlined,
            color: theme.textTheme.bodyLarge?.color,
            size: 28,
          ),
          onPressed: () {},
        ),
        const SizedBox(width: 8),
      ],
    );
  }
}

class _AppDrawer extends StatelessWidget {
  const _AppDrawer();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = AuthService();
    final user = auth.currentUser;
    final String initial = user?.displayName?.isNotEmpty == true
        ? user!.displayName!.substring(0, 1).toUpperCase()
        : 'U';

    return Drawer(
      backgroundColor: theme.scaffoldBackgroundColor.withOpacity(0.8),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: theme.primaryColor,
                    child: Text(
                      initial,
                      style: TextStyle(
                          color: theme.colorScheme.onPrimary, fontSize: 20),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user?.displayName ?? 'User',
                            style: theme.textTheme.titleMedium),
                        Text(user?.email ?? '',
                            style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            _buildDrawerItem(
              icon: Icons.palette_outlined,
              text: 'Appearance',
              onTap: () {
                Navigator.pop(context); // Close drawer first
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (context) => const ThemeScreen(),
                ));
              },
            ),
            _buildDrawerItem(
                icon: Icons.settings_outlined, text: 'Settings', onTap: () {}),
            const Spacer(),
            const Divider(height: 1),
            _buildDrawerItem(
                icon: Icons.logout,
                text: 'Sign Out',
                onTap: () => auth.signOut()),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerItem(
      {required IconData icon,
        required String text,
        required GestureTapCallback onTap}) {
    return ListTile(leading: Icon(icon), title: Text(text), onTap: onTap);
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  const _SearchField({required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        hintText: 'Search...',
        prefixIcon:
        Icon(Icons.search, color: theme.textTheme.bodySmall?.color),
        filled: true,
        fillColor: theme.dividerColor.withOpacity(0.5),
        contentPadding: const EdgeInsets.symmetric(vertical: 0),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 64),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_business_outlined,
                size: 80, color: Theme.of(context).dividerColor),
            const SizedBox(height: 24),
            Text('Your Space is Ready',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 12),
            Text('Add your first restaurant to get started.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge),
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
    return Container(
      color: theme.scaffoldBackgroundColor,
      child: Stack(
        children: [
          Positioned(
            top: -100,
            left: -150,
            child: _buildShape(theme.primaryColor.withOpacity(0.2), 350),
          ),
          Positioned(
            bottom: -150,
            right: -200,
            child: _buildShape(theme.colorScheme.surface.withOpacity(0.2), 450),
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

// --- REUSABLE WIDGETS ---

class BenefitsCarousel extends StatefulWidget {
  const BenefitsCarousel({super.key});
  @override
  State<BenefitsCarousel> createState() => _BenefitsCarouselState();
}

class _BenefitsCarouselState extends State<BenefitsCarousel> {
  final PageController _pageController = PageController(viewportFraction: 0.85);
  double _currentPage = 0.0;
  Timer? _timer;

  final List<Map<String, dynamic>> _benefits = [
    {
      'icon': Icons.sync_alt_rounded,
      'title': 'Streamline Operations',
      'description': 'Manage tables, orders, and staff all in one place.',
    },
    {
      'icon': Icons.insights_rounded,
      'title': 'Gain Valuable Insights',
      'description': 'Track your sales and performance with detailed analytics.',
    },
    {
      'icon': Icons.favorite_border_rounded,
      'title': 'Enhance Guest Experience',
      'description': 'Faster service and smoother billing for happier customers.',
    },
  ];

  @override
  void initState() {
    super.initState();
    _pageController.addListener(() {
      if (mounted) {
        setState(() {
          _currentPage = _pageController.page ?? 0.0;
        });
      }
    });

    _timer = Timer.periodic(const Duration(seconds: 5), (Timer timer) {
      if (!mounted) return;
      int nextPage = (_currentPage + 1).toInt() % _benefits.length;
      if (_pageController.hasClients) {
        _pageController.animateToPage(
          nextPage,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeIn,
        );
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 140,
          child: PageView.builder(
            controller: _pageController,
            itemCount: _benefits.length,
            itemBuilder: (context, index) {
              return Opacity(
                opacity: 1,
                child: Transform.scale(
                  scale: 1,
                  child: BenefitCard(
                    icon: _benefits[index]['icon'],
                    title: _benefits[index]['title'],
                    description: _benefits[index]['description'],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_benefits.length, (index) {
            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.symmetric(horizontal: 4.0),
              height: 8.0,
              width: _currentPage.round() == index ? 24.0 : 8.0,
              decoration: BoxDecoration(
                color: _currentPage.round() == index
                    ? Theme.of(context).primaryColor
                    : Theme.of(context).dividerColor,
                borderRadius: BorderRadius.circular(12),
              ),
            );
          }),
        ),
      ],
    );
  }
}

class BenefitCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const BenefitCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withOpacity(0.5),
        borderRadius: BorderRadius.circular(20),
        border:
        Border.all(color: theme.dividerColor.withOpacity(0.5), width: 1),
      ),
      child: Row(
        children: [
          Icon(icon, size: 36, color: theme.primaryColor),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: theme.textTheme.bodyMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class RestaurantCard extends StatefulWidget {
  final Restaurant restaurant;
  const RestaurantCard({super.key, required this.restaurant});

  @override
  State<RestaurantCard> createState() => _RestaurantCardState();
}

class _RestaurantCardState extends State<RestaurantCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Container(
        margin: const EdgeInsets.only(bottom: 20),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (context) =>
                      RestaurantDashboardScreen(restaurant: widget.restaurant),
                ));
              },
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                widget.restaurant.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.settings),
                              onPressed: () {
                                Navigator.of(context).push(MaterialPageRoute(
                                  builder: (context) => EditRestaurantScreen(
                                      restaurant: widget.restaurant),
                                ));
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.restaurant.address,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyLarge,
                        ),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            children: [
                              Text('Manage',
                                  style: theme.textTheme.bodyMedium),
                              const SizedBox(width: 8),
                              Icon(
                                Icons.arrow_forward,
                                color: theme.textTheme.bodyMedium?.color,
                                size: 16,
                              ),
                            ],
                          ),
                        ),
                      ],
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