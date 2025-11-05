import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cravy/models/order_models.dart';
import 'package:cravy/screen/restaurant/billing_setup/bill_design_screen.dart';
import 'package:cravy/screen/restaurant/billing_setup/manage_coupon_screen.dart';
import 'package:cravy/screen/restaurant/menu/menu_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../orders/bill_template_screen.dart';
import '../orders/create_order_screen.dart';

class QuickBillScreen extends StatefulWidget {
  final String restaurantId;
  const QuickBillScreen({super.key, required this.restaurantId});

  @override
  State<QuickBillScreen> createState() => _QuickBillScreenState();
}

class _QuickBillScreenState extends State<QuickBillScreen>
    with TickerProviderStateMixin {
  // --- SHARED STATE ---
  final Map<String, OrderItem> _selectedItems = {};
  List<MenuItem> _allMenuItems = [];
  bool _isLoading = true;

  // --- MENU PANEL STATE ---
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  TabController? _categoryTabController;
  List<String> _currentTabCategories = [];
  String _selectedMenuId = 'All';
  String? _defaultMenuId;
  List<QueryDocumentSnapshot> _menus = [];

  // --- BILLING PANEL STATE ---
  final TextEditingController _discountController = TextEditingController();
  final TextEditingController _couponController = TextEditingController();
  final TextEditingController _adHocChargeController = TextEditingController();
  final TextEditingController _adHocChargeLabelController =
  TextEditingController();
  String _adHocChargeType = 'percentage';
  double _discountPercentage = 0.0;
  CouponModel? _appliedCoupon;
  String? _couponError;
  BillConfiguration? _billConfig;
  String _orderType = 'Dine-In';
  final List<CustomerInfo> _customers = [];
  final TextEditingController _addressController = TextEditingController();


  @override
  void initState() {
    super.initState();
    _loadInitialData();

    // Add listeners
    _searchController.addListener(_onSearchChanged);
    _discountController.addListener(_onDiscountChanged);
    _adHocChargeController.addListener(_recalculateBill);
    _adHocChargeLabelController.addListener(_recalculateBill);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _discountController.dispose();
    _couponController.dispose();
    _adHocChargeController.dispose();
    _adHocChargeLabelController.dispose();
    _categoryTabController?.dispose();
    _addressController.dispose();
    super.dispose();
  }

  // --- DATA LOADING & STATE MANAGEMENT ---
  Future<void> _loadInitialData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    await _fetchRestaurantAndMenus();
    await Future.wait([
      _fetchAllMenuItems(),
      _fetchBillConfiguration(),
    ]);
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchRestaurantAndMenus() async {
    try {
      final restaurantDoc = await FirebaseFirestore.instance
          .collection('restaurants')
          .doc(widget.restaurantId)
          .get();
      final menusSnapshot = await FirebaseFirestore.instance
          .collection('restaurants')
          .doc(widget.restaurantId)
          .collection('menus')
          .get();
      if (mounted) {
        setState(() {
          _defaultMenuId = restaurantDoc.data()?['defaultQuickBillMenuId'];
          _menus = menusSnapshot.docs;
          _selectedMenuId = _defaultMenuId ?? 'All';
        });
      }
    } catch (e) {
      debugPrint("Error fetching restaurant/menu data: $e");
    }
  }

  Future<void> _fetchAllMenuItems() async {
    try {
      final List<MenuItem> allItems = [];
      for (var menuDoc in _menus) {
        final itemsSnapshot =
        await menuDoc.reference.collection('items').get();
        allItems.addAll(itemsSnapshot.docs.map((doc) {
          final item = MenuItem.fromFirestore(doc);
          item.menuId = menuDoc.id;
          return item;
        }));
      }
      if (mounted) {
        setState(() {
          _allMenuItems = allItems;
        });
      }
    } catch (e) {
      debugPrint("Error fetching menu items: $e");
    }
  }

  Future<void> _fetchBillConfiguration() async {
    try {
      final restaurantRef = FirebaseFirestore.instance
          .collection('restaurants')
          .doc(widget.restaurantId);
      final restaurantDoc = await restaurantRef.get();
      final defaultBillConfigId = restaurantDoc.data()?['defaultBillConfigId'];

      if (defaultBillConfigId != null) {
        final configDoc = await restaurantRef
            .collection('billConfigurations')
            .doc(defaultBillConfigId)
            .get();
        if (configDoc.exists && mounted) {
          setState(() {
            _billConfig = BillConfiguration.fromFirestore(configDoc);
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching bill configuration: $e");
    }
  }

  void _onSearchChanged() {
    if (mounted) setState(() => _searchQuery = _searchController.text);
  }

  void _onDiscountChanged() {
    final value = double.tryParse(_discountController.text) ?? 0.0;
    if (value >= 0 && value <= 100) {
      if (mounted) setState(() => _discountPercentage = value / 100.0);
    }
  }

  void _recalculateBill() {
    if (mounted) setState(() {});
  }

  void _addOrUpdateItemInBill(OrderItem newItem) {
    setState(() {
      if (_selectedItems.containsKey(newItem.uniqueId)) {
        _selectedItems[newItem.uniqueId]!.quantity++;
      } else {
        _selectedItems[newItem.uniqueId] = newItem;
      }
    });
  }

  void _updateQuantity(String uniqueId, int change) {
    setState(() {
      if (_selectedItems.containsKey(uniqueId)) {
        _selectedItems[uniqueId]!.quantity += change;
        if (_selectedItems[uniqueId]!.quantity <= 0) {
          _selectedItems.remove(uniqueId);
        }
      }
    });
  }

  void _removeItemFromBill(String uniqueId) {
    setState(() {
      _selectedItems.remove(uniqueId);
    });
  }

  Future<void> _setDefaultMenu(String? menuId) async {
    try {
      await FirebaseFirestore.instance
          .collection('restaurants')
          .doc(widget.restaurantId)
          .update({'defaultQuickBillMenuId': menuId});
      if (mounted) {
        setState(() {
          _defaultMenuId = menuId;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Default menu updated!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint("Error setting default menu: $e");
    }
  }

  void _addSimpleItem(MenuItem item) {
    final uniqueId = OrderItem.generateUniqueId(item, []);
    setState(() {
      if (_selectedItems.containsKey(uniqueId)) {
        _selectedItems[uniqueId]!.quantity++;
      } else {
        _selectedItems[uniqueId] = OrderItem(
          menuItem: item,
          selectedOptions: [],
          quantity: 1,
          menuName: "Quick Bill",
        );
      }
    });
  }

  Future<void> _handleItemTap(MenuItem item) async {
    if (item.optionGroups.isNotEmpty) {
      final List<SelectedOption>? selectedOptions = await showDialog(
        context: context,
        builder: (_) => _CustomizeItemDialog(menuItem: item),
      );

      if (selectedOptions != null) {
        final newItem = OrderItem(
          menuItem: item,
          selectedOptions: selectedOptions,
          quantity: 1,
          menuName: "Quick Bill",
        );
        _addOrUpdateItemInBill(newItem);
      }
    } else {
      _addSimpleItem(item);
    }
  }

  bool _fuzzySearch(String text, String query) {
    var queryChars = query.toLowerCase().runes.iterator;
    var textChars = text.toLowerCase().runes.iterator;

    if (!queryChars.moveNext()) {
      return true; // Empty query matches everything
    }

    while (textChars.moveNext()) {
      if (textChars.current == queryChars.current) {
        if (!queryChars.moveNext()) {
          return true; // All query chars were found in order
        }
      }
    }
    // If we finished the text but not the query, it's not a match.
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quick Bill'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth > 850) {
            return _buildWideLayout();
          } else {
            return _buildNarrowLayout();
          }
        },
      ),
    );
  }

  Widget _buildWideLayout() {
    return Row(
      children: [
        Expanded(flex: 3, child: _buildMenuPanel()),
        const VerticalDivider(width: 1),
        Expanded(flex: 2, child: _buildBillingPanel()),
      ],
    );
  }

  Widget _buildNarrowLayout() {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.restaurant_menu), text: 'Menu'),
              Tab(icon: Icon(Icons.receipt_long), text: 'Bill'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [_buildMenuPanel(), _buildBillingPanel()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuPanel() {
    final menuItems = _selectedMenuId == 'All'
        ? _allMenuItems
        : _allMenuItems.where((item) => item.menuId == _selectedMenuId).toList();

    final filteredItems = menuItems
        .where((item) => _fuzzySearch(item.name, _searchQuery))
        .toList();

    final categories =
    filteredItems.map((item) => item.category).toSet().toList();
    categories.sort();
    final newTabCategories = ['All', ...categories];

    if (_categoryTabController == null ||
        !listEquals(_currentTabCategories, newTabCategories)) {
      _categoryTabController?.dispose();
      _categoryTabController =
          TabController(length: newTabCategories.length, vsync: this);
      _currentTabCategories = newTabCategories;
    }

    return Column(
      children: [
        _buildMenuSelectionBar(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              hintText: 'Search menu items...',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12.0))),
              contentPadding: EdgeInsets.symmetric(horizontal: 16.0),
            ),
          ),
        ),
        TabBar(
          controller: _categoryTabController,
          isScrollable: true,
          tabs: newTabCategories.map((c) => Tab(text: c)).toList(),
        ),
        Expanded(
          child: TabBarView(
            controller: _categoryTabController,
            children: newTabCategories.map((category) {
              final categoryItems = category == 'All'
                  ? filteredItems
                  : filteredItems
                  .where((item) => item.category == category)
                  .toList();
              return _buildMenuGrid(categoryItems);
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildMenuSelectionBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: ChoiceChip(
                label: const Text('All Menus'),
                selected: _selectedMenuId == 'All',
                onSelected: (selected) {
                  if (selected) {
                    setState(() => _selectedMenuId = 'All');
                    _setDefaultMenu(null); // Set default to 'All'
                  }
                },
                avatar: _defaultMenuId == null
                    ? const Icon(Icons.check, size: 16)
                    : null,
              ),
            ),
            ..._menus.map((doc) {
              final menuId = doc.id;
              final menuName = doc['name'] as String;
              final isSelected = _selectedMenuId == menuId;
              final isDefault = _defaultMenuId == menuId;
              return Padding(
                key: ValueKey(menuId),
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: ChoiceChip(
                  label: Text(menuName),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() => _selectedMenuId = menuId);
                      _setDefaultMenu(menuId);
                    }
                  },
                  avatar: isDefault ? const Icon(Icons.check, size: 16) : null,
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuGrid(List<MenuItem> items) {
    if (items.isEmpty) {
      return const Center(child: Text("No items match your search."));
    }
    return GridView.builder(
      padding: const EdgeInsets.all(8.0),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.85,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final simpleUniqueId = OrderItem.generateUniqueId(item, []);
        final selectedSimpleItem = _selectedItems[simpleUniqueId];

        final customizedItemCount = _selectedItems.values
            .where((orderItem) =>
        orderItem.menuItem.id == item.id &&
            orderItem.selectedOptions.isNotEmpty)
            .length;

        final simpleItemQuantity = selectedSimpleItem?.quantity ?? 0;

        return _MenuItemCard(
          item: item,
          simpleItemQuantity: simpleItemQuantity,
          customizedItemCount: customizedItemCount,
          onTap: () => _handleItemTap(item),
          // Use the new function for both incrementing and the initial add
          onIncrement: () => _addSimpleItem(item),
          onDecrement: () => _updateQuantity(simpleUniqueId, -1),
        );
      },
    );
  }

  Widget _buildBillingPanel() {
    final theme = Theme.of(context);
    final formatter = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
    final items = _selectedItems.values.toList();

    final subtotal = items.fold(0.0, (sum, item) => sum + item.totalPrice);
    final discountAmount = subtotal * _discountPercentage;
    final couponDiscount = _calculateCouponDiscount(subtotal);

    double runningTotal = subtotal - discountAmount - couponDiscount;
    final Map<String, double> finalCharges = {};

    if (_billConfig != null) {
      for (var charge in _billConfig!.customCharges) {
        if (charge.isMandatory) {
          final chargeAmount = runningTotal * (charge.rate / 100.0);
          finalCharges['${charge.label} (${charge.rate.toStringAsFixed(1)}%)'] =
              chargeAmount;
          runningTotal += chargeAmount;
        }
      }
    }

    final adHocCharge = _calculateAdHocCharge(runningTotal);
    if (adHocCharge.value > 0) {
      finalCharges[adHocCharge.key] = adHocCharge.value;
      runningTotal += adHocCharge.value;
    }
    final grandTotal = runningTotal;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Current Bill', style: theme.textTheme.headlineSmall),
          const Divider(),
          _buildCustomerDetailsSection(),
          const SizedBox(height: 16),
          _buildOrderDetailsSection(),
          const Divider(),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48.0),
              child: Center(
                  child: Text('No items added yet.',
                      style: TextStyle(fontSize: 16))),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return ListTile(
                  title: Text('${item.quantity}x ${item.menuItem.name}'),
                  subtitle: item.selectedOptions.isEmpty
                      ? null
                      : Text(item.selectedOptions
                      .map((o) => o.optionName)
                      .join(', ')),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(formatter.format(item.totalPrice)),
                      IconButton(
                        icon: const Icon(Icons.delete_forever),
                        color: theme.colorScheme.error,
                        onPressed: () => _removeItemFromBill(item.uniqueId),
                        tooltip: 'Remove Item',
                      ),
                    ],
                  ),
                );
              },
            ),
          const SizedBox(height: 24),
          _buildSummaryRow('Subtotal', subtotal, theme, isTotal: true),
          const Divider(height: 32),
          Text('Discounts & Charges', style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          TextFormField(
              controller: _discountController,
              decoration: const InputDecoration(
                  labelText: 'Staff Discount (%)', suffixText: '%'),
              keyboardType: TextInputType.number),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                    controller: _couponController,
                    decoration: InputDecoration(
                        labelText: 'Coupon Code', errorText: _couponError),
                    textCapitalization: TextCapitalization.characters),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                  onPressed: () => _applyCoupon(subtotal),
                  child: const Text('Apply')),
            ],
          ),
          const Divider(height: 32),
          Text('Ad-Hoc Charges', style: theme.textTheme.titleMedium),
          _buildAdHocChargeInput(),
          const Divider(height: 32),
          Text('Final Breakdown', style: theme.textTheme.titleLarge),
          const Divider(height: 16),
          _buildSummaryRow('Subtotal', subtotal, theme),
          _buildSummaryRow('Staff Discount', -discountAmount, theme),
          if (_appliedCoupon != null)
            _buildSummaryRow(
                'Coupon: ${_appliedCoupon!.code}', -couponDiscount, theme),
          if (finalCharges.isNotEmpty) ...[
            const Divider(height: 16, thickness: 0.5),
            ...finalCharges.entries
                .map((e) => _buildSummaryRow(e.key, e.value, theme)),
          ],
          const Divider(height: 32),
          _buildSummaryRow('Grand Total', grandTotal, theme,
              isGrandTotal: true),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: items.isEmpty
                ? null
                : () => _showPaymentDialog(
              grandTotal,
              _discountPercentage,
              _appliedCoupon?.code,
              couponDiscount,
              finalCharges,
            ),
            icon: const Icon(Icons.payment),
            label: Text('Process Payment: ${formatter.format(grandTotal)}'),
            style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 20),
                textStyle: const TextStyle(fontSize: 18)),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerDetailsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_customers.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: Text('No customer added (optional).'),
            ),
          ),
        ..._customers.map((c) => Card(
          elevation: 1,
          child: ListTile(
            title: Text(c.name),
            subtitle: Text(c.phone),
            trailing: IconButton(
              icon: const Icon(Icons.close, size: 20),
              onPressed: () => setState(() => _customers.removeWhere((cust) => cust.id == c.id)),
            ),
          ),
        )),
        const SizedBox(height: 8),
        Center(
          child: OutlinedButton.icon(
            onPressed: _showAddEditCustomerDialog,
            icon: const Icon(Icons.add),
            label: const Text('Add Customer'),
          ),
        ),
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
          items: ['Dine-In', 'Takeaway', 'Delivery', 'Guest']
              .map((type) => DropdownMenuItem(value: type, child: Text(type)))
              .toList(),
          onChanged: (value) => setState(() {
            _orderType = value!;
          }),
        ),
        if (_orderType == 'Delivery') ...[
          const SizedBox(height: 16),
          TextFormField(
            controller: _addressController,
            decoration: const InputDecoration(labelText: 'Delivery Address'),
            maxLines: 2,
          ),
        ],
        const SizedBox(height: 16),
      ],
    );
  }

  Future<void> _applyCoupon(double subtotal) async {
    final code = _couponController.text.trim().toUpperCase();
    if (code.isEmpty) {
      setState(() {
        _appliedCoupon = null;
        _couponError = null;
      });
      return;
    }
    final snapshot = await FirebaseFirestore.instance
        .collection('restaurants')
        .doc(widget.restaurantId)
        .collection('coupons')
        .where('code', isEqualTo: code)
        .limit(1)
        .get();
    if (snapshot.docs.isEmpty) {
      setState(() => _couponError = 'Invalid Coupon Code');
      return;
    }
    final coupon = CouponModel.fromFirestore(snapshot.docs.first);
    if (subtotal * (1 - _discountPercentage) < coupon.minOrderAmount) {
      setState(() => _couponError =
      'Min order of ₹${coupon.minOrderAmount.toStringAsFixed(0)} not met.');
      return;
    }
    setState(() {
      _appliedCoupon = coupon;
      _couponError = null;
    });
  }

  double _calculateCouponDiscount(double subtotal) {
    if (_appliedCoupon == null) return 0.0;
    final discountedSubtotal = subtotal * (1 - _discountPercentage);
    if (discountedSubtotal < _appliedCoupon!.minOrderAmount) return 0.0;
    return _appliedCoupon!.type == 'percentage'
        ? discountedSubtotal * (_appliedCoupon!.value / 100.0)
        : _appliedCoupon!.value;
  }

  MapEntry<String, double> _calculateAdHocCharge(double base) {
    final value = double.tryParse(_adHocChargeController.text.trim()) ?? 0.0;
    final label = _adHocChargeLabelController.text.trim();
    String finalLabel = label.isNotEmpty ? label : 'Ad-Hoc Charge';
    if (value <= 0) return MapEntry(finalLabel, 0.0);
    if (_adHocChargeType == 'percentage') {
      return MapEntry('$finalLabel (${value.toStringAsFixed(1)}%)',
          base * (value / 100.0));
    }
    return MapEntry('$finalLabel (Fixed)', value);
  }

  Widget _buildAdHocChargeInput() {
    return Column(
      children: [
        TextFormField(
          controller: _adHocChargeLabelController,
          decoration: const InputDecoration(labelText: 'Charge Label/Reason'),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _adHocChargeController,
                decoration: InputDecoration(
                    labelText: _adHocChargeType == 'percentage'
                        ? 'Rate (%)'
                        : 'Amount (₹)'),
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 8),
            DropdownButton<String>(
              value: _adHocChargeType,
              items: const [
                DropdownMenuItem(value: 'percentage', child: Text('Percent')),
                DropdownMenuItem(value: 'fixed', child: Text('Fixed')),
              ],
              onChanged: (v) =>
              v != null ? setState(() => _adHocChargeType = v) : null,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSummaryRow(String label, double amount, ThemeData theme,
      {bool isTotal = false, bool isGrandTotal = false}) {
    final formatter = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
    TextStyle style = theme.textTheme.bodyLarge!;
    if (isGrandTotal) {
      style = theme.textTheme.headlineSmall!
          .copyWith(color: theme.primaryColor, fontWeight: FontWeight.bold);
    } else if (isTotal) {
      style =
          theme.textTheme.titleMedium!.copyWith(fontWeight: FontWeight.bold);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(formatter.format(amount), style: style),
        ],
      ),
    );
  }

  void _showPaymentDialog(
      double grandTotal,
      double discountPercentage,
      String? couponCode,
      double couponDiscount,
      Map<String, double> finalCharges,
      ) {
    showDialog(
      context: context,
      builder: (dialogContext) => _PaymentMethodDialog(
        grandTotal: grandTotal,
        onConfirm: (paymentMethod) async {
          Navigator.of(dialogContext).pop(); // Close payment dialog
          final sessionKey = await _createOrder(
            discountPercentage,
            couponCode,
            couponDiscount,
            paymentMethod,
            grandTotal,
            finalCharges,
          );

          // ✨ NEW: Call the global print function
          if (mounted) {
            await showPrintedBill(
              context: context,
              restaurantId: widget.restaurantId,
              sessionKey: sessionKey,
              paymentMethod: paymentMethod,
            );
          }
          _processFinalBill(); // Clear the screen for the next bill
        },
      ),
    );
  }

  Future<String> _createOrder(
      double discountPercentage,
      String? couponCode,
      double couponDiscount,
      String paymentMethod,
      double finalTotal,
      Map<String, double> finalCharges,
      ) async {

    final restaurantRef = FirebaseFirestore.instance.collection('restaurants').doc(widget.restaurantId);
    String newBillNumber = '';
    String sessionKey = '';

    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final restaurantDoc = await transaction.get(restaurantRef);
      final restaurantData = restaurantDoc.data() as Map<String, dynamic>?;

      int currentBillCount;

      // ✨ FIX: Check if the counter field exists.
      if (restaurantData != null && restaurantData.containsKey('totalBillCount')) {
        // If it exists, use it.
        currentBillCount = restaurantData['totalBillCount'];
      } else {
        // If not, count previous paid orders to initialize.
        final paidOrdersSnapshot = await restaurantRef
            .collection('orders')
            .where('isPaid', isEqualTo: true)
            .get();
        currentBillCount = paidOrdersSnapshot.docs.length;
      }

      newBillNumber = (currentBillCount + 1).toString().padLeft(4, '0');

      // Increment the bill count.
      transaction.update(restaurantRef, {'totalBillCount': currentBillCount + 1});

      // Create the new order document.
      final newOrderRef = restaurantRef.collection('orders').doc();
      sessionKey = 'QuickBill-$newBillNumber';

      final itemsForFirestore = _selectedItems.values.map((item) => {
        'menuItemId': item.menuItem.id,
        'name': item.menuItem.name,
        'price': item.menuItem.price,
        'quantity': item.quantity,
        'status': 'Completed',
        'selectedOptions': item.selectedOptions.map((o) => o.toMap()).toList(),
      }).toList();

      final chargesList = finalCharges.entries
          .map((e) => {'label': e.key, 'amount': e.value})
          .toList();

      transaction.set(newOrderRef, {
        'orderType': _orderType,
        'sessionKey': sessionKey,
        'items': itemsForFirestore,
        'totalAmount': finalTotal,
        'status': 'Completed',
        'isPaid': true,
        'isSessionActive': false,
        'createdAt': FieldValue.serverTimestamp(),
        'customers': _customers.map((c) => c.toMap()).toList(),
        'deliveryAddress': _orderType == 'Delivery' ? _addressController.text.trim() : null,
        'billingDetails': {
          'billNumber': newBillNumber,
          'discount': discountPercentage,
          'couponCode': couponCode,
          'couponDiscount': couponDiscount,
          'finalTotal': finalTotal,
          'paymentMethod': paymentMethod,
          'billedAt': FieldValue.serverTimestamp(),
          'appliedCharges': chargesList,
        }
      });
    });

    return sessionKey;
  }

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

  void _processFinalBill() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Bill Processed Successfully!'),
        backgroundColor: Colors.green,
      ),
    );

    setState(() {
      _selectedItems.clear();
      _discountController.clear();
      _couponController.clear();
      _adHocChargeController.clear();
      _adHocChargeLabelController.clear();
      _discountPercentage = 0.0;
      _appliedCoupon = null;
      _couponError = null;
    });
  }
}

class _MenuItemCard extends StatelessWidget {
  final MenuItem item;
  final int simpleItemQuantity;
  final int customizedItemCount;
  final VoidCallback onTap;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  const _MenuItemCard({
    required this.item,
    required this.simpleItemQuantity,
    required this.customizedItemCount,
    required this.onTap,
    required this.onIncrement,
    required this.onDecrement,
  });

  Widget _buildQuantityControls(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: onDecrement,
          color: theme.colorScheme.error,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: Text(
            simpleItemQuantity.toString(),
            style: theme.textTheme.titleMedium,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          onPressed: onIncrement,
          color: theme.primaryColor,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasOptions = item.optionGroups.isNotEmpty;
    final showQuantityControls = simpleItemQuantity > 0;
    final bool isActive = showQuantityControls || customizedItemCount > 0;

    return Card(
      elevation: isActive ? 4 : 2,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isActive ? theme.primaryColor : Colors.transparent,
          width: 2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              item.name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            Text(
              NumberFormat.currency(locale: 'en_IN', symbol: '₹')
                  .format(item.price),
              style: theme.textTheme.bodyMedium,
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  transitionBuilder: (child, animation) {
                    return ScaleTransition(scale: animation, child: child);
                  },
                  child: showQuantityControls
                      ? _buildQuantityControls(context)
                      : OutlinedButton(
                    key: const ValueKey('add_default'),
                    onPressed: onIncrement,
                    child: const Icon(Icons.add),
                  ),
                ),
                if (hasOptions) ...[
                  const SizedBox(height: 4),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: onTap,
                    icon: const Icon(Icons.tune, size: 20),
                    label: customizedItemCount > 0
                        ? CircleAvatar(
                      radius: 10,
                      backgroundColor: theme.primaryColor,
                      child: Text(
                        customizedItemCount.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    )
                        : const Text('Custom'),
                  ),
                ]
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomizeItemDialog extends StatefulWidget {
  final MenuItem menuItem;
  const _CustomizeItemDialog({required this.menuItem});

  @override
  State<_CustomizeItemDialog> createState() => _CustomizeItemDialogState();
}

class _CustomizeItemDialogState extends State<_CustomizeItemDialog> {
  final Map<String, SelectedOption> _selectedOptions = {};
  final _formKey = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Customize ${widget.menuItem.name}'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: widget.menuItem.optionGroups.map((group) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Text(group.name,
                        style: Theme.of(context).textTheme.titleLarge),
                  ),
                  if (group.isMultiSelect)
                    ...group.options
                        .map((option) => _buildCheckboxOption(group, option))
                  else
                    _buildRadioOptionGroup(group),
                ],
              );
            }).toList(),
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        ElevatedButton(
            onPressed: _confirmSelection, child: const Text('Add to Order')),
      ],
    );
  }

  void _confirmSelection() {
    if (_formKey.currentState!.validate()) {
      Navigator.of(context).pop(_selectedOptions.values.toList());
    }
  }

  Widget _buildRadioOptionGroup(OptionGroup group) {
    return FormField<String>(
      validator: (value) {
        if (group.isRequired && value == null) {
          return 'Please select an option for ${group.name}.';
        }
        return null;
      },
      builder: (state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...group.options
                .map((option) => _buildRadioOption(group, option, state)),
            if (state.hasError)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(state.errorText!,
                    style:
                    TextStyle(color: Theme.of(context).colorScheme.error)),
              )
          ],
        );
      },
    );
  }

  Widget _buildRadioOption(
      OptionGroup group, OptionItem option, FormFieldState<String> state) {
    return RadioListTile<String>(
      title: Text(option.name),
      subtitle: option.additionalPrice > 0
          ? Text('+ ₹${option.additionalPrice.toStringAsFixed(2)}')
          : null,
      value: option.name,
      groupValue: _selectedOptions[group.name]?.optionName,
      onChanged: (String? value) {
        setState(() {
          _selectedOptions[group.name] = SelectedOption(
            groupName: group.name,
            optionName: option.name,
            additionalPrice: option.additionalPrice,
            inventoryItemId: option.recipeLink.inventoryItemId,
            quantityUsed: option.recipeLink.quantityUsed,
          );
          state.didChange(value);
        });
      },
    );
  }

  Widget _buildCheckboxOption(OptionGroup group, OptionItem option) {
    return CheckboxListTile(
      title: Text(option.name),
      subtitle: option.additionalPrice > 0
          ? Text('+ ₹${option.additionalPrice.toStringAsFixed(2)}')
          : null,
      value: _selectedOptions.containsKey(option.name),
      onChanged: (bool? value) {
        setState(() {
          if (value == true) {
            _selectedOptions[option.name] = SelectedOption(
              groupName: group.name,
              optionName: option.name,
              additionalPrice: option.additionalPrice,
              inventoryItemId: option.recipeLink.inventoryItemId,
              quantityUsed: option.recipeLink.quantityUsed,
            );
          } else {
            _selectedOptions.remove(option.name);
          }
        });
      },
    );
  }
}

class _PaymentMethodDialog extends StatelessWidget {
  final double grandTotal;
  final Function(String paymentMethod) onConfirm;

  const _PaymentMethodDialog(
      {required this.grandTotal, required this.onConfirm});

  void _showOtherPaymentDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Other Payment Method'),
        content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'e.g., Gift Card')),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.of(dialogContext).pop(controller.text.trim());
              }
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    ).then((value) {
      if (value != null && value is String) onConfirm(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Select Payment Method'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Amount Due: ${formatter.format(grandTotal)}',
              style: theme.textTheme.titleLarge?.copyWith(
                  color: theme.primaryColor, fontWeight: FontWeight.bold)),
          const Divider(),
          _buildPaymentOption(
              context, 'Cash', Icons.money, () => onConfirm('Cash')),
          _buildPaymentOption(context, 'Card / POS', Icons.credit_card,
                  () => onConfirm('Card')),
          _buildPaymentOption(
              context, 'UPI / QR', Icons.qr_code, () => onConfirm('UPI')),
          _buildPaymentOption(context, 'Other', Icons.more_horiz,
                  () => _showOtherPaymentDialog(context)),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'))
      ],
    );
  }

  Widget _buildPaymentOption(
      BuildContext context, String title, IconData icon, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: Theme.of(context).primaryColor),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
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
      final customer = CustomerInfo(
          id: widget.customer?.id ?? const Uuid().v4(),
          name: _nameController.text.trim(),
          phone: _phoneController.text.trim());
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
              validator: (val) =>
              val!.isEmpty ? 'Phone cannot be empty' : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        ElevatedButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}