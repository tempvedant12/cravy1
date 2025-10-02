import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cravy/screen/restaurant/inventory/inventory_screen.dart';

class Supplier {
  final String id;
  final String name;
  final String contactPerson;
  final String phone;
  final String email;
  final String address;
  final List<String> supplies;

  Supplier({
    required this.id,
    required this.name,
    required this.contactPerson,
    required this.phone,
    required this.email,
    required this.address,
    required this.supplies,
  });

  factory Supplier.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return Supplier(
      id: doc.id,
      name: data['name'] ?? '',
      contactPerson: data['contactPerson'] ?? '',
      phone: data['phone'] ?? '',
      email: data['email'] ?? '',
      address: data['address'] ?? '',
      supplies: List<String>.from(data['supplies'] ?? []),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'contactPerson': contactPerson,
      'phone': phone,
      'email': email,
      'address': address,
      'supplies': supplies,
    };
  }
}

class PurchaseOrderItem {
  final String inventoryItemId;
  final String name;
  final double quantity;
  final String unit;
  final double price;

  PurchaseOrderItem({
    required this.inventoryItemId,
    required this.name,
    required this.quantity,
    required this.unit,
    required this.price,
  });

  factory PurchaseOrderItem.fromMap(Map<String, dynamic> map) {
    return PurchaseOrderItem(
      inventoryItemId: map['inventoryItemId'] ?? '',
      name: map['name'] ?? '',
      quantity: (map['quantity'] ?? 0.0).toDouble(),
      unit: map['unit'] ?? '',
      price: (map['price'] ?? 0.0).toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'inventoryItemId': inventoryItemId,
      'name': name,
      'quantity': quantity,
      'unit': unit,
      'price': price,
    };
  }
}

class PurchaseOrder {
  final String id;
  final String supplierId;
  final String supplierName;
  final DateTime orderDate;
  final DateTime? deliveryDate;
  final String status; // 'Pending', 'Completed', 'Cancelled'
  final List<PurchaseOrderItem> items;
  final double totalAmount;
  final double amountPaid;
  final String paymentMethod;
  final String paymentStatus;

  PurchaseOrder({
    required this.id,
    required this.supplierId,
    required this.supplierName,
    required this.orderDate,
    this.deliveryDate,
    required this.status,
    required this.items,
    required this.totalAmount,
    required this.amountPaid,
    required this.paymentMethod,
    required this.paymentStatus,
  });

  factory PurchaseOrder.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return PurchaseOrder(
      id: doc.id,
      supplierId: data['supplierId'] ?? '',
      supplierName: data['supplierName'] ?? '',
      orderDate: (data['orderDate'] as Timestamp).toDate(),
      deliveryDate: (data['deliveryDate'] as Timestamp?)?.toDate(),
      status: data['status'] ?? 'Pending',
      items: (data['items'] as List<dynamic>? ?? [])
          .map((item) => PurchaseOrderItem.fromMap(item))
          .toList(),
      totalAmount: (data['totalAmount'] ?? 0.0).toDouble(),
      amountPaid: (data['amountPaid'] ?? 0.0).toDouble(),
      paymentMethod: data['paymentMethod'] ?? 'Other',
      paymentStatus: data['paymentStatus'] ?? 'Unpaid',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'supplierId': supplierId,
      'supplierName': supplierName,
      'orderDate': orderDate,
      'deliveryDate': deliveryDate,
      'status': status,
      'items': items.map((item) => item.toMap()).toList(),
      'totalAmount': totalAmount,
      'amountPaid': amountPaid,
      'paymentMethod': paymentMethod,
      'paymentStatus': paymentStatus,
    };
  }
}