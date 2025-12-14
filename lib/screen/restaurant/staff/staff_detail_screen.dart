// lib/screen/restaurant/staff/staff_detail_screen.dart

import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cravy/screen/restaurant/staff/add_edit_staff_screen.dart';
import 'package:cravy/screen/restaurant/staff/staff_and_roles_screen.dart';
import 'package:cravy/screen/restaurant/staff/staff_payment_dialogs.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:async';

class StaffDetailScreen extends StatefulWidget {
  final String restaurantId;
  final Staff staff;

  const StaffDetailScreen({
    super.key,
    required this.restaurantId,
    required this.staff,
  });

  @override
  State<StaffDetailScreen> createState() => _StaffDetailScreenState();
}

class _StaffDetailScreenState extends State<StaffDetailScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  late Future<Staff> _staffFuture;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _staffFuture = _fetchStaff();
  }

  Future<Staff> _fetchStaff() async {
    final doc = await FirebaseFirestore.instance
        .collection('restaurants')
        .doc(widget.restaurantId)
        .collection('staff')
        .doc(widget.staff.id)
        .get();

    if (!doc.exists) return widget.staff;
    return Staff.fromFirestore(doc);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: FutureBuilder<Staff>(
          future: _staffFuture,
          builder: (context, snapshot) {
            return Text(snapshot.data?.name ?? widget.staff.name);
          },
        ),
        backgroundColor: theme.scaffoldBackgroundColor.withOpacity(0.85),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit Staff Member',
            onPressed: () async {
              final staffToEdit = await _staffFuture;
              await Navigator.of(context).push(MaterialPageRoute(
                builder: (context) => AddEditStaffScreen(
                  restaurantId: widget.restaurantId,
                  staff: staffToEdit,
                ),
              ));
              if (mounted) setState(() => _staffFuture = _fetchStaff());
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.person_outline), text: 'Details'),
            Tab(icon: Icon(Icons.calendar_month_outlined), text: 'Attendance'),
            Tab(icon: Icon(Icons.payment_outlined), text: 'Payments'),
          ],
        ),
      ),
      body: Stack(
        children: [
          const _StaticBackground(),
          SafeArea(
            child: TabBarView(
              controller: _tabController,
              children: [
                FutureBuilder<Staff>(
                  future: _staffFuture,
                  builder: (context, snapshot) =>
                      _buildDetailsTab(theme, snapshot.data ?? widget.staff),
                ),
                FutureBuilder<Staff>(
                  future: _staffFuture,
                  builder: (context, snapshot) => _AttendanceHistoryTab(
                    restaurantId: widget.restaurantId,
                    staff: snapshot.data ?? widget.staff,
                  ),
                ),
                FutureBuilder<Staff>(
                  future: _staffFuture,
                  builder: (context, snapshot) => _PaymentHistoryTab(
                    restaurantId: widget.restaurantId,
                    staff: snapshot.data ?? widget.staff,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassCard({required Widget child, String? title, EdgeInsets? padding}) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: padding ?? const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.2)),
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
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (title != null) ...[
              Text(title, style: theme.textTheme.titleLarge),
              const Divider(height: 24),
            ],
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildDetailsTab(ThemeData theme, Staff staff) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildGlassCard(
          title: 'Contact Information',
          child: Column(
            children: [
              _buildDetailRow(theme, Icons.phone_outlined, 'Phone',
                  staff.phone.isEmpty ? 'N/A' : staff.phone),
              _buildDetailRow(theme, Icons.email_outlined, 'Email',
                  staff.email.isEmpty ? 'N/A' : staff.email),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildGlassCard(
          title: 'Role & Pay',
          child: Column(
            children: [
              _buildDetailRow(theme, Icons.badge_outlined, 'Role', staff.role),
              _buildDetailRow(
                  theme,
                  Icons.payments_outlined,
                  'Pay Type',
                  staff.paymentType.isEmpty ? 'N/A' : staff.paymentType),
              _buildDetailRow(
                  theme,
                  Icons.account_balance_wallet_outlined,
                  'Pay Rate',
                  staff.payRate == 0
                      ? 'N/A'
                      : '₹${staff.payRate.toStringAsFixed(2)} / ${staff.paymentType.toLowerCase() == 'salary' ? 'month' : (staff.paymentType.toLowerCase() == 'daily' ? 'day' : 'hour')}'),
              _buildDetailRow(theme, Icons.access_time, 'Shift Start',
                  staff.shiftStartTime.isEmpty ? '09:00' : staff.shiftStartTime),
              if (staff.paymentType == 'Salary')
                _buildDetailRow(
                    theme,
                    Icons.calendar_month_outlined,
                    'Salary Payday',
                    '${staff.salaryPayday}${_getDaySuffix(staff.salaryPayday)} of month'),
            ],
          ),
        ),
      ],
    );
  }

  String _getDaySuffix(int day) {
    if (day >= 11 && day <= 13) return 'th';
    switch (day % 10) {
      case 1: return 'st';
      case 2: return 'nd';
      case 3: return 'rd';
      default: return 'th';
    }
  }

  Widget _buildDetailRow(
      ThemeData theme, IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, color: theme.primaryColor, size: 20),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.bodySmall),
                Text(value, style: theme.textTheme.bodyLarge),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --- NEW SPLIT-VIEW ATTENDANCE TAB ---
class _AttendanceHistoryTab extends StatefulWidget {
  final String restaurantId;
  final Staff staff;

  const _AttendanceHistoryTab({required this.restaurantId, required this.staff});

  @override
  State<_AttendanceHistoryTab> createState() => _AttendanceHistoryTabState();
}

class _AttendanceHistoryTabState extends State<_AttendanceHistoryTab> {
  DateTime _focusedMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _selectedDay =
  DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  Map<DateTime, Attendance> _attendanceEvents = {};
  Attendance? _selectedDayAttendance;
  StreamSubscription? _attendanceSubscription;

  @override
  void initState() {
    super.initState();
    _fetchMonthData();
  }

  @override
  void dispose() {
    _attendanceSubscription?.cancel();
    super.dispose();
  }

  void _fetchMonthData() {
    _attendanceSubscription?.cancel();
    final startOfMonth = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final endOfMonth = DateTime(
        _focusedMonth.year, _focusedMonth.month + 1, 0, 23, 59, 59);

    _attendanceSubscription = FirebaseFirestore.instance
        .collection('restaurants')
        .doc(widget.restaurantId)
        .collection('attendance')
        .where('staffId', isEqualTo: widget.staff.id)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth))
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endOfMonth))
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        setState(() {
          _attendanceEvents = {
            for (var doc in snapshot.docs)
              (doc['date'] as Timestamp)
                  .toDate()
                  .copyWith(
                  hour: 0,
                  minute: 0,
                  second: 0,
                  millisecond: 0,
                  microsecond: 0): Attendance.fromFirestore(doc)
          };
          _updateSelectedDayAttendance();
        });
      }
    });
  }

  void _updateSelectedDayAttendance() {
    final normalized =
    DateTime(_selectedDay.year, _selectedDay.month, _selectedDay.day);
    setState(() {
      _selectedDayAttendance = _attendanceEvents[normalized];
    });
  }

  void _onDaySelected(DateTime day) {
    setState(() {
      _selectedDay = day;
      _updateSelectedDayAttendance();
    });
  }

  void _onMonthChanged(int increment) {
    setState(() {
      _focusedMonth =
          DateTime(_focusedMonth.year, _focusedMonth.month + increment, 1);
      _selectedDay = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
      _attendanceEvents.clear();
    });
    _fetchMonthData();
  }

  void _openEditDialog() {
    showDialog(
      context: context,
      builder: (context) => _EditAttendanceDialog(
        restaurantId: widget.restaurantId,
        staff: widget.staff,
        date: _selectedDay,
        existingAttendance: _selectedDayAttendance,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // --- RESPONSIVE LAYOUT BUILDER ---
    return LayoutBuilder(
      builder: (context, constraints) {
        // Use a breakpoint to decide between split view and list view
        bool isWide = constraints.maxWidth > 700;

        if (isWide) {
          // --- SPLIT VIEW (50% Calendar / 50% Details) ---
          return Padding(
            padding: const EdgeInsets.all(24.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left Side: Calendar (Takes full height)
                Expanded(
                  flex: 1,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _buildCalendarHeader(context),
                        const SizedBox(height: 16),
                        // Calendar Grid needs to take remaining space
                        Expanded(
                          child: _buildCalendarGrid(context, isCompact: false),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 24),
                // Right Side: Details (Takes full height)
                Expanded(
                  flex: 1,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                    ),
                    padding: const EdgeInsets.all(24),
                    child: _buildDayTimeline(context),
                  ),
                ),
              ],
            ),
          );
        } else {
          // --- MOBILE LIST VIEW (Original Layout) ---
          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            children: [
              _buildCalendarHeader(context),
              const SizedBox(height: 16),
              // On mobile, grid wraps content height, doesn't expand
              _buildCalendarGrid(context, isCompact: true),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 8),
              _buildDayTimeline(context),
            ],
          );
        }
      },
    );
  }

  Widget _buildCalendarHeader(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(DateFormat.yMMMM().format(_focusedMonth),
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold)),
        Row(
          children: [
            IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () => _onMonthChanged(-1)),
            IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () => _onMonthChanged(1)),
          ],
        ),
      ],
    );
  }

  Widget _buildCalendarGrid(BuildContext context, {required bool isCompact}) {
    final theme = Theme.of(context);
    final daysInMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0).day;
    final firstWeekday = DateTime(_focusedMonth.year, _focusedMonth.month, 1).weekday;
    final offset = firstWeekday == 7 ? 0 : firstWeekday;
    final weekDays = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

    // In expanded mode, we want cells to stretch to fill height
    // We calculate a childAspectRatio based on available height (not easy in standard GridView)
    // OR we use LayoutBuilder inside Expanded to calculate fit.

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: weekDays.map((d) => Expanded(
            child: Text(d, textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold, color: Colors.grey)),
          )).toList(),
        ),
        const SizedBox(height: 12),
        // Use Flexible/Expanded for the grid if not compact
        isCompact
            ? _buildGrid(theme, daysInMonth, offset, 1.3) // Fixed ratio for mobile
            : Expanded(
          child: LayoutBuilder(builder: (context, constraints) {
            // Calculate aspect ratio to fill the height
            // 5 or 6 rows usually.
            // Estimate rows: (days + offset) / 7
            int rows = ((daysInMonth + offset) / 7).ceil();
            double cellHeight = (constraints.maxHeight - (rows * 8)) / rows;
            double cellWidth = (constraints.maxWidth - (6 * 4)) / 7;
            double ratio = cellWidth / cellHeight;

            return _buildGrid(theme, daysInMonth, offset, ratio);
          }),
        ),
      ],
    );
  }

  Widget _buildGrid(ThemeData theme, int daysInMonth, int offset, double ratio) {
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(), // No internal scroll
      shrinkWrap: true, // Only if inside scrollable parent (mobile)
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        childAspectRatio: ratio,
        mainAxisSpacing: 8,
        crossAxisSpacing: 4,
      ),
      itemCount: daysInMonth + offset,
      itemBuilder: (context, index) {
        if (index < offset) return const SizedBox.shrink();

        final day = index - offset + 1;
        final date = DateTime(_focusedMonth.year, _focusedMonth.month, day);
        final attendance = _attendanceEvents[date];

        final isSelected = date.year == _selectedDay.year &&
            date.month == _selectedDay.month &&
            date.day == _selectedDay.day;

        final isToday = DateTime.now().year == date.year &&
            DateTime.now().month == date.month &&
            DateTime.now().day == date.day;

        Color? dotColor;
        if (attendance != null) {
          if (attendance.status == 'Present') dotColor = Colors.green;
          else if (attendance.status == 'Late') dotColor = Colors.orange;
          else if (attendance.status == 'Absent') dotColor = Colors.red;
          else if (attendance.status == 'Early') dotColor = Colors.blue;
          else if (attendance.status == 'Half Day') dotColor = Colors.purple;
        }

        return GestureDetector(
          onTap: () => _onDaySelected(date),
          behavior: HitTestBehavior.opaque,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: isSelected
                    ? BoxDecoration(
                  color: theme.primaryColor,
                  shape: BoxShape.circle,
                )
                    : null,
                alignment: Alignment.center,
                child: Text(
                  '$day',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: isSelected
                        ? Colors.white
                        : (isToday ? theme.primaryColor : theme.textTheme.bodyMedium?.color),
                    fontWeight: isSelected || isToday
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              if (dotColor != null)
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                  ),
                )
              else
                const SizedBox(height: 5),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDayTimeline(BuildContext context) {
    final theme = Theme.of(context);
    final att = _selectedDayAttendance;
    final isFuture = _selectedDay.isAfter(DateTime.now());

    final dateString = DateFormat.yMMMMEEEEd().format(_selectedDay);

    if (att == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center, // Center vertically in empty state
        children: [
          _buildTimelineHeader(theme, dateString),
          const SizedBox(height: 40), // More space
          Center(
            child: Column(
              children: [
                Icon(Icons.event_note, size: 48, color: theme.dividerColor),
                const SizedBox(height: 16),
                Text("No records for this day.",
                    style: theme.textTheme.bodyLarge), // Larger text
                const SizedBox(height: 24),
                if (!isFuture)
                  ElevatedButton.icon( // More prominent button
                    onPressed: _openEditDialog,
                    icon: const Icon(Icons.add),
                    label: const Text("Add Attendance"),
                  ),
              ],
            ),
          )
        ],
      );
    }

    String checkIn = att.checkIn != null ? DateFormat.jm().format(att.checkIn!) : '--:--';
    String checkOut = att.checkOut != null ? DateFormat.jm().format(att.checkOut!) : '--:--';
    String duration = '--';
    if (att.checkIn != null && att.checkOut != null) {
      final diff = att.checkOut!.difference(att.checkIn!);
      duration = '${diff.inHours}h ${diff.inMinutes.remainder(60)}m';
    } else if (att.checkIn != null) {
      duration = 'In Progress';
    }

    Color statusColor = Colors.grey;
    if (att.status == 'Present') statusColor = Colors.green;
    else if (att.status == 'Late') statusColor = Colors.orange;
    else if (att.status == 'Absent') statusColor = Colors.red;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(dateString, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            IconButton(onPressed: _openEditDialog, icon: const Icon(Icons.edit, size: 20), padding: EdgeInsets.zero,),
          ],
        ),
        const SizedBox(height: 32), // More spacing
        // Status Row
        Row(
          children: [
            Container(width: 4, height: 50, color: statusColor, margin: const EdgeInsets.only(right: 16)),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(att.status.toUpperCase(), style: theme.textTheme.bodyMedium?.copyWith(color: statusColor, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                const SizedBox(height: 8),
                Text("Total: $duration", style: theme.textTheme.headlineSmall), // Larger Total
              ],
            )
          ],
        ),
        const SizedBox(height: 40), // More spacing
        // Timeline
        _buildTimelineItem(theme, "Check In", checkIn, Icons.login, isFirst: true),
        _buildTimelineItem(theme, "Check Out", checkOut, Icons.logout, isLast: true),
      ],
    );
  }

  Widget _buildTimelineHeader(ThemeData theme, String text) {
    return Text(text, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold));
  }

  Widget _buildTimelineItem(ThemeData theme, String title, String time, IconData icon, {bool isFirst = false, bool isLast = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 50,
          child: Column(
            children: [
              Container(width: 2, height: 15, color: isFirst ? Colors.transparent : theme.dividerColor),
              Container(
                padding: const EdgeInsets.all(10), // Larger circle
                decoration: BoxDecoration(color: theme.scaffoldBackgroundColor, shape: BoxShape.circle, border: Border.all(color: theme.dividerColor)),
                child: Icon(icon, size: 18, color: theme.textTheme.bodyMedium?.color),
              ),
              Container(width: 2, height: 40, color: isLast ? Colors.transparent : theme.dividerColor),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 12.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                Text(time, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        )
      ],
    );
  }
}

// --- DIALOG FOR EDITING ATTENDANCE (Unchanged) ---
class _EditAttendanceDialog extends StatefulWidget {
  final String restaurantId;
  final Staff staff;
  final DateTime date;
  final Attendance? existingAttendance;

  const _EditAttendanceDialog({
    required this.restaurantId,
    required this.staff,
    required this.date,
    this.existingAttendance,
  });

  @override
  State<_EditAttendanceDialog> createState() => _EditAttendanceDialogState();
}

class _EditAttendanceDialogState extends State<_EditAttendanceDialog> {
  String _status = 'Absent';
  TimeOfDay? _checkIn;
  TimeOfDay? _checkOut;
  final List<String> _statuses = ['Present', 'Late', 'Absent', 'Half Day', 'Holiday'];

  @override
  void initState() {
    super.initState();
    if (widget.existingAttendance != null) {
      _status = widget.existingAttendance!.status.isNotEmpty ? widget.existingAttendance!.status : 'Present';
      if (widget.existingAttendance!.checkIn != null) {
        _checkIn = TimeOfDay.fromDateTime(widget.existingAttendance!.checkIn!);
      }
      if (widget.existingAttendance!.checkOut != null) {
        _checkOut = TimeOfDay.fromDateTime(widget.existingAttendance!.checkOut!);
      }
    } else {
      _status = 'Present';
      final parts = widget.staff.shiftStartTime.split(':');
      _checkIn = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    }
  }

  void _calculateAutoStatus() {
    if (_checkIn == null) return;
    final parts = widget.staff.shiftStartTime.split(':');
    final shiftStart = DateTime(0, 1, 1, int.parse(parts[0]), int.parse(parts[1]));
    final actualStart = DateTime(0, 1, 1, _checkIn!.hour, _checkIn!.minute);

    if (actualStart.isAfter(shiftStart.add(const Duration(minutes: 15)))) {
      setState(() => _status = 'Late');
    } else {
      setState(() => _status = 'Present');
    }
  }

  Future<void> _pickTime(bool isCheckIn) async {
    final initial = isCheckIn ? _checkIn : _checkOut;
    final picked = await showTimePicker(
      context: context,
      initialTime: initial ?? TimeOfDay.now(),
    );

    if (picked != null) {
      setState(() {
        if (isCheckIn) {
          _checkIn = picked;
          _calculateAutoStatus();
        } else {
          _checkOut = picked;
        }
      });
    }
  }

  Future<void> _save() async {
    final ref = FirebaseFirestore.instance.collection('restaurants').doc(widget.restaurantId).collection('attendance');

    DateTime? inDate;
    DateTime? outDate;

    if (_checkIn != null) {
      inDate = DateTime(widget.date.year, widget.date.month, widget.date.day, _checkIn!.hour, _checkIn!.minute);
    }
    if (_checkOut != null) {
      outDate = DateTime(widget.date.year, widget.date.month, widget.date.day, _checkOut!.hour, _checkOut!.minute);
    }

    final data = {
      'staffId': widget.staff.id,
      'date': Timestamp.fromDate(widget.date),
      'status': _status,
      'checkIn': inDate != null ? Timestamp.fromDate(inDate) : null,
      'checkOut': outDate != null ? Timestamp.fromDate(outDate) : null,
    };

    if (widget.existingAttendance == null) {
      await ref.add(data);
    } else {
      await ref.doc(widget.existingAttendance!.id).update(data);
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    if (widget.existingAttendance != null) {
      await FirebaseFirestore.instance
          .collection('restaurants')
          .doc(widget.restaurantId)
          .collection('attendance')
          .doc(widget.existingAttendance!.id)
          .delete();
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit ${DateFormat('MMM d').format(widget.date)}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              value: _status,
              decoration: const InputDecoration(labelText: 'Status'),
              items: _statuses.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
              onChanged: (val) => setState(() => _status = val!),
            ),
            const SizedBox(height: 16),
            ListTile(
              title: const Text('Check In'),
              subtitle: Text(_checkIn?.format(context) ?? 'Not Set'),
              trailing: const Icon(Icons.access_time),
              onTap: () => _pickTime(true),
              tileColor: Colors.grey.withOpacity(0.1),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            const SizedBox(height: 8),
            ListTile(
              title: const Text('Check Out'),
              subtitle: Text(_checkOut?.format(context) ?? 'Not Set'),
              trailing: const Icon(Icons.access_time),
              onTap: () => _pickTime(false),
              tileColor: Colors.grey.withOpacity(0.1),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ],
        ),
      ),
      actions: [
        if (widget.existingAttendance != null)
          TextButton(onPressed: _delete, child: Text('Clear', style: TextStyle(color: Theme.of(context).colorScheme.error))),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

class _PaymentHistoryTab extends StatelessWidget {
  final String restaurantId;
  final Staff staff;

  const _PaymentHistoryTab({required this.restaurantId, required this.staff});

  void _logPayment(BuildContext context) {
    showStaffPaymentDialog(context, staff, restaurantId);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    String fabLabel = 'Log Payment';
    IconData fabIcon = Icons.add;
    switch (staff.paymentType) {
      case 'Salary':
        fabLabel = 'Pay Salary';
        fabIcon = Icons.calendar_month_outlined;
        break;
      case 'Daily':
        fabLabel = 'Log Daily Pay';
        fabIcon = Icons.today_outlined;
        break;
      case 'Hourly':
        fabLabel = 'Log Hourly Pay';
        fabIcon = Icons.access_time_outlined;
        break;
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('restaurants')
            .doc(restaurantId)
            .collection('staff')
            .doc(staff.id)
            .collection('payments')
            .orderBy('paidAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('No payment history found.'));
          }

          final payments = snapshot.data!.docs
              .map((doc) => StaffPayment.fromFirestore(doc))
              .toList();

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: payments.length,
            itemBuilder: (context, index) {
              final payment = payments[index];
              final String title = '₹${payment.amount.toStringAsFixed(2)}';

              String subtitle =
                  'Paid on: ${DateFormat.yMMMd().add_jm().format(payment.paidAt)}';

              if (payment.paymentType == 'Salary' && payment.payPeriodStart != null) {
                subtitle += '\nFor: ${DateFormat.yMMMM().format(payment.payPeriodStart!)}';
              } else if (payment.payPeriodStart != null && payment.payPeriodEnd != null) {
                final start = payment.payPeriodStart!;
                final end = payment.payPeriodEnd!;
                if (start.year == end.year && start.month == end.month && start.day == end.day) {
                  subtitle += '\nFor: ${DateFormat.yMMMd().format(start)}';
                } else {
                  subtitle += '\nPeriod: ${DateFormat.yMd().format(start)} - ${DateFormat.yMd().format(end)}';
                }
              }
              if (payment.notes.isNotEmpty) {
                subtitle += '\nNotes: ${payment.notes}';
              }

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: theme.primaryColor.withOpacity(0.1),
                    child: Icon(Icons.attach_money, color: theme.primaryColor),
                  ),
                  title: Text(
                    title,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  subtitle: Text(subtitle),
                  trailing:
                  const Icon(Icons.check_circle, color: Colors.green),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _logPayment(context),
        icon: Icon(fabIcon),
        label: Text(fabLabel),
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