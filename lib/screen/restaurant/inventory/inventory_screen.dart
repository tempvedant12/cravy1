import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cravy/screen/restaurant/inventory/add_edit_inventory_item_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'dart:ui';


class InventoryItem {
  final String id;
  final String name;
  final String category;
  final double quantity;
  final String unit;
  final double lowStockThreshold;
  final String type; // 'veg', 'non-veg', or 'none'

  InventoryItem({
    required this.id,
    required this.name,
    required this.category,
    required this.quantity,
    required this.unit,
    required this.lowStockThreshold,
    required this.type,
  });

  factory InventoryItem.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return InventoryItem(
      id: doc.id,
      name: data['name'] ?? 'No Name',
      category: data['category'] ?? 'Uncategorized',
      quantity: (data['quantity'] ?? 0.0).toDouble(),
      unit: data['unit'] ?? '',
      lowStockThreshold: (data['lowStockThreshold'] ?? 0.0).toDouble(),
      type: data['type'] ?? 'none',
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is InventoryItem &&
              runtimeType == other.runtimeType &&
              id == other.id;

  @override
  int get hashCode => id.hashCode;
}


class InventoryScreen extends StatefulWidget {
  final String restaurantId;
  const InventoryScreen({super.key, required this.restaurantId});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  late final Stream<QuerySnapshot> _inventoryStream;
  String _selectedCategory = 'All Items';
  String _selectedTypeFilter = 'All'; // 'All', 'veg', 'non-veg'
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _inventoryStream = FirebaseFirestore.instance
        .collection('restaurants')
        .doc(widget.restaurantId)
        .collection('inventory')
        .orderBy('name')
        .snapshots();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text;
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _navigateToEditScreen(InventoryItem? item) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AddEditInventoryItemScreen(
          restaurantId: widget.restaurantId,
          item: item,
        ),
      ),
    );
  }

  Future<void> _deleteItem(InventoryItem item) async {
    final bool? confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Item?'),
        content: Text(
            'Are you sure you want to delete "${item.name}"? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Delete',
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      try {
        await FirebaseFirestore.instance
            .collection('restaurants')
            .doc(widget.restaurantId)
            .collection('inventory')
            .doc(item.id)
            .delete();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('"${item.name}" has been deleted.'),
              backgroundColor: Colors.green[700],
            ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _navigateToEditScreen(null),
        child: const Icon(Icons.add),
      ),
      body: Stack(
        children: [
          const _StaticBackground(),
          StreamBuilder<QuerySnapshot>(
            stream: _inventoryStream,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return _buildEmptyState();
              }

              final allItems = snapshot.data!.docs
                  .map((doc) => InventoryItem.fromFirestore(doc))
                  .toList();
              final categories = [
                'All Items',
                ...allItems.map((item) => item.category).toSet()
              ];

              final displayedItems = allItems.where((item) {
                final categoryMatch = _selectedCategory == 'All Items' ||
                    item.category == _selectedCategory;
                final searchMatch = item.name
                    .toLowerCase()
                    .contains(_searchQuery.toLowerCase());
                final typeMatch = _selectedTypeFilter == 'All' ||
                    item.type == _selectedTypeFilter;
                return categoryMatch && searchMatch && typeMatch;
              }).toList();

              return LayoutBuilder(builder: (context, constraints) {
                if (constraints.maxWidth < 800) {
                  return _buildMobileLayout(
                      context, allItems, categories, displayedItems);
                } else {
                  return _buildDesktopLayout(
                      context, allItems, categories, displayedItems);
                }
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLayout(
      BuildContext context,
      List<InventoryItem> allItems,
      List<String> categories,
      List<InventoryItem> displayedItems) {
    return DefaultTabController(
      length: categories.length,
      child: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverAppBar(
              title: const Text('Inventory'),
              pinned: true,
              floating: true,
              snap: true,
              forceElevated: innerBoxIsScrolled,
              backgroundColor:
              Theme.of(context).scaffoldBackgroundColor.withOpacity(0.8),
              actions: [
                PopupMenuButton<String>(
                  onSelected: (value) {
                    setState(() {
                      _selectedTypeFilter = value;
                    });
                  },
                  itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                    const PopupMenuItem<String>(
                      value: 'All',
                      child: Text('All Types'),
                    ),
                    const PopupMenuItem<String>(
                      value: 'veg',
                      child: Text('Veg'),
                    ),
                    const PopupMenuItem<String>(
                      value: 'non-veg',
                      child: Text('Non-Veg'),
                    ),
                  ],
                ),
              ],
              flexibleSpace: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                  child: Container(color: Colors.transparent),
                ),
              ),
              bottom: TabBar(
                isScrollable: true,
                tabs:
                categories.map((category) => Tab(text: category)).toList(),
                onTap: (index) {
                  setState(() {
                    _selectedCategory = categories[index];
                  });
                },
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: _SearchField(controller: _searchController),
              ),
            ),
          ];
        },
        body: _ItemsList(
          items: displayedItems,
          onItemTap: _navigateToEditScreen,
          onItemDelete: _deleteItem,
        ),
      ),
    );
  }

  Widget _buildDesktopLayout(
      BuildContext context,
      List<InventoryItem> allItems,
      List<String> categories,
      List<InventoryItem> displayedItems) {
    return Row(
      children: [
        _CategorySidebar(
          categories: categories,
          selectedCategory: _selectedCategory,
          onCategorySelected: (category) {
            setState(() {
              _selectedCategory = category;
            });
          },
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: CustomScrollView(
            slivers: [
              SliverAppBar(
                title: Text(_selectedCategory),
                pinned: true,
                backgroundColor:
                Theme.of(context).scaffoldBackgroundColor.withOpacity(0.8),
                flexibleSpace: ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                    child: Container(color: Colors.transparent),
                  ),
                ),
                actions: [
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      setState(() {
                        _selectedTypeFilter = value;
                      });
                    },
                    itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                      const PopupMenuItem<String>(
                        value: 'All',
                        child: Text('All Types'),
                      ),
                      const PopupMenuItem<String>(
                        value: 'veg',
                        child: Text('Veg'),
                      ),
                      const PopupMenuItem<String>(
                        value: 'non-veg',
                        child: Text('Non-Veg'),
                      ),
                    ],
                  ),
                  SizedBox(
                    width: 250,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 8.0, horizontal: 16),
                      child: _SearchField(controller: _searchController),
                    ),
                  ),
                ],
              ),
              if (displayedItems.isEmpty)
                SliverFillRemaining(
                  child: Center(
                      child: Text(_searchQuery.isEmpty
                          ? 'No items in this category.'
                          : 'No items match your search.')),
                )
              else
                _ItemsGrid(
                  items: displayedItems,
                  onItemTap: _navigateToEditScreen,
                  onItemDelete: _deleteItem,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    final theme = Theme.of(context);
    return Column(
      children: [
        AppBar(
          title: const Text('Inventory'),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        Expanded(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.inventory_2_outlined,
                    size: 80, color: theme.dividerColor),
                const SizedBox(height: 24),
                Text('Your Inventory is Empty',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium),
                const SizedBox(height: 12),
                Text('Tap the + button to add your first item.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge),
              ],
            ),
          ),
        ),
      ],
    );
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
        hintText: 'Search items...',
        prefixIcon: const Icon(Icons.search, size: 20),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        filled: true,
        fillColor: theme.colorScheme.surface.withOpacity(0.5),
      ),
    );
  }
}

class _CategorySidebar extends StatelessWidget {
  final List<String> categories;
  final String selectedCategory;
  final ValueChanged<String> onCategorySelected;

  const _CategorySidebar({
    required this.categories,
    required this.selectedCategory,
    required this.onCategorySelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 250,
      color: theme.colorScheme.surface.withOpacity(0.2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 24, 16, 12),
            child: Text('Categories', style: theme.textTheme.titleSmall),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12.0),
              children: categories.map((category) {
                final isSelected = category == selectedCategory;
                return ListTile(
                  title: Text(category,
                      style: TextStyle(
                          fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal)),
                  selected: isSelected,
                  selectedTileColor: theme.primaryColor.withOpacity(0.1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  onTap: () => onCategorySelected(category),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemsList extends StatelessWidget {
  final List<InventoryItem> items;
  final Function(InventoryItem) onItemTap;
  final Function(InventoryItem) onItemDelete;

  const _ItemsList(
      {required this.items,
        required this.onItemTap,
        required this.onItemDelete});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Center(child: Text('No items match your search.'));
    }
    return AnimationLimiter(
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 80.0),
        itemCount: items.length,
        itemBuilder: (context, index) {
          return AnimationConfiguration.staggeredList(
            position: index,
            duration: const Duration(milliseconds: 375),
            child: SlideAnimation(
              verticalOffset: 50.0,
              child: FadeInAnimation(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: InventoryItemCard(
                    item: items[index],
                    onTap: () => onItemTap(items[index]),
                    onDelete: () => onItemDelete(items[index]),
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

class _ItemsGrid extends StatelessWidget {
  final List<InventoryItem> items;
  final Function(InventoryItem) onItemTap;
  final Function(InventoryItem) onItemDelete;

  const _ItemsGrid(
      {required this.items,
        required this.onItemTap,
        required this.onItemDelete});

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.all(24.0),
      sliver: AnimationLimiter(
        child: SliverGrid.builder(
          itemCount: items.length,
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 350,
            mainAxisSpacing: 20,
            crossAxisSpacing: 20,
            childAspectRatio: 2.5,
          ),
          itemBuilder: (context, index) {
            return AnimationConfiguration.staggeredGrid(
              position: index,
              duration: const Duration(milliseconds: 375),
              columnCount: 3,
              child: ScaleAnimation(
                child: FadeInAnimation(
                  child: InventoryItemCard(
                    item: items[index],
                    onTap: () => onItemTap(items[index]),
                    onDelete: () => onItemDelete(items[index]),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class InventoryItemCard extends StatefulWidget {
  final InventoryItem item;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const InventoryItemCard({
    super.key,
    required this.item,
    required this.onTap,
    required this.onDelete,
  });

  @override
  State<InventoryItemCard> createState() => _InventoryItemCardState();
}

class _InventoryItemCardState extends State<InventoryItemCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLowStock = widget.item.quantity <= widget.item.lowStockThreshold;
    final typeColor = widget.item.type == 'veg'
        ? Colors.green
        : widget.item.type == 'non-veg'
        ? Colors.red
        : Colors.grey;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            splashColor: theme.primaryColor.withOpacity(0.1),
            highlightColor: theme.primaryColor.withOpacity(0.05),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
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
              child: Row(
                children: [
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inventory_2_outlined,
                          size: 28,
                          color:
                          theme.textTheme.bodyLarge?.color?.withOpacity(0.8)),
                      const SizedBox(height: 4),
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: typeColor,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: theme.scaffoldBackgroundColor,
                            width: 2,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          widget.item.name,
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.item.category,
                          style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.textTheme.bodyMedium?.color
                                  ?.withOpacity(0.7)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${widget.item.quantity.toStringAsFixed(1)} ${widget.item.unit}',
                        style: theme.textTheme.bodyLarge
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      if (isLowStock)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.error.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Low Stock',
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.error,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  ),
                  IconButton(
                    icon: Icon(Icons.delete_outline,
                        color: theme.colorScheme.error.withOpacity(0.8)),
                    onPressed: widget.onDelete,
                    splashRadius: 20,
                    tooltip: 'Delete Item',
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