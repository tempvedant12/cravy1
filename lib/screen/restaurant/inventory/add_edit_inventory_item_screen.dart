import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cravy/screen/restaurant/inventory/inventory_screen.dart';
import 'package:cravy/services/unit_converter_service.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'dart:ui';

class AddEditInventoryItemScreen extends StatefulWidget {
  final String restaurantId;
  final InventoryItem? item;

  const AddEditInventoryItemScreen({
    super.key,
    required this.restaurantId,
    this.item,
  });

  @override
  State<AddEditInventoryItemScreen> createState() =>
      _AddEditInventoryItemScreenState();
}

class _AddEditInventoryItemScreenState
    extends State<AddEditInventoryItemScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  late TextEditingController _nameController;
  late TextEditingController _categoryController;
  late TextEditingController _quantityController;
  late String _selectedUnit;
  late TextEditingController _lowStockThresholdController;
  late String _selectedType;

  late Future<List<String>> _categorySuggestionsFuture;
  final List<String> _allUnits = UnitConverterService.getAllUnits();

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.item?.name ?? '');
    _categoryController =
        TextEditingController(text: widget.item?.category ?? '');
    _quantityController =
        TextEditingController(text: widget.item?.quantity.toString() ?? '0.0');
    _selectedUnit = widget.item?.unit ?? 'kg';
    _lowStockThresholdController = TextEditingController(
        text: widget.item?.lowStockThreshold.toString() ?? '0.0');
    _selectedType = widget.item?.type ?? 'none';

    _categorySuggestionsFuture = _fetchCategorySuggestions();
  }

  Future<List<String>> _fetchCategorySuggestions() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('restaurants')
        .doc(widget.restaurantId)
        .collection('inventory')
        .get();

    if (snapshot.docs.isEmpty) {
      return [];
    }
    final categories =
    snapshot.docs.map((doc) => doc.data()['category'] as String).toSet();
    return categories.toList();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _categoryController.dispose();
    _quantityController.dispose();
    _lowStockThresholdController.dispose();
    super.dispose();
  }

  Future<void> _saveItem() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);
      try {
        final collection = FirebaseFirestore.instance
            .collection('restaurants')
            .doc(widget.restaurantId)
            .collection('inventory');

        final itemData = {
          'name': _nameController.text.trim(),
          'category': _categoryController.text.trim(),
          'quantity': double.tryParse(_quantityController.text) ?? 0.0,
          'unit': _selectedUnit,
          'lowStockThreshold':
          double.tryParse(_lowStockThresholdController.text) ?? 0.0,
          'lastUpdated': FieldValue.serverTimestamp(),
          'type': _selectedType,
        };

        if (widget.item == null) {
          await collection.add(itemData);
        } else {
          await collection.doc(widget.item!.id).update(itemData);
        }

        if (mounted) Navigator.of(context).pop();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error saving item: ${e.toString()}')),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _deleteItem() async {
    if (widget.item == null) return;

    final bool? confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Item?'),
        content:
        const Text('Are you sure you want to delete this inventory item?'),
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
      setState(() => _isLoading = true);
      try {
        await FirebaseFirestore.instance
            .collection('restaurants')
            .doc(widget.restaurantId)
            .collection('inventory')
            .doc(widget.item!.id)
            .delete();
        if (mounted) Navigator.of(context).pop();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting item: ${e.toString()}')),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.item != null;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Item' : 'Add Item'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (isEditing)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _deleteItem,
            ),
        ],
      ),
      body: Stack(
        children: [
          const _StaticBackground(),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: AnimationLimiter(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24.0),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: AnimationConfiguration.toStaggeredList(
                          duration: const Duration(milliseconds: 375),
                          childAnimationBuilder: (widget) => SlideAnimation(
                            verticalOffset: 50.0,
                            child: FadeInAnimation(child: widget),
                          ),
                          children: [
                            _FormHeader(
                              title: isEditing
                                  ? 'Edit Inventory Item'
                                  : 'Add New Item to Inventory',
                              subtitle:
                              'Fill in the details below to update your stock.',
                            ),
                            const SizedBox(height: 40),
                            _buildTextField(
                              controller: _nameController,
                              label: 'Item Name',
                              icon: Icons.label_outline,
                              validator: (val) => val!.trim().isEmpty
                                  ? 'Please enter a name'
                                  : null,
                            ),
                            const SizedBox(height: 20),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: _buildCategoryAutocompleteField(),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  flex: 2,
                                  child: _buildTypeDropdown(),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: _buildTextField(
                                    controller: _quantityController,
                                    label: 'Quantity',
                                    icon: Icons.format_list_numbered,
                                    keyboardType: TextInputType.number,
                                    validator: (val) =>
                                    double.tryParse(val!) == null
                                        ? 'Enter a valid number'
                                        : null,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  flex: 2,
                                  child: _buildUnitDropdown(),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            _buildTextField(
                              controller: _lowStockThresholdController,
                              label: 'Low Stock Threshold',
                              icon: Icons.warning_amber_rounded,
                              keyboardType: TextInputType.number,
                              validator: (val) =>
                              double.tryParse(val!) == null
                                  ? 'Enter a valid number'
                                  : null,
                            ),
                            const SizedBox(height: 40),
                            _isLoading
                                ? const Center(
                                child: CircularProgressIndicator())
                                : ElevatedButton.icon(
                              icon: const Icon(Icons.save_outlined),
                              onPressed: _saveItem,
                              label: Text(isEditing
                                  ? 'Save Changes'
                                  : 'Add Item'),
                            ),
                          ],
                        ),
                      ),
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

  Widget _buildUnitDropdown() {
    return DropdownButtonFormField<String>(
      value: _selectedUnit,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Unit',
        prefixIcon: Icon(Icons.straighten_outlined, size: 22),
      ),
      items: _allUnits.map((String unit) {
        return DropdownMenuItem<String>(
          value: unit,
          child: Text(unit, overflow: TextOverflow.ellipsis),
        );
      }).toList(),
      onChanged: (String? newValue) {
        if (newValue != null) {
          setState(() {
            _selectedUnit = newValue;
          });
        }
      },
      validator: (value) => value == null ? 'Please select a unit' : null,
    );
  }

  Widget _buildTypeDropdown() {
    return DropdownButtonFormField<String>(
      value: _selectedType,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Type',
        prefixIcon: Icon(Icons.fastfood_outlined, size: 22),
      ),
      items: ['none', 'veg', 'non-veg'].map((String type) {
        return DropdownMenuItem<String>(
          value: type,
          child: Text(type[0].toUpperCase() + type.substring(1),
              overflow: TextOverflow.ellipsis),
        );
      }).toList(),
      onChanged: (String? newValue) {
        if (newValue != null) {
          setState(() {
            _selectedType = newValue;
          });
        }
      },
      validator: (value) => value == null ? 'Please select a type' : null,
    );
  }

  Widget _buildCategoryAutocompleteField() {
    return FutureBuilder<List<String>>(
      future: _categorySuggestionsFuture,
      builder: (context, snapshot) {
        final suggestions = snapshot.data ?? [];
        return Autocomplete<String>(
          optionsBuilder: (TextEditingValue textEditingValue) {
            if (textEditingValue.text.isEmpty) {
              return const Iterable<String>.empty();
            }
            return suggestions.where((String option) {
              return option
                  .toLowerCase()
                  .contains(textEditingValue.text.toLowerCase());
            });
          },
          onSelected: (String selection) {
            _categoryController.text = selection;
          },
          fieldViewBuilder:
              (context, controller, focusNode, onFieldSubmitted) {
            if (_categoryController.text != controller.text) {
              _categoryController.text = controller.text;
            }
            return TextFormField(
              controller: controller,
              focusNode: focusNode,
              decoration: const InputDecoration(
                labelText: 'Category',
                prefixIcon: Icon(Icons.category_outlined, size: 22),
              ),
              validator: (val) =>
              val!.trim().isEmpty ? 'Please enter a category' : null,
              style: Theme.of(context).textTheme.bodyLarge,
            );
          },
          initialValue: TextEditingValue(text: _categoryController.text),
        );
      },
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    required FormFieldValidator<String> validator,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 22),
      ),
      keyboardType: keyboardType,
      validator: validator,
      style: Theme.of(context).textTheme.bodyLarge,
    );
  }
}

class _FormHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  const _FormHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Icon(
          Icons.inventory_2_outlined,
          size: 40,
          color: theme.primaryColor,
        ),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge,
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