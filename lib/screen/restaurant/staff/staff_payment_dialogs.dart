// lib/screen/restaurant/staff/staff_payment_dialogs.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cravy/screen/restaurant/staff/staff_and_roles_screen.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// --- StaffPayment Model ---
// Copied from staff_detail_screen.dart
class StaffPayment {
  final String id;
  final double amount;
  final DateTime paidAt;
  final String notes;
  final String paymentType;
  final double payRate;
  final DateTime? payPeriodStart;
  final DateTime? payPeriodEnd;

  StaffPayment({
    required this.id,
    required this.amount,
    required this.paidAt,
    required this.notes,
    required this.paymentType,
    required this.payRate,
    this.payPeriodStart,
    this.payPeriodEnd,
  });

  factory StaffPayment.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return StaffPayment(
      id: doc.id,
      amount: (data['amount'] as num?)?.toDouble() ?? 0.0,
      paidAt: (data['paidAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      notes: data['notes'] as String? ?? '',
      paymentType: data['paymentType'] as String? ?? '',
      payRate: (data['payRate'] as num?)?.toDouble() ?? 0.0,
      payPeriodStart: (data['payPeriodStart'] as Timestamp?)?.toDate(),
      payPeriodEnd: (data['payPeriodEnd'] as Timestamp?)?.toDate(),
    );
  }
}

// --- PUBLIC HELPER FUNCTION ---
/// Shows the correct payment dialog based on the staff's payment type.
void showStaffPaymentDialog(
    BuildContext context, Staff staff, String restaurantId) {
  if (staff.paymentType == 'Salary') {
    showDialog(
      context: context,
      builder: (dialogContext) => PaySalaryDialog(
        restaurantId: restaurantId,
        staff: staff,
      ),
    );
  } else {
    // Use a generic dialog for Hourly, Daily, or N/A
    showDialog(
      context: context,
      builder: (dialogContext) => PayGenericDialog(
        restaurantId: restaurantId,
        staff: staff,
      ),
    );
  }
}

// --- Dialog for paying SALARY ---
class PaySalaryDialog extends StatefulWidget {
  final String restaurantId;
  final Staff staff;

  const PaySalaryDialog({super.key, required this.restaurantId, required this.staff});

  @override
  State<PaySalaryDialog> createState() => _PaySalaryDialogState();
}

class _PaySalaryDialogState extends State<PaySalaryDialog> {
  late Future<List<StaffPayment>> _paymentHistoryFuture;
  Set<String> _paidMonths = {}; // Stores "YYYY-MM"
  DateTime _selectedMonth =
  DateTime(DateTime.now().year, DateTime.now().month, 1);

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

    final payments =
    snapshot.docs.map((doc) => StaffPayment.fromFirestore(doc)).toList();
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
    final payPeriodEnd = DateTime(month.year, month.month + 1, 0);

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
              return DateTime(
                  DateTime.now().year, DateTime.now().month - index, 1);
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
                  subtitle: Text(
                      'Amount: ₹${widget.staff.payRate.toStringAsFixed(2)}'),
                  trailing: isPaid
                      ? const Chip(
                      label: Text('PAID'), backgroundColor: Colors.green)
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

// --- Dialog for paying HOURLY/DAILY ---
class PayGenericDialog extends StatefulWidget {
  final String restaurantId;
  final Staff staff;

  const PayGenericDialog({super.key, required this.restaurantId, required this.staff});

  @override
  State<PayGenericDialog> createState() => _PayGenericDialogState();
}

class _PayGenericDialogState extends State<PayGenericDialog> {
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
      // Go back to the last Monday
      final startOfWeek = today.subtract(Duration(days: today.weekday - 1));
      _payPeriod = DateTimeRange(start: startOfWeek, end: today);
    }
  }

  Future<void> _selectDateRange() async {
    final isDaily = widget.staff.paymentType == 'Daily';

    if (isDaily) {
      final picked = await showDatePicker(
        context: context,
        initialDate: _payPeriod?.start ?? DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime.now().add(const Duration(days: 1)),
      );
      if (picked != null) {
        setState(() {
          _payPeriod = DateTimeRange(start: picked, end: picked);
        });
      }
    } else {
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
  }

  Future<void> _savePayment() async {
    if (!_formKey.currentState!.validate()) return;
    if (_payPeriod == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a pay period.')));
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
                keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
                validator: (val) => (double.tryParse(val ?? '') ?? 0) <= 0
                    ? 'Enter a valid amount'
                    : null,
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(isDaily ? 'Pay Date' : 'Pay Period'),
                subtitle: Text(_payPeriod == null
                    ? 'Not Set'
                    : (isDaily
                    ? DateFormat.yMMMd().format(_payPeriod!.start)
                    : '${DateFormat.yMd().format(_payPeriod!.start)} - ${DateFormat.yMd().format(_payPeriod!.end)}')),
                trailing: const Icon(Icons.calendar_today),
                onTap: _selectDateRange,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _notesController,
                decoration: InputDecoration(
                    labelText: 'Notes (e.g., ${isDaily ? 'Bonus' : '40 hours'})'),
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