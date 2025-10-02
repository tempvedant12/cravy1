

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cravy/screen/restaurant/inventory/inventory_screen.dart'
as inventory;
import 'package:cravy/screen/restaurant/menu/menu_screen.dart';
import 'package:cravy/services/unit_converter_service.dart';

class SelectIngredientsScreen extends StatefulWidget {
  final String restaurantId;
  final List<RecipeItem> initialRecipe;

  const SelectIngredientsScreen({
    super.key,
    required this.restaurantId,
    required this.initialRecipe,
  });

  @override
  State<SelectIngredientsScreen> createState() =>
      _SelectIngredientsScreenState();
}

class _SelectIngredientsScreenState extends State<SelectIngredientsScreen> {
  List<inventory.InventoryItem> _inventoryItems = [];
  List<inventory.InventoryItem> _filteredInventory = [];
  List<RecipeItem> _selectedRecipe = [];
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedRecipe = List<RecipeItem>.from(widget.initialRecipe);
    _searchController.addListener(_filterInventory);
  }

  @override
  void dispose() {
    _searchController.removeListener(_filterInventory);
    _searchController.dispose();
    super.dispose();
  }

  void _filterInventory() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredInventory = _inventoryItems.where((item) {
        return item.name.toLowerCase().contains(query);
      }).toList();
    });
  }

  void _onItemSelected(inventory.InventoryItem item) async {
    
    final existingRecipeItem = _selectedRecipe.firstWhere(
            (recipe) => recipe.inventoryItemId == item.id,
        orElse: () => RecipeItem(inventoryItemId: '', name: '', quantityUsed: 0.0, unit: ''));

    final double? quantityInBaseUnit = await showDialog(
      context: context,
      builder: (context) => _EnterQuantityDialog(
        item: item,
        initialQuantity: existingRecipeItem.quantityUsed,
      ),
    );

    if (quantityInBaseUnit != null) {
      setState(() {
        final index = _selectedRecipe.indexWhere((recipe) => recipe.inventoryItemId == item.id);

        if (quantityInBaseUnit > 0) {
          final newRecipeItem = RecipeItem(
              inventoryItemId: item.id,
              name: item.name,
              quantityUsed: quantityInBaseUnit,
              unit: item.unit);
          if (index != -1) {
            _selectedRecipe[index] = newRecipeItem; 
          } else {
            _selectedRecipe.add(newRecipeItem); 
          }
        } else if (index != -1) {
          _selectedRecipe.removeAt(index); 
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isWideScreen = MediaQuery.of(context).size.width > 700;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Ingredients'),
        actions: [
          if (isWideScreen)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: ElevatedButton.icon(
                icon: const Icon(Icons.check),
                label: const Text('Done'),
                onPressed: _selectedRecipe.isNotEmpty
                    ? () => Navigator.of(context).pop(_selectedRecipe)
                    : null,
              ),
            )
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('restaurants')
            .doc(widget.restaurantId)
            .collection('inventory')
            .orderBy('name')
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          _inventoryItems = snapshot.data!.docs
              .map((doc) => inventory.InventoryItem.fromFirestore(doc))
              .toList();
          if (_searchController.text.isEmpty) {
            _filteredInventory = _inventoryItems;
          }

          final categories = _inventoryItems.map((item) => item.category).toSet().toList();

          return isWideScreen
              ? _buildWideLayout(theme, categories)
              : _buildNarrowLayout(theme, categories);
        },
      ),
    );
  }

  Widget _buildWideLayout(ThemeData theme, List<String> categories) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: _buildInventoryPanel(theme, categories),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          flex: 1,
          child: _buildSelectedList(),
        ),
      ],
    );
  }

  Widget _buildNarrowLayout(ThemeData theme, List<String> categories) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: 'Inventory'),
              Tab(text: 'Selected'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildInventoryPanel(theme, categories),
                _buildSelectedList(showDoneButton: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInventoryPanel(ThemeData theme, List<String> categories) {
    return DefaultTabController(
      length: categories.length + 1,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search inventory...',
                prefixIcon: const Icon(Icons.search),
              ),
            ),
          ),
          TabBar(
            isScrollable: true,
            tabs: [
              const Tab(text: 'All Items'),
              ...categories.map((c) => Tab(text: c)),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildInventoryList(_filteredInventory),
                ...categories.map((category) {
                  final items = _filteredInventory
                      .where((item) => item.category == category)
                      .toList();
                  return _buildInventoryList(items);
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInventoryList(List<inventory.InventoryItem> items) {
    if (items.isEmpty) {
      return const Center(child: Text('No items found.'));
    }
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return ListTile(
          title: Text(item.name),
          subtitle: Text(item.category),
          trailing: const Icon(Icons.add_circle_outline),
          onTap: () => _onItemSelected(item),
        );
      },
    );
  }

  Widget _buildSelectedList({bool showDoneButton = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text('Selected Ingredients (${_selectedRecipe.length})',
              style: Theme.of(context).textTheme.titleMedium),
        ),
        Expanded(
          child: _selectedRecipe.isEmpty
              ? const Center(child: Text('No ingredients selected.'))
              : ListView.builder(
            itemCount: _selectedRecipe.length,
            itemBuilder: (context, index) {
              final item = _selectedRecipe[index];
              final inventoryItem = _inventoryItems.firstWhere((invItem) => invItem.id == item.inventoryItemId);
              return ListTile(
                title: Text(item.name),
                trailing: Text('${item.quantityUsed.toStringAsFixed(2)} ${item.unit}'),
                onTap: () => _onItemSelected(inventoryItem), 
              );
            },
          ),
        ),
        if (showDoneButton)
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.check),
                label: const Text('Done'),
                onPressed: _selectedRecipe.isNotEmpty
                    ? () => Navigator.of(context).pop(_selectedRecipe)
                    : null,
              ),
            ),
          ),
      ],
    );
  }
}


class _EnterQuantityDialog extends StatefulWidget {
  final inventory.InventoryItem item;
  final double initialQuantity;
  const _EnterQuantityDialog({required this.item, this.initialQuantity = 0.0});

  @override
  State<_EnterQuantityDialog> createState() => _EnterQuantityDialogState();
}

class _EnterQuantityDialogState extends State<_EnterQuantityDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _controller;
  late List<String> _compatibleUnits;
  late String _selectedUnit;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuantity > 0 ? widget.initialQuantity.toString() : '');
    _compatibleUnits = UnitConverterService.getCompatibleUnits(widget.item.unit);
    _selectedUnit = widget.item.unit;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Quantity for ${widget.item.name}'),
      content: Form(
        key: _formKey,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min, 
          children: [
            Expanded(
              flex: 3,
              child: TextFormField(
                controller: _controller,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Quantity Used'),
                validator: (val) => (val == null || double.tryParse(val) == null || double.parse(val) < 0)
                    ? 'Invalid'
                    : null,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: DropdownButtonFormField<String>(
                value: _selectedUnit,
                isExpanded: true,
                items: _compatibleUnits.map((String unit) {
                  return DropdownMenuItem<String>(
                    value: unit,
                    child: Text(unit, overflow: TextOverflow.ellipsis),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  setState(() {
                    _selectedUnit = newValue!;
                  });
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        ElevatedButton(
            onPressed: () {
              if (_formKey.currentState!.validate()) {
                final enteredQuantity = double.parse(_controller.text);
                final baseQuantity = UnitConverterService.convertToBase(enteredQuantity, _selectedUnit);
                final conversionFactor = UnitConverterService.convertToBase(1.0, widget.item.unit);
                Navigator.of(context).pop(baseQuantity / conversionFactor);
              }
            },
            child: const Text('Confirm')),
      ],
    );
  }
}