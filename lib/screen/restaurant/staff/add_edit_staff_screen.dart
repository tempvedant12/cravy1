import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

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
  late String _name;
  late String _role;
  late String _phone;
  late String _email;

  @override
  void initState() {
    super.initState();
    _name = widget.staff?.name ?? '';
    _role = widget.staff?.role ?? 'Staff';
    _phone = widget.staff?.phone ?? '';
    _email = widget.staff?.email ?? '';
  }

  void _saveStaff() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      final staffData = {
        'name': _name,
        'role': _role,
        'phone': _phone,
        'email': _email,
      };
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
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.staff == null ? 'Add Staff' : 'Edit Staff'),
        actions: [
          if (widget.staff != null)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () async {
                await FirebaseFirestore.instance
                    .collection('restaurants')
                    .doc(widget.restaurantId)
                    .collection('staff')
                    .doc(widget.staff!.id)
                    .delete();
                Navigator.of(context).pop();
              },
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              initialValue: _name,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: (value) =>
              value!.isEmpty ? 'Please enter a name' : null,
              onSaved: (value) => _name = value!,
            ),
            TextFormField(
              initialValue: _role,
              decoration: const InputDecoration(labelText: 'Role'),
              validator: (value) =>
              value!.isEmpty ? 'Please enter a role' : null,
              onSaved: (value) => _role = value!,
            ),
            TextFormField(
              initialValue: _phone,
              decoration: const InputDecoration(labelText: 'Phone'),
              keyboardType: TextInputType.phone,
              onSaved: (value) => _phone = value!,
            ),
            TextFormField(
              initialValue: _email,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
              onSaved: (value) => _email = value!,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _saveStaff,
        child: const Icon(Icons.save),
      ),
    );
  }
}