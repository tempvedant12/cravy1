import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cravy/screen/restaurant/staff/staff_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:intl/intl.dart';
import 'add_edit_staff_screen.dart';

// --- UPDATED Staff Model ---
class Staff {
  final String id;
  final String name;
  final String role;
  final String phone;
  final String email;
  final double payRate;
  final String paymentType;

  Staff({
    required this.id,
    required this.name,
    required this.role,
    required this.phone,
    required this.email,
    required this.payRate,
    required this.paymentType,
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
    );
  }
}

// --- NEW Attendance Model (simplified from old file) ---
class Attendance {
  final String id;
  final String staffId;
  final DateTime date;
  final bool isPresent;

  Attendance({
    required this.id,
    required this.staffId,
    required this.date,
    required this.isPresent,
  });

  factory Attendance.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return Attendance(
      id: doc.id,
      staffId: data['staffId'],
      date: (data['date'] as Timestamp).toDate(),
      isPresent: data['isPresent'],
    );
  }
}

// --- NEW Combined Model ---
class StaffWithAttendance {
  final Staff staff;
  final Attendance? attendance;
  final bool isPresent;

  StaffWithAttendance({
    required this.staff,
    this.attendance,
  }) : isPresent = attendance?.isPresent ?? false;
}

// --- HEAVILY MODIFIED SCREEN ---
class StaffAndRolesScreen extends StatefulWidget {
  final String restaurantId;
  const StaffAndRolesScreen({super.key, required this.restaurantId});

  @override
  State<StaffAndRolesScreen> createState() => _StaffAndRolesScreenState();
}

class _StaffAndRolesScreenState extends State<StaffAndRolesScreen> {
  final DateTime _today =
  DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);

  Future<void> _toggleAttendance(Staff staff, Attendance? attendance) async {
    final attendanceRef = FirebaseFirestore.instance
        .collection('restaurants')
        .doc(widget.restaurantId)
        .collection('attendance');

    if (attendance == null) {
      // No record for today exists, create one
      await attendanceRef.add({
        'staffId': staff.id,
        'date': Timestamp.fromDate(_today),
        'isPresent': true, // Mark as present on first toggle
      });
    } else {
      // Record exists, update it
      await attendanceRef
          .doc(attendance.id)
          .update({'isPresent': !attendance.isPresent});
    }
  }

  // --- NEW: Delete Staff Function ---
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
      // Note: In a production app, you might want a Cloud Function
      // to delete subcollections (like payments). Here, we just delete the main staff doc.
      await FirebaseFirestore.instance
          .collection('restaurants')
          .doc(widget.restaurantId)
          .collection('staff')
          .doc(staff.id)
          .delete();

      // TODO: Also delete attendance records where staffId == staff.id
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      extendBodyBehindAppBar: true, // For background
      appBar: AppBar(
        title: Text('Staff Attendance (${DateFormat.yMMMd().format(_today)})'),
        backgroundColor:
        theme.scaffoldBackgroundColor.withOpacity(0.85), // Glassmorphic app bar
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.group_outlined),
            tooltip: 'Manage Roles (Coming Soon)',
            onPressed: () {
              // Placeholder for role management screen
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          const _StaticBackground(), // Add background
          SafeArea(
            child: StreamBuilder<QuerySnapshot>(
              // --- STREAM 1: LISTEN TO STAFF LIST ---
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
                if (staffSnapshot.hasError) {
                  return Center(child: Text('Error: ${staffSnapshot.error}'));
                }
                if (!staffSnapshot.hasData ||
                    staffSnapshot.data!.docs.isEmpty) {
                  return const Center(child: Text('No staff members found.'));
                }

                final staffList = staffSnapshot.data!.docs
                    .map((doc) => Staff.fromFirestore(doc))
                    .toList();

                // --- STREAM 2 (FIX): LISTEN TO ATTENDANCE ---
                return StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('restaurants')
                      .doc(widget.restaurantId)
                      .collection('attendance')
                      .where('date', isEqualTo: Timestamp.fromDate(_today))
                      .snapshots(),
                  builder: (context, attendanceSnapshot) {
                    // --- MERGE LOGIC ---
                    // We can build the list even if attendance is just waiting
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
                    // --- END MERGE LOGIC ---

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
                                  item: item,
                                  onTap: () {
                                    Navigator.of(context).push(MaterialPageRoute(
                                      builder: (context) => StaffDetailScreen(
                                        restaurantId: widget.restaurantId,
                                        staff: item.staff,
                                      ),
                                    ));
                                  },
                                  onToggle: (boolValue) {
                                    _toggleAttendance(
                                        item.staff, item.attendance);
                                  },
                                  // --- PASS DELETE FUNCTION ---
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

// --- NEW: REDESIGNED STAFF CARD ---
class _StaffAttendanceCard extends StatefulWidget {
  final StaffWithAttendance item;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete; // --- ADDED DELETE CALLBACK ---

  const _StaffAttendanceCard(
      {required this.item,
        required this.onTap,
        required this.onToggle,
        required this.onDelete}); // --- ADDED DELETE CALLBACK ---

  @override
  State<_StaffAttendanceCard> createState() => _StaffAttendanceCardState();
}

class _StaffAttendanceCardState extends State<_StaffAttendanceCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final String initial =
    widget.item.staff.name.isNotEmpty ? widget.item.staff.name[0] : '?';

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
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
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
              child: ListTile(
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
                subtitle: Text(widget.item.staff.role),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.item.isPresent ? 'Present' : 'Absent',
                      style: TextStyle(
                          color: widget.item.isPresent
                              ? Colors.green
                              : Colors.red,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    Switch(
                      value: widget.item.isPresent,
                      onChanged: widget.onToggle,
                      activeColor: Colors.green,
                    ),
                    // --- ADDED DELETE BUTTON ---
                    IconButton(
                      icon: Icon(Icons.delete_outline,
                          color: theme.colorScheme.error.withOpacity(0.7)),
                      onPressed: widget.onDelete,
                      tooltip: 'Delete Staff',
                    ),
                  ],
                ),
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