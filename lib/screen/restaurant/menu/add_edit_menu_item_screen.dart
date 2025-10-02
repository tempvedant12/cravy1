import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cravy/screen/restaurant/inventory/inventory_screen.dart'
as inventory;
import 'package:cravy/screen/restaurant/menu/menu_screen.dart';
import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';

import 'SelectIngredientsScreen.dart';
import 'manage_option_group_screen.dart';

// Top-level helper function to ensure it's accessible everywhere in this file.
Widget _buildCleanContainer(
    {required BuildContext context,
      required Widget child,
      EdgeInsets padding = EdgeInsets.zero}) {
  final theme = Theme.of(context);
  return Container(
    decoration: BoxDecoration(
      color: theme.colorScheme.surface.withOpacity(0.5),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Padding(padding: padding, child: child),
  );
}

class AddEditMenuItemScreen extends StatefulWidget {
  final String restaurantId;
  final String menuId;
  final MenuItem? menuItem;

  const AddEditMenuItemScreen(
      {super.key,
        required this.restaurantId,
        required this.menuId,
        this.menuItem});

  @override
  State<AddEditMenuItemScreen> createState() => _AddEditMenuItemScreenState();
}

class _AddEditMenuItemScreenState extends State<AddEditMenuItemScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  late TextEditingController _nameController;
  late TextEditingController _descController;
  late TextEditingController _priceController;
  late TextEditingController _categoryController;
  late List<RecipeItem> _baseRecipe;
  late List<OptionGroup> _optionGroups;
  late String _itemType;
  late Set<String> _targetMenuIds;
  bool _isTypeLocked = false;

  late Future<List<String>> _categorySuggestionsFuture;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.menuItem?.name ?? '');
    _descController =
        TextEditingController(text: widget.menuItem?.description ?? '');
    _priceController =
        TextEditingController(text: widget.menuItem?.price.toString() ?? '');
    _categoryController =
        TextEditingController(text: widget.menuItem?.category ?? '');
    _baseRecipe = List<RecipeItem>.from(widget.menuItem?.baseRecipe ?? []);
    _optionGroups =
    List<OptionGroup>.from(widget.menuItem?.optionGroups ?? []);
    _itemType = widget.menuItem?.type ?? 'veg'; // Default to 'veg'
    _targetMenuIds = {widget.menuId};

    _categorySuggestionsFuture = _fetchCategorySuggestions();
    _determineAndSetItemType();
  }

  Future<void> _determineAndSetItemType() async {
    if (_isTypeLocked) return;

    final inventoryIds = <String>{};
    for (var item in _baseRecipe) {
      inventoryIds.add(item.inventoryItemId);
    }
    for (var group in _optionGroups) {
      for (var option in group.options) {
        inventoryIds.add(option.recipeLink.inventoryItemId);
      }
    }

    if (inventoryIds.isEmpty) {
      if (mounted) {
        setState(() {
          _itemType = 'veg'; // Default to veg if no ingredients
          _isTypeLocked = false;
        });
      }
      return;
    }

    final inventorySnapshot = await FirebaseFirestore.instance
        .collection('restaurants')
        .doc(widget.restaurantId)
        .collection('inventory')
        .where(FieldPath.documentId, whereIn: inventoryIds.toList())
        .get();

    String determinedType = 'veg';
    for (var doc in inventorySnapshot.docs) {
      final item = inventory.InventoryItem.fromFirestore(doc);
      if (item.type == 'non-veg') {
        determinedType = 'non-veg';
        break;
      }
    }

    if (mounted) {
      setState(() {
        _itemType = determinedType;
        _isTypeLocked = true;
      });
    }
  }

  Future<List<String>> _fetchCategorySuggestions() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('restaurants')
        .doc(widget.restaurantId)
        .collection('menus')
        .doc(widget.menuId)
        .collection('items')
        .get();

    if (snapshot.docs.isEmpty) return [];
    final categories =
    snapshot.docs.map((doc) => doc.data()['category'] as String).toSet();
    return categories.toList();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _priceController.dispose();
    _categoryController.dispose();
    super.dispose();
  }

  Future<void> _performSave() async {
    if (!_formKey.currentState!.validate() || _targetMenuIds.isEmpty) {
      if (_targetMenuIds.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Please select at least one menu to save to.')),
        );
      }
      return;
    }

    setState(() => _isLoading = true);
    try {
      final itemData = {
        'name': _nameController.text.trim(),
        'description': _descController.text.trim(),
        'price': double.tryParse(_priceController.text) ?? 0.0,
        // Category is correctly saved here, provided _categoryController is up to date
        'category': _categoryController.text.trim(),
        'baseRecipe': _baseRecipe.map((item) => item.toMap()).toList(),
        'optionGroups': _optionGroups.map((item) => item.toMap()).toList(),
        'type': _itemType,
      };

      final batch = FirebaseFirestore.instance.batch();
      final restaurantRef = FirebaseFirestore.instance
          .collection('restaurants')
          .doc(widget.restaurantId);

      for (final menuId in _targetMenuIds) {
        final menuItemsCollection =
        restaurantRef.collection('menus').doc(menuId).collection('items');
        if (widget.menuItem != null && menuId == widget.menuId) {
          batch.update(menuItemsCollection.doc(widget.menuItem!.id), itemData);
        } else {
          batch.set(menuItemsCollection.doc(), itemData);
        }
      }

      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Saved item to ${_targetMenuIds.length} ${_targetMenuIds.length > 1 ? "menus" : "menu"} successfully!')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error saving to multiple menus: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _manageBaseRecipe() async {
    final List<RecipeItem>? result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => SelectIngredientsScreen(
          restaurantId: widget.restaurantId,
          initialRecipe: _baseRecipe,
        ),
      ),
    );

    if (result != null) {
      setState(() {
        _baseRecipe = result;
        _isTypeLocked = false;
      });
      _determineAndSetItemType();
    }
  }

  void _manageOptionGroup({OptionGroup? existingGroup}) async {
    final OptionGroup? result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ManageOptionGroupScreen(
          restaurantId: widget.restaurantId,
          initialGroup: existingGroup,
        ),
      ),
    );

    if (result != null) {
      setState(() {
        if (existingGroup != null) {
          final index = _optionGroups.indexOf(existingGroup);
          _optionGroups[index] = result;
        } else {
          _optionGroups.add(result);
        }
        _isTypeLocked = false;
      });
      _determineAndSetItemType();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title:
        Text(widget.menuItem == null ? 'Add Menu Item' : 'Edit Menu Item'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Stack(
        children: [
          const _StaticBackground(),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 700),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24.0),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildTextField(
                            controller: _nameController,
                            label: 'Dish Name',
                            icon: Icons.restaurant_menu),
                        const SizedBox(height: 16),
                        _buildTypeSelector(),
                        const SizedBox(height: 16),
                        _buildTextField(
                            controller: _descController,
                            label: 'Description (Optional)',
                            icon: Icons.notes),
                        const SizedBox(height: 20),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _buildTextField(
                                  controller: _priceController,
                                  label: 'Price',
                                  icon: Icons.currency_rupee,
                                  keyboardType: TextInputType.number),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _buildCategoryAutocompleteField(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 30),
                        _buildIngredientsSection(),
                        const SizedBox(height: 20),
                        _buildOptionsSection(),
                        const SizedBox(height: 40),
                        _MenuSelectionDropdown(
                          restaurantId: widget.restaurantId,
                          initialSelectedMenus: _targetMenuIds,
                          onChanged: (selectedIds) {
                            setState(() {
                              _targetMenuIds = selectedIds;
                            });
                          },
                        ),
                        const SizedBox(height: 16),
                        _isLoading
                            ? const Center(child: CircularProgressIndicator())
                            : ElevatedButton.icon(
                          onPressed: _performSave,
                          icon: const Icon(Icons.save_outlined),
                          label: Text(
                              'Save to ${_targetMenuIds.length} Menu(s)'),
                          style: ElevatedButton.styleFrom(
                            padding:
                            const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeSelector() {
    bool hasIngredients = _baseRecipe.isNotEmpty || _optionGroups.isNotEmpty;
    return _buildCleanContainer(
      context: context,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ChoiceChip(
            label: const Text('Veg'),
            selected: _itemType == 'veg',
            onSelected: (selected) {
              if (selected) {
                setState(() {
                  _itemType = 'veg';
                  _isTypeLocked = true;
                });
              }
            },
            selectedColor: Colors.green,
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text('Non-Veg'),
            selected: _itemType == 'non-veg',
            onSelected: (selected) {
              if (selected) {
                setState(() {
                  _itemType = 'non-veg';
                  _isTypeLocked = true;
                });
              }
            },
            selectedColor: Colors.red,
          ),
          const Spacer(),
          IconButton(
            icon: Icon(
                _isTypeLocked ? Icons.lock_outline : Icons.lock_open_outlined),
            tooltip: _isTypeLocked
                ? 'Unlock to auto-detect from ingredients'
                : 'Auto-detecting type',
            color: _isTypeLocked ? Theme.of(context).primaryColor : null,
            onPressed: !hasIngredients
                ? null
                : () {
              setState(() {
                _isTypeLocked = !_isTypeLocked;
                if (!_isTypeLocked) {
                  _determineAndSetItemType();
                }
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryAutocompleteField() {
    return FutureBuilder<List<String>>(
      future: _categorySuggestionsFuture,
      builder: (context, snapshot) {
        final suggestions = snapshot.data ?? [];
        return _buildCleanContainer(
          context: context,
          child: Autocomplete<String>(
            optionsBuilder: (TextEditingValue textEditingValue) {
              if (textEditingValue.text == '') return const Iterable<String>.empty();
              return suggestions.where((String option) => option
                  .toLowerCase()
                  .contains(textEditingValue.text.toLowerCase()));
            },
            // Handles selection from suggestions
            onSelected: (String selection) =>
            _categoryController.text = selection,

            fieldViewBuilder:
                (context, controller, focusNode, onFieldSubmitted) {

              return TextFormField(
                // Use the controller supplied by Autocomplete
                controller: controller,
                focusNode: focusNode,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  prefixIcon: Icon(Icons.category_outlined, size: 22),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.fromLTRB(0, 18, 16, 18),
                ),
                validator: (val) =>
                val!.trim().isEmpty ? 'Please enter a category' : null,
                style: Theme.of(context).textTheme.bodyLarge,

                // FIX: Explicitly update the main state controller on every change (typing new text)
                onChanged: (text) {
                  _categoryController.text = text;
                },

                onFieldSubmitted: (text) {
                  _categoryController.text = text;
                  onFieldSubmitted();
                },
              );
            },
            // The initial value is correctly passed here to Autocomplete
            initialValue: TextEditingValue(text: _categoryController.text),
          ),
        );
      },
    );
  }

  Widget _buildTextField(
      {required TextEditingController controller,
        required String label,
        required IconData icon,
        TextInputType? keyboardType}) {
    return _buildCleanContainer(
      context: context,
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          fillColor: Colors.transparent,
          labelText: label,
          prefixIcon: Icon(icon, size: 22),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.fromLTRB(0, 18, 16, 18),
        ),
        keyboardType: keyboardType,
        validator: (val) {
          if (!label.contains('(Optional)') && (val == null || val.isEmpty)) {
            return 'This field cannot be empty';
          }
          return null;
        },
        style: Theme.of(context).textTheme.bodyLarge,
      ),
    );
  }

  Widget _buildIngredientsSection() {
    final theme = Theme.of(context);
    return _buildCleanContainer(
      context: context,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading:
            Icon(Icons.inventory_2_outlined, color: theme.primaryColor),
            title: Text("Ingredients", style: theme.textTheme.titleMedium),
            contentPadding: EdgeInsets.zero,
          ),
          ..._baseRecipe.map((item) => ListTile(
            title: Text(item.name),
            trailing: Text(
                '${item.quantityUsed.toStringAsFixed(2)} ${item.unit}'),
          )),
          const SizedBox(height: 10),
          Center(
            child: OutlinedButton.icon(
              onPressed: _manageBaseRecipe,
              icon: const Icon(Icons.edit_note),
              label: const Text('Edit Ingredients'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionsSection() {
    final theme = Theme.of(context);
    return _buildCleanContainer(
      context: context,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: Icon(Icons.add_shopping_cart_outlined,
                color: theme.primaryColor),
            title: Text("Customizable Options",
                style: theme.textTheme.titleMedium),
            subtitle: Text("e.g., Sauces, Toppings, or Combo Meals",
                style: theme.textTheme.bodySmall),
            contentPadding: EdgeInsets.zero,
          ),
          ..._optionGroups.map((group) => ListTile(
            title: Text(group.name),
            subtitle: Text('${group.options.length} options'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => _manageOptionGroup(existingGroup: group),
          )),
          const SizedBox(height: 10),
          Center(
            child: OutlinedButton.icon(
              onPressed: () => _manageOptionGroup(),
              icon: const Icon(Icons.add),
              label: const Text('Add Option Group'),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuSelectionDropdown extends StatefulWidget {
  final String restaurantId;
  final Set<String> initialSelectedMenus;
  final ValueChanged<Set<String>> onChanged;

  const _MenuSelectionDropdown({
    required this.restaurantId,
    required this.initialSelectedMenus,
    required this.onChanged,
  });

  @override
  _MenuSelectionDropdownState createState() => _MenuSelectionDropdownState();
}

class _MenuSelectionDropdownState extends State<_MenuSelectionDropdown> {
  String _displayText = 'Loading...';
  Map<String, String> _allMenus = {};

  @override
  void initState() {
    super.initState();
    _fetchMenus();
  }

  Future<void> _fetchMenus() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('restaurants')
        .doc(widget.restaurantId)
        .collection('menus')
        .get();
    if (mounted) {
      setState(() {
        _allMenus = {for (var doc in snapshot.docs) doc.id: doc['name']};
        _updateDisplayText();
      });
    }
  }

  void _updateDisplayText() {
    if (widget.initialSelectedMenus.length == _allMenus.length) {
      _displayText = 'All Menus';
    } else if (widget.initialSelectedMenus.length == 1) {
      _displayText = _allMenus[widget.initialSelectedMenus.first] ?? '1 Menu';
    } else {
      _displayText = '${widget.initialSelectedMenus.length} Menus Selected';
    }
  }

  void _showSelectionDialog() async {
    final Set<String>? result = await showDialog<Set<String>>(
      context: context,
      builder: (context) => _SelectMenusDialog(
        allMenus: _allMenus,
        currentMenuId: widget.initialSelectedMenus.first,
        initiallySelected: widget.initialSelectedMenus,
      ),
    );
    if (result != null) {
      widget.onChanged(result);
      setState(_updateDisplayText);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _buildCleanContainer(
      context: context,
      child: ListTile(
        leading: const Icon(Icons.menu_book_outlined),
        title: const Text('Save To'),
        trailing: TextButton.icon(
          icon: const Icon(Icons.arrow_drop_down),
          label: Text(_displayText),
          onPressed: _showSelectionDialog,
        ),
      ),
    );
  }
}

class _SelectMenusDialog extends StatefulWidget {
  final Map<String, String> allMenus;
  final String currentMenuId;
  final Set<String> initiallySelected;

  const _SelectMenusDialog({
    required this.allMenus,
    required this.currentMenuId,
    required this.initiallySelected,
  });

  @override
  State<_SelectMenusDialog> createState() => _SelectMenusDialogState();
}

class _SelectMenusDialogState extends State<_SelectMenusDialog> {
  late Set<String> _selectedMenuIds;

  @override
  void initState() {
    super.initState();
    _selectedMenuIds = Set.from(widget.initiallySelected);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select Menus to Save In'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: widget.allMenus.entries.map((entry) {
            final menuId = entry.key;
            final menuName = entry.value;
            final isCurrentMenu = menuId == widget.currentMenuId;

            return CheckboxListTile(
              title: Text(menuName),
              subtitle: isCurrentMenu ? const Text('(Current Menu)') : null,
              value: _selectedMenuIds.contains(menuId),
              onChanged: isCurrentMenu
                  ? null
                  : (bool? value) {
                setState(() {
                  if (value == true) {
                    _selectedMenuIds.add(menuId);
                  } else {
                    _selectedMenuIds.remove(menuId);
                  }
                });
              },
            );
          }).toList(),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(_selectedMenuIds),
          child: const Text('Confirm'),
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