import 'dart:ui'; // Added for BackdropFilter
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cravy/screen/restaurant/staff/add_edit_staff_screen.dart';
import 'package:cravy/screen/restaurant/staff/staff_and_roles_screen.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:async'; // Import for StreamSubscription

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
  late Future<Staff> _staffFuture; // <-- Add future for live updates

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _staffFuture = _fetchStaff(); // <-- Initialize future
  }

  // --- NEW: Function to re-fetch staff data ---
  // This is useful if the user edits the staff details and comes back
  Future<Staff> _fetchStaff() async {
    final doc = await FirebaseFirestore.instance
        .collection('restaurants')
        .doc(widget.restaurantId)
        .collection('staff')
        .doc(widget.staff.id)
        .get();

    // Fallback in case the staff member was deleted while on this screen
    if (!doc.exists) {
      return widget.staff;
    }
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
      extendBodyBehindAppBar: true, // For background
      appBar: AppBar(
        // Use a FutureBuilder to update the name if it's edited
        title: FutureBuilder<Staff>(
          future: _staffFuture,
          builder: (context, snapshot) {
            return Text(snapshot.data?.name ?? widget.staff.name);
          },
        ),
        backgroundColor:
        theme.scaffoldBackgroundColor.withOpacity(0.85), // Glassmorphic
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit Staff Member',
            onPressed: () async {
              // --- FIX: Await the future to get the latest data ---
              final staffToEdit = await _staffFuture;

              // Navigate to AddEditStaffScreen
              await Navigator.of(context).push(MaterialPageRoute(
                builder: (context) => AddEditStaffScreen(
                  restaurantId: widget.restaurantId,
                  staff: staffToEdit, // Pass the most recent data
                ),
              ));
              // --- NEW: Refresh staff data when returning ---
              if (mounted) {
                setState(() {
                  _staffFuture = _fetchStaff();
                });
              }
              // ---------------------------------------------
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
          const _StaticBackground(), // Add background
          // --- FIX: Wrap TabBarView in SafeArea ---
          SafeArea(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Use FutureBuilder to pass the latest staff data to the tabs
                FutureBuilder<Staff>(
                  future: _staffFuture,
                  builder: (context, snapshot) {
                    final staffData = snapshot.data ?? widget.staff;
                    return _buildDetailsTab(theme, staffData);
                  },
                ),
                _AttendanceHistoryTab(
                    restaurantId: widget.restaurantId,
                    staffId: widget.staff.id),
                FutureBuilder<Staff>(
                  future: _staffFuture,
                  builder: (context, snapshot) {
                    final staffData = snapshot.data ?? widget.staff;
                    return _PaymentHistoryTab(
                        restaurantId: widget.restaurantId, staff: staffData);
                  },
                ),
              ],
            ),
          ),
          // ---------------------------------------
        ],
      ),
    );
  }

  // Helper to build the glassmorphic card
  Widget _buildGlassCard({required Widget child, String? title}) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(20),
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

  // --- MODIFIED: Accepts Staff object ---
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
                      : '₹${staff.payRate.toStringAsFixed(2)} / ${staff.paymentType.toLowerCase() == 'salary' ? 'month' : 'hour'}'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRow(
      ThemeData theme, IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
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

// --- REFACTORED ATTENDANCE TAB (NOW STATEFUL WITH CALENDAR) ---
class _AttendanceHistoryTab extends StatefulWidget {
  final String restaurantId;
  final String staffId;

  const _AttendanceHistoryTab(
      {required this.restaurantId, required this.staffId});

  @override
  State<_AttendanceHistoryTab> createState() => _AttendanceHistoryTabState();
}

class _AttendanceHistoryTabState extends State<_AttendanceHistoryTab> {
  DateTime _focusedMonth =
  DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime? _selectedDay =
  DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);

  // Stores the attendance for the _focusedMonth
  Map<DateTime, Attendance> _attendanceEvents = {};
  Attendance? _selectedDayAttendance;

  StreamSubscription? _attendanceSubscription;

  @override
  void initState() {
    super.initState();
    _fetchMonthAttendance();
  }

  @override
  void dispose() {
    _attendanceSubscription?.cancel();
    super.dispose();
  }

  void _fetchMonthAttendance() {
    _attendanceSubscription?.cancel();

    final startOfMonth = _focusedMonth;
    final endOfMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0)
        .add(const Duration(days: 1));

    _attendanceSubscription = FirebaseFirestore.instance
        .collection('restaurants')
        .doc(widget.restaurantId)
        .collection('attendance')
        .where('staffId', isEqualTo: widget.staffId)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth))
        .where('date', isLessThan: Timestamp.fromDate(endOfMonth))
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        setState(() {
          _attendanceEvents = {
            for (var doc in snapshot.docs)
              (doc['date'] as Timestamp).toDate():
              Attendance.fromFirestore(doc)
          };
          _updateSelectedDayAttendance();
        });
      }
    });
  }

  void _updateSelectedDayAttendance() {
    if (_selectedDay == null) {
      _selectedDayAttendance = null;
    } else {
      // Normalize the selected day to avoid time-of-day issues
      final normalizedSelectedDay =
      DateTime(_selectedDay!.year, _selectedDay!.month, _selectedDay!.day);
      _selectedDayAttendance = _attendanceEvents[normalizedSelectedDay];
    }
  }

  void _onDaySelected(DateTime day) {
    setState(() {
      _selectedDay = day;
      _updateSelectedDayAttendance();
    });
  }

  void _onMonthChanged(bool isNext) {
    setState(() {
      _focusedMonth = DateTime(
          _focusedMonth.year, _focusedMonth.month + (isNext ? 1 : -1), 1);
      // Clear selected day when changing month
      _selectedDay = null;
      _selectedDayAttendance = null;
    });
    _fetchMonthAttendance();
  }

  Future<void> _toggleSelectedDayAttendance() async {
    if (_selectedDay == null) return;

    // Normalize the day to midnight
    final normalizedDay =
    DateTime(_selectedDay!.year, _selectedDay!.month, _selectedDay!.day);

    final attendanceRef = FirebaseFirestore.instance
        .collection('restaurants')
        .doc(widget.restaurantId)
        .collection('attendance');

    // Cannot edit attendance for future dates
    final today =
    DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    if (normalizedDay.isAfter(today)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Cannot modify attendance for a future date.')));
      return;
    }

    if (_selectedDayAttendance == null) {
      // No record, create one (mark as PRESENT)
      await attendanceRef.add({
        'staffId': widget.staffId,
        'date': Timestamp.fromDate(normalizedDay), // Use normalized day
        'isPresent': true,
      });
    } else {
      // Record exists, update it
      await attendanceRef
          .doc(_selectedDayAttendance!.id)
          .update({'isPresent': !_selectedDayAttendance!.isPresent});
    }
    // The stream will automatically update the UI
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildGlassCard(
          child: Column(
            children: [
              _buildCalendarHeader(context),
              _buildWeekHeader(context),
              _buildCalendarGrid(context),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildAttendanceToggle(context),
      ],
    );
  }

  // Helper to build the glassmorphic card
  Widget _buildGlassCard({required Widget child, String? title}) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        // Reduced padding slightly
        padding: const EdgeInsets.all(16),
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

  Widget _buildCalendarHeader(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: () => _onMonthChanged(false),
        ),
        Text(
          DateFormat.yMMMM().format(_focusedMonth),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: () => _onMonthChanged(true),
        ),
      ],
    );
  }

  Widget _buildWeekHeader(BuildContext context) {
    final daysOfWeek = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      // --- FIX: Changed aspect ratio to make header row shorter ---

      childAspectRatio: 4.0,
      children: daysOfWeek
          .map((day) => Center(
        child: Text(
          day,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ))
          .toList(),
    );
  }

  Widget _buildCalendarGrid(BuildContext context) {
    final theme = Theme.of(context);
    final daysInMonth =
        DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0).day;
    final firstDayWeekday = _focusedMonth.weekday;
    final gridStartIndex = firstDayWeekday % 7; // 0=Sunday, 1=Monday...

    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        // --- FIX: Changed aspect ratio to 1.0 to make cells square ---
        childAspectRatio: 5.0,
      ),
      itemCount: daysInMonth + gridStartIndex,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemBuilder: (context, index) {
        if (index < gridStartIndex) {
          return Container(); // Empty cell before the 1st day
        }

        final day = index - gridStartIndex + 1;
        final date = DateTime(_focusedMonth.year, _focusedMonth.month, day);
        final attendance = _attendanceEvents[date];

        final isSelected = _selectedDay != null &&
            date.year == _selectedDay!.year &&
            date.month == _selectedDay!.month &&
            date.day == _selectedDay!.day;

        return GestureDetector(
          onTap: () => _onDaySelected(date),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: isSelected
                  ? theme.primaryColor.withOpacity(0.3)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Text(day.toString()),
                if (attendance != null)
                  Positioned(
                    bottom: 4,
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color:
                        attendance.isPresent ? Colors.green : Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                  )
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAttendanceToggle(BuildContext context) {
    if (_selectedDay == null) {
      // Show a prompt if no day is selected
      return _buildGlassCard(
        child: Center(
          child: Text(
            'Select a day to view or edit attendance.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      );
    }

    final theme = Theme.of(context);
    final status = _selectedDayAttendance?.isPresent;
    final String statusText =
    status == null ? 'No Record' : (status ? 'Present' : 'Absent');
    final Color statusColor =
    status == null ? Colors.grey : (status ? Colors.green : Colors.red);
    final String buttonText = status == null
        ? 'Mark as Present'
        : (status ? 'Mark as Absent' : 'Mark as Present');

    // Disable button for future dates
    final bool isFutureDate = _selectedDay!.isAfter(
        DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day));

    return _buildGlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              DateFormat.yMMMd().format(_selectedDay!),
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              statusText,
              style: theme.textTheme.titleLarge?.copyWith(
                color: statusColor,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: isFutureDate ? null : _toggleSelectedDayAttendance,
              child: Text(isFutureDate ? 'Cannot Edit Future' : buttonText),
            )
          ],
        ));
  }
}

class _PaymentHistoryTab extends StatelessWidget {
  final String restaurantId;
  final Staff staff;

  const _PaymentHistoryTab({required this.restaurantId, required this.staff});

  void _logPayment(BuildContext context) {
    final amountController = TextEditingController();
    final notesController = TextEditingController();

    // Set default amount based on pay rate
    if (staff.paymentType == 'Salary' && staff.payRate > 0) {
      amountController.text = staff.payRate.toStringAsFixed(2);
    }

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Log Payment'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: amountController,
              decoration: const InputDecoration(labelText: 'Amount Paid (₹)'),
              keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
              validator: (val) => (double.tryParse(val ?? '') ?? 0) <= 0
                  ? 'Enter a valid amount'
                  : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: notesController,
              decoration:
              const InputDecoration(labelText: 'Notes (e.g., Nov Salary)'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final amount = double.tryParse(amountController.text);
              if (amount == null || amount <= 0) return;

              await FirebaseFirestore.instance
                  .collection('restaurants')
                  .doc(restaurantId)
                  .collection('staff')
                  .doc(staff.id)
                  .collection('payments')
                  .add({
                'amount': amount,
                'notes': notesController.text.trim(),
                'paidAt': FieldValue.serverTimestamp(),
                'payRate': staff.payRate,
                'paymentType': staff.paymentType,
              });
              Navigator.of(dialogContext).pop();
            },
            child: const Text('Save Payment'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent, // For background
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

          final payments = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: payments.length,
            itemBuilder: (context, index) {
              final payment = payments[index].data() as Map<String, dynamic>;
              final amount = (payment['amount'] as num?)?.toDouble() ?? 0.0;
              final paidAt = (payment['paidAt'] as Timestamp?)?.toDate();
              final notes = payment['notes'] as String? ?? '';

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: theme.primaryColor.withOpacity(0.1),
                    child: Icon(Icons.check, color: theme.primaryColor),
                  ),
                  title: Text(
                    '₹${amount.toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  subtitle: Text(
                    '${paidAt != null ? DateFormat.yMMMd().add_jm().format(paidAt) : 'N/A'}${notes.isNotEmpty ? '\n$notes' : ''}',
                  ),
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
        icon: const Icon(Icons.add),
        label: const Text('Log Payment'),
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