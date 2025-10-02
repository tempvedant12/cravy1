import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'dart:ui';

import '../tables_and_reservations/tables_and_reservations_screen.dart';

class OrderAssignment {
  final Map<String, String> tableLabels;
  final Map<String, Set<int>> selections;
  final Map<String, String> tableFloorNames;
  final Map<String, int> tableCapacities;


  OrderAssignment({
    required this.selections,
    required this.tableLabels,
    required this.tableFloorNames,
    required this.tableCapacities,
  });

  String toDisplayString() {
    if (selections.isEmpty) {
      return 'No tables or seats selected.'; 
    }
    final parts = <String>[];
    selections.forEach((tableId, seats) {
      final label = tableLabels[tableId] ?? 'Table';
      final floorName = tableFloorNames[tableId];
      final prefix = floorName != null ? '$floorName - ' : '';
      final capacity = tableCapacities[tableId] ?? 0;

      if (seats.isEmpty || (capacity > 0 && seats.length == capacity)) {
        parts.add('$prefix$label (All)');
      } else {
        final seatLabels = seats.map((s) => 'S$s').join(', ');
        parts.add('$prefix$label ($seatLabels)');
      }
    });
    return parts.join(' | ');
  }
}

class AssignTableScreen extends StatefulWidget {
  final String restaurantId;
  const AssignTableScreen({super.key, required this.restaurantId});

  @override
  State<AssignTableScreen> createState() => _AssignTableScreenState();
}

class _AssignTableScreenState extends State<AssignTableScreen> with SingleTickerProviderStateMixin {
  final Map<String, Set<int>> _selections = {};
  final Map<String, TableModel> _tableData = {};
  final Map<String, FloorModel> _floorData = {};

  TabController? _tabController;
  List<FloorModel> _floors = [];

  @override
  void initState() {
    super.initState();
    _fetchFloorsAndInitializeController();
  }

  Future<void> _fetchFloorsAndInitializeController() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('restaurants')
        .doc(widget.restaurantId)
        .collection('floors')
        .orderBy('order')
        .get();

    if (mounted) {
      final floors = snapshot.docs.map((doc) {
        final floor = FloorModel.fromFirestore(doc);
        _floorData[floor.id] = floor;
        return floor;
      }).toList();

      setState(() {
        _floors = floors;
        _tabController = TabController(length: _floors.length, vsync: this);
      });
    }
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  void _updateSelection(String tableId, Set<int> seats) {
    setState(() {
      if (seats.isEmpty) {
        _selections.remove(tableId);
      } else {
        _selections[tableId] = seats;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          const _StaticBackground(),
          _tabController == null
              ? const Center(child: CircularProgressIndicator())
              : Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              title: const Text('Assign to Table'),
              backgroundColor: Theme.of(context).scaffoldBackgroundColor.withOpacity(0.85),
              elevation: 0,
              bottom: TabBar(
                controller: _tabController,
                isScrollable: true,
                tabs: _floors.map((floor) => Tab(text: floor.name)).toList(),
              ),
            ),
            body: TabBarView(
              controller: _tabController,
              children: _floors.map((floor) {
                return _FloorTableList(
                  restaurantId: widget.restaurantId,
                  floor: floor,
                  selections: _selections,
                  tableDataCache: _tableData,
                  onSelectionChanged: (entry) {
                    _updateSelection(entry.key, entry.value);
                  },
                );
              }).toList(),
            ),
          ),
          _buildConfirmationPanel(),
        ],
      ),
    );
  }

  Widget _buildConfirmationPanel() {
    final theme = Theme.of(context);
    final hasSelection = _selections.isNotEmpty;

    final currentAssignment = OrderAssignment(
      selections: _selections,
      tableLabels: _tableData.map((id, table) => MapEntry(id, table.label)),
      tableFloorNames: _tableData.map((id, table) {
        final floor = _floorData[table.floorId];
        return MapEntry(id, floor?.name ?? '');
      }),
      tableCapacities: _tableData.map((id, table) => MapEntry(id, table.capacity)),
    );

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
              border: Border(
                top: BorderSide(color: theme.dividerColor, width: 1.5),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: Text(
                    currentAssignment.toDisplayString(),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    final result = OrderAssignment(
                      selections: _selections,
                      tableLabels: _tableData.map((id, table) => MapEntry(id, table.label)),
                      tableFloorNames: currentAssignment.tableFloorNames,
                      tableCapacities: currentAssignment.tableCapacities,
                    );
                    Navigator.of(context).pop(result);
                  },
                  icon: const Icon(Icons.check),
                  label: const Text('Confirm Assignment'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
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

class _FloorTableList extends StatefulWidget {
  final String restaurantId;
  final FloorModel floor;
  final Map<String, Set<int>> selections;
  final ValueChanged<MapEntry<String, Set<int>>> onSelectionChanged;
  final Map<String, TableModel> tableDataCache;

  const _FloorTableList({
    required this.restaurantId,
    required this.floor,
    required this.selections,
    required this.onSelectionChanged,
    required this.tableDataCache,
  });

  @override
  State<_FloorTableList> createState() => _FloorTableListState();
}

class _FloorTableListState extends State<_FloorTableList> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('restaurants')
          .doc(widget.restaurantId)
          .collection('tables')
          .where('floorId', isEqualTo: widget.floor.id)
          .snapshots(),
      builder: (context, tableSnapshot) {
        if (tableSnapshot.connectionState == ConnectionState.waiting && widget.tableDataCache.values.where((t) => t.floorId == widget.floor.id).isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!tableSnapshot.hasData || tableSnapshot.data!.docs.isEmpty) {
          return Center(child: Text('No tables found on ${widget.floor.name}.'));
        }

        final tables = tableSnapshot.data!.docs.map((doc) {
          final table = TableModel.fromFirestore(doc);
          widget.tableDataCache[table.id] = table;
          return table;
        }).toList();

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 150),
          itemCount: tables.length,
          itemBuilder: (context, index) {
            final table = tables[index];
            return StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('restaurants')
                  .doc(widget.restaurantId)
                  .collection('orders')
                  .where('tableIds', arrayContains: table.id)
                  .where('isSessionActive', isEqualTo: true)
                  .snapshots(),
              builder: (context, orderSnapshot) {
                final Set<int> occupiedSeats = {};
                if (orderSnapshot.hasData) {
                  for (var doc in orderSnapshot.data!.docs) {
                    final data = doc.data() as Map<String, dynamic>;
                    final assignment = data['assignment'] as Map<String, dynamic>?;
                    if (assignment != null && assignment.containsKey(table.id)) {
                      final seatsForThisOrder = List.from(assignment[table.id]);
                      if (seatsForThisOrder.isEmpty) {
                        occupiedSeats.addAll(table.seats.map((s) => s.seatNumber));
                      } else {
                        occupiedSeats.addAll(seatsForThisOrder.cast<int>());
                      }
                    }
                  }
                }

                return _TableSelectionCard(
                  table: table,
                  occupiedSeats: occupiedSeats,
                  initialSelection: widget.selections[table.id] ?? {},
                  onSelectionChanged: (newSelection) {
                    widget.onSelectionChanged(MapEntry(table.id, newSelection));
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}


class _TableSelectionCard extends StatefulWidget {
  final TableModel table;
  final Set<int> initialSelection;
  final ValueChanged<Set<int>> onSelectionChanged;
  final Set<int> occupiedSeats;

  const _TableSelectionCard({
    required this.table,
    required this.initialSelection,
    required this.onSelectionChanged,
    required this.occupiedSeats,
  });

  @override
  State<_TableSelectionCard> createState() => _TableSelectionCardState();
}

class _TableSelectionCardState extends State<_TableSelectionCard> {
  late Set<int> _selectedSeats;

  @override
  void initState() {
    super.initState();
    _selectedSeats = widget.initialSelection;
  }

  @override
  void didUpdateWidget(covariant _TableSelectionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialSelection != oldWidget.initialSelection) {
      _selectedSeats = widget.initialSelection;
    }
  }

  void _toggleSeat(int seatNumber) {
    setState(() {
      if (_selectedSeats.contains(seatNumber)) {
        _selectedSeats.remove(seatNumber);
      } else {
        _selectedSeats.add(seatNumber);
      }
    });
    widget.onSelectionChanged(_selectedSeats);
  }

  void _toggleSelectAll(bool? value) {
    final availableSeats = widget.table.seats
        .map((s) => s.seatNumber)
        .where((seatNum) => !widget.occupiedSeats.contains(seatNum))
        .toSet();

    setState(() {
      if (value == true) {
        _selectedSeats = availableSeats;
      } else {
        _selectedSeats.clear();
      }
    });
    widget.onSelectionChanged(_selectedSeats);
  }

  @override
  Widget build(BuildContext context) {
    final availableSeats = widget.table.seats.where((s) => !widget.occupiedSeats.contains(s.seatNumber)).toList();
    final isFullyOccupied = availableSeats.isEmpty && widget.table.seats.isNotEmpty;

    final isAllAvailableSelected = availableSeats.isNotEmpty && _selectedSeats.length == availableSeats.length && _selectedSeats.every((s) => availableSeats.any((av) => av.seatNumber == s));
    final isIndeterminate = _selectedSeats.isNotEmpty && !isAllAvailableSelected;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      color: isFullyOccupied ? Colors.grey.withOpacity(0.3) : null,
      child: Column(
        children: [
          CheckboxListTile(
            title: Row(
              children: [
                Text(widget.table.label,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isFullyOccupied ? Colors.grey.shade700 : null,
                    )),
                const Spacer(),
                if (isFullyOccupied)
                  const Chip(
                    label: Text("Occupied"),
                    backgroundColor: Colors.red,
                    labelStyle: TextStyle(color: Colors.white),
                  )
                else if (widget.occupiedSeats.isNotEmpty)
                  const Chip(
                    label: Text("Partially Occupied"),
                    backgroundColor: Colors.orange,
                    labelStyle: TextStyle(color: Colors.white),
                  )
              ],
            ),
            value:
            isIndeterminate ? null : isAllAvailableSelected,
            tristate: true,
            onChanged: isFullyOccupied ? null : _toggleSelectAll,
            controlAffinity: ListTileControlAffinity.leading,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: widget.table.seats.isEmpty
                ? const Align(
              alignment: Alignment.centerLeft,
              child: Text("No seats defined for this table.",
                  style: TextStyle(fontStyle: FontStyle.italic)),
            )
                : Wrap(
              spacing: 8.0,
              runSpacing: 8.0,
              children: widget.table.seats.map((seat) {
                final isSeatSelected =
                _selectedSeats.contains(seat.seatNumber);
                final isSeatOccupied = widget.occupiedSeats.contains(seat.seatNumber);

                return ChoiceChip(
                  label: Text('S${seat.seatNumber}'),
                  selected: isSeatSelected,
                  backgroundColor: isSeatOccupied ? Colors.red.shade200 : null,
                  selectedColor: isSeatSelected ? Theme.of(context).primaryColor : (isSeatOccupied ? Colors.red.shade200 : null),
                  labelStyle: TextStyle(color: isSeatOccupied ? Colors.white : null),
                  onSelected: isSeatOccupied ? null : (selected) {
                    _toggleSeat(seat.seatNumber);
                  },
                );
              }).toList(),
            ),
          ),
        ],
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