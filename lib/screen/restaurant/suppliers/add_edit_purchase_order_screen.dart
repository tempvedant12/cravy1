import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cravy/models/supplier_model.dart';
import 'package:cravy/screen/restaurant/inventory/inventory_screen.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class AddEditPurchaseOrderScreen extends StatefulWidget {
  final String restaurantId;
  final PurchaseOrder? purchaseOrder;
  final Supplier? supplier;

  const AddEditPurchaseOrderScreen({
    super.key,
    required this.restaurantId,
    this.purchaseOrder,
    this.supplier,
  });

  @override
  State<AddEditPurchaseOrderScreen> createState() =>
      _AddEditPurchaseOrderScreenState();
}

class _AddEditPurchaseOrderScreenState
    extends State<AddEditPurchaseOrderScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  Supplier? _selectedSupplier;
  DateTime _orderDate = DateTime.now();
  DateTime? _deliveryDate;
  String _status = 'Pending';
  List<PurchaseOrderItem> _items = [];
  double _totalAmount = 0.0;
  double _amountPaid = 0.0;
  late TextEditingController _amountPaidController;
  String _paymentMethod = 'Other';
  String _paymentStatus = 'Unpaid';

  @override
  void initState() {
    super.initState();
    if (widget.purchaseOrder != null) {
      _selectedSupplier = Supplier(
        id: widget.purchaseOrder!.supplierId,
        name: widget.purchaseOrder!.supplierName,
        contactPerson: '',
        phone: '',
        email: '',
        address: '',
        supplies: [],
      );
      _orderDate = widget.purchaseOrder!.orderDate;
      _deliveryDate = widget.purchaseOrder!.deliveryDate;
      _status = widget.purchaseOrder!.status;
      _items = widget.purchaseOrder!.items;
      _totalAmount = widget.purchaseOrder!.totalAmount;
      _amountPaid = widget.purchaseOrder!.amountPaid;
      _paymentMethod = widget.purchaseOrder!.paymentMethod;
      _paymentStatus = widget.purchaseOrder!.paymentStatus;
    } else if (widget.supplier != null) {
      _selectedSupplier = widget.supplier;
    }
    _amountPaidController =
        TextEditingController(text: _amountPaid.toString());
    _updatePaymentStatus();
  }

  @override
  void dispose() {
    _amountPaidController.dispose();
    super.dispose();
  }

  void _calculateTotal() {
    setState(() {
      _totalAmount =
          _items.fold(0.0, (sum, item) => sum + (item.quantity * item.price));
      _updatePaymentStatus();
    });
  }

  void _updatePaymentStatus() {
    setState(() {
      if (_paymentMethod == 'Pay Later') {
        _paymentStatus = 'Pay Later';
      } else if (_amountPaid >= _totalAmount && _totalAmount > 0) {
        _paymentStatus = 'Paid';
      } else if (_amountPaid > 0) {
        _paymentStatus = 'Partially Paid';
      } else {
        _paymentStatus = 'Unpaid';
      }
    });
  }

  Future<void> _savePurchaseOrder() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      setState(() => _isLoading = true);

      final poData = {
        'supplierId': _selectedSupplier!.id,
        'supplierName': _selectedSupplier!.name,
        'orderDate': _orderDate,
        'deliveryDate': _deliveryDate,
        'status': _status,
        'items': _items.map((item) => item.toMap()).toList(),
        'totalAmount': _totalAmount,
        'amountPaid': _amountPaid,
        'paymentMethod': _paymentMethod,
        'paymentStatus': _paymentStatus,
      };

      try {
        final collection = FirebaseFirestore.instance
            .collection('restaurants')
            .doc(widget.restaurantId)
            .collection('purchaseOrders');

        if (widget.purchaseOrder == null) {
          await collection.add(poData);
        } else {
          await collection.doc(widget.purchaseOrder!.id).update(poData);
        }

        if (_status == 'Completed') {
          await _updateInventory();
        }

        if (mounted) Navigator.of(context).pop();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Error saving purchase order: ${e.toString()}')),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _updateInventory() async {
    final inventoryRef = FirebaseFirestore.instance
        .collection('restaurants')
        .doc(widget.restaurantId)
        .collection('inventory');

    WriteBatch batch = FirebaseFirestore.instance.batch();

    for (var item in _items) {
      QuerySnapshot querySnapshot =
      await inventoryRef.where('name', isEqualTo: item.name).limit(1).get();

      if (querySnapshot.docs.isNotEmpty) {
        DocumentReference docRef = querySnapshot.docs.first.reference;
        batch.update(docRef, {'quantity': FieldValue.increment(item.quantity)});
      } else {
        DocumentReference docRef = inventoryRef.doc();
        batch.set(docRef, {
          'name': item.name,
          'category': 'Uncategorized',
          'quantity': item.quantity,
          'unit': item.unit,
          'lowStockThreshold': 0.0,
          'lastUpdated': FieldValue.serverTimestamp(),
        });
      }
    }
    await batch.commit();
  }

  void _addOrEditItem([PurchaseOrderItem? existingItem]) async {
    final result = await showDialog<PurchaseOrderItem>(
      context: context,
      builder: (context) => _AddEditPurchaseOrderItemDialog(
        restaurantId: widget.restaurantId,
        existingItem: existingItem,
      ),
    );

    if (result != null) {
      setState(() {
        if (existingItem != null) {
          final index = _items.indexWhere((item) => item.name == existingItem.name);
          if (index != -1) {
            _items[index] = result;
          }
        } else {
          _items.add(result);
        }
        _calculateTotal();
        _amountPaidController.text = _totalAmount.toString();
        _amountPaid = _totalAmount;
        _updatePaymentStatus();
      });
    }
  }

  void _deleteItem(int index) {
    setState(() {
      _items.removeAt(index);
      _calculateTotal();
      _amountPaidController.text = _totalAmount.toString();
      _amountPaid = _totalAmount;
      _updatePaymentStatus();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.purchaseOrder == null
            ? 'New Purchase Order'
            : 'Edit Purchase Order'),
      ),
      body: Stack(
        children: [
          const _StaticBackground(),
          Form(
            key: _formKey,
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16.0),
                    children: [
                      if (_selectedSupplier != null)
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.business),
                            title: Text(_selectedSupplier!.name),
                            subtitle: const Text('Supplier'),
                          ),
                        ),
                      if (_selectedSupplier == null)
                        const Text('Please select a supplier.'),
                      const SizedBox(height: 16),
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.calendar_today),
                          title: Text(DateFormat.yMMMd().format(_orderDate)),
                          subtitle: const Text('Order Date'),
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _orderDate,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2101),
                            );
                            if (picked != null) {
                              setState(() {
                                _orderDate = picked;
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _status,
                              decoration: const InputDecoration(
                                labelText: 'Status',
                                border: OutlineInputBorder(),
                              ),
                              items: ['Pending', 'Completed', 'Cancelled']
                                  .map((status) => DropdownMenuItem(
                                  value: status, child: Text(status)))
                                  .toList(),
                              onChanged: (value) {
                                setState(() {
                                  _status = value!;
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _paymentMethod,
                              decoration: const InputDecoration(
                                labelText: 'Payment Method',
                                border: OutlineInputBorder(),
                              ),
                              items: ['Cash', 'Card', 'UPI', 'Other', 'Pay Later']
                                  .map((method) => DropdownMenuItem(
                                  value: method, child: Text(method)))
                                  .toList(),
                              onChanged: (value) {
                                setState(() {
                                  _paymentMethod = value!;
                                  _updatePaymentStatus();
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _amountPaidController,
                        decoration: const InputDecoration(
                          labelText: 'Amount Paid',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (value) {
                          _amountPaid = double.tryParse(value) ?? 0.0;
                          _updatePaymentStatus();
                        },
                        onSaved: (value) {
                          _amountPaid = double.tryParse(value ?? '0.0') ?? 0.0;
                        },
                      ),
                      const SizedBox(height: 16),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Items',
                                style: TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                              const Divider(),
                              ..._items.asMap().entries.map((entry) {
                                int idx = entry.key;
                                PurchaseOrderItem item = entry.value;
                                return Dismissible(
                                  key: Key(item.name),
                                  direction: DismissDirection.endToStart,
                                  onDismissed: (direction) {
                                    _deleteItem(idx);
                                  },
                                  background: Container(
                                    color: Colors.red,
                                    alignment: Alignment.centerRight,
                                    padding: const EdgeInsets.symmetric(horizontal: 20),
                                    child: const Icon(Icons.delete, color: Colors.white),
                                  ),
                                  child: ListTile(
                                    title: Text(item.name),
                                    subtitle: Text(
                                        '${item.quantity} ${item.unit} @ ₹${item.price.toStringAsFixed(2)}'),
                                    trailing: Text(
                                        '₹${(item.quantity * item.price).toStringAsFixed(2)}'),
                                    onTap: () => _addOrEditItem(item),
                                  ),
                                );
                              }),
                              Center(
                                child: TextButton.icon(
                                  onPressed: () => _addOrEditItem(),
                                  icon: const Icon(Icons.add),
                                  label: const Text('Add Item'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      const Divider(),
                      ListTile(
                        title: const Text(
                          'Total Amount',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        trailing: Text(
                          '₹${_totalAmount.toStringAsFixed(2)}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                      ),
                      ListTile(
                        title: const Text(
                          'Payment Status',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        trailing: Text(
                          _paymentStatus,
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: _paymentStatus == 'Paid'
                                  ? Colors.green
                                  : _paymentStatus == 'Partially Paid'
                                  ? Colors.orange
                                  : Colors.red),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_isLoading)
                        const Center(child: CircularProgressIndicator())
                      else
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _savePurchaseOrder,
                            child: const Text('Save Purchase Order'),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AddEditPurchaseOrderItemDialog extends StatefulWidget {
  final String restaurantId;
  final PurchaseOrderItem? existingItem;

  const _AddEditPurchaseOrderItemDialog(
      {required this.restaurantId, this.existingItem});

  @override
  State<_AddEditPurchaseOrderItemDialog> createState() =>
      _AddEditPurchaseOrderItemDialogState();
}

class _AddEditPurchaseOrderItemDialogState
    extends State<_AddEditPurchaseOrderItemDialog> {
  final _formKey = GlobalKey<FormState>();
  String? _inventoryItemId;
  late TextEditingController _nameController;
  late TextEditingController _quantityController;
  late TextEditingController _priceController;
  late TextEditingController _totalPriceController;
  String? _unit;
  bool _isPricePerUnit = true;

  InventoryItem? _selectedInventoryItem;

  @override
  void initState() {
    super.initState();
    _inventoryItemId = widget.existingItem?.inventoryItemId;
    _nameController = TextEditingController(text: widget.existingItem?.name ?? '');
    _quantityController = TextEditingController(
        text: widget.existingItem?.quantity.toString() ?? '1');
    _priceController =
        TextEditingController(text: widget.existingItem?.price.toString() ?? '');
    _totalPriceController = TextEditingController(
        text: widget.existingItem != null
            ? (widget.existingItem!.price * widget.existingItem!.quantity)
            .toString()
            : '');
    _unit = widget.existingItem?.unit;

    _quantityController.addListener(_updatePrices);
    _priceController.addListener(_updateTotalPrice);
    _totalPriceController.addListener(_updatePricePerUnit);
  }

  void _updatePrices() {
    if (_isPricePerUnit) {
      _updateTotalPrice();
    } else {
      _updatePricePerUnit();
    }
  }

  void _updateTotalPrice() {
    if (!_isPricePerUnit) return;
    final quantity = double.tryParse(_quantityController.text) ?? 0;
    final price = double.tryParse(_priceController.text) ?? 0;
    _totalPriceController.text = (quantity * price).toStringAsFixed(2);
  }

  void _updatePricePerUnit() {
    if (_isPricePerUnit) return;
    final quantity = double.tryParse(_quantityController.text) ?? 1;
    final totalPrice = double.tryParse(_totalPriceController.text) ?? 0;
    _priceController.text = (totalPrice / quantity).toStringAsFixed(2);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _quantityController.dispose();
    _priceController.dispose();
    _totalPriceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existingItem == null ? 'Add Item' : 'Edit Item'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('restaurants')
                    .doc(widget.restaurantId)
                    .collection('inventory')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const CircularProgressIndicator();
                  }
                  final items = snapshot.data!.docs
                      .map((doc) => InventoryItem.fromFirestore(doc))
                      .toList();
                  return DropdownButtonFormField<InventoryItem>(
                    value: _selectedInventoryItem,
                    hint: const Text('Select an inventory item'),
                    isExpanded: true,
                    items: items.map((item) {
                      return DropdownMenuItem<InventoryItem>(
                        value: item,
                        child: Text(item.name, overflow: TextOverflow.ellipsis),
                      );
                    }).toList(),
                    onChanged: (item) {
                      setState(() {
                        _selectedInventoryItem = item;
                        if (item != null) {
                          _inventoryItemId = item.id;
                          _nameController.text = item.name;
                          _unit = item.unit;
                        }
                      });
                    },
                  );
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Item Name'),
                validator: (value) => value!.isEmpty ? 'Enter a name' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _quantityController,
                decoration: const InputDecoration(labelText: 'Quantity'),
                keyboardType: TextInputType.number,
                validator: (value) =>
                double.tryParse(value!) == null ? 'Invalid quantity' : null,
              ),
              const SizedBox(height: 16),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment<bool>(
                      value: true,
                      label: Text('Price/Unit'),
                      icon: Icon(Icons.tag)),
                  ButtonSegment<bool>(
                      value: false,
                      label: Text('Total Price'),
                      icon: Icon(Icons.attach_money)),
                ],
                selected: {_isPricePerUnit},
                onSelectionChanged: (newSelection) {
                  setState(() {
                    _isPricePerUnit = newSelection.first;
                  });
                },
              ),
              const SizedBox(height: 16),
              if (_isPricePerUnit)
                TextFormField(
                  controller: _priceController,
                  decoration: const InputDecoration(labelText: 'Price per unit'),
                  keyboardType: TextInputType.number,
                )
              else
                TextFormField(
                  controller: _totalPriceController,
                  decoration: const InputDecoration(labelText: 'Total Price'),
                  keyboardType: TextInputType.number,
                ),
            ],
          ),
        ),
      ),
      actions: [
        if (widget.existingItem != null)
          TextButton.icon(
            onPressed: () {
              // You can call a delete function here
              Navigator.of(context).pop();
            },
            icon: const Icon(Icons.delete),
            label: const Text('Delete'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (_formKey.currentState!.validate()) {
                  final item = PurchaseOrderItem(
                    inventoryItemId: _inventoryItemId ?? '',
                    name: _nameController.text,
                    quantity: double.parse(_quantityController.text),
                    unit: _unit ?? 'unit',
                    price: double.tryParse(_priceController.text) ?? 0.0,
                  );
                  Navigator.of(context).pop(item);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ],
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