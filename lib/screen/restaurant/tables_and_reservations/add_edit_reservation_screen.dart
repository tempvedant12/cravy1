

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cravy/screen/restaurant/tables_and_reservations/tables_and_reservations_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:intl/intl.dart';

class AddEditReservationScreen extends StatefulWidget {
  final String restaurantId;
  final Reservation? reservation;

  const AddEditReservationScreen(
      {super.key, required this.restaurantId, this.reservation});

  @override
  _AddEditReservationScreenState createState() =>
      _AddEditReservationScreenState();
}

class _AddEditReservationScreenState extends State<AddEditReservationScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _guestsController;
  late TextEditingController _notesController;
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();
  String _status = 'Confirmed';
  String _type = 'Standard';
  String? _assignedTableId;
  String? _assignedTableName;

  List<TableModel> _availableTables = [];

  @override
  void initState() {
    super.initState();
    _nameController =
        TextEditingController(text: widget.reservation?.customerName ?? '');
    _phoneController =
        TextEditingController(text: widget.reservation?.phone ?? '');
    _guestsController = TextEditingController(
        text: widget.reservation?.numberOfGuests.toString() ?? '');
    _notesController =
        TextEditingController(text: widget.reservation?.notes ?? '');

    if (widget.reservation != null) {
      _selectedDate = widget.reservation!.dateTime;
      _selectedTime = TimeOfDay.fromDateTime(widget.reservation!.dateTime);
      _status = widget.reservation!.status;
      _type = widget.reservation!.type;
      _assignedTableId = widget.reservation!.assignedTableId;
      _assignedTableName = widget.reservation!.assignedTableName;
    }
    _fetchTables();
  }

  Future<void> _fetchTables() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('restaurants')
        .doc(widget.restaurantId)
        .collection('tables')
        .get();
    if (mounted) {
      setState(() {
        _availableTables =
            snapshot.docs.map((doc) => TableModel.fromFirestore(doc)).toList();
      });
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _selectTime(BuildContext context) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );
    if (picked != null && picked != _selectedTime) {
      setState(() {
        _selectedTime = picked;
      });
    }
  }

  Future<void> _saveReservation() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);

      final reservationDateTime = _type == 'Standard'
          ? DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        _selectedTime.hour,
        _selectedTime.minute,
      )
          : DateTime.now();

      final reservationData = {
        'customerName': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'numberOfGuests': int.tryParse(_guestsController.text) ?? 1,
        'dateTime': Timestamp.fromDate(reservationDateTime),
        'notes': _notesController.text.trim(),
        'status': _status,
        'type': _type,
        'assignedTableId': _assignedTableId,
        'assignedTableName': _assignedTableName,
      };

      try {
        final collection = FirebaseFirestore.instance
            .collection('restaurants')
            .doc(widget.restaurantId)
            .collection('reservations');

        if (widget.reservation == null) {
          await collection.add(reservationData);
        } else {
          await collection.doc(widget.reservation!.id).update(reservationData);
        }

        if (mounted) Navigator.of(context).pop();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error saving reservation: $e')),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
            widget.reservation == null ? 'Add Reservation' : 'Edit Reservation'),
        backgroundColor: Colors.transparent,
        elevation: 0,
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
                            _buildSectionHeader(
                                'Type', Icons.confirmation_number_outlined),
                            _buildDropdown(_type, ['Standard', 'Waitlist'],
                                    (val) {
                                  setState(() => _type = val!);
                                }),
                            const SizedBox(height: 24),
                            _buildSectionHeader(
                                'Guest Info', Icons.person_outline),
                            _buildTextField(
                              controller: _nameController,
                              label: 'Customer Name',
                              icon: Icons.person_pin_circle_outlined,
                            ),
                            const SizedBox(height: 16),
                            _buildTextField(
                              controller: _phoneController,
                              label: 'Phone Number',
                              icon: Icons.phone_outlined,
                              keyboardType: TextInputType.phone,
                            ),
                            const SizedBox(height: 16),
                            _buildTextField(
                              controller: _guestsController,
                              label: 'Number of Guests',
                              icon: Icons.people_alt_outlined,
                              keyboardType: TextInputType.number,
                            ),
                            if (_type == 'Standard') ...[
                              const SizedBox(height: 24),
                              _buildSectionHeader(
                                  'Date & Time', Icons.calendar_today_outlined),
                              _buildDateTimePickers(),
                            ],
                            const SizedBox(height: 24),
                            _buildSectionHeader(
                                'Details', Icons.notes_outlined),
                            _buildTableDropdown(),
                            const SizedBox(height: 16),
                            _buildTextField(
                              controller: _notesController,
                              label: 'Notes (Optional)',
                              icon: Icons.speaker_notes_outlined,
                            ),
                            const SizedBox(height: 16),
                            _buildDropdown(_status, [
                              'Confirmed',
                              'Seated',
                              'Cancelled',
                              'Completed',
                              'No Show'
                            ], (val) {
                              setState(() => _status = val!);
                            }),
                            const SizedBox(height: 40),
                            _isLoading
                                ? const Center(
                                child: CircularProgressIndicator())
                                : ElevatedButton.icon(
                              icon: const Icon(Icons.save_outlined),
                              onPressed: _saveReservation,
                              label: const Text('Save Reservation'),
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

  Widget _buildSectionHeader(String title, IconData icon) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        children: [
          Icon(icon, color: theme.primaryColor, size: 20),
          const SizedBox(width: 8),
          Text(title, style: theme.textTheme.titleMedium),
        ],
      ),
    );
  }

  Widget _buildDateTimePickers() {
    final theme = Theme.of(context);
    return _buildCleanContainer(
      child: Row(
        children: [
          Expanded(
            child: ListTile(
              title: Text(DateFormat.yMMMd().format(_selectedDate)),
              leading: const Icon(Icons.calendar_today_outlined),
              onTap: () => _selectDate(context),
            ),
          ),
          Container(
              height: 40,
              width: 1,
              color: theme.dividerColor.withOpacity(0.5)),
          Expanded(
            child: ListTile(
              title: Text(_selectedTime.format(context)),
              leading: const Icon(Icons.access_time_outlined),
              onTap: () => _selectTime(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableDropdown() {
    return _buildCleanContainer(
      child: DropdownButtonFormField<String>(
        value: _assignedTableId,
        decoration: const InputDecoration(
          labelText: 'Assign Table (Optional)',
          prefixIcon: Icon(Icons.table_restaurant_outlined, size: 22),
          border: InputBorder.none,
          contentPadding: EdgeInsets.fromLTRB(0, 18, 16, 18),
        ),
        items: _availableTables.map((TableModel table) {
          return DropdownMenuItem<String>(
            value: table.id,
            child: Text(table.label),
          );
        }).toList(),
        onChanged: (String? newValue) {
          if (newValue != null) {
            final selectedTable =
            _availableTables.firstWhere((tbl) => tbl.id == newValue);
            setState(() {
              _assignedTableId = newValue;
              _assignedTableName = selectedTable.label;
            });
          }
        },
      ),
    );
  }

  Widget _buildDropdown(
      String value, List<String> items, ValueChanged<String?> onChanged) {
    return _buildCleanContainer(
      child: DropdownButtonFormField<String>(
        value: value,
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.flag_outlined, size: 22),
          border: InputBorder.none,
          contentPadding: EdgeInsets.fromLTRB(0, 18, 16, 18),
        ),
        items: items.map((String item) {
          return DropdownMenuItem<String>(
            value: item,
            child: Text(item),
          );
        }).toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
  }) {
    return _buildCleanContainer(
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 22),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.fromLTRB(0, 18, 16, 18),
        ),
        keyboardType: keyboardType,
        validator: (val) {
          if (!label.contains('(Optional)') &&
              (val == null || val.trim().isEmpty)) {
            return 'This field cannot be empty';
          }
          if (keyboardType == TextInputType.number &&
              val!.isNotEmpty &&
              int.tryParse(val) == null) {
            return 'Please enter a valid number';
          }
          return null;
        },
        style: Theme.of(context).textTheme.bodyLarge,
      ),
    );
  }

  Widget _buildCleanContainer({required Widget child}) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withOpacity(0.5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.dividerColor.withOpacity(0.5)),
        ),
        child: child,
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