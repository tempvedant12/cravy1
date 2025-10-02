

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cravy/screen/restaurant/tables_and_reservations/tables_and_reservations_screen.dart';
import 'package:flutter/material.dart';

class ManageFloorPlanScreen extends StatefulWidget {
  final String restaurantId;
  const ManageFloorPlanScreen({super.key, required this.restaurantId});

  @override
  State<ManageFloorPlanScreen> createState() => _ManageFloorPlanScreenState();
}

class _ManageFloorPlanScreenState extends State<ManageFloorPlanScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Floor Plan'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('restaurants')
            .doc(widget.restaurantId)
            .collection('floors')
            .orderBy('order')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          }
          final floors = snapshot.data?.docs
              .map((doc) => FloorModel.fromFirestore(doc))
              .toList() ??
              [];

          if (floors.isEmpty) {
            return _buildEmptyState(context, floors);
          }

          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 80), 
            itemCount: floors.length,
            itemBuilder: (context, index) {
              final floor = floors[index];
              return Card(
                margin: const EdgeInsets.all(16).copyWith(bottom: 0),
                child: ExpansionTile(
                  title: Text(floor.name, style: Theme.of(context).textTheme.titleLarge),
                  trailing: IconButton(
                    icon: const Icon(Icons.edit_note),
                    onPressed: () => _manageFloor(context, floors, existingFloor: floor),
                  ),
                  initiallyExpanded: true,
                  children: [
                    _buildTableListForFloor(floor, floors),
                  ],
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          _manageFloor(context, []); 
        },
        icon: const Icon(Icons.add),
        label: const Text('Add Floor'),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, List<FloorModel> floors) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.layers_clear, size: 80, color: Theme.of(context).dividerColor),
          const SizedBox(height: 24),
          Text('No Floors Created', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 12),
          Text(
            'Tap the button below to add your first floor.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }


  Widget _buildTableListForFloor(FloorModel floor, List<FloorModel> allFloors) {
    return StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('restaurants')
            .doc(widget.restaurantId)
            .collection('tables')
            .where('floorId', isEqualTo: floor.id)
            .orderBy('label')
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const LinearProgressIndicator();

          final tables = snapshot.data!.docs.map((doc) => TableModel.fromFirestore(doc)).toList();

          return Column(
            children: [
              ...tables.map((table) => ListTile(
                title: Text(table.label),
                subtitle: Text('${table.capacity} seats'),
                trailing: IconButton(
                  icon: const Icon(Icons.edit, size: 20),
                  onPressed: () => _addOrEditTable(context, table, floor),
                ),
              )),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Add Table'),
                  onPressed: () => _addOrEditTable(context, null, floor),
                ),
              ),
            ],
          );
        });
  }

  Future<void> _manageFloor(BuildContext context, List<FloorModel> floors, {FloorModel? existingFloor}) async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => _AddEditFloorDialog(floor: existingFloor),
    );

    if (result == null) return;

    final action = result['action'];
    final name = result['name'];

    final collection = FirebaseFirestore.instance.collection('restaurants').doc(widget.restaurantId).collection('floors');

    if (action == 'save' && name != null && name.isNotEmpty) {
      if (existingFloor == null) {
        await collection.add({'name': name, 'order': floors.length});
      } else {
        await collection.doc(existingFloor.id).update({'name': name});
      }
    } else if (action == 'delete' && existingFloor != null) {
      _deleteFloor(existingFloor);
    }
  }

  Future<void> _deleteFloor(FloorModel floor) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Delete "${floor.name}"?'),
        content: const Text('This will also delete all tables on this floor. This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Delete', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final restaurantRef = FirebaseFirestore.instance.collection('restaurants').doc(widget.restaurantId);
      final tablesQuery = await restaurantRef.collection('tables').where('floorId', isEqualTo: floor.id).get();

      WriteBatch batch = FirebaseFirestore.instance.batch();

      for (var doc in tablesQuery.docs) {
        batch.delete(doc.reference);
      }

      batch.delete(restaurantRef.collection('floors').doc(floor.id));

      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"${floor.name}" and all its tables were deleted.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting floor: $e')),
        );
      }
    }
  }

  void _addOrEditTable(BuildContext context, TableModel? table, FloorModel currentFloor) async {
    final result = await showDialog<TableModel>(
      context: context,
      builder: (_) => _AddEditTableDialog(
        table: table,
        floorId: currentFloor.id,
      ),
    );

    if (result != null) {
      final collection = FirebaseFirestore.instance.collection('restaurants').doc(widget.restaurantId).collection('tables');
      if (table == null) {
        await collection.add(result.toMap());
      } else {
        await collection.doc(table.id).update(result.toMap());
      }
    }
  }
}




class _AddEditFloorDialog extends StatefulWidget {
  final FloorModel? floor;
  const _AddEditFloorDialog({this.floor});

  @override
  State<_AddEditFloorDialog> createState() => _AddEditFloorDialogState();
}

class _AddEditFloorDialogState extends State<_AddEditFloorDialog> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.floor != null) {
      _controller.text = widget.floor!.name;
    }
  }
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.floor == null ? 'Add Floor' : 'Manage Floor'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'e.g., Rooftop Terrace'),
      ),
      actions: [
        if (widget.floor != null)
          TextButton(
            onPressed: () => Navigator.of(context).pop({'action': 'delete'}),
            child: Text('Delete Floor', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        const Spacer(),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ElevatedButton(
            onPressed: () => Navigator.of(context).pop({'action': 'save', 'name': _controller.text.trim()}),
            child: const Text('Save')),
      ],
    );
  }
}

class _AddEditTableDialog extends StatefulWidget {
  final TableModel? table;
  final String floorId;

  const _AddEditTableDialog({this.table, required this.floorId});

  @override
  State<_AddEditTableDialog> createState() => _AddEditTableDialogState();
}

class _AddEditTableDialogState extends State<_AddEditTableDialog> {
  final _formKey = GlobalKey<FormState>();
  late String _label;
  late int _capacity;
  late TableShape _shape;

  @override
  void initState() {
    super.initState();
    _label = widget.table?.label ?? '';
    _capacity = widget.table?.capacity ?? 4;
    _shape = widget.table?.shape ?? TableShape.square;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.table == null ? 'Add Table' : 'Edit Table'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              initialValue: _label,
              decoration: const InputDecoration(labelText: 'Table Label (e.g., T1)'),
              validator: (val) => val!.isEmpty ? 'Please enter a label' : null,
              onSaved: (val) => _label = val!,
            ),
            const SizedBox(height: 16),
            TextFormField(
              initialValue: _capacity.toString(),
              decoration: const InputDecoration(labelText: 'Number of Seats'),
              keyboardType: TextInputType.number,
              validator: (val) => int.tryParse(val!) == null || int.parse(val) <= 0 ? 'Enter a valid number' : null,
              onSaved: (val) => _capacity = int.parse(val!),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ElevatedButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();

      List<Seat> seats;
      if (widget.table != null && widget.table!.capacity == _capacity) {
        seats = widget.table!.seats;
      } else {
        seats = List.generate(
          _capacity,
              (index) => Seat(seatNumber: index + 1),
        );
      }

      final newTable = TableModel(
        id: widget.table?.id ?? '',
        label: _label,
        floorId: widget.floorId,
        seats: seats,
        shape: _shape,
      );
      Navigator.of(context).pop(newTable);
    }
  }
}