

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cravy/screen/restaurant/inventory/inventory_screen.dart'
as inventory;
import 'package:cravy/screen/restaurant/menu/menu_screen.dart';
import 'package:cravy/services/unit_converter_service.dart';

class ManageOptionGroupScreen extends StatefulWidget {
  final String restaurantId;
  final OptionGroup? initialGroup;

  const ManageOptionGroupScreen({
    super.key,
    required this.restaurantId,
    this.initialGroup,
  });

  @override
  State<ManageOptionGroupScreen> createState() =>
      _ManageOptionGroupScreenState();
}

class _ManageOptionGroupScreenState extends State<ManageOptionGroupScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _groupNameController;
  late bool _isMultiSelect;
  late bool _isRequired;
  late List<OptionItem> _options;

  @override
  void initState() {
    super.initState();
    _groupNameController =
        TextEditingController(text: widget.initialGroup?.name ?? '');
    _isMultiSelect = widget.initialGroup?.isMultiSelect ?? false;
    _isRequired = widget.initialGroup?.isRequired ?? false;
    _options = List<OptionItem>.from(widget.initialGroup?.options ?? []);
  }

  void _addOrEditOption({OptionItem? existingOption}) async {
    final result = await showDialog<OptionItem>(
      context: context,
      builder: (context) => _AddEditOptionDialog(
        restaurantId: widget.restaurantId,
        optionItem: existingOption,
      ),
    );

    if (result != null) {
      setState(() {
        if (existingOption != null) {
          final index = _options.indexOf(existingOption);
          _options[index] = result;
        } else {
          _options.add(result);
        }
      });
    }
  }

  void _saveGroup() {
    if (_formKey.currentState!.validate()) {
      final newGroup = OptionGroup(
        name: _groupNameController.text.trim(),
        isMultiSelect: _isMultiSelect,
        isRequired: _isRequired,
        options: _options,
      );
      Navigator.of(context).pop(newGroup);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initialGroup == null ? 'Add Group' : 'Edit Group'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: _saveGroup,
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _groupNameController,
              decoration: const InputDecoration(labelText: 'Group Name (e.g., Toppings)'),
              validator: (val) =>
              val!.isEmpty ? 'Please enter a name' : null,
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Allow multiple selections?'),
              subtitle: const Text('e.g., for toppings'),
              value: _isMultiSelect,
              onChanged: (val) => setState(() => _isMultiSelect = val),
            ),
            SwitchListTile(
              title: const Text('Is this choice required?'),
              subtitle: const Text('e.g., for pizza crust type'),
              value: _isRequired,
              onChanged: (val) => setState(() => _isRequired = val),
            ),
            const Divider(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Options', style: Theme.of(context).textTheme.titleLarge),
                OutlinedButton.icon(
                  onPressed: () => _addOrEditOption(),
                  icon: const Icon(Icons.add),
                  label: const Text('Add Option'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_options.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text('No options added yet.'),
                ),
              ),
            ..._options.map((option) => Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                title: Text(option.name),
                subtitle: Text(
                    'Uses ${option.recipeLink.quantityUsed.toStringAsFixed(2)} ${option.recipeLink.unit} of ${option.recipeLink.name}'),
                trailing: Text('+ ₹${option.additionalPrice.toStringAsFixed(2)}'),
                onTap: () => _addOrEditOption(existingOption: option),
              ),
            )),
          ],
        ),
      ),
    );
  }
}


class _AddEditOptionDialog extends StatefulWidget {
  final String restaurantId;
  final OptionItem? optionItem;

  const _AddEditOptionDialog({required this.restaurantId, this.optionItem});

  @override
  State<_AddEditOptionDialog> createState() => _AddEditOptionDialogState();
}

class _AddEditOptionDialogState extends State<_AddEditOptionDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _priceController;
  RecipeItem? _selectedRecipeLink;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.optionItem?.name ?? '');
    _priceController = TextEditingController(
        text: widget.optionItem?.additionalPrice.toString() ?? '0.0');
    _selectedRecipeLink = widget.optionItem?.recipeLink;
  }

  void _selectIngredient() async {
    final inventory.InventoryItem? selectedItem = await showDialog(
      context: context,
      builder: (context) =>
          SelectInventoryItemDialog(restaurantId: widget.restaurantId),
    );

    if (selectedItem != null && mounted) {
      final double? quantity = await showDialog(
        context: context,
        builder: (context) =>
            EnterQuantityDialog(item: selectedItem),
      );

      if (quantity != null && quantity > 0) {
        setState(() {
          _selectedRecipeLink = RecipeItem(
            inventoryItemId: selectedItem.id,
            name: selectedItem.name,
            quantityUsed: quantity,
            unit: selectedItem.unit,
          );
          if (_nameController.text.isEmpty) {
            _nameController.text = selectedItem.name;
          }
        });
      }
    }
  }

  void _saveOption() {
    if (_formKey.currentState!.validate()) {
      if (_selectedRecipeLink == null) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please link an inventory item.')));
        return;
      }
      final newOption = OptionItem(
        name: _nameController.text.trim(),
        additionalPrice: double.tryParse(_priceController.text) ?? 0.0,
        recipeLink: _selectedRecipeLink!,
      );
      Navigator.of(context).pop(newOption);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.optionItem == null ? 'Add Option' : 'Edit Option'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Option Name (e.g., Extra Cheese)'),
              validator: (val) =>
              val!.isEmpty ? 'Please enter a name' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _priceController,
              decoration: const InputDecoration(labelText: 'Additional Price'),
              keyboardType: TextInputType.number,
              validator: (val) =>
              val!.isEmpty || double.tryParse(val) == null
                  ? 'Enter a valid price'
                  : null,
            ),
            const SizedBox(height: 16),
            ListTile(
              title: const Text('Linked Inventory Item'),
              subtitle: Text(_selectedRecipeLink?.name ?? 'Not selected'),
              trailing: const Icon(Icons.edit),
              onTap: _selectIngredient,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ElevatedButton(onPressed: _saveOption, child: const Text('Save')),
      ],
    );
  }
}



class SelectInventoryItemDialog extends StatelessWidget {
  final String restaurantId;
  const SelectInventoryItemDialog({super.key, required this.restaurantId});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select Ingredient'),
      content: SizedBox(
        width: double.maxFinite,
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('restaurants')
              .doc(restaurantId)
              .collection('inventory')
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            final items = snapshot.data!.docs
                .map((doc) => inventory.InventoryItem.fromFirestore(doc))
                .toList();
            return ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, index) {
                return ListTile(
                  title: Text(items[index].name),
                  onTap: () => Navigator.of(context).pop(items[index]),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class EnterQuantityDialog extends StatefulWidget {
  final inventory.InventoryItem item;
  const EnterQuantityDialog({super.key, required this.item});

  @override
  State<EnterQuantityDialog> createState() => _EnterQuantityDialogState();
}

class _EnterQuantityDialogState extends State<EnterQuantityDialog> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  late List<String> _compatibleUnits;
  late String _selectedUnit;

  @override
  void initState() {
    super.initState();
    _compatibleUnits =
        UnitConverterService.getCompatibleUnits(widget.item.unit);
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
          children: [
            Expanded(
              flex: 2,
              child: TextFormField(
                controller: _controller,
                keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Quantity Used'),
                validator: (val) => (val == null ||
                    double.tryParse(val) == null ||
                    double.parse(val) <= 0)
                    ? 'Invalid'
                    : null,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 1,
              child: DropdownButtonFormField<String>(
                value: _selectedUnit,
                items: _compatibleUnits.map((String unit) {
                  return DropdownMenuItem<String>(
                    value: unit,
                    child: Text(unit),
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
                final conversionFactor =
                UnitConverterService.convertToBase(1.0, widget.item.unit);
                Navigator.of(context).pop(baseQuantity / conversionFactor);
              }
            },
            child: const Text('Add')),
      ],
    );
  }
}