import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'add_edit_staff_screen.dart';
import 'attendance_screen.dart';

class Staff {
  final String id;
  final String name;
  final String role;
  final String phone;
  final String email;

  Staff({
    required this.id,
    required this.name,
    required this.role,
    required this.phone,
    required this.email,
  });

  factory Staff.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return Staff(
      id: doc.id,
      name: data['name'] ?? '',
      role: data['role'] ?? 'Staff',
      phone: data['phone'] ?? '',
      email: data['email'] ?? '',
    );
  }
}

class StaffAndRolesScreen extends StatelessWidget {
  final String restaurantId;
  const StaffAndRolesScreen({super.key, required this.restaurantId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff & Roles'),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (context) =>
                    AttendanceScreen(restaurantId: restaurantId),
              ));
            },
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('restaurants')
            .doc(restaurantId)
            .collection('staff')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('No staff members found.'));
          }
          final staffList = snapshot.data!.docs
              .map((doc) => Staff.fromFirestore(doc))
              .toList();
          return ListView.builder(
            itemCount: staffList.length,
            itemBuilder: (context, index) {
              final staff = staffList[index];
              return ListTile(
                title: Text(staff.name),
                subtitle: Text(staff.role),
                trailing: IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () {
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (context) => AddEditStaffScreen(
                        restaurantId: restaurantId,
                        staff: staff,
                      ),
                    ));
                  },
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (context) =>
                AddEditStaffScreen(restaurantId: restaurantId),
          ));
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}