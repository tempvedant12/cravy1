import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../orders/create_order_screen.dart';

class CustomersScreen extends StatelessWidget {
  final String restaurantId;
  const CustomersScreen({super.key, required this.restaurantId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Customers'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('restaurants')
            .doc(restaurantId)
            .collection('orders')
            .where('customers', isNotEqualTo: [])
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('No customers found.'));
          }
          final orders = snapshot.data!.docs;
          final customers = <String, CustomerInfo>{};
          for (var order in orders) {
            final data = order.data() as Map<String, dynamic>;
            final customerList = data['customers'] as List<dynamic>? ?? [];
            for (var customerData in customerList) {
              final customer =
              CustomerInfo.fromMap(customerData as Map<String, dynamic>);
              customers[customer.id] = customer;
            }
          }
          return ListView(
            children: customers.values.map((customer) {
              return ExpansionTile(
                title: Text(customer.name),
                subtitle: Text(customer.phone),
                children: [
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('restaurants')
                        .doc(restaurantId)
                        .collection('orders')
                        .where('customers',
                        arrayContains: customer.toMap())
                        .snapshots(),
                    builder: (context, orderSnapshot) {
                      if (!orderSnapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final customerOrders = orderSnapshot.data!.docs;
                      return Column(
                        children: customerOrders.map((order) {
                          final data = order.data() as Map<String, dynamic>;
                          final billingDetails = data['billingDetails'] as Map<String, dynamic>? ?? {};
                          final total = billingDetails['finalTotal'] ?? data['totalAmount'] ?? 0;
                          return ListTile(
                            title: Text(
                                'Order #${order.id.substring(0, 6).toUpperCase()}'),
                            subtitle: Text(
                                'on ${DateFormat.yMMMd().format((billingDetails['billedAt'] as Timestamp? ?? data['createdAt'] as Timestamp).toDate())}'),
                            trailing: Text('₹${total.toStringAsFixed(2)}'),
                          );
                        }).toList(),
                      );
                    },
                  ),
                ],
              );
            }).toList(),
          );
        },
      ),
    );
  }
}