import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'staff_and_roles_screen.dart';

class Attendance {
  final String staffId;
  final DateTime date;
  final bool isPresent;

  Attendance(
      {required this.staffId, required this.date, required this.isPresent});

  factory Attendance.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return Attendance(
      staffId: data['staffId'],
      date: (data['date'] as Timestamp).toDate(),
      isPresent: data['isPresent'],
    );
  }
}

class AttendanceScreen extends StatefulWidget {
  final String restaurantId;
  const AttendanceScreen({super.key, required this.restaurantId});

  @override
  _AttendanceScreenState createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  DateTime _selectedDate = DateTime.now();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
            'Attendance for ${DateFormat.yMMMd().format(_selectedDate)}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _selectedDate,
                firstDate: DateTime(2020),
                lastDate: DateTime.now(),
              );
              if (picked != null) {
                setState(() {
                  _selectedDate = picked;
                });
              }
            },
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('restaurants')
            .doc(widget.restaurantId)
            .collection('staff')
            .snapshots(),
        builder: (context, staffSnapshot) {
          if (!staffSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final staffList = staffSnapshot.data!.docs
              .map((doc) => Staff.fromFirestore(doc))
              .toList();
          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('restaurants')
                .doc(widget.restaurantId)
                .collection('attendance')
                .where('date',
                isEqualTo: Timestamp.fromDate(DateTime(
                    _selectedDate.year,
                    _selectedDate.month,
                    _selectedDate.day)))
                .snapshots(),
            builder: (context, attendanceSnapshot) {
              if (!attendanceSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final attendanceList = attendanceSnapshot.data!.docs
                  .map((doc) => Attendance.fromFirestore(doc))
                  .toList();
              return ListView.builder(
                itemCount: staffList.length,
                itemBuilder: (context, index) {
                  final staff = staffList[index];
                  final attendance = attendanceList.firstWhere(
                        (att) => att.staffId == staff.id,
                    orElse: () => Attendance(
                        staffId: staff.id,
                        date: _selectedDate,
                        isPresent: false),
                  );
                  return CheckboxListTile(
                    title: Text(staff.name),
                    value: attendance.isPresent,
                    onChanged: (value) {
                      final attendanceRef = FirebaseFirestore.instance
                          .collection('restaurants')
                          .doc(widget.restaurantId)
                          .collection('attendance');
                      if (attendanceSnapshot.data!.docs.any(
                              (doc) => doc['staffId'] == staff.id)) {
                        attendanceRef
                            .doc(attendanceSnapshot.data!.docs
                            .firstWhere(
                                (doc) => doc['staffId'] == staff.id)
                            .id)
                            .update({'isPresent': value});
                      } else {
                        attendanceRef.add({
                          'staffId': staff.id,
                          'date': Timestamp.fromDate(DateTime(
                              _selectedDate.year,
                              _selectedDate.month,
                              _selectedDate.day)),
                          'isPresent': value,
                        });
                      }
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}