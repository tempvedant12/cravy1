// lib/services/inventory_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class InventoryService {
  final String restaurantId;
  final FirebaseFirestore _firestore;

  InventoryService({required this.restaurantId})
      : _firestore = FirebaseFirestore.instance;

  /// Deducts the ingredients used in an order from the inventory.
  ///
  /// This function now relies on the orderedItems list having embedded
  /// recipe information (baseRecipe and selectedOptions maps) to calculate
  /// deductions directly, bypassing the need to query the menu items again.
  Future<void> updateInventoryForOrder(List<Map<String, dynamic>> orderedItems) async {
    final inventoryRef = _firestore
        .collection('restaurants')
        .doc(restaurantId)
        .collection('inventory');

    // **REMOVED: Menu item fetch logic is no longer needed.**

    // Use a transaction to ensure atomic updates
    await _firestore.runTransaction((transaction) async {
      final Map<String, double> deductions = {};

      // Calculate total deductions for each inventory item
      for (final orderedItem in orderedItems) {
        final orderQuantity = (orderedItem['quantity'] as num?)?.toDouble() ?? 0.0;
        if (orderQuantity <= 0) continue;

        // 1. Deduct for base recipe
        final baseRecipe = List<Map<String, dynamic>>.from(orderedItem['baseRecipe'] ?? []);
        for (final recipeItemMap in baseRecipe) {
          final inventoryId = recipeItemMap['inventoryItemId'] as String?;
          final quantityUsed = (recipeItemMap['quantityUsed'] as num?)?.toDouble() ?? 0.0;

          if (inventoryId != null && inventoryId.isNotEmpty && quantityUsed > 0) {
            final quantityToDeduct = quantityUsed * orderQuantity;
            deductions.update(
              inventoryId,
                  (value) => value + quantityToDeduct,
              ifAbsent: () => quantityToDeduct,
            );
          }
        }

        // 2. Deduct for selected options (which include inventory link data)
        final selectedOptions = (orderedItem['selectedOptions'] as List<dynamic>? ?? []);
        for (final optionMap in selectedOptions) {
          final inventoryId = optionMap['inventoryItemId'] as String?;
          final quantityUsed = (optionMap['quantityUsed'] as num?)?.toDouble() ?? 0.0;

          if (inventoryId != null && inventoryId.isNotEmpty && quantityUsed > 0) {
            final quantityToDeduct = quantityUsed * orderQuantity;
            deductions.update(inventoryId, (value) => value + quantityToDeduct, ifAbsent: () => quantityToDeduct);
          }
        }
      }

      // Fetch all required inventory items in one go
      if (deductions.isNotEmpty) {
        final keys = deductions.keys.where((k) => k.isNotEmpty).toList();
        if (keys.isNotEmpty) {
          final inventoryQuery = await inventoryRef
              .where(FieldPath.documentId, whereIn: keys)
              .get();

          for (final doc in inventoryQuery.docs) {
            final currentQuantity = (doc.data()['quantity'] as num).toDouble();
            final deduction = deductions[doc.id] ?? 0.0;

            // Safety check: ensure inventory doesn't go below zero
            if (currentQuantity - deduction < 0) {
              throw Exception('Insufficient inventory for item ${doc.data()['name']}');
            }

            transaction.update(
                doc.reference, {'quantity': currentQuantity - deduction});
          }
        }
      }
    });
  }
}