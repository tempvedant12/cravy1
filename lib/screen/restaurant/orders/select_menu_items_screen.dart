// lib/screen/restaurant/orders/select_menu_items_screen.dart

import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cravy/models/order_models.dart';
import 'package:cravy/screen/restaurant/menu/menu_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:ui';

// --- NEW MODEL FOR CONSISTENT DISPLAY/ORDERING ---
class MenuDisplayItem {
  final MenuItem item;
  final String menuName;
  final String menuId;

  MenuDisplayItem({required this.item, required this.menuName, required this.menuId});

  // Proxy getters for convenience
  String get id => item.id;
  String get name => item.name;
  String get category => item.category;
  List<OptionGroup> get optionGroups => item.optionGroups;
  double get price => item.price;
  String get type => item.type; // Expose type for filtering
}

class MenuData {
  final List<dynamic> menuItems; // List of MenuDisplayItem
  final Map<String, double> inventoryLevels;
  MenuData({required this.menuItems, required this.inventoryLevels});
}

class SelectMenuItemsScreen extends StatefulWidget {
  final String restaurantId;
  const SelectMenuItemsScreen({
    super.key,
    required this.restaurantId,
  });

  @override
  State<SelectMenuItemsScreen> createState() => _SelectMenuItemsScreenState();
}

class _SelectMenuItemsScreenState extends State<SelectMenuItemsScreen> with TickerProviderStateMixin {
  final Map<String, OrderItem> _selectedItems = {};
  String? _selectedMenuId;
  String? _selectedMenuName;
  List<DocumentSnapshot> _allMenus = []; // <--- ADDED: Store all menus

  void _updateQuantity(String uniqueId, int change) {
    setState(() {
      if (_selectedItems.containsKey(uniqueId)) {
        _selectedItems[uniqueId]!.quantity += change;
        if (_selectedItems[uniqueId]!.quantity <= 0) {
          _selectedItems.remove(uniqueId);
        }
      }
    });
  }

  void _addItem(OrderItem newItem) {
    setState(() {
      if (_selectedItems.containsKey(newItem.uniqueId)) {
        _selectedItems[newItem.uniqueId]!.quantity += newItem.quantity;
      } else {
        _selectedItems[newItem.uniqueId] = newItem;
      }
    });
  }


  @override
  Widget build(BuildContext context) {
    // Define the AppBar content for calculation and use
    final PreferredSizeWidget mainAppBar = AppBar(
      title: Text(_selectedMenuName ?? 'Select Items'),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor.withOpacity(0.85),
      elevation: 0,
      bottom: const TabBar(
        tabs: [
          Tab(icon: Icon(Icons.restaurant_menu), text: 'Browse Menu'),
          Tab(icon: Icon(Icons.shopping_cart_checkout), text: 'Selected Items'),
        ],
      ),
    );

    // Calculate the required top padding: Status bar height + AppBar's preferred size (which includes the primary TabBar)
    final double requiredPadding = mainAppBar.preferredSize.height + MediaQuery.of(context).padding.top;

    return DefaultTabController(
      length: 2,
      child: Stack( // <--- ADDED Stack
        children: [
          const _StaticBackground(), // <--- ADDED Background
          Scaffold(
            extendBodyBehindAppBar: true, // <--- ADDED
            backgroundColor: Colors.transparent, // <--- MODIFIED
            appBar: mainAppBar, // <--- Used defined AppBar
            bottomNavigationBar: _buildBottomMenuBar(),
            body: Stack(
              children: [
                // Apply Padding to push content below the AppBar/TabBar region
                Padding(
                  padding: EdgeInsets.only(top: requiredPadding), // <--- MODIFIED
                  child: TabBarView(
                    children: [
                      _selectedMenuId != null ?
                      _MenuContent(
                        key: ValueKey(_selectedMenuId), // This is the crucial part
                        restaurantId: widget.restaurantId,
                        selectedMenuId: _selectedMenuId!,
                        menus: _allMenus, // <--- MODIFIED: Pass the menus list
                        onItemSelected: _addItem,
                        selectedItems: _selectedItems,
                      ) : const Center(child: CircularProgressIndicator()),
                      _SelectedItemsList(
                        selectedItems: _selectedItems.values.toList(),
                        onQuantityChanged: _updateQuantity,
                      ),
                    ],
                  ),
                ),
                _buildConfirmationPanel(),
              ],
            ),
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

                  // --- ADDED: Capture and store menus list ---
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && !listEquals(_allMenus, menus)) {
                      setState(() {
                        _allMenus = menus;
                      });
                    }
                  });
                  // ------------------------------------------

                  if (_selectedMenuId == null && menus.isNotEmpty) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        setState(() {
                          _selectedMenuId = menus.first.id;
                          _selectedMenuName = menus.first['name'];
                        });
                      }
                    });
                  }

                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        if (menus.length > 1)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4.0),
                            child: ChoiceChip(
                              label: const Text('All Menus'),
                              selected: _selectedMenuId == 'ALL_MENUS',
                              onSelected: (selected) {
                                if (selected) {
                                  setState(() {
                                    _selectedMenuId = 'ALL_MENUS';
                                    _selectedMenuName = 'All Menus';
                                  });
                                }
                              },
                            ),
                          ),
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
                                    _selectedMenuName = doc['name'];
                                  });
                                }
                              },
                            ),
                          );
                        }).toList(),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildConfirmationPanel() {
    final theme = Theme.of(context);
    final hasSelection = _selectedItems.isNotEmpty;
    final totalItemCount = _selectedItems.values.fold(0, (sum, item) => sum + item.quantity);
    return AnimatedSlide(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      offset: hasSelection ? Offset.zero : const Offset(0, 2),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ClipRRect(
          child: Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: theme.scaffoldBackgroundColor.withOpacity(0.8),
              border: Border(top: BorderSide(color: theme.dividerColor, width: 1.5)),
            ),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.of(context).pop(_selectedItems.values.toList()),
                icon: const Icon(Icons.check),
                label: Text('Add $totalItemCount Items'),
                style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuContent extends StatefulWidget {
  final String restaurantId;
  final String selectedMenuId;
  final List<DocumentSnapshot> menus; // <--- Correctly defined
  final Function(OrderItem) onItemSelected;
  final Map<String, OrderItem> selectedItems;


  const _MenuContent({
    super.key,
    required this.restaurantId,
    required this.selectedMenuId,
    required this.menus, // <--- Correctly defined
    required this.onItemSelected,
    required this.selectedItems,
  });

  @override
  State<_MenuContent> createState() => _MenuContentState();
}


class _MenuContentState extends State<_MenuContent> with TickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _debounce;
  late TabController _foodTypeTabController;
  String _selectedFoodType = 'All';
  Stream<MenuData>? _menuDataStream;
  List<StreamSubscription> _allMenuSubscriptions = [];
  StreamSubscription? _inventorySubscription;
  StreamSubscription? _menuSubscription;


  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _menuDataStream = _getMenuDataStream(widget.selectedMenuId);
    _foodTypeTabController = TabController(length: 3, vsync: this);
    _foodTypeTabController.addListener(() {
      if (mounted && !_foodTypeTabController.indexIsChanging) {
        setState(() {
          switch (_foodTypeTabController.index) {
            case 0:
              _selectedFoodType = 'All';
              break;
            case 1:
              _selectedFoodType = 'veg';
              break;
            case 2:
              _selectedFoodType = 'non-veg';
              break;
          }
        });
      }
    });
  }

  Stream<MenuData> _getMenuDataStream(String menuId) {
    _menuSubscription?.cancel();
    _inventorySubscription?.cancel();
    for (var sub in _allMenuSubscriptions) {
      sub.cancel();
    }
    _allMenuSubscriptions.clear();

    final controller = StreamController<MenuData>();
    Map<String, double>? latestInventory;
    final Map<String, List<MenuDisplayItem>> allMenuCurrentItems = {};

    void updateStream(List<dynamic> latestMenu) {
      if (latestInventory != null && !controller.isClosed) {
        // --- ADDED: Sort combined list for consistency ---
        latestMenu.sort((a, b) {
          final catCompare = a.category.compareTo(b.category);
          if (catCompare != 0) return catCompare;
          return a.name.compareTo(b.name);
        });
        // ------------------------------------------------

        controller.add(MenuData(
          menuItems: latestMenu,
          inventoryLevels: latestInventory!,
        ));
      }
    }

    _inventorySubscription = FirebaseFirestore.instance
        .collection('restaurants')
        .doc(widget.restaurantId)
        .collection('inventory')
        .snapshots()
        .listen((snapshot) {
      final inventoryMap = <String, double>{};
      for (var doc in snapshot.docs) {
        inventoryMap[doc.id] = (doc.data())['quantity']?.toDouble() ?? 0.0;
      }
      latestInventory = inventoryMap;

      final List<dynamic> combinedItems = allMenuCurrentItems.values.expand((i) => i).toList();
      updateStream(combinedItems);
    });

    if (menuId == 'ALL_MENUS') {
      // --- FIX: Iterate over widget.menus to create streams for all menus ---
      for (var doc in widget.menus) {
        final String currentMenuId = doc.id;
        final String currentMenuName = doc['name'];
        final sub = FirebaseFirestore.instance
            .collection('restaurants')
            .doc(widget.restaurantId)
            .collection('menus')
            .doc(currentMenuId)
            .collection('items')
            .orderBy('category')
            .orderBy('name')
            .snapshots()
            .listen((snapshot) {
          allMenuCurrentItems[currentMenuId] = snapshot.docs.map((d) =>
              MenuDisplayItem(
                  item: MenuItem.fromFirestore(d),
                  menuName: currentMenuName,
                  menuId: currentMenuId
              )).toList();
          final List<dynamic> combinedItems = allMenuCurrentItems.values.expand((i) => i).toList();
          updateStream(combinedItems);
        });
        _allMenuSubscriptions.add(sub);
      }
      controller.onCancel = () {
        _inventorySubscription?.cancel();
        for(var sub in _allMenuSubscriptions) { sub.cancel(); }
        _allMenuSubscriptions.clear();
      };
      // -----------------------------------------------------------------------
    } else {
      // --- MODIFIED: Safely get the single menu name ---
      final menuDoc = widget.menus.firstWhere((d) => d.id == menuId, orElse: () => throw Exception('Menu document not found'));
      final String singleMenuName = menuDoc['name'];

      _menuSubscription = FirebaseFirestore.instance
          .collection('restaurants')
          .doc(widget.restaurantId)
          .collection('menus')
          .doc(menuId)
          .collection('items')
          .orderBy('category')
          .orderBy('name')
          .snapshots()
          .listen((snapshot) {
        final List<MenuDisplayItem> singleMenu = snapshot.docs.map((doc) =>
            MenuDisplayItem(
                item: MenuItem.fromFirestore(doc),
                menuName: singleMenuName,
                menuId: menuId
            )).toList();
        allMenuCurrentItems[menuId] = singleMenu;
        updateStream(singleMenu);
      });
      controller.onCancel = () {
        _inventorySubscription?.cancel();
        _menuSubscription?.cancel();
      };
    }
    return controller.stream;
  }


  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _debounce?.cancel();
    _foodTypeTabController.dispose();
    _menuSubscription?.cancel();
    _inventorySubscription?.cancel();
    for (var sub in _allMenuSubscriptions) {
      sub.cancel();
    }
    super.dispose();
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _searchQuery = _searchController.text;
        });
      }
    });
  }

  void _handleItemTap(MenuDisplayItem item, int availableQuantity, Map<String, double> inventoryLevels) async {
    if (availableQuantity <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This item is out of stock.')));
      return;
    }
    if (item.optionGroups.isEmpty) {
      widget.onItemSelected(OrderItem(menuItem: item.item, selectedOptions: [], quantity: 1, menuName: item.menuName));
    } else {
      final List<SelectedOption>? selectedOptions = await showDialog(
        context: context,
        builder: (_) => _CustomizeItemDialog(
          menuItem: item.item,
          inventoryLevels: _getRemainingInventoryForOptions(inventoryLevels), // <--- MODIFIED: Pass remaining inventory
        ),
      );
      if (selectedOptions != null) {
        widget.onItemSelected(OrderItem(menuItem: item.item, selectedOptions: selectedOptions, quantity: 1, menuName: item.menuName));
      }
    }
  }

  // --- NEW HELPER: Calculate committed inventory from items already in cart ---
  Map<String, double> _getCommittedInventory(Map<String, OrderItem> selectedItems) {
    final Map<String, double> committed = {};

    for (var item in selectedItems.values) {
      // 1. Commit Base Recipe
      for (var recipeItem in item.menuItem.baseRecipe) {
        final quantityToCommit = recipeItem.quantityUsed * item.quantity;
        committed.update(
          recipeItem.inventoryItemId,
              (value) => value + quantityToCommit,
          ifAbsent: () => quantityToCommit,
        );
      }

      // 2. Commit Selected Options
      for (var option in item.selectedOptions) {
        final quantityToCommit = option.quantityUsed * item.quantity;
        committed.update(
          option.inventoryItemId,
              (value) => value + quantityToCommit,
          ifAbsent: () => quantityToCommit,
        );
      }
    }

    return committed;
  }
  // ---------------------------------------------------------------------------

  // --- NEW HELPER: Calculate remaining inventory for the Option Dialog ---
  Map<String, double> _getRemainingInventoryForOptions(Map<String, double> inventoryLevels) {
    final committed = _getCommittedInventory(widget.selectedItems);
    final Map<String, double> remaining = {};
    inventoryLevels.forEach((key, value) {
      remaining[key] = value - (committed[key] ?? 0.0);
    });
    return remaining;
  }
  // ---------------------------------------------------------------------


  // --- MODIFIED: Checks remaining inventory after accounting for items already in cart ---
  int _getAvailableQuantity(MenuDisplayItem item, Map<String, double> inventoryLevels) {
    // 1. Calculate inventory already reserved by items currently in the cart
    final committed = _getCommittedInventory(widget.selectedItems);

    if (item.item.baseRecipe.isEmpty) return 999;
    int maxPossible = 999;

    // 2. Check availability for the base recipe against the remaining stock
    for (var recipeItem in item.item.baseRecipe) {
      final rawAvailable = inventoryLevels[recipeItem.inventoryItemId] ?? 0.0;
      final committedQty = committed[recipeItem.inventoryItemId] ?? 0.0;

      // Calculate the true remaining available quantity
      final remainingAvailableQty = rawAvailable - committedQty;

      if (recipeItem.quantityUsed <= 0) continue;

      // If remaining is zero or negative, the item is out of stock for the next unit.
      if (remainingAvailableQty <= 0) return 0;

      // Calculate how many units of the item can be made from this ingredient's remaining stock
      final possibleFromThisIngredient = (remainingAvailableQty / recipeItem.quantityUsed).floor();
      maxPossible = min(maxPossible, possibleFromThisIngredient);
    }
    return maxPossible;
  }
  // -----------------------------------------------------------------------------------

  void _directAddOne(MenuDisplayItem item) {
    final newItem = OrderItem(
        menuItem: item.item, selectedOptions: [], quantity: 1, menuName: item.menuName);
    widget.onItemSelected(newItem);
  }

  void _directRemoveOne(MenuItem item) {
    // This logic needs to be handled in the parent `_SelectMenuItemsScreenState`
  }


  @override
  Widget build(BuildContext context) {
    return StreamBuilder<MenuData>(
        stream: _menuDataStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: Text('Loading menu...'));
          }

          final menuData = snapshot.data!;
          final allItems = menuData.menuItems.cast<MenuDisplayItem>();
          final inventoryLevels = menuData.inventoryLevels;

          final typeFilteredItems = allItems.where((item) {
            return _selectedFoodType == 'All' || item.type == _selectedFoodType;
          }).toList();

          final searchAndTypeFilteredItems = typeFilteredItems.where((item) {
            return item.name.toLowerCase().contains(_searchQuery.toLowerCase());
          }).toList();

          return Column(
            children: [
              _buildSearchAction(context, _searchController),
              TabBar(
                controller: _foodTypeTabController,
                tabs: const [
                  Tab(text: 'All'),
                  Tab(text: 'Veg'),
                  Tab(text: 'Non-Veg'),
                ],
              ),
              Expanded(
                child: _CategoryTabsView(
                  key: ValueKey('${widget.selectedMenuId}_$_selectedFoodType'),
                  items: searchAndTypeFilteredItems,
                  selectedItems: widget.selectedItems,
                  inventoryLevels: inventoryLevels,
                  onItemTap: _handleItemTap,
                  getAvailableQuantity: _getAvailableQuantity,
                  onAddOne: _directAddOne,
                  onRemoveOne: _directRemoveOne,
                  showMenuTag: widget.menus.length > 1,
                ),
              ),
            ],
          );
        }
    );
  }

}


class _CategoryTabsView extends StatefulWidget {
  final List<MenuDisplayItem> items;
  final Map<String, OrderItem> selectedItems;
  final Map<String, double> inventoryLevels;
  final Function(MenuDisplayItem, int, Map<String, double>) onItemTap;
  final int Function(MenuDisplayItem, Map<String, double>) getAvailableQuantity;
  final Function(MenuDisplayItem) onAddOne;
  final Function(MenuItem) onRemoveOne;
  final bool showMenuTag;

  const _CategoryTabsView({
    super.key,
    required this.items,
    required this.selectedItems,
    required this.inventoryLevels,
    required this.onItemTap,
    required this.getAvailableQuantity,
    required this.onAddOne,
    required this.onRemoveOne,
    required this.showMenuTag,
  });

  @override
  State<_CategoryTabsView> createState() => _CategoryTabsViewState();
}

class _CategoryTabsViewState extends State<_CategoryTabsView> with TickerProviderStateMixin {
  TabController? _categoryTabController;
  List<String> _tabCategories = [];

  @override
  void initState() {
    super.initState();
    _updateTabs();
  }

  @override
  void didUpdateWidget(covariant _CategoryTabsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Rebuild tabs if the items passed to this widget have changed
    if (!listEquals(oldWidget.items.map((e) => e.id).toList(), widget.items.map((e) => e.id).toList())) {
      _updateTabs();
    }
  }

  void _updateTabs() {
    final categories = widget.items.map((item) => item.category).toSet().toList();
    categories.sort();
    final newTabCategories = ['All', ...categories];

    // Check if the actual categories have changed before rebuilding the controller
    if (!listEquals(_tabCategories, newTabCategories)) {
      setState(() {
        _tabCategories = newTabCategories;
        _categoryTabController?.dispose();
        _categoryTabController = TabController(length: _tabCategories.length, vsync: this);
      });
    }
  }

  @override
  void dispose() {
    _categoryTabController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_categoryTabController == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (widget.items.isEmpty) {
      return const Center(child: Text('No items for this filter.'));
    }

    return Column(
      children: [
        TabBar(
          controller: _categoryTabController,
          isScrollable: true,
          tabs: _tabCategories.map((c) => Tab(text: c)).toList(),
        ),
        Expanded(
          child: TabBarView(
            controller: _categoryTabController,
            children: _tabCategories.map((category) {
              final itemsToShow = category == 'All'
                  ? widget.items
                  : widget.items.where((item) => item.category == category).toList();
              return _MenuItemsGrid(
                items: itemsToShow,
                selectedItems: widget.selectedItems,
                onItemTap: (item, qty) => widget.onItemTap(item, qty, widget.inventoryLevels),
                getAvailableQuantity: (item) => widget.getAvailableQuantity(item as MenuDisplayItem, widget.inventoryLevels),
                onAddOne: widget.onAddOne,
                onRemoveOne: widget.onRemoveOne,
                showMenuTag: widget.showMenuTag,
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}


class _MenuItemsGrid extends StatelessWidget {
  final List<MenuDisplayItem> items;
  final Map<String, OrderItem> selectedItems;
  final Function(MenuDisplayItem item, int availableQuantity) onItemTap;
  final int Function(MenuDisplayItem item) getAvailableQuantity;
  final Function(MenuDisplayItem item) onAddOne;
  final Function(MenuItem item) onRemoveOne;
  final bool showMenuTag;

  const _MenuItemsGrid(
      {required this.items,
        required this.selectedItems,
        required this.onItemTap,
        required this.getAvailableQuantity,
        required this.onAddOne,
        required this.onRemoveOne,
        required this.showMenuTag});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const Center(child: Text("No items found."));
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 200,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 0.85),
      itemBuilder: (context, index) {
        final itemDisplay = items[index];
        final availableQty = getAvailableQuantity(itemDisplay);
        final selectedQty = selectedItems.values
            .where((orderItem) => orderItem.menuItem.id == itemDisplay.item.id)
            .fold(0, (sum, orderItem) => sum + orderItem.quantity);

        return SelectableItemCard(
          item: itemDisplay.item,
          menuName: itemDisplay.menuName,
          showMenuTag: showMenuTag,
          onTap: () => onItemTap(itemDisplay, availableQty),
          availableQuantity: availableQty,
          selectedQuantity: selectedQty,
          onAddOne: itemDisplay.item.optionGroups.isEmpty ? () => onAddOne(itemDisplay) : null,
          onRemoveOne: itemDisplay.item.optionGroups.isEmpty ? () => onRemoveOne(itemDisplay.item) : null,
        );
      },
    );
  }
}

class SelectableItemCard extends StatelessWidget {
  final MenuItem item;
  final VoidCallback onTap;
  final int availableQuantity;
  final int selectedQuantity;
  final VoidCallback? onAddOne;
  final VoidCallback? onRemoveOne;
  final String menuName;
  final bool showMenuTag;


  const SelectableItemCard(
      {super.key,
        required this.item,
        required this.onTap,
        required this.availableQuantity,
        required this.selectedQuantity,
        this.onAddOne,
        this.onRemoveOne,
        required this.menuName,
        required this.showMenuTag});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAvailable = availableQuantity > 0;
    final actionText = item.optionGroups.isEmpty ? 'Add' : 'Customize';
    final showQuantityControls = selectedQuantity > 0 && item.optionGroups.isEmpty;
    final showCustomizedCounter = selectedQuantity > 0 && item.optionGroups.isNotEmpty;
    final typeColor = item.type == 'veg'
        ? Colors.green
        : item.type == 'non-veg'
        ? Colors.red
        : Colors.grey;

    return Opacity(
      opacity: isAvailable ? 1.0 : 0.5,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.ease,
          decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.dividerColor)),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Container(
                        color: theme.colorScheme.surface.withOpacity(0.5),
                        padding: const EdgeInsets.all(8.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (showMenuTag)
                              Chip(
                                label: Text(menuName, style: theme.textTheme.bodySmall?.copyWith(fontSize: 10, fontWeight: FontWeight.bold)),
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                              ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (item.type != 'none')
                                  Container(
                                    margin: const EdgeInsets.only(right: 4.0),
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: typeColor,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                Flexible(
                                  child: Text(item.name,
                                      textAlign: TextAlign.center,
                                      style: theme.textTheme.titleMedium,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text('₹${item.price.toStringAsFixed(2)}',
                                style: theme.textTheme.bodyMedium
                                    ?.copyWith(color: theme.primaryColor)),
                          ],
                        ),
                      ),
                    ),
                    if (showQuantityControls)
                      Container(
                        height: 48,
                        color: theme.dividerColor.withOpacity(0.5),
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              iconSize: 24,
                              onPressed: onRemoveOne,
                              color: theme.colorScheme.error,
                            ),
                            Text(
                              selectedQuantity.toString(),
                              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            IconButton(
                              icon: Icon(Icons.add_circle_outline, color: theme.primaryColor),
                              iconSize: 24,
                              onPressed: onAddOne,
                            ),
                          ],
                        ),
                      )
                    else
                      Container(
                        height: 48,
                        color: theme.dividerColor.withOpacity(0.5),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(actionText,
                                style: theme.textTheme.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.bold)),
                            if (showCustomizedCounter) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: theme.primaryColor,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${selectedQuantity}x',
                                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onPrimary, fontWeight: FontWeight.bold),
                                ),
                              )
                            ]
                          ],
                        ),
                      ),
                  ],
                ),
                if (!isAvailable)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(15)),
                      child: const Center(
                          child: Text('OUT OF STOCK',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16))),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectedItemsList extends StatelessWidget {
  final List<OrderItem> selectedItems;
  final Function(String uniqueId, int change) onQuantityChanged;

  const _SelectedItemsList(
      {required this.selectedItems, required this.onQuantityChanged});

  @override
  Widget build(BuildContext context) {
    if (selectedItems.isEmpty) {
      return const Center(child: Text('No items selected yet.'));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 100),
      itemCount: selectedItems.length,
      itemBuilder: (context, index) {
        final orderItem = selectedItems[index];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: ListTile(
            title: Row(
              children: [
                Expanded(child: Text(orderItem.menuItem.name)),
                Chip(
                  label: Text(orderItem.menuName,
                      style: const TextStyle(fontSize: 12)),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                )
              ],
            ),
            subtitle: orderItem.selectedOptions.isEmpty
                ? null
                : Text(orderItem.selectedOptions
                .map((o) => o.optionName)
                .join(', ')),
            trailing: _buildQuantityControl(Theme.of(context), orderItem),
          ),
        );
      },
    );
  }

  Widget _buildQuantityControl(ThemeData theme, OrderItem orderItem) {
    return SizedBox(
      width: 120,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: () => onQuantityChanged(orderItem.uniqueId, -1),
              iconSize: 22),
          Text(orderItem.quantity.toString(),
              style: theme.textTheme.titleMedium),
          IconButton(
              icon: Icon(Icons.add_circle_outline, color: theme.primaryColor),
              onPressed: () => onQuantityChanged(orderItem.uniqueId, 1),
              iconSize: 22),
        ],
      ),
    );
  }
}

class _CustomizeItemDialog extends StatefulWidget {
  final MenuItem menuItem;
  // This inventoryLevels now represents the *remaining* inventory after current cart deductions
  final Map<String, double> inventoryLevels;

  const _CustomizeItemDialog(
      {required this.menuItem, required this.inventoryLevels});

  @override
  State<_CustomizeItemDialog> createState() => _CustomizeItemDialogState();
}

class _CustomizeItemDialogState extends State<_CustomizeItemDialog> {
  final Map<String, SelectedOption> _selectedOptions = {};
  final _formKey = GlobalKey<FormState>();

  // Helper to check if a recipe link is available based on remaining inventory
  bool _isOptionAvailable(RecipeItem recipeLink) {
    return (widget.inventoryLevels[recipeLink.inventoryItemId] ?? 0) >= recipeLink.quantityUsed;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Customize ${widget.menuItem.name}'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: widget.menuItem.optionGroups.map((group) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Text(group.name,
                        style: Theme.of(context).textTheme.titleLarge),
                  ),
                  if (group.isMultiSelect)
                    ...group.options
                        .map((option) => _buildCheckboxOption(group, option))
                  else
                    _buildRadioOptionGroup(group),
                ],
              );
            }).toList(),
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        ElevatedButton(
            onPressed: _confirmSelection, child: const Text('Add to Order')),
      ],
    );
  }

  void _confirmSelection() {
    if (_formKey.currentState!.validate()) {
      Navigator.of(context).pop(_selectedOptions.values.toList());
    }
  }

  Widget _buildRadioOptionGroup(OptionGroup group) {
    return FormField<String>(
      validator: (value) {
        if (group.isRequired && value == null) {
          return 'Please select an option for ${group.name}.';
        }
        return null;
      },
      builder: (state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...group.options
                .map((option) => _buildRadioOption(group, option, state)),
            if (state.hasError)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(state.errorText!,
                    style:
                    TextStyle(color: Theme.of(context).colorScheme.error)),
              )
          ],
        );
      },
    );
  }

  Widget _buildRadioOption(
      OptionGroup group, OptionItem option, FormFieldState<String> state) {
    final bool isAvailable = _isOptionAvailable(option.recipeLink);

    return RadioListTile<String>(
      title: Text(option.name),
      subtitle: Text('+ ₹${option.additionalPrice.toStringAsFixed(2)}'),
      value: option.name,
      groupValue: _selectedOptions[group.name]?.optionName,
      onChanged: isAvailable
          ? (String? value) {
        setState(() {
          _selectedOptions[group.name] = SelectedOption(
            groupName: group.name,
            optionName: option.name,
            additionalPrice: option.additionalPrice,
            inventoryItemId: option.recipeLink.inventoryItemId,
            quantityUsed: option.recipeLink.quantityUsed,
          );
          state.didChange(value);
        });
      }
          : null,
    );
  }

  Widget _buildCheckboxOption(OptionGroup group, OptionItem option) {
    final bool isAvailable = _isOptionAvailable(option.recipeLink);

    return CheckboxListTile(
      title: Text(option.name),
      subtitle: Text('+ ₹${option.additionalPrice.toStringAsFixed(2)}'),
      value: _selectedOptions.containsKey(option.name),
      onChanged: isAvailable
          ? (bool? value) {
        setState(() {
          if (value == true) {
            _selectedOptions[option.name] = SelectedOption(
              groupName: group.name,
              optionName: option.name,
              additionalPrice: option.additionalPrice,
              inventoryItemId: option.recipeLink.inventoryItemId,
              quantityUsed: option.recipeLink.quantityUsed,
            );
          } else {
            _selectedOptions.remove(option.name);
          }
        });
      }
          : null,
    );
  }
}

Widget _buildSearchAction(
    BuildContext context, TextEditingController controller) {
  return Padding(
    padding: const EdgeInsets.all(8.0),
    child: TextField(
      controller: controller,
      decoration: InputDecoration(
        hintText: 'Search items...',
        prefixIcon: const Icon(Icons.search, size: 20),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
        filled: true,
        fillColor: Theme.of(context).colorScheme.surface.withOpacity(0.5),
      ),
    ),
  );
}

// --- ADDED _StaticBackground Class ---
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