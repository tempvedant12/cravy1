import 'dart:ui'; // Added for BackdropFilter
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cravy/screen/restaurant/staff/add_edit_staff_screen.dart';
import 'package:cravy/screen/restaurant/staff/staff_and_roles_screen.dart';
import 'package:cravy/screen/restaurant/staff/staff_payment_dialogs.dart';
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
                // --- MODIFIED: Pass staff to attendance tab ---
                FutureBuilder<Staff>(
                  future: _staffFuture,
                  builder: (context, snapshot) {
                    final staffData = snapshot.data ?? widget.staff;
                    return _AttendanceHistoryTab(
                      restaurantId: widget.restaurantId,
                      staff: staffData, // Pass the full staff object
                    );
                  },
                ),
                // ---------------------------------------------
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
                  // --- FIX: Added 'daily' logic ---
                      : '₹${staff.payRate.toStringAsFixed(2)} / ${staff.paymentType.toLowerCase() == 'salary' ? 'month' : (staff.paymentType.toLowerCase() == 'daily' ? 'day' : 'hour')}'),
              // --- NEW: Show Salary Payday ---
              if (staff.paymentType == 'Salary')
                _buildDetailRow(
                    theme,
                    Icons.calendar_month_outlined,
                    'Salary Payday',
                    '${staff.salaryPayday.toString()}${_getDaySuffix(staff.salaryPayday)} of the month'
                ),
              // ---------------------------------
            ],
          ),
        ),
      ],
    );
  }

  String _getDaySuffix(int day) {
    if (day >= 11 && day <= 13) {
      return 'th';
    }
    switch (day % 10) {
      case 1:
        return 'st';
      case 2:
        return 'nd';
      case 3:
        return 'rd';
      default:
        return 'th';
    }
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
  final Staff staff; // <-- Changed from staffId to full Staff object

  const _AttendanceHistoryTab(
      {required this.restaurantId, required this.staff});

  @override
  State<_AttendanceHistoryTab> createState() => _AttendanceHistoryTabState();
}

class _AttendanceHistoryTabState extends State<_AttendanceHistoryTab> {
  DateTime _focusedMonth =
  DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime? _selectedDay =
  DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);

  Map<DateTime, Attendance> _attendanceEvents = {};
  // --- NEW: Store payments that overlap with this month ---
  List<StaffPayment> _monthPayments = [];
  // ------------------------------------------------------
  Attendance? _selectedDayAttendance;

  StreamSubscription? _attendanceSubscription;
  StreamSubscription? _paymentSubscription; // <-- NEW

  @override
  void initState() {
    super.initState();
    _fetchMonthData(); // <-- Renamed
  }

  @override
  void dispose() {
    _attendanceSubscription?.cancel();
    _paymentSubscription?.cancel(); // <-- NEW
    super.dispose();
  }

  // --- MODIFIED: Fetches both attendance and payments ---
  void _fetchMonthData() {
    _attendanceSubscription?.cancel();
    _paymentSubscription?.cancel();

    final startOfMonth = _focusedMonth;
    final endOfMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0)
        .add(const Duration(days: 1));

    // 1. Fetch Attendance
    _attendanceSubscription = FirebaseFirestore.instance
        .collection('restaurants')
        .doc(widget.restaurantId)
        .collection('attendance')
        .where('staffId', isEqualTo: widget.staff.id) // Use staff.id
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

    // 2. Fetch Payments
    _paymentSubscription = FirebaseFirestore.instance
        .collection('restaurants')
        .doc(widget.restaurantId)
        .collection('staff')
        .doc(widget.staff.id)
        .collection('payments')
    // Find payments where the *period* overlaps with the *month*
        .where('payPeriodEnd', isGreaterThanOrEqualTo: startOfMonth)
    // We also need to check the start, but Firestore can't do two range filters on different fields.
    // So we filter by end date and will manually filter by start date in the listener.
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        setState(() {
          _monthPayments = snapshot.docs
              .map((doc) => StaffPayment.fromFirestore(doc))
              .where((p) => p.payPeriodStart != null && p.payPeriodStart!.isBefore(endOfMonth)) // Manual filter
              .toList();
        });
      }
    });
  }
  // ----------------------------------------------------

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
      _monthPayments = []; // Clear old payment data
    });
    _fetchMonthData(); // <-- Renamed
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
        'staffId': widget.staff.id,
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
        childAspectRatio: 1.0,
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

        // --- NEW: Check if this day is part of a paid period ---
        final bool isPaid = _monthPayments.any((p) {
          // Normalize dates to ignore time
          final startDate = DateTime(p.payPeriodStart!.year, p.payPeriodStart!.month, p.payPeriodStart!.day);
          final endDate = DateTime(p.payPeriodEnd!.year, p.payPeriodEnd!.month, p.payPeriodEnd!.day);
          return !date.isBefore(startDate) && !date.isAfter(endDate);
        });
        // ------------------------------------------------------

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
                // --- NEW: Show dollar sign if paid ---
                if (isPaid)
                  Positioned(
                    top: 4,
                    left: 4,
                    child: Icon(
                      Icons.attach_money,
                      color: Colors.green.withOpacity(0.8),
                      size: 14,
                    ),
                  ),
                // -------------------------------------
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

    // --- FIX: Shorter button text to prevent overflow ---
    final String buttonText = status == null
        ? 'Mark Present'
        : (status ? 'Mark Absent' : 'Mark Present');
    // ----------------------------------------------------

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
              // --- FIX: Use new button text ---
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

  // --- MODIFIED: Call the new public function ---
  void _logPayment(BuildContext context) {
    showStaffPaymentDialog(context, staff, restaurantId);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // --- NEW: Dynamic FAB label ---
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
    // ----------------------------

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

          // --- MODIFIED: Use new StaffPayment model ---
          final payments = snapshot.data!.docs
              .map((doc) => StaffPayment.fromFirestore(doc))
              .toList();

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: payments.length,
            itemBuilder: (context, index) {
              final payment = payments[index];
              final String title = '₹${payment.amount.toStringAsFixed(2)}';

              // --- NEW: Detailed subtitle ---
              String subtitle =
                  'Paid on: ${DateFormat.yMMMd().add_jm().format(payment.paidAt)}';

              if (payment.paymentType == 'Salary' && payment.payPeriodStart != null) {
                subtitle += '\nFor: ${DateFormat.yMMMM().format(payment.payPeriodStart!)}';
              } else if (payment.payPeriodStart != null && payment.payPeriodEnd != null) {
                // Check if it's a single day
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
              // -----------------------------

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
                  subtitle: Text(subtitle), // Use new subtitle
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
        icon: Icon(fabIcon), // Use new icon
        label: Text(fabLabel), // Use new label
      ),
    );
  }
}

class _PaySalaryDialog extends StatefulWidget {
  final String restaurantId;
  final Staff staff;

  const _PaySalaryDialog({required this.restaurantId, required this.staff});

  @override
  State<_PaySalaryDialog> createState() => _PaySalaryDialogState();
}

class _PaySalaryDialogState extends State<_PaySalaryDialog> {
  late Future<List<StaffPayment>> _paymentHistoryFuture;
  Set<String> _paidMonths = {}; // Stores "YYYY-MM"
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);

  @override
  void initState() {
    super.initState();
    _paymentHistoryFuture = _fetchPaymentHistory();
  }

  Future<List<StaffPayment>> _fetchPaymentHistory() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('restaurants')
        .doc(widget.restaurantId)
        .collection('staff')
        .doc(widget.staff.id)
        .collection('payments')
        .where('paymentType', isEqualTo: 'Salary')
        .get();

    final payments = snapshot.docs.map((doc) => StaffPayment.fromFirestore(doc)).toList();
    _paidMonths = payments
        .where((p) => p.payPeriodStart != null)
        .map((p) => DateFormat('yyyy-MM').format(p.payPeriodStart!))
        .toSet();

    return payments;
  }

  Future<void> _payMonth(DateTime month) async {
    final notes = 'Salary for ${DateFormat.yMMMM().format(month)}';
    final amount = widget.staff.payRate;
    final payPeriodStart = month;
    final payPeriodEnd = DateTime(month.year, month.month + 1, 0); // Last day of the month

    await FirebaseFirestore.instance
        .collection('restaurants')
        .doc(widget.restaurantId)
        .collection('staff')
        .doc(widget.staff.id)
        .collection('payments')
        .add({
      'amount': amount,
      'notes': notes,
      'paidAt': FieldValue.serverTimestamp(),
      'payRate': widget.staff.payRate,
      'paymentType': 'Salary',
      'payPeriodStart': Timestamp.fromDate(payPeriodStart),
      'payPeriodEnd': Timestamp.fromDate(payPeriodEnd),
    });

    if (mounted) {
      Navigator.of(context).pop(); // Close the dialog
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text('Pay Salary for ${widget.staff.name}'),
      content: SizedBox(
        width: double.maxFinite,
        child: FutureBuilder<List<StaffPayment>>(
          future: _paymentHistoryFuture,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            // Generate list of last 12 months
            final months = List.generate(12, (index) {
              return DateTime(DateTime.now().year, DateTime.now().month - index, 1);
            });

            return ListView.builder(
              shrinkWrap: true,
              itemCount: months.length,
              itemBuilder: (context, index) {
                final month = months[index];
                final monthKey = DateFormat('yyyy-MM').format(month);
                final isPaid = _paidMonths.contains(monthKey);

                return ListTile(
                  title: Text(DateFormat.yMMMM().format(month)),
                  subtitle: Text('Amount: ₹${widget.staff.payRate.toStringAsFixed(2)}'),
                  trailing: isPaid
                      ? const Chip(label: Text('PAID'), backgroundColor: Colors.green)
                      : ElevatedButton(
                    onPressed: () => _payMonth(month),
                    child: const Text('Pay'),
                  ),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close')),
      ],
    );
  }
}

class _PayGenericDialog extends StatefulWidget {
  final String restaurantId;
  final Staff staff;

  const _PayGenericDialog({required this.restaurantId, required this.staff});

  @override
  State<_PayGenericDialog> createState() => _PayGenericDialogState();
}

class _PayGenericDialogState extends State<_PayGenericDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  DateTimeRange? _payPeriod;

  @override
  void initState() {
    super.initState();
    if (widget.staff.paymentType == 'Daily') {
      _payPeriod = DateTimeRange(start: DateTime.now(), end: DateTime.now());
    } else {
      // Default to the last week for hourly
      final today = DateTime.now();
      final startOfWeek = today.subtract(Duration(days: today.weekday + 6));
      _payPeriod = DateTimeRange(start: startOfWeek, end: today);
    }
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: _payPeriod,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) {
      setState(() {
        _payPeriod = picked;
      });
    }
  }

  Future<void> _savePayment() async {
    if (!_formKey.currentState!.validate()) return;
    if (_payPeriod == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a pay period.')));
      return;
    }

    final amount = double.tryParse(_amountController.text);

    await FirebaseFirestore.instance
        .collection('restaurants')
        .doc(widget.restaurantId)
        .collection('staff')
        .doc(widget.staff.id)
        .collection('payments')
        .add({
      'amount': amount,
      'notes': _notesController.text.trim(),
      'paidAt': FieldValue.serverTimestamp(),
      'payRate': widget.staff.payRate,
      'paymentType': widget.staff.paymentType,
      'payPeriodStart': Timestamp.fromDate(_payPeriod!.start),
      'payPeriodEnd': Timestamp.fromDate(_payPeriod!.end),
    });

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDaily = widget.staff.paymentType == 'Daily';

    return AlertDialog(
      title: Text('Log ${widget.staff.paymentType} Pay'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _amountController,
                decoration: const InputDecoration(labelText: 'Amount Paid (₹)'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (val) => (double.tryParse(val ?? '') ?? 0) <= 0
                    ? 'Enter a valid amount'
                    : null,
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(isDaily ? 'Pay Date' : 'Pay Period'),
                subtitle: Text(_payPeriod == null ? 'Not Set' :
                (isDaily ? DateFormat.yMMMd().format(_payPeriod!.start)
                    : '${DateFormat.yMd().format(_payPeriod!.start)} - ${DateFormat.yMd().format(_payPeriod!.end)}')),
                trailing: const Icon(Icons.calendar_today),
                onTap: _selectDateRange,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _notesController,
                decoration: InputDecoration(labelText: 'Notes (e.g., ${isDaily ? 'Bonus' : '40 hours'})'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _savePayment,
          child: const Text('Save Payment'),
        ),
      ],
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