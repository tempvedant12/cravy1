// lib/models/order_models.dart

import 'package:cravy/screen/restaurant/menu/menu_screen.dart';

// Represents a single chosen option for a menu item in an order
class SelectedOption {
  final String groupName;
  final String optionName;
  final double additionalPrice;
  final String inventoryItemId; // ID of the linked inventory item
  final double quantityUsed;    // How much of it is used

  SelectedOption({
    required this.groupName,
    required this.optionName,
    required this.additionalPrice,
    required this.inventoryItemId,
    required this.quantityUsed,
  });

  Map<String, dynamic> toMap() {
    return {
      'groupName': groupName,
      'optionName': optionName,
      'additionalPrice': additionalPrice,
      'inventoryItemId': inventoryItemId,
      'quantityUsed': quantityUsed,
    };
  }

  factory SelectedOption.fromMap(Map<String, dynamic> map) {
    return SelectedOption(
      groupName: map['groupName'] ?? '',
      optionName: map['optionName'] ?? '',
      additionalPrice: (map['additionalPrice'] ?? 0.0).toDouble(),
      inventoryItemId: map['inventoryItemId'] ?? '',
      quantityUsed: (map['quantityUsed'] ?? 0.0).toDouble(),
    );
  }
}

// Represents a unique instance of a menu item in an order, including its customizations
class OrderItem {
  final MenuItem menuItem;
  int quantity;
  final List<SelectedOption> selectedOptions;
  final String menuName;
  // A unique ID to differentiate the same menu item with different options (e.g., a Coke vs. a Pepsi in two different combos)
  final String uniqueId;

  OrderItem({
    required this.menuItem,
    this.quantity = 1,
    required this.selectedOptions,
    required this.menuName,
  }) : uniqueId = _generateUniqueId(menuItem.id, selectedOptions);

  // Generates a consistent ID based on the menu item and its selected options
  static String _generateUniqueId(String menuItemId, List<SelectedOption> options) {
    if (options.isEmpty) {
      return menuItemId;
    }
    // Sort options by name to ensure the ID is the same regardless of selection order
    final sortedOptions = List<SelectedOption>.from(options)
      ..sort((a, b) => a.optionName.compareTo(b.optionName));
    final optionsId = sortedOptions.map((o) => o.optionName).join(',');
    return '$menuItemId-[$optionsId]';
  }

  // Calculates the total price for this item (base price + options) * quantity
  double get totalPrice {
    final optionsPrice = selectedOptions.fold(0.0, (sum, option) => sum + option.additionalPrice);
    return (menuItem.price + optionsPrice) * quantity;
  }

  // Calculates the price of a single unit of this item with its options
  double get singleItemPrice {
    final optionsPrice = selectedOptions.fold(0.0, (sum, option) => sum + option.additionalPrice);
    return menuItem.price + optionsPrice;
  }

  Map<String, dynamic> toMap() {
    return {
      'menuItemId': menuItem.id,
      'name': menuItem.name,
      'price': menuItem.price, // Base price
      'quantity': quantity,
      'status': 'Pending', // Default status
      'selectedOptions': selectedOptions.map((o) => o.toMap()).toList(),
    };
  }

  factory OrderItem.fromMap(Map<String, dynamic> map, List<MenuItem> allMenuItems) {
    final menuItem = allMenuItems.firstWhere((item) => item.id == map['menuItemId']);
    final options = (map['selectedOptions'] as List<dynamic>? ?? [])
        .map((opt) => SelectedOption.fromMap(opt))
        .toList();

    return OrderItem(
      menuItem: menuItem,
      quantity: map['quantity'] ?? 1,
      selectedOptions: options,
      menuName: map['menuName'] ?? '',
    );
  }
}