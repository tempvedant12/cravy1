

import 'dart:async';
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cravy/screen/restaurant/orders/assign_table_screen.dart';
import 'package:cravy/screen/restaurant/orders/create_order_screen.dart';
import 'package:cravy/screen/restaurant/orders/order_session_screen.dart';
import 'package:cravy/screen/restaurant/tables_and_reservations/add_edit_reservation_screen.dart';
import 'package:cravy/screen/restaurant/tables_and_reservations/manage_floor_plan_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:intl/intl.dart';



class Reservation {
  final String id;
  final String customerName;
  final String phone;
  final int numberOfGuests;
  final DateTime dateTime;
  final String notes;
  final String status; 
  final String type; 
  final String? assignedTableId;
  final String? assignedTableName;

  Reservation({
    required this.id,
    required this.customerName,
    required this.phone,
    required this.numberOfGuests,
    required this.dateTime,
    required this.notes,
    required this.status,
    this.assignedTableId,
    this.assignedTableName,
    required this.type,
  });

  factory Reservation.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return Reservation(
      id: doc.id,
      customerName: data['customerName'] ?? 'No Name',
      phone: data['phone'] ?? '',
      numberOfGuests: data['numberOfGuests'] ?? 0,
      dateTime: (data['dateTime'] as Timestamp).toDate(),
      notes: data['notes'] ?? '',
      status: data['status'] ?? 'Confirmed',
      assignedTableId: data['assignedTableId'],
      assignedTableName: data['assignedTableName'],
      type: data['type'] ?? 'Standard',
    );
  }
}

enum SeatStatus { Available, Seated, Billing, Reserved }
enum TableShape { square, circle }

class FloorModel {
  final String id;
  final String name;
  final int order;

  FloorModel({required this.id, required this.name, required this.order});

  factory FloorModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return FloorModel(
      id: doc.id,
      name: data['name'] ?? 'Unnamed Floor',
      order: data['order'] ?? 0,
    );
  }
}

class Seat {
  final int seatNumber;
  SeatStatus status;

  Seat({required this.seatNumber, this.status = SeatStatus.Available});

  factory Seat.fromMap(Map<String, dynamic> map) {
    return Seat(
      seatNumber: map['seatNumber'] ?? 0,
      status: SeatStatus.values.firstWhere(
            (e) => e.toString() == map['status'],
        orElse: () => SeatStatus.Available,
      ),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'seatNumber': seatNumber,
      'status': status.toString(),
    };
  }
}

class TableModel {
  final String id;
  final String label;
  final String floorId;
  final List<Seat> seats;
  final TableShape shape;
  final String? activeSessionId;
  final String? activeSessionKey;
  final String? reservationId;

  TableModel({
    required this.id,
    required this.label,
    required this.floorId,
    required this.seats,
    this.shape = TableShape.square,
    this.activeSessionId,
    this.activeSessionKey,
    this.reservationId,
  });

  factory TableModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    var seatList = data['seats'] as List<dynamic>? ?? [];
    return TableModel(
      id: doc.id,
      label: data['label'] ?? 'Table',
      floorId: data['floorId'] ?? '',
      seats: seatList.map((s) => Seat.fromMap(s)).toList(),
      shape:
      (data['shape'] == 'circle') ? TableShape.circle : TableShape.square,
      activeSessionKey: data['activeSessionKey'],
      reservationId: data['reservationId'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'label': label,
      'floorId': floorId,
      'seats': seats.map((s) => s.toMap()).toList(),
      'shape': shape.toString().split('.').last,
      if (activeSessionKey != null) 'activeSessionKey': activeSessionKey,
      if (reservationId != null) 'reservationId': reservationId,
    };
  }

  int get capacity => seats.length;
}



class TablesAndReservationsScreen extends StatefulWidget {
  final String restaurantId;
  const TablesAndReservationsScreen({super.key, required this.restaurantId});

  @override
  State<TablesAndReservationsScreen> createState() => _TablesAndReservationsScreenState();
}

class _TablesAndReservationsScreenState extends State<TablesAndReservationsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      setState(() {}); 
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          const _StaticBackground(),
          Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              title: const Text('Tables & Reservations'),
              backgroundColor: Theme.of(context).scaffoldBackgroundColor.withOpacity(0.85),
              elevation: 0,
              bottom: TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(icon: Icon(Icons.table_restaurant_outlined), text: 'Floor Plan'),
                  Tab(icon: Icon(Icons.calendar_today_outlined), text: 'Booked'),
                  Tab(icon: Icon(Icons.people_alt_outlined), text: 'Waitlist'),
                ],
              ),
            ),
            body: TabBarView(
              controller: _tabController,
              children: [
                _buildFloorPlan(),
                _buildReservationList(type: 'Standard'),
                _buildReservationList(type: 'Waitlist'),
              ],
            ),
            floatingActionButton: _buildFloatingActionButton(),
          ),
        ],
      ),
    );
  }

  Widget? _buildFloatingActionButton() {
    if (_tabController.index == 0) {
      return FloatingActionButton(
        onPressed: () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (context) => ManageFloorPlanScreen(restaurantId: widget.restaurantId),
          ));
        },
        child: const Icon(Icons.edit_note),
        tooltip: 'Manage Floor Plan',
      );
    } else {
      return FloatingActionButton(
        onPressed: () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (context) => AddEditReservationScreen(restaurantId: widget.restaurantId),
          ));
        },
        child: const Icon(Icons.person_add),
        tooltip: 'Add Reservation or Waitlist',
      );
    }
  }


  Widget _buildFloorPlan() {
    return StreamBuilder<QuerySnapshot>(
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
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('No floors created yet.'));
        }
        final floors = snapshot.data!.docs.map((doc) => FloorModel.fromFirestore(doc)).toList();
        return FloorPlanView(
          restaurantId: widget.restaurantId,
          floors: floors,
        );
      },
    );
  }

  Widget _buildReservationList({required String type}) {
    Query baseQuery = FirebaseFirestore.instance
        .collection('restaurants')
        .doc(widget.restaurantId)
        .collection('reservations')
        .where('type', isEqualTo: type);

    if (type == 'Standard') {
      baseQuery = baseQuery.where('dateTime', isGreaterThanOrEqualTo: DateTime.now()).orderBy('dateTime');
    } else {
      baseQuery = baseQuery.orderBy('dateTime');
    }

    return StreamBuilder<QuerySnapshot>(
      stream: baseQuery.snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        if (snapshot.data!.docs.isEmpty) return Center(child: Text('No guests in ${type.toLowerCase()} list.'));

        final reservations = snapshot.data!.docs.map((doc) => Reservation.fromFirestore(doc)).toList();

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: reservations.length,
          itemBuilder: (context, index) {
            final reservation = reservations[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                title: Text('${reservation.customerName} (${reservation.numberOfGuests} guests)'),
                subtitle: Text('Time: ${DateFormat.jm().format(reservation.dateTime)}\nTable: ${reservation.assignedTableName ?? 'Any'}'),
                trailing: Text(reservation.status),
                onTap: (){
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (context) => AddEditReservationScreen(restaurantId: widget.restaurantId, reservation: reservation),
                  ));
                },
              ),
            );
          },
        );
      },
    );
  }
}



class FloorPlanView extends StatelessWidget {
  final String restaurantId;
  final List<FloorModel> floors;

  const FloorPlanView({super.key, required this.restaurantId, required this.floors});

  @override
  Widget build(BuildContext context) {
    if (floors.isEmpty) {
      return const Center(child: Text("No floors created."));
    }
    return DefaultTabController(
      length: floors.length,
      child: Column(
        children: [
          TabBar(
            isScrollable: true,
            tabs: floors.map((floor) => _FloorTab(restaurantId: restaurantId, floor: floor)).toList(),
          ),
          Expanded(
            child: TabBarView(
              children: floors.map((floor) => _FloorGrid(restaurantId: restaurantId, floor: floor)).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _FloorTab extends StatelessWidget {
  final String restaurantId;
  final FloorModel floor;
  const _FloorTab({required this.restaurantId, required this.floor});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('restaurants').doc(restaurantId).collection('tables').where('floorId', isEqualTo: floor.id).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return Tab(text: floor.name);

        final tables = snapshot.data!.docs;
        final activeTables = tables.where((doc) => (doc.data() as Map<String, dynamic>)['activeSessionKey'] != null).length;

        return Tab(text: '${floor.name} ($activeTables/${tables.length})');
      },
    );
  }
}

class _FloorGrid extends StatelessWidget {
  final String restaurantId;
  final FloorModel floor;

  const _FloorGrid({required this.restaurantId, required this.floor});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('restaurants')
          .doc(restaurantId)
          .collection('tables')
          .where('floorId', isEqualTo: floor.id)
          .orderBy('label')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final tables = snapshot.data!.docs.map((doc) => TableModel.fromFirestore(doc)).toList();

        if (tables.isEmpty) {
          return const Center(child: Text("No tables on this floor. Add one from the Tables & Floor settings."));
        }
        return AnimationLimiter(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: tables.length,
            itemBuilder: (context, index) {
              return AnimationConfiguration.staggeredList(
                position: index,
                duration: const Duration(milliseconds: 375),
                child: SlideAnimation(
                  verticalOffset: 50.0,
                  child: FadeInAnimation(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: TableStatusCard(
                        restaurantId: restaurantId,
                        table: tables[index],
                        floor: floor,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}


class TableStatusCard extends StatelessWidget {
  final String restaurantId;
  final TableModel table;
  final FloorModel floor;

  const TableStatusCard({
    super.key,
    required this.restaurantId,
    required this.table,
    required this.floor,
  });

  
  void _handleTap(BuildContext context) async {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => CreateOrderScreen(
        restaurantId: restaurantId,
      ),
    ));
  }
  

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 2,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: theme.colorScheme.surface.withOpacity(0.5),
      child: InkWell(
        onTap: () => _handleTap(context),
        onLongPress: () => _showTableActions(context),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Text(
                table.label,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              _buildContent(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('restaurants')
          .doc(restaurantId)
          .collection('orders')
          .where('tableIds', arrayContains: table.id)
          .where('isSessionActive', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const CircularProgressIndicator();

        final activeOrders = snapshot.data!.docs;
        final groupedBySession = <String, List<DocumentSnapshot>>{};
        for (final order in activeOrders) {
          final key = (order.data() as Map<String, dynamic>)['sessionKey'];
          if (key != null) {
            groupedBySession.putIfAbsent(key, () => []).add(order);
          }
        }

        final Set<int> occupiedSeats = {};
        for (var session in groupedBySession.values) {
          final assignment = (session.first.data() as Map<String, dynamic>)['assignment'] as Map<String, dynamic>?;
          if (assignment != null && assignment[table.id] != null) {
            occupiedSeats.addAll(Set<int>.from(assignment[table.id]));
          }
        }
        final availableSeats = table.seats.where((s) => !occupiedSeats.contains(s.seatNumber)).toList();


        return Column(
          children: [
            ...groupedBySession.entries.map((entry) {
              return _SessionSubCard(
                restaurantId: restaurantId,
                sessionKey: entry.key,
                sessionOrders: entry.value,
                table: table,
              );
            }),
            if (availableSeats.isNotEmpty && groupedBySession.isNotEmpty)
              const Divider(height: 20),
            if (availableSeats.isNotEmpty)
              _buildAvailableSeats(context, availableSeats),
          ],
        );
      },
    );
  }

  Widget _buildAvailableSeats(BuildContext context, List<Seat> availableSeats) {
    return Column(
      children: [
        Text('Available Seats', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8.0,
          runSpacing: 8.0,
          alignment: WrapAlignment.center,
          children: availableSeats.map((seat) {
            return Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: Colors.green,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  seat.seatNumber.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  void _showTableActions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Wrap(
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.add_circle_outline),
              title: const Text('Add New Order'),
              onTap: () {
                Navigator.pop(context);
                _handleTap(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.cleaning_services_outlined),
              title: const Text('Mark as Available'),
              onTap: () {
                Navigator.pop(context);
                
              },
            ),
          ],
        );
      },
    );
  }
}

class _SessionSubCard extends StatelessWidget {
  final String restaurantId;
  final String sessionKey;
  final List<DocumentSnapshot> sessionOrders;
  final TableModel table;

  const _SessionSubCard({
    required this.restaurantId,
    required this.sessionKey,
    required this.sessionOrders,
    required this.table,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalAmount = sessionOrders.fold<double>(0.0, (sum, doc) => sum + ((doc.data() as Map<String, dynamic>)['totalAmount'] ?? 0.0));

    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (context) => OrderSessionScreen(
              restaurantId: restaurantId,
              sessionKey: sessionKey,
              initialOrders: sessionOrders,
            ),
          ));
        },
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(sessionKey, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      NumberFormat.currency(locale: 'en_IN', symbol: '₹').format(totalAmount),
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: theme.primaryColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.open_with),
                tooltip: 'Shift Table',
                onPressed: () => _shiftTable(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _shiftTable(BuildContext context) async {
    final newTable = await showDialog<TableModel>(
      context: context,
      builder: (_) => _SelectTableDialog(restaurantId: restaurantId, currentTableId: table.id),
    );

    if (newTable != null && context.mounted) {
      final batch = FirebaseFirestore.instance.batch();

      
      for (var orderDoc in sessionOrders) {
        batch.update(orderDoc.reference, {
          'tableIds': [newTable.id],
          'assignment': {newTable.id: (orderDoc.data() as Map<String, dynamic>)['assignment'][table.id]},
          'assignmentLabel': newTable.label,
          'sessionKey': newTable.label,
        });
      }

      
      batch.update(
        FirebaseFirestore.instance.collection('restaurants').doc(restaurantId).collection('tables').doc(table.id),
        {'activeSessionKey': FieldValue.delete()},
      );
      batch.update(
        FirebaseFirestore.instance.collection('restaurants').doc(restaurantId).collection('tables').doc(newTable.id),
        {'activeSessionKey': newTable.label},
      );

      await batch.commit();

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Shifted from ${table.label} to ${newTable.label}')));
    }
  }
}

class _SelectTableDialog extends StatelessWidget {
  final String restaurantId;
  final String currentTableId;

  const _SelectTableDialog({required this.restaurantId, required this.currentTableId});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select a New Table'),
      content: SizedBox(
        width: double.maxFinite,
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('restaurants')
              .doc(restaurantId)
              .collection('tables')
              .where('activeSessionKey', isNull: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            final tables = snapshot.data!.docs
                .where((doc) => doc.id != currentTableId) 
                .map((doc) => TableModel.fromFirestore(doc))
                .toList();

            if (tables.isEmpty) return const Text('No available tables to shift to.');

            return ListView.builder(
              shrinkWrap: true,
              itemCount: tables.length,
              itemBuilder: (context, index) {
                final table = tables[index];
                return ListTile(
                  title: Text(table.label),
                  onTap: () => Navigator.of(context).pop(table),
                );
              },
            );
          },
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

Future<void> updateTableSessionStatus(String restaurantId,
    Map<String, Set<int>> assignments, String sessionKey,
    {required bool closeSession}) async {
  final batch = FirebaseFirestore.instance.batch();
  final restaurantRef =
  FirebaseFirestore.instance.collection('restaurants').doc(restaurantId);

  for (final tableId in assignments.keys) {
    final tableRef = restaurantRef.collection('tables').doc(tableId);
    final seatsToUpdate = assignments[tableId] ?? {};

    
    final snapshot = await tableRef.get();
    if (!snapshot.exists) continue;

    final currentTable = TableModel.fromFirestore(snapshot);
    final newSeats = List<Seat>.from(currentTable.seats);

    
    for (final seat in newSeats) {
      final isAssigned = seatsToUpdate.contains(seat.seatNumber) ||
          seatsToUpdate.isEmpty;

      if (isAssigned) {
        seat.status = closeSession ? SeatStatus.Available : SeatStatus.Seated;
      }
    }

    
    batch.update(tableRef, {
      'seats': newSeats.map((s) => s.toMap()).toList(),
      'activeSessionKey': closeSession ? FieldValue.delete() : sessionKey,
    });
  }

  await batch.commit();
}