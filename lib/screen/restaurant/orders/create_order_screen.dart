import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cravy/models/order_models.dart';
import 'package:cravy/screen/restaurant/orders/assign_table_screen.dart';
import 'package:cravy/screen/restaurant/orders/select_menu_items_screen.dart';
import 'package:cravy/services/inventory_service.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../tables_and_reservations/tables_and_reservations_screen.dart';

class CustomerInfo {
  final String id;
  String name;
  String phone;
  CustomerInfo({required this.id, required this.name, required this.phone});
  Map<String, dynamic> toMap() => {'id': id, 'name': name, 'phone': phone};
}

class CreateOrderScreen extends StatefulWidget {
  final String restaurantId;
  final OrderAssignment? initialAssignment;
  final List<CustomerInfo>? initialCustomers;
  const CreateOrderScreen({super.key, required this.restaurantId, this.initialAssignment, this.initialCustomers});

  @override
  State<CreateOrderScreen> createState() => _CreateOrderScreenState();
}

class _CreateOrderScreenState extends State<CreateOrderScreen> {
  final _formKey = GlobalKey<FormState>();
  String _orderType = 'Dine-In';
  Map<String, OrderItem> _selectedItems = {};
  bool _isLoading = false;
  OrderAssignment? _assignment;
  final List<CustomerInfo> _customers = [];
  late final TextEditingController _addressController;
  late final TextEditingController _notesController;

  @override
  void initState() {
    super.initState();
    _addressController = TextEditingController();
    _notesController = TextEditingController();
    if (widget.initialAssignment != null) _assignment = widget.initialAssignment;
    if (widget.initialCustomers != null) _customers.addAll(widget.initialCustomers!);
  }

  @override
  void dispose() {
    _addressController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  double get _totalAmount => _selectedItems.values.fold(0.0, (sum, item) => sum + item.totalPrice);

  // --- FIX/ENHANCEMENT: Map OrderItem to Firestore document structure with necessary details ---
  Map<String, dynamic> _mapItemToFirestore(OrderItem item) {
    return {
      'menuItemId': item.menuItem.id,
      'name': item.menuItem.name,
      'price': item.menuItem.price,
      'quantity': item.quantity,
      'status': 'Pending',
      'selectedOptions': item.selectedOptions.map((o) => o.toMap()).toList(),
      // Embed full recipe and type data for InventoryService and other screens (like Order Details)
      'baseRecipe': item.menuItem.baseRecipe.map((r) => r.toMap()).toList(),
      'type': item.menuItem.type,
      'menuName': item.menuName, // Include menu name
    };
  }
  // -------------------------------------------------------------------------------------------

  void _navigateAndSelectItems() async {
    final List<OrderItem>? result = await Navigator.of(context).push(MaterialPageRoute(builder: (context) => SelectMenuItemsScreen(restaurantId: widget.restaurantId)));
    if (result != null) {
      setState(() {
        for (var newItem in result) {
          // If a complex item with options is selected, it will have a uniqueId that includes the options.
          if (_selectedItems.containsKey(newItem.uniqueId)) {
            _selectedItems[newItem.uniqueId]!.quantity += newItem.quantity;
          } else {
            _selectedItems[newItem.uniqueId] = newItem;
          }
        }
      });
    }
  }

  void _navigateAndAssignTable() async {
    final OrderAssignment? result = await Navigator.of(context).push(MaterialPageRoute(builder: (context) => AssignTableScreen(restaurantId: widget.restaurantId)));
    if (result != null) setState(() => _assignment = result);
  }

  Future<void> _placeOrder() async {
    if (_formKey.currentState!.validate()) {
      if (_selectedItems.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please add at least one item to the order.')));
        return;
      }
      if (_orderType == 'Dine-In' && _assignment == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please assign a table for Dine-In orders.')));
        return;
      }
      setState(() => _isLoading = true);

      // *** MODIFIED: Use the new mapping function to include baseRecipe/type ***
      final itemsForFirestore = _selectedItems.values.map((item) => _mapItemToFirestore(item)).toList();

      try {
        final inventoryService = InventoryService(restaurantId: widget.restaurantId);
        // This call is now safe because itemsForFirestore contains the baseRecipe and type info.
        await inventoryService.updateInventoryForOrder(itemsForFirestore);

        await FirebaseFirestore.instance.collection('restaurants').doc(widget.restaurantId).collection('orders').add({
          'orderType': _orderType,
          'sessionKey': _assignment?.toDisplayString() ?? (_customers.isNotEmpty ? _customers.first.name : 'Guest'),
          'assignment': _assignment?.selections.map((key, value) => MapEntry(key, value.toList())),
          'assignmentLabel': _assignment?.toDisplayString(),
          'tableIds': _assignment?.selections.keys.toList() ?? [],
          'items': itemsForFirestore,
          'totalAmount': _totalAmount,
          'status': 'Pending',
          'createdAt': FieldValue.serverTimestamp(),
          'customers': _customers.map((c) => c.toMap()).toList(),
          'deliveryAddress': _orderType == 'Delivery' ? _addressController.text.trim() : null,
          'notes': _notesController.text.trim(),
          'isSessionActive': true,
        });

        if (_orderType == 'Dine-In' && _assignment != null) {
          await updateTableSessionStatus(widget.restaurantId, _assignment!.selections, _assignment!.toDisplayString(), closeSession: false);
        }
        if (mounted) Navigator.of(context).pop();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error placing order: ${e.toString()}')));
        print(e);
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  void _updateItemQuantity(String uniqueId, int change) {
    setState(() {
      if (_selectedItems.containsKey(uniqueId)) {
        final item = _selectedItems[uniqueId]!;
        item.quantity += change;
        if (item.quantity <= 0) _selectedItems.remove(uniqueId);
      }
    });
  }

  // --- ADDED METHOD TO SHOW CUSTOMER DIALOG ---
  void _showAddEditCustomerDialog() async {
    final CustomerInfo? result = await showDialog(
      context: context,
      builder: (_) => const _AddEditCustomerDialog(),
    );

    if (result != null) {
      setState(() {
        _customers.add(result);
      });
    }
  }
  // ------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Order')),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  _buildSectionCard(title: 'Customer Details', icon: Icons.people_outline, child: _buildCustomerDetailsSection()),
                  const SizedBox(height: 20),
                  _buildSectionCard(title: 'Order & Items', icon: Icons.receipt_long_outlined, child: _buildOrderDetailsSection()),
                ],
              ),
            ),
            _buildSummaryAndPlaceOrder(),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard({required String title, required IconData icon, required Widget child}) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [Icon(icon, color: Theme.of(context).primaryColor), const SizedBox(width: 8), Text(title, style: Theme.of(context).textTheme.titleLarge)]),
            const Divider(height: 24),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerDetailsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_customers.isEmpty) const Center(child: Padding(padding: EdgeInsets.symmetric(vertical: 8.0), child: Text('No customer added (optional).'))),
        ..._customers.map((c) => Card(elevation: 1, child: ListTile(title: Text(c.name), subtitle: Text(c.phone), trailing: IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => setState(() => _customers.removeWhere((cust) => cust.id == c.id)))))),
        const SizedBox(height: 8),
        // FIX: Connect button to the dialog method
        Center(child: OutlinedButton.icon(onPressed: _showAddEditCustomerDialog, icon: const Icon(Icons.add), label: const Text('Add Customer'))),
      ],
    );
  }

  Widget _buildOrderDetailsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          value: _orderType,
          decoration: const InputDecoration(labelText: 'Order Type'),
          items: ['Dine-In', 'Takeaway', 'Delivery'].map((type) => DropdownMenuItem(value: type, child: Text(type))).toList(),
          onChanged: (value) => setState(() {
            _orderType = value!;
            if (_orderType != 'Dine-In') _assignment = null;
          }),
        ),
        if (_orderType == 'Dine-In') ...[
          const SizedBox(height: 10),
          ListTile(leading: const Icon(Icons.deck_outlined), title: Text(_assignment?.toDisplayString() ?? 'Not Assigned'), trailing: const Icon(Icons.chevron_right), onTap: _navigateAndAssignTable),
        ],
        const SizedBox(height: 10),
        OutlinedButton.icon(onPressed: _navigateAndSelectItems, icon: const Icon(Icons.add_shopping_cart), label: const Text('Add / Edit Items')),
        const SizedBox(height: 10),
        if (_selectedItems.isNotEmpty)
          ..._selectedItems.values.map((item) {
            return ListTile(
              // *** MODIFIED: Show Menu Name and Veg/Non-Veg Indicator ***
              title: Row(
                children: [
                  if (item.menuItem.type != 'none')
                    Container(
                      margin: const EdgeInsets.only(right: 8.0),
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: item.menuItem.type == 'veg' ? Colors.green : Colors.red,
                        shape: BoxShape.circle,
                        border: Border.all(color: Theme.of(context).cardColor, width: 1),
                      ),
                    ),
                  Expanded(child: Text(item.menuItem.name)),
                  Chip(
                    label: Text(item.menuName, style: const TextStyle(fontSize: 12)),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  )
                ],
              ),
              // *** END MODIFIED ***
              subtitle: item.selectedOptions.isEmpty ? null : Text(item.selectedOptions.map((o) => o.optionName).join(', '), style: Theme.of(context).textTheme.bodySmall),
              trailing: _buildQuantityControl(Theme.of(context), item),
            );
          }),
        const SizedBox(height: 16),
        TextFormField(controller: _notesController, decoration: const InputDecoration(labelText: 'Order Notes'), maxLines: 2),
      ],
    );
  }

  Widget _buildSummaryAndPlaceOrder() {
    return Material(
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total:', style: Theme.of(context).textTheme.headlineSmall),
                Text('₹${_totalAmount.toStringAsFixed(2)}', style: Theme.of(context).textTheme.headlineSmall),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: _isLoading ? const Center(child: CircularProgressIndicator()) : ElevatedButton(onPressed: _placeOrder, child: const Text('Place Order'), style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16))),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuantityControl(ThemeData theme, OrderItem item) {
    return SizedBox(
      width: 120,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: () => _updateItemQuantity(item.uniqueId, -1), iconSize: 22),
          Text(item.quantity.toString(), style: theme.textTheme.titleMedium),
          IconButton(icon: Icon(Icons.add_circle_outline, color: theme.primaryColor), onPressed: () => _updateItemQuantity(item.uniqueId, 1), iconSize: 22),
        ],
      ),
    );
  }
}

class _AddEditCustomerDialog extends StatefulWidget {
  final CustomerInfo? customer;
  const _AddEditCustomerDialog({this.customer});
  @override
  State<_AddEditCustomerDialog> createState() => _AddEditCustomerDialogState();
}

class _AddEditCustomerDialogState extends State<_AddEditCustomerDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _phoneController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.customer?.name ?? '');
    _phoneController = TextEditingController(text: widget.customer?.phone ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _save() {
    if (_formKey.currentState!.validate()) {
      final customer = CustomerInfo(id: widget.customer?.id ?? const Uuid().v4(), name: _nameController.text.trim(), phone: _phoneController.text.trim());
      Navigator.of(context).pop(customer);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.customer == null ? 'Add Customer' : 'Edit Customer'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: (val) => val!.isEmpty ? 'Name cannot be empty' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _phoneController,
              decoration: const InputDecoration(labelText: 'Phone'),
              keyboardType: TextInputType.phone,
              validator: (val) => val!.isEmpty ? 'Phone cannot be empty' : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ElevatedButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}