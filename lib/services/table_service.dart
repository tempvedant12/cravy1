// lib/services/table_service.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cravy/screen/restaurant/tables_and_reservations/tables_and_reservations_screen.dart';

import '../screen/restaurant/orders/assign_table_screen.dart'; // For TableModel, FloorModel

/// A reusable function to shift an entire session (all its orders) to a new table.
/// This handles updating all orders, the old table, and the new table.
Future<void> shiftTableSession(
    BuildContext context,
    String restaurantId,
    List<DocumentSnapshot> sessionOrders,
    ) async {
  if (sessionOrders.isEmpty) return;

  // --- FIX: Capture ScaffoldMessenger BEFORE the await ---
  // This ensures we can show a SnackBar even if the original card's context is unmounted.
  final messenger = ScaffoldMessenger.of(context);
  // -----------------------------------------------------

  // 1. Get current assignment info from the first order
  final firstOrderData = sessionOrders.first.data() as Map<String, dynamic>;
  final oldSessionKey = firstOrderData['sessionKey'] as String? ?? 'Unknown';
  final currentAssignmentMap =
      firstOrderData['assignment'] as Map<String, dynamic>? ?? {};

  // Convert from Map<String, dynamic(List)> to Map<String, Set<int>>
  final Map<String, Set<int>> currentSelections = {};
  currentAssignmentMap.forEach((key, value) {
    currentSelections[key] = Set<int>.from(value as List);
  });

  // Check if this is a table-based order
  if (currentSelections.isEmpty) {
    messenger.showSnackBar( // Use captured messenger
      const SnackBar(
          content: Text('This order type (e.g., Takeaway) cannot be shifted.')),
    );
    return;
  }

  // 2. Show the full AssignTableScreen to pick a new assignment
  // The context is still valid here for navigation.
  final newAssignment = await Navigator.of(context).push<OrderAssignment>(
    MaterialPageRoute(
      builder: (_) => AssignTableScreen(
        restaurantId: restaurantId,
        initialSelections: currentSelections, // <-- This is the key!
      ),
    ),
  );

  // 3. If a new assignment was returned, perform the batch update
  // --- FIX: Remove the context.mounted check from the logic block ---
  if (newAssignment != null && newAssignment.selections.isNotEmpty) {
    try {
      final newSessionKey = newAssignment.toDisplayString();

      // 4. Update table statuses
      // We need to free the OLD tables first
      await updateTableSessionStatus(
          restaurantId,
          currentSelections, // Pass the old assignment map
          oldSessionKey, // Pass the old session key
          closeSession: true, // This tells the function to free the tables
          oldSessionKey: oldSessionKey
      );

      // Then occupy the NEW tables
      await updateTableSessionStatus(
        restaurantId,
        newAssignment.selections, // Pass the new assignment map
        newSessionKey, // Pass the new session key
        closeSession: false, // This tells the function to occupy the tables
      );

      // 5. Update all orders in the session
      final batch = FirebaseFirestore.instance.batch();
      for (var orderDoc in sessionOrders) {
        batch.update(orderDoc.reference, {
          'tableIds': newAssignment.selections.keys.toList(),
          'assignment': newAssignment.selections
              .map((key, value) => MapEntry(key, value.toList())),
          'assignmentLabel': newSessionKey, // The display string is the label
          'sessionKey': newSessionKey, // Update session key
        });
      }
      await batch.commit();

      // --- FIX: Use the captured messenger ---
      messenger.showSnackBar(
          const SnackBar(content: Text('Table assignment updated successfully!')));
    } catch (e) {
      // --- FIX: Use the captured messenger ---
      messenger.showSnackBar(
          SnackBar(content: Text('Error updating assignment: ${e.toString()}')));
    }
  }
  // -----------------------------------------------------------------
}

/// A reusable dialog that shows all floors and tables,
/// allowing selection of a new, available table.
class SelectTableDialog extends StatefulWidget {
  final String restaurantId;
  final String currentTableId;

  const SelectTableDialog({
    super.key,
    required this.restaurantId,
    required this.currentTableId,
  });

  @override
  State<SelectTableDialog> createState() => _SelectTableDialogState();
}

class _SelectTableDialogState extends State<SelectTableDialog>
    with SingleTickerProviderStateMixin {
  TabController? _tabController;
  List<FloorModel> _floors = [];

  @override
  void initState() {
    super.initState();
    _fetchFloorsAndInitialize();
  }

  Future<void> _fetchFloorsAndInitialize() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('restaurants')
        .doc(widget.restaurantId)
        .collection('floors')
        .orderBy('order')
        .get();

    if (mounted) {
      setState(() {
        _floors =
            snapshot.docs.map((doc) => FloorModel.fromFirestore(doc)).toList();
        _tabController = TabController(length: _floors.length, vsync: this);
      });
    }
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select a New Table'),
      content: _floors.isEmpty || _tabController == null
          ? const Center(child: CircularProgressIndicator())
          : SizedBox(
        width: double.maxFinite,
        height: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TabBar(
              controller: _tabController,
              isScrollable: true,
              tabs: _floors.map((floor) => Tab(text: floor.name)).toList(),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: _floors.map((floor) {
                  return _TableListForFloor(
                    restaurantId: widget.restaurantId,
                    floorId: floor.id,
                    currentTableId: widget.currentTableId,
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _TableListForFloor extends StatelessWidget {
  final String restaurantId;
  final String floorId;
  final String currentTableId;

  const _TableListForFloor({
    required this.restaurantId,
    required this.floorId,
    required this.currentTableId,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('restaurants')
          .doc(restaurantId)
          .collection('tables')
          .where('floorId', isEqualTo: floorId)
          .orderBy('label')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final tables =
        snapshot.data!.docs.map((doc) => TableModel.fromFirestore(doc)).toList();

        if (tables.isEmpty) return const Text('No available tables to shift to.');

        return ListView.builder(
          shrinkWrap: true,
          itemCount: tables.length,
          itemBuilder: (context, index) {
            final table = tables[index];
            final isCurrent = table.id == currentTableId;
            final isOccupied =
                table.activeSessionKey != null && !isCurrent;

            return ListTile(
              title: Text(table.label),
              trailing: isCurrent
                  ? const Text('(Current)')
                  : isOccupied
                  ? const Text('(Occupied)')
                  : null,
              enabled: !isCurrent && !isOccupied,
              onTap: () => Navigator.of(context).pop(table),
            );
          },
        );
      },
    );
  }
}