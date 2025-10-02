import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cravy/screen/restaurant/menu/add_edit_menu_item_screen.dart';
import 'package:cravy/screen/restaurant/menu/manage_menus_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'dart:ui';

// --- DATA MODELS (No Changes Needed) ---

class RecipeItem {
  final String inventoryItemId;
  final String name;
  final double quantityUsed;
  final String unit;

  RecipeItem({
    required this.inventoryItemId,
    required this.name,
    required this.quantityUsed,
    required this.unit,
  });

  factory RecipeItem.fromMap(Map<String, dynamic> map) {
    return RecipeItem(
      inventoryItemId: map['inventoryItemId'] ?? '',
      name: map['name'] ?? '',
      quantityUsed: (map['quantityUsed'] ?? 0.0).toDouble(),
      unit: map['unit'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'inventoryItemId': inventoryItemId,
      'name': name,
      'quantityUsed': quantityUsed,
      'unit': unit,
    };
  }
}

class OptionItem {
  final String name;
  final double additionalPrice;
  final RecipeItem recipeLink;

  OptionItem({
    required this.name,
    required this.additionalPrice,
    required this.recipeLink,
  });

  factory OptionItem.fromMap(Map<String, dynamic> map) {
    return OptionItem(
      name: map['name'] ?? '',
      additionalPrice: (map['additionalPrice'] ?? 0.0).toDouble(),
      recipeLink: RecipeItem.fromMap(map['recipeLink'] ?? {}),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'additionalPrice': additionalPrice,
      'recipeLink': recipeLink.toMap(),
    };
  }
}

class OptionGroup {
  final String name;
  final List<OptionItem> options;
  final bool isMultiSelect;
  final bool isRequired;

  OptionGroup({
    required this.name,
    required this.options,
    required this.isMultiSelect,
    required this.isRequired,
  });

  factory OptionGroup.fromMap(Map<String, dynamic> map) {
    var optionsData = map['options'] as List<dynamic>? ?? [];
    return OptionGroup(
      name: map['name'] ?? '',
      options: optionsData.map((item) => OptionItem.fromMap(item)).toList(),
      isMultiSelect: map['isMultiSelect'] ?? false,
      isRequired: map['isRequired'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'options': options.map((item) => item.toMap()).toList(),
      'isMultiSelect': isMultiSelect,
      'isRequired': isRequired,
    };
  }
}

class MenuItem {
  final String id;
  final String name;
  final String description;
  final String category;
  final double price;
  final List<RecipeItem> baseRecipe;
  final List<OptionGroup> optionGroups;
  final String type; // 'veg', 'non-veg', or 'none'

  MenuItem({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.price,
    required this.baseRecipe,
    required this.optionGroups,
    required this.type,
  });

  factory MenuItem.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    var baseRecipeData = data['baseRecipe'] as List<dynamic>? ?? [];
    var optionGroupsData = data['optionGroups'] as List<dynamic>? ?? [];

    return MenuItem(
      id: doc.id,
      name: data['name'] ?? 'No Name',
      description: data['description'] ?? '',
      category: data['category'] ?? 'Uncategorized',
      price: (data['price'] ?? 0.0).toDouble(),
      baseRecipe:
      baseRecipeData.map((item) => RecipeItem.fromMap(item)).toList(),
      optionGroups:
      optionGroupsData.map((item) => OptionGroup.fromMap(item)).toList(),
      type: data['type'] ?? 'none',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'category': category,
      'price': price,
      'baseRecipe': baseRecipe.map((i) => i.toMap()).toList(),
      'optionGroups': optionGroups.map((g) => g.toMap()).toList(),
      'type': type,
    };
  }
}


// --- REWRITTEN MENU SCREEN ---

class MenuScreen extends StatefulWidget {
  final String restaurantId;
  const MenuScreen({super.key, required this.restaurantId});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  String? _selectedMenuId;

  void _manageMenus() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ManageMenusScreen(restaurantId: widget.restaurantId),
      ),
    );
  }

  void _navigateToEditScreen() {
    if (_selectedMenuId == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AddEditMenuItemScreen(
          restaurantId: widget.restaurantId,
          menuId: _selectedMenuId!,
          menuItem: null, // Always adding a new item from this button
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      // The bottom bar is now part of the main scaffold and handles menu selection.
      bottomNavigationBar: _buildBottomMenuBar(),
      body: Stack(
        children: [
          const _StaticBackground(),
          // This StreamBuilder ONLY fetches the list of available menus.
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('restaurants')
                .doc(widget.restaurantId)
                .collection('menus')
                .snapshots(),
            builder: (context, menuSnapshot) {
              if (menuSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (!menuSnapshot.hasData || menuSnapshot.data!.docs.isEmpty) {
                return _buildEmptyState(context, isNoMenus: true);
              }

              final menus = menuSnapshot.data!.docs;
              // Set the first menu as selected by default.
              if (_selectedMenuId == null && menus.isNotEmpty) {
                // Use addPostFrameCallback to avoid calling setState during a build.
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    setState(() {
                      _selectedMenuId = menus.first.id;
                    });
                  }
                });
              }

              // If a menu is selected, show the content. Otherwise, show a loader.
              return _selectedMenuId != null
                  ? _MenuContent(
                // Use a Key to force the content to rebuild when the menu changes.
                key: ValueKey(_selectedMenuId),
                restaurantId: widget.restaurantId,
                menuId: _selectedMenuId!,
              )
                  : const Center(child: CircularProgressIndicator());
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBottomMenuBar() {
    return Material(
      elevation: 8.0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        child: Row(
          children: [
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('restaurants')
                    .doc(widget.restaurantId)
                    .collection('menus')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const SizedBox();
                  final menus = snapshot.data!.docs;
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        ...menus.map((doc) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4.0),
                            child: ChoiceChip(
                              label: Text(doc['name']),
                              selected: _selectedMenuId == doc.id,
                              onSelected: (selected) {
                                if (selected) {
                                  setState(() {
                                    _selectedMenuId = doc.id;
                                  });
                                }
                              },
                            ),
                          );
                        }).toList(),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4.0),
                          child: ActionChip(
                            avatar: const Icon(Icons.add),
                            label: const Text('Create Menu'),
                            onPressed: _manageMenus,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle),
              onPressed: _selectedMenuId == null ? null : _navigateToEditScreen,
              tooltip: 'Add Item to Selected Menu',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, {required bool isNoMenus}) {
    final theme = Theme.of(context);
    final content = Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.menu_book_outlined, size: 80, color: theme.dividerColor),
          const SizedBox(height: 24),
          Text(isNoMenus ? 'No Menus Found' : 'Your Menu is Empty',
              textAlign: TextAlign.center, style: theme.textTheme.headlineMedium),
          const SizedBox(height: 12),
          Text(
              isNoMenus
                  ? 'Tap the "Create Menu" button to get started.'
                  : 'Tap the + button to add your first dish.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge),
        ],
      ),
    );

    if (isNoMenus) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Menu'),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: content,
      );
    }
    return content;
  }
}


// --- NEW WIDGET TO MANAGE MENU CONTENT ---

class _MenuContent extends StatefulWidget {
  final String restaurantId;
  final String menuId;

  const _MenuContent({super.key, required this.restaurantId, required this.menuId});

  @override
  State<_MenuContent> createState() => _MenuContentState();
}

class _MenuContentState extends State<_MenuContent> with TickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _debounce;

  late TabController _foodTypeTabController;
  TabController? _categoryTabController;

  List<String> _currentTabCategories = [];
  String _selectedFoodType = 'All';

  @override
  void initState() {
    super.initState();
    _foodTypeTabController = TabController(length: 3, vsync: this);
    _foodTypeTabController.addListener(() {
      if (mounted) {
        setState(() {
          switch (_foodTypeTabController.index) {
            case 0: _selectedFoodType = 'All'; break;
            case 1: _selectedFoodType = 'veg'; break;
            case 2: _selectedFoodType = 'non-veg'; break;
          }
        });
      }
    });
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _debounce?.cancel();
    _foodTypeTabController.dispose();
    _categoryTabController?.dispose();
    super.dispose();
  }

  _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _searchQuery = _searchController.text);
    });
  }

  void _navigateToEditScreen(MenuItem? menuItem) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AddEditMenuItemScreen(
          restaurantId: widget.restaurantId,
          menuId: widget.menuId,
          menuItem: menuItem,
        ),
      ),
    );
  }

  // *** NEW: Delete Menu Item Function ***
  Future<void> _deleteMenuItem(MenuItem item) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Item?'),
        content: Text('Are you sure you want to delete "${item.name}"? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text('Delete', style: TextStyle(color: Theme.of(context).colorScheme.error))
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      try {
        await FirebaseFirestore.instance
            .collection('restaurants')
            .doc(widget.restaurantId)
            .collection('menus')
            .doc(widget.menuId)
            .collection('items')
            .doc(item.id)
            .delete();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('"${item.name}" deleted successfully!')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting item: ${e.toString()}')),
          );
        }
      }
    }
  }
  // ************************************

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('restaurants')
          .doc(widget.restaurantId)
          .collection('menus')
          .doc(widget.menuId)
          .collection('items')
          .orderBy('category')
          .orderBy('name')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(title: const Text("Menu Error")),
            body: Center(child: Text('Error: ${snapshot.error}')),
          );
        }

        final List<MenuItem> allItems = snapshot.hasData
            ? snapshot.data!.docs.map((doc) => MenuItem.fromFirestore(doc)).toList()
            : [];

        final categories = allItems.map((item) => item.category).toSet().toList();
        categories.sort();
        final newTabCategories = ['All', ...categories];

        final List<MenuItem> filteredItems = allItems.where((item) {
          final searchMatch = item.name.toLowerCase().contains(_searchQuery.toLowerCase());
          final typeMatch = _selectedFoodType == 'All' || item.type == _selectedFoodType;
          return searchMatch && typeMatch;
        }).toList();

        if (!listEquals(_currentTabCategories, newTabCategories)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _categoryTabController?.dispose();
                _categoryTabController = TabController(length: newTabCategories.length, vsync: this);
                _currentTabCategories = newTabCategories;
              });
            }
          });
        }

        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: const Text("Menu"),
            backgroundColor: Theme.of(context).scaffoldBackgroundColor.withOpacity(0.85),
            elevation: 0,
            actions: [_buildSearchAction(context)],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(100),
              child: Column(
                children: [
                  TabBar(
                    controller: _foodTypeTabController,
                    tabs: const [Tab(text: 'All'), Tab(text: 'Veg'), Tab(text: 'Non-Veg')],
                  ),
                  _categoryTabController == null
                      ? const SizedBox(height: 48)
                      : TabBar(
                    controller: _categoryTabController,
                    isScrollable: true,
                    tabs: newTabCategories.map((category) => Tab(text: category)).toList(),
                  ),
                ],
              ),
            ),
          ),
          body: !snapshot.hasData
              ? const Center(child: CircularProgressIndicator())
              : allItems.isEmpty
              ? _buildEmptyState(context, isNoMenus: false)
              : _categoryTabController == null
              ? Container()
              : TabBarView(
            controller: _categoryTabController,
            children: newTabCategories.map((category) {
              final List<MenuItem> categoryItems = category == 'All'
                  ? filteredItems
                  : filteredItems.where((item) => item.category == category).toList();
              return _MenuItemsList(
                items: categoryItems,
                onItemTap: _navigateToEditScreen,
                onItemDelete: _deleteMenuItem, // *** PASS NEW FUNCTION ***
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Widget _buildSearchAction(BuildContext context) {
    return SizedBox(
      width: 250,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16),
        child: TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Search menu...',
            prefixIcon: const Icon(Icons.search, size: 20),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            filled: true,
            fillColor: Theme.of(context).colorScheme.surface.withOpacity(0.5),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, {required bool isNoMenus}) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.menu_book_outlined, size: 80, color: theme.dividerColor),
          const SizedBox(height: 24),
          Text(isNoMenus ? 'No Menus Found' : 'Your Menu is Empty',
              textAlign: TextAlign.center, style: theme.textTheme.headlineMedium),
          const SizedBox(height: 12),
          Text(
              isNoMenus
                  ? 'Tap the edit icon to create your first menu.'
                  : 'Tap the + button to add your first dish.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge),
        ],
      ),
    );
  }
}

// --- WIDGET WITH AutomaticKeepAliveClientMixin ---

class _MenuItemsList extends StatefulWidget {
  final List<MenuItem> items;
  final Function(MenuItem) onItemTap;
  final Function(MenuItem) onItemDelete; // *** NEW FIELD ***
  const _MenuItemsList({required this.items, required this.onItemTap, required this.onItemDelete});

  @override
  State<_MenuItemsList> createState() => _MenuItemsListState();
}

class _MenuItemsListState extends State<_MenuItemsList> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (widget.items.isEmpty) {
      return const Center(child: Text("No items found for this filter."));
    }
    return AnimationLimiter(
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
        itemCount: widget.items.length,
        itemBuilder: (context, index) {
          return AnimationConfiguration.staggeredList(
            position: index,
            duration: const Duration(milliseconds: 375),
            child: SlideAnimation(
              verticalOffset: 50.0,
              child: FadeInAnimation(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: MenuItemCard(
                    item: widget.items[index],
                    onTap: () => widget.onItemTap(widget.items[index]),
                    onDelete: () => widget.onItemDelete(widget.items[index]), // *** PASS DELETE HANDLER ***
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

// --- CARD AND BACKGROUND WIDGETS (No Changes Needed) ---

class MenuItemCard extends StatelessWidget {
  final MenuItem item;
  final VoidCallback onTap;
  final VoidCallback onDelete; // *** NEW FIELD ***
  const MenuItemCard({super.key, required this.item, required this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ingredientsString = item.baseRecipe.map((e) => e.name).join(', ');
    final optionsString = item.optionGroups.map((e) => e.name).join(' • ');

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.2)),
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
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center, // *** MODIFIED: Center alignment for balance ***
                children: [
                  if (item.type != 'none')
                    Container(
                      margin: const EdgeInsets.only(right: 8.0), // Removed top: 6.0
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: item.type == 'veg' ? Colors.green : Colors.red,
                        shape: BoxShape.circle,
                        border: Border.all(color: theme.cardColor, width: 2),
                      ),
                    ),
                  Expanded(
                    child: Text(
                      item.name,
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),

                  // Price and Delete Button Group
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '₹${item.price.toStringAsFixed(2)}',
                        style: theme.textTheme.titleMedium?.copyWith( // *** MODIFIED: Reduced size for better alignment ***
                            fontWeight: FontWeight.bold,
                            color: theme.primaryColor),
                      ),
                      // *** NEW: Delete Button ***
                      IconButton(
                        icon: Icon(Icons.delete_outline, color: theme.colorScheme.error, size: 22), // Increased icon size slightly
                        onPressed: onDelete,
                        tooltip: 'Delete Item',
                        padding: EdgeInsets.zero,
                        constraints: BoxConstraints(minWidth: 40, minHeight: 40),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (item.description.isNotEmpty) ...[
                Text(
                  item.description,
                  style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.textTheme.bodyMedium?.color
                          ?.withOpacity(0.8)),
                ),
                const SizedBox(height: 12),
              ],
              if (ingredientsString.isNotEmpty) ...[
                _buildInfoRow(
                  theme,
                  icon: Icons.inventory_2_outlined,
                  title: 'Contains:',
                  value: ingredientsString,
                ),
                const SizedBox(height: 8),
              ],
              if (optionsString.isNotEmpty) ...[
                _buildInfoRow(
                  theme,
                  icon: Icons.add_shopping_cart_outlined,
                  title: 'Options:',
                  value: optionsString,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(ThemeData theme,
      {required IconData icon, required String title, required String value}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: theme.primaryColor.withOpacity(0.8)),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(
            TextSpan(
              text: '$title ',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
              children: [
                TextSpan(
                  text: value,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.normal),
                ),
              ],
            ),
          ),
        ),
      ],
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