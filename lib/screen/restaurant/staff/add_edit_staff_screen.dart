import 'dart:ui'; // Import for UI effects
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
  bool _isLoading = false; // Added for loading state

  late String _name;
  late String _role;
  late String _phone;
  late String _email;
  // --- NEW FIELDS ---
  late double _payRate;
  late String _paymentType;
  late TextEditingController _payRateController;

  final List<String> _paymentTypes = ['Salary', 'Hourly', 'N/A'];
  // ------------------

  @override
  void initState() {
    super.initState();
    _name = widget.staff?.name ?? '';
    _role = widget.staff?.role ?? 'Staff';
    _phone = widget.staff?.phone ?? '';
    _email = widget.staff?.email ?? '';
    // --- NEW FIELDS ---
    _payRate = widget.staff?.payRate ?? 0.0;
    _paymentType = (widget.staff?.paymentType.isEmpty ?? true)
        ? 'N/A'
        : widget.staff!.paymentType;
    _payRateController =
        TextEditingController(text: _payRate == 0 ? '' : _payRate.toString());
    // ------------------
  }

  @override
  void dispose() {
    _payRateController.dispose();
    super.dispose();
  }

  void _saveStaff() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      setState(() => _isLoading = true); // Start loading

      final staffData = {
        'name': _name,
        'role': _role,
        'phone': _phone,
        'email': _email,
        'payRate': _payRate,
        'paymentType': _paymentType,
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
        if (mounted) setState(() => _isLoading = false); // Stop loading
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
      extendBodyBehindAppBar: true, // For background
      appBar: AppBar(
        title: Text(widget.staff == null ? 'Add Staff' : 'Edit Staff'),
        backgroundColor:
        theme.scaffoldBackgroundColor.withOpacity(0.85), // Glassmorphic
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
          const _StaticBackground(), // Add background
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
                        // Dynamic suffix text
                        suffixText: _paymentType == 'N/A'
                            ? ''
                            : '/ ${_paymentType.toLowerCase() == 'salary' ? 'month' : 'hour'}',
                        onSaved: (value) =>
                        _payRate = double.tryParse(value ?? '0.0') ?? 0.0,
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

  // --- NEW: Helper widget for glass text fields ---
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

  // --- NEW: Helper widget for glass dropdowns ---
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