// lib/screen/restaurant/staff/staff_and_roles_screen.dart

import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cravy/screen/restaurant/staff/staff_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:intl/intl.dart';
import 'add_edit_staff_screen.dart';
import 'staff_payment_dialogs.dart';

// --- UPDATED Staff Model with Shift Time ---
class Staff {
  final String id;
  final String name;
  final String role;
  final String phone;
  final String email;
  final double payRate;
  final String paymentType;
  final int salaryPayday;
  final String shiftStartTime; // Format: "HH:mm"

  Staff({
    required this.id,
    required this.name,
    required this.role,
    required this.phone,
    required this.email,
    required this.payRate,
    required this.paymentType,
    required this.salaryPayday,
    required this.shiftStartTime,
  });

  factory Staff.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return Staff(
      id: doc.id,
      name: data['name'] ?? '',
      role: data['role'] ?? 'Staff',
      phone: data['phone'] ?? '',
      email: data['email'] ?? '',
      payRate: (data['payRate'] as num?)?.toDouble() ?? 0.0,
      paymentType: data['paymentType'] ?? '',
      salaryPayday: (data['salaryPayday'] as num?)?.toInt() ?? 1,
      shiftStartTime: data['shiftStartTime'] ?? '09:00', // Default 9 AM
    );
  }
}

// --- UPDATED Attendance Model ---
class Attendance {
  final String id;
  final String staffId;
  final DateTime date;
  final DateTime? checkIn;
  final DateTime? checkOut;
  final String status; // 'Late', 'Present', 'Absent', 'Early'

  Attendance({
    required this.id,
    required this.staffId,
    required this.date,
    this.checkIn,
    this.checkOut,
    this.status = '',
  });

  factory Attendance.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return Attendance(
      id: doc.id,
      staffId: data['staffId'],
      date: (data['date'] as Timestamp).toDate(),
      checkIn: (data['checkIn'] as Timestamp?)?.toDate(),
      checkOut: (data['checkOut'] as Timestamp?)?.toDate(),
      status: data['status'] ?? '',
    );
  }
}

// --- Combined Model ---
class StaffWithAttendance {
  final Staff staff;
  final Attendance? attendance;

  StaffWithAttendance({
    required this.staff,
    this.attendance,
  });
}

class StaffAndRolesScreen extends StatefulWidget {
  final String restaurantId;
  const StaffAndRolesScreen({super.key, required this.restaurantId});

  @override
  State<StaffAndRolesScreen> createState() => _StaffAndRolesScreenState();
}

class _StaffAndRolesScreenState extends State<StaffAndRolesScreen> {
  final DateTime _today =
  DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);

  // --- NEW: Open Mark Attendance Dialog ---
  void _openMarkAttendanceDialog(Staff staff, Attendance? attendance) {
    showDialog(
      context: context,
      builder: (context) => _MarkAttendanceDialog(
        restaurantId: widget.restaurantId,
        staff: staff,
        existingAttendance: attendance,
        date: _today,
      ),
    );
  }

  Future<void> _deleteStaff(Staff staff) async {
    final bool? confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Staff?'),
        content: Text(
            'Are you sure you want to delete "${staff.name}"? This will also remove all their attendance and payment history. This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseFirestore.instance
          .collection('restaurants')
          .doc(widget.restaurantId)
          .collection('staff')
          .doc(staff.id)
          .delete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text('Staff Attendance (${DateFormat.yMMMd().format(_today)})'),
        backgroundColor:
        theme.scaffoldBackgroundColor.withOpacity(0.85),
        elevation: 0,
      ),
      body: Stack(
        children: [
          const _StaticBackground(),
          SafeArea(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('restaurants')
                  .doc(widget.restaurantId)
                  .collection('staff')
                  .orderBy('name')
                  .snapshots(),
              builder: (context, staffSnapshot) {
                if (staffSnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!staffSnapshot.hasData ||
                    staffSnapshot.data!.docs.isEmpty) {
                  return const Center(child: Text('No staff members found.'));
                }

                final staffList = staffSnapshot.data!.docs
                    .map((doc) => Staff.fromFirestore(doc))
                    .toList();

                return StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('restaurants')
                      .doc(widget.restaurantId)
                      .collection('attendance')
                      .where('date', isEqualTo: Timestamp.fromDate(_today))
                      .snapshots(),
                  builder: (context, attendanceSnapshot) {
                    final attendanceList = attendanceSnapshot.data?.docs
                        .map((doc) => Attendance.fromFirestore(doc))
                        .toList() ??
                        [];

                    final Map<String, Attendance> attendanceMap = {
                      for (var att in attendanceList) att.staffId: att
                    };

                    final staffWithAttendanceList = staffList.map((staff) {
                      return StaffWithAttendance(
                        staff: staff,
                        attendance: attendanceMap[staff.id],
                      );
                    }).toList();

                    return AnimationLimiter(
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                        itemCount: staffWithAttendanceList.length,
                        itemBuilder: (context, index) {
                          final item = staffWithAttendanceList[index];
                          return AnimationConfiguration.staggeredList(
                            position: index,
                            duration: const Duration(milliseconds: 375),
                            child: SlideAnimation(
                              verticalOffset: 50.0,
                              child: FadeInAnimation(
                                child: _StaffAttendanceCard(
                                  restaurantId: widget.restaurantId,
                                  item: item,
                                  onTap: () {
                                    Navigator.of(context).push(MaterialPageRoute(
                                      builder: (context) => StaffDetailScreen(
                                        restaurantId: widget.restaurantId,
                                        staff: item.staff,
                                      ),
                                    ));
                                  },
                                  onMarkAttendance: () => _openMarkAttendanceDialog(item.staff, item.attendance),
                                  onDelete: () => _deleteStaff(item.staff),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (context) =>
                AddEditStaffScreen(restaurantId: widget.restaurantId),
          ));
        },
        tooltip: 'Add New Staff',
        child: const Icon(Icons.add),
      ),
    );
  }
}

// --- NEW: Mark Attendance Dialog ---
class _MarkAttendanceDialog extends StatefulWidget {
  final String restaurantId;
  final Staff staff;
  final Attendance? existingAttendance;
  final DateTime date;

  const _MarkAttendanceDialog({
    required this.restaurantId,
    required this.staff,
    this.existingAttendance,
    required this.date,
  });

  @override
  State<_MarkAttendanceDialog> createState() => _MarkAttendanceDialogState();
}

class _MarkAttendanceDialogState extends State<_MarkAttendanceDialog> {
  TimeOfDay? _checkInTime;
  TimeOfDay? _checkOutTime;
  String _status = 'Absent'; // Default

  final List<String> _statusOptions = ['Present', 'Late', 'Absent', 'Half Day'];

  @override
  void initState() {
    super.initState();
    if (widget.existingAttendance != null) {
      if (widget.existingAttendance!.checkIn != null) {
        _checkInTime = TimeOfDay.fromDateTime(widget.existingAttendance!.checkIn!);
      }
      if (widget.existingAttendance!.checkOut != null) {
        _checkOutTime = TimeOfDay.fromDateTime(widget.existingAttendance!.checkOut!);
      }
      _status = widget.existingAttendance!.status.isNotEmpty
          ? widget.existingAttendance!.status
          : 'Absent';
    } else {
      // Default to "Present" if creating new and current time matches roughly
      _status = 'Present';
      _checkInTime = TimeOfDay.now(); // Auto-suggest current time
      _calculateAutoStatus(); // Run logic once
    }
  }

  // --- LOGIC: Auto-calculate Status ---
  void _calculateAutoStatus() {
    if (_checkInTime == null) return;

    final now = DateTime.now();
    // Parse staff shift start time (e.g. "09:00")
    final shiftParts = widget.staff.shiftStartTime.split(':');
    final shiftStart = DateTime(now.year, now.month, now.day,
        int.parse(shiftParts[0]), int.parse(shiftParts[1]));

    // Create check-in datetime for comparison
    final checkIn = DateTime(now.year, now.month, now.day,
        _checkInTime!.hour, _checkInTime!.minute);

    // Tolerance: 15 mins late
    if (checkIn.isAfter(shiftStart.add(const Duration(minutes: 15)))) {
      setState(() => _status = 'Late');
    } else {
      setState(() => _status = 'Present');
    }
  }

  Future<void> _pickCheckInTime() async {
    final picked = await showTimePicker(context: context, initialTime: _checkInTime ?? TimeOfDay.now());
    if (picked != null) {
      setState(() {
        _checkInTime = picked;
      });
      // Auto-update status when time changes
      _calculateAutoStatus();
    }
  }

  Future<void> _pickCheckOutTime() async {
    final picked = await showTimePicker(context: context, initialTime: _checkOutTime ?? TimeOfDay.now());
    if (picked != null) {
      setState(() => _checkOutTime = picked);
    }
  }

  Future<void> _save() async {
    final attendanceRef = FirebaseFirestore.instance
        .collection('restaurants')
        .doc(widget.restaurantId)
        .collection('attendance');

    final now = widget.date;

    // Combine date with time components
    DateTime? checkInDateTime;
    DateTime? checkOutDateTime;

    if (_checkInTime != null) {
      checkInDateTime = DateTime(now.year, now.month, now.day, _checkInTime!.hour, _checkInTime!.minute);
    }
    if (_checkOutTime != null) {
      checkOutDateTime = DateTime(now.year, now.month, now.day, _checkOutTime!.hour, _checkOutTime!.minute);
    }

    // If status is Absent, clear times? (Optional, but user said user has power)
    // We will save whatever the user set.

    final data = {
      'staffId': widget.staff.id,
      'date': Timestamp.fromDate(widget.date),
      'checkIn': checkInDateTime != null ? Timestamp.fromDate(checkInDateTime) : null,
      'checkOut': checkOutDateTime != null ? Timestamp.fromDate(checkOutDateTime) : null,
      'status': _status,
    };

    if (widget.existingAttendance == null) {
      await attendanceRef.add(data);
    } else {
      await attendanceRef.doc(widget.existingAttendance!.id).update(data);
    }

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Mark Attendance: ${widget.staff.name}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Shift Start:', style: TextStyle(fontSize: 12, color: Colors.grey)),
            Text(widget.staff.shiftStartTime, style: const TextStyle(fontWeight: FontWeight.bold)),
            const Divider(),

            // Status Dropdown
            DropdownButtonFormField<String>(
              value: _status,
              decoration: const InputDecoration(labelText: 'Status'),
              items: _statusOptions.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
              onChanged: (val) => setState(() => _status = val!),
            ),
            const SizedBox(height: 16),

            // Check In Time
            ListTile(
              title: const Text('Check In Time'),
              subtitle: Text(_checkInTime?.format(context) ?? 'Not Set'),
              trailing: const Icon(Icons.access_time),
              onTap: _pickCheckInTime,
              tileColor: Colors.grey.withOpacity(0.1),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            const SizedBox(height: 8),

            // Check Out Time
            ListTile(
              title: const Text('Check Out Time'),
              subtitle: Text(_checkOutTime?.format(context) ?? 'Not Set'),
              trailing: const Icon(Icons.access_time),
              onTap: _pickCheckOutTime,
              tileColor: Colors.grey.withOpacity(0.1),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

// --- UPDATED CARD ---
class _StaffAttendanceCard extends StatefulWidget {
  final String restaurantId;
  final StaffWithAttendance item;
  final VoidCallback onTap;
  final VoidCallback onMarkAttendance; // <-- Replaces ClockIn/Out
  final VoidCallback onDelete;

  const _StaffAttendanceCard(
      {required this.restaurantId,
        required this.item,
        required this.onTap,
        required this.onMarkAttendance,
        required this.onDelete});

  @override
  State<_StaffAttendanceCard> createState() => _StaffAttendanceCardState();
}

class _StaffAttendanceCardState extends State<_StaffAttendanceCard> {
  bool _isHovered = false;
  late Stream<QuerySnapshot> _paymentStream;

  @override
  void initState() {
    super.initState();
    _paymentStream = FirebaseFirestore.instance
        .collection('restaurants')
        .doc(widget.restaurantId)
        .collection('staff')
        .doc(widget.item.staff.id)
        .collection('payments')
        .orderBy('paidAt', descending: true)
        .limit(1)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final String initial =
    widget.item.staff.name.isNotEmpty ? widget.item.staff.name[0] : '?';

    final att = widget.item.attendance;

    String statusText = 'Not Marked';
    Color statusColor = Colors.grey;
    String timeInfo = '';

    if (att != null) {
      statusText = att.status;
      if (statusText == 'Present') statusColor = Colors.green;
      else if (statusText == 'Late') statusColor = Colors.orange;
      else if (statusText == 'Absent') statusColor = Colors.red;
      else if (statusText == 'Half Day') statusColor = Colors.purple;

      if (att.checkIn != null) {
        timeInfo = 'In: ${DateFormat.jm().format(att.checkIn!)}';
      }
      if (att.checkOut != null) {
        timeInfo += ' - Out: ${DateFormat.jm().format(att.checkOut!)}';

        // Calculate Duration
        if (att.checkIn != null) {
          final diff = att.checkOut!.difference(att.checkIn!);
          final hours = diff.inHours;
          final mins = diff.inMinutes.remainder(60);
          timeInfo += '\n(${hours}h ${mins}m)';
        }
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _isHovered
                      ? theme.primaryColor.withOpacity(0.5)
                      : Colors.white.withOpacity(0.2),
                  width: 1.5,
                ),
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.surface.withOpacity(0.3),
                    theme.colorScheme.surface.withOpacity(0.1),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: theme.primaryColor,
                      child: Text(
                        initial,
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onPrimary),
                      ),
                    ),
                    title: Text(widget.item.staff.name,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.item.staff.role),
                        if (timeInfo.isNotEmpty)
                          Text(timeInfo, style: theme.textTheme.bodySmall?.copyWith(fontSize: 11)),
                      ],
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: statusColor.withOpacity(0.5)),
                          ),
                          child: Text(statusText,
                              style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12)),
                        ),
                      ],
                    ),
                  ),

                  const Divider(height: 1),

                  // --- ACTION BAR ---
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        TextButton.icon(
                          onPressed: widget.onMarkAttendance,
                          icon: const Icon(Icons.access_time),
                          label: const Text('Mark Attendance'),
                        ),

                        // Vertical Divider
                        Container(width: 1, height: 20, color: theme.dividerColor),

                        IconButton(
                          icon: Icon(Icons.payments_outlined, color: theme.primaryColor),
                          onPressed: () {
                            showStaffPaymentDialog(
                              context,
                              widget.item.staff,
                              widget.restaurantId,
                            );
                          },
                          tooltip: 'Log Payment',
                        ),
                        IconButton(
                          icon: Icon(Icons.delete_outline,
                              color: theme.colorScheme.error.withOpacity(0.7)),
                          onPressed: widget.onDelete,
                          tooltip: 'Delete Staff',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// --- NEW: BACKGROUND WIDGET ---
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