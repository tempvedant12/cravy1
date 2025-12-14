// lib/screen/restaurant/staff/add_edit_staff_screen.dart

import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';

import 'staff_and_roles_screen.dart';

class AddEditStaffScreen extends StatefulWidget {
  final String restaurantId;
  final Staff? staff;

  const AddEditStaffScreen({super.key, required this.restaurantId, this.staff});

  @override
  _AddEditStaffScreenState createState() => _AddEditStaffScreenState();
}

class _AddEditStaffScreenState extends State<AddEditStaffScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  late String _name;
  late String _role;
  late String _phone;
  late String _email;
  late double _payRate;
  late String _paymentType;
  late TextEditingController _payRateController;
  late int _salaryPayday;
  late TextEditingController _paydayController;

  // --- NEW: Shift Start Time ---
  TimeOfDay _shiftStartTime = const TimeOfDay(hour: 9, minute: 0);
  // -----------------------------

  final List<String> _paymentTypes = ['Salary', 'Hourly', 'Daily', 'N/A'];

  @override
  void initState() {
    super.initState();
    _name = widget.staff?.name ?? '';
    _role = widget.staff?.role ?? 'Staff';
    _phone = widget.staff?.phone ?? '';
    _email = widget.staff?.email ?? '';
    _payRate = widget.staff?.payRate ?? 0.0;
    _paymentType = (widget.staff?.paymentType.isEmpty ?? true)
        ? 'N/A'
        : widget.staff!.paymentType;
    _payRateController =
        TextEditingController(text: _payRate == 0 ? '' : _payRate.toString());
    _salaryPayday = widget.staff?.salaryPayday ?? 1;
    _paydayController = TextEditingController(text: _salaryPayday.toString());

    // --- NEW: Initialize Shift Time from existing data ---
    if (widget.staff != null && widget.staff!.shiftStartTime.isNotEmpty) {
      final parts = widget.staff!.shiftStartTime.split(':');
      if (parts.length == 2) {
        _shiftStartTime = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
      }
    }
    // ----------------------------------
  }

  @override
  void dispose() {
    _payRateController.dispose();
    _paydayController.dispose();
    super.dispose();
  }

  // --- NEW: Helper to select time ---
  Future<void> _selectShiftTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _shiftStartTime,
    );
    if (picked != null && picked != _shiftStartTime) {
      setState(() {
        _shiftStartTime = picked;
      });
    }
  }
  // ---------------------------------

  void _saveStaff() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      setState(() => _isLoading = true);

      // Format time as HH:mm for saving
      final String formattedShiftTime =
          '${_shiftStartTime.hour.toString().padLeft(2, '0')}:${_shiftStartTime.minute.toString().padLeft(2, '0')}';

      final staffData = {
        'name': _name,
        'role': _role,
        'phone': _phone,
        'email': _email,
        'payRate': _payRate,
        'paymentType': _paymentType,
        'salaryPayday': _paymentType == 'Salary' ? _salaryPayday : 1,
        'shiftStartTime': formattedShiftTime, // <-- SAVE THIS
      };
      try {
        if (widget.staff == null) {
          await FirebaseFirestore.instance
              .collection('restaurants')
              .doc(widget.restaurantId)
              .collection('staff')
              .add(staffData);
        } else {
          await FirebaseFirestore.instance
              .collection('restaurants')
              .doc(widget.restaurantId)
              .collection('staff')
              .doc(widget.staff!.id)
              .update(staffData);
        }
        if (mounted) Navigator.of(context).pop();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error saving staff: ${e.toString()}'))
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _deleteStaff() async {
    final bool? confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Staff?'),
        content: Text(
            'Are you sure you want to delete "${widget.staff!.name}"? This action cannot be undone.'),
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
      setState(() => _isLoading = true);
      try {
        await FirebaseFirestore.instance
            .collection('restaurants')
            .doc(widget.restaurantId)
            .collection('staff')
            .doc(widget.staff!.id)
            .delete();
        if (mounted) Navigator.of(context).pop();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error deleting staff: ${e.toString()}'))
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(widget.staff == null ? 'Add Staff' : 'Edit Staff'),
        backgroundColor: theme.scaffoldBackgroundColor.withOpacity(0.85),
        elevation: 0,
        actions: [
          if (widget.staff != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete Staff',
              onPressed: _deleteStaff,
            ),
        ],
      ),
      body: Stack(
        children: [
          const _StaticBackground(),
          SafeArea(
            child: Form(
              key: _formKey,
              child: AnimationLimiter(
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: AnimationConfiguration.toStaggeredList(
                    duration: const Duration(milliseconds: 375),
                    childAnimationBuilder: (widget) => SlideAnimation(
                      verticalOffset: 50.0,
                      child: FadeInAnimation(child: widget),
                    ),
                    children: [
                      _buildGlassTextField(
                        initialValue: _name,
                        label: 'Name',
                        icon: Icons.person_outline,
                        validator: (value) =>
                        value!.isEmpty ? 'Please enter a name' : null,
                        onSaved: (value) => _name = value!,
                      ),
                      const SizedBox(height: 20),
                      _buildGlassTextField(
                        initialValue: _role,
                        label: 'Role',
                        icon: Icons.badge_outlined,
                        validator: (value) =>
                        value!.isEmpty ? 'Please enter a role' : null,
                        onSaved: (value) => _role = value!,
                      ),
                      const SizedBox(height: 20),
                      _buildGlassTextField(
                        initialValue: _phone,
                        label: 'Phone',
                        icon: Icons.phone_outlined,
                        keyboardType: TextInputType.phone,
                        onSaved: (value) => _phone = value!,
                      ),
                      const SizedBox(height: 20),
                      _buildGlassTextField(
                        initialValue: _email,
                        label: 'Email',
                        icon: Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress,
                        onSaved: (value) => _email = value!,
                      ),

                      // --- NEW: Shift Start Time Picker UI ---
                      const SizedBox(height: 20),
                      GestureDetector(
                        onTap: _selectShiftTime,
                        child: AbsorbPointer(
                          child: _buildGlassTextField(
                            label: 'Shift Start Time',
                            icon: Icons.access_time,
                            // Convert TimeOfDay to display string (e.g. 9:00 AM)
                            controller: TextEditingController(text: _shiftStartTime.format(context)),
                          ),
                        ),
                      ),
                      // ------------------------------------

                      const Divider(height: 40),
                      _buildGlassDropdownField(
                        value: _paymentType,
                        label: 'Payment Type',
                        icon: Icons.schedule_outlined,
                        items: _paymentTypes.map((String type) {
                          return DropdownMenuItem<String>(
                            value: type,
                            child: Text(type),
                          );
                        }).toList(),
                        onChanged: (String? newValue) {
                          setState(() {
                            _paymentType = newValue!;
                          });
                        },
                        onSaved: (value) => _paymentType = value ?? 'N/A',
                      ),
                      const SizedBox(height: 20),
                      _buildGlassTextField(
                        controller: _payRateController,
                        label: 'Pay Rate (₹)',
                        icon: Icons.payments_outlined,
                        keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'^\d+\.?\d{0,2}')),
                        ],
                        suffixText: _paymentType == 'N/A'
                            ? ''
                            : '/ ${_paymentType.toLowerCase() == 'salary' ? 'month' : (_paymentType.toLowerCase() == 'daily' ? 'day' : 'hour')}',
                        onSaved: (value) =>
                        _payRate = double.tryParse(value ?? '0.0') ?? 0.0,
                      ),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                        child: _paymentType == 'Salary'
                            ? Padding(
                          padding: const EdgeInsets.only(top: 20.0),
                          child: _buildGlassTextField(
                            controller: _paydayController,
                            label: 'Salary Payday (e.g., 1-31)',
                            icon: Icons.calendar_today_outlined,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(2),
                            ],
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter a day';
                              }
                              final day = int.tryParse(value);
                              if (day == null || day < 1 || day > 31) {
                                return 'Enter a valid day (1-31)';
                              }
                              return null;
                            },
                            onSaved: (value) =>
                            _salaryPayday = int.tryParse(value ?? '1') ?? 1,
                          ),
                        )
                            : const SizedBox.shrink(),
                      ),
                      const SizedBox(height: 40),
                      _isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : ElevatedButton.icon(
                        onPressed: _saveStaff,
                        icon: const Icon(Icons.save_outlined),
                        label: Text(widget.staff == null
                            ? 'Add Staff'
                            : 'Save Changes'),
                        style: ElevatedButton.styleFrom(
                          padding:
                          const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassTextField({
    TextEditingController? controller,
    String? initialValue,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? suffixText,
    FormFieldValidator<String>? validator,
    FormFieldSetter<String>? onSaved,
  }) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withOpacity(0.3),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: TextFormField(
          controller: controller,
          initialValue: initialValue,
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: Icon(icon, size: 22),
            suffixText: suffixText,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.fromLTRB(0, 18, 16, 18),
            labelStyle: theme.textTheme.bodyLarge,
          ),
          style: theme.textTheme.bodyLarge,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          validator: validator,
          onSaved: onSaved,
        ),
      ),
    );
  }

  Widget _buildGlassDropdownField<T>({
    required T value,
    required String label,
    required IconData icon,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
    FormFieldSetter<T>? onSaved,
  }) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withOpacity(0.3),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: DropdownButtonFormField<T>(
          value: value,
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: Icon(icon, size: 22),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.fromLTRB(0, 18, 16, 18),
            labelStyle: theme.textTheme.bodyLarge,
          ),
          items: items,
          onChanged: onChanged,
          onSaved: onSaved,
          dropdownColor: theme.colorScheme.surface,
          style: theme.textTheme.bodyLarge,
        ),
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