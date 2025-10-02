import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cravy/models/order_models.dart';
import 'package:cravy/screen/restaurant/menu/menu_screen.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../billing_setup/manage_coupon_screen.dart';
import 'bill_template_screen.dart';
import '../billing_setup/bill_design_screen.dart'; // Import for BillConfiguration

class BillingScreen extends StatefulWidget {
  final String restaurantId;
  final String sessionKey;

  const BillingScreen({
    super.key,
    required this.restaurantId,
    required this.sessionKey,
  });

  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen> {
  final TextEditingController _discountController = TextEditingController();
  final TextEditingController _couponController = TextEditingController();

  // --- NEW: Ad-hoc charge state ---
  final TextEditingController _adHocChargeController = TextEditingController();
  String _adHocChargeType = 'percentage'; // 'percentage' or 'fixed'
  final TextEditingController _adHocChargeLabelController = TextEditingController(); // ADDED
  // ---------------------------------

  double _discountPercentage = 0.0;
  CouponModel? _appliedCoupon;
  String? _couponError;
  List<MenuItem> _allMenuItems = [];

  // --- NEW: Bill Config state ---
  BillConfiguration? _billConfig;
  Future<void>? _initialDataLoad;
  // ------------------------------

  @override
  void initState() {
    super.initState();
    _discountController.addListener(_onDiscountChanged);
    _adHocChargeController.addListener(_recalculateBill); // NEW
    _adHocChargeLabelController.addListener(_recalculateBill); // ADDED
    _initialDataLoad = _loadInitialData(); // Start loading data
  }


  // --- NEW: Combined data loading function ---
  Future<void> _loadInitialData() async {
    await _fetchAllMenuItems();
    await _fetchBillConfiguration();
  }

  Future<void> _fetchBillConfiguration() async {
    final restaurantRef = FirebaseFirestore.instance.collection('restaurants').doc(widget.restaurantId);
    final restaurantDoc = await restaurantRef.get();
    final defaultBillConfigId = restaurantDoc.data()?['defaultBillConfigId'];

    if (defaultBillConfigId != null) {
      final configDoc = await restaurantRef.collection('billConfigurations').doc(defaultBillConfigId).get();
      if (configDoc.exists && mounted) {
        setState(() {
          _billConfig = BillConfiguration.fromFirestore(configDoc);
        });
      }
    }
  }
  // -------------------------------------------

  // Trigger recalculation when ad-hoc charge changes
  void _recalculateBill() {
    if (mounted) setState(() {});
  }

  Future<void> _fetchAllMenuItems() async {
    // FIX: Iterate through all menus to fetch all items
    final menusSnapshot = await FirebaseFirestore.instance
        .collection('restaurants')
        .doc(widget.restaurantId)
        .collection('menus')
        .get();

    final List<MenuItem> allItems = [];

    for (var menuDoc in menusSnapshot.docs) {
      final itemsSnapshot = await menuDoc.reference.collection('items').get();
      allItems.addAll(itemsSnapshot.docs.map((doc) => MenuItem.fromFirestore(doc)));
    }

    if (mounted) {
      setState(() {
        _allMenuItems = allItems;
      });
    }
  }


  @override
  void dispose() {
    _discountController.dispose();
    _couponController.dispose();
    _adHocChargeController.dispose(); // NEW
    _adHocChargeLabelController.dispose(); // ADDED
    super.dispose();
  }

  void _onDiscountChanged() {
    final value = double.tryParse(_discountController.text) ?? 0.0;
    if (value >= 0 && value <= 100) {
      setState(() {
        _discountPercentage = value / 100.0;
      });
    }
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

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('restaurants')
          .doc(widget.restaurantId)
          .collection('coupons')
          .where('code', isEqualTo: code)
          .get();

      if (snapshot.docs.isEmpty) {
        setState(() {
          _appliedCoupon = null;
          _couponError = 'Invalid Coupon Code';
        });
        return;
      }

      final coupon = CouponModel.fromFirestore(snapshot.docs.first);

      if (subtotal * (1 - _discountPercentage) < coupon.minOrderAmount) { // FIX: Check against subtotal AFTER staff discount
        setState(() {
          _appliedCoupon = null;
          _couponError =
          'Min order amount of ₹${coupon.minOrderAmount.toStringAsFixed(2)} not met after staff discount.';
        });
        return;
      }

      setState(() {
        _appliedCoupon = coupon;
        _couponError = null;
      });
    } catch (e) {
      setState(() {
        _appliedCoupon = null;
        _couponError = 'Error applying coupon.';
      });
    }
  }

  double _calculateCouponDiscount(double subtotal) {
    if (_appliedCoupon == null) return 0.0;
    final discountedSubtotal = subtotal * (1 - _discountPercentage);

    // Re-validate minimum amount after staff discount
    if (discountedSubtotal < _appliedCoupon!.minOrderAmount) {
      // Don't call setState here, just return 0. The future builder will handle the state update/error if necessary.
      return 0.0;
    }

    if (_appliedCoupon!.type == 'percentage') {
      return discountedSubtotal * (_appliedCoupon!.value / 100.0);
    } else {
      return _appliedCoupon!.value;
    }
  }

  // --- NEW: Calculates the value of the ad-hoc charge based on type and value ---
  MapEntry<String, double> _calculateAdHocCharge(double subtotalAfterDiscounts) {
    final input = _adHocChargeController.text.trim();
    final value = double.tryParse(input) ?? 0.0;

    // Use user-provided label or a default
    final userLabel = _adHocChargeLabelController.text.trim();
    String finalLabel = userLabel.isNotEmpty ? userLabel : 'Ad-Hoc Charge';

    if (value <= 0) return MapEntry(finalLabel, 0.0);

    if (_adHocChargeType == 'percentage') {
      final amount = subtotalAfterDiscounts * (value / 100.0);
      finalLabel = '$finalLabel (${input}%)'; // Append percentage to label
      return MapEntry(finalLabel, amount);
    } else { // Fixed amount
      finalLabel = '$finalLabel (Fixed)'; // Append fixed tag to label
      return MapEntry(finalLabel, value);
    }
  }
  // -----------------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          const _StaticBackground(),
          FutureBuilder( // Check if initial data (config/menu items) is loaded
            future: _initialDataLoad,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting || _allMenuItems.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }

              // Now proceed with the StreamBuilder for orders
              return Scaffold(
                backgroundColor: Colors.transparent,
                appBar: AppBar(
                  title: Text('Bill: ${widget.sessionKey}'),
                  backgroundColor: Theme.of(context).scaffoldBackgroundColor.withOpacity(0.85),
                  elevation: 0,
                ),
                body: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('restaurants')
                      .doc(widget.restaurantId)
                      .collection('orders')
                      .where('sessionKey', isEqualTo: widget.sessionKey)
                      .where('isSessionActive', isEqualTo: true)
                      .snapshots(),
                  builder: (context, orderSnapshot) {
                    if (!orderSnapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final sessionOrders = orderSnapshot.data!.docs;
                    if (sessionOrders.isEmpty) {
                      return const Center(
                          child: Text('Orders not found for this session.'));
                    }

                    final aggregatedItems = _aggregateOrders(sessionOrders);
                    final subtotal = aggregatedItems.values
                        .fold(0.0, (sum, item) => sum + item.totalPrice);

                    final discountAmount = subtotal * _discountPercentage;
                    final couponDiscount = _calculateCouponDiscount(subtotal);

                    // --- FIX: Calculate Running Total and Charges ---
                    // Initialize the running total after applying discounts
                    double runningTotal = subtotal - discountAmount - couponDiscount;

                    final Map<String, double> finalCharges = {};

                    // 1. Mandatory Custom Charges from Config (Compounding)
                    if (_billConfig != null) {
                      for (var charge in _billConfig!.customCharges) {
                        // Check if the charge is marked as mandatory to be applied automatically
                        if (charge.isMandatory) {
                          // Calculate the charge amount based on the current running total
                          final chargeAmount = runningTotal * (charge.rate / 100.0);

                          finalCharges['${charge.label} (${charge.rate.toStringAsFixed(1)}%)'] = chargeAmount;

                          // Add the charge amount to the running total (compounding)
                          runningTotal += chargeAmount;
                        }
                      }
                    }

                    // 2. Ad-Hoc Charge (Compounding)
                    final MapEntry<String, double> adHocCharge = _calculateAdHocCharge(runningTotal);
                    if (adHocCharge.value > 0) {
                      finalCharges[adHocCharge.key] = adHocCharge.value;
                      // Add the ad-hoc charge to the running total
                      runningTotal += adHocCharge.value;
                    }

                    // The final total is the value of the running total after all calculations
                    final grandTotal = runningTotal;
                    // -----------------------------------------------------------


                    return _buildBillUI(
                      context,
                      aggregatedItems.values.toList(),
                      subtotal,
                      discountAmount,
                      couponDiscount,
                      grandTotal,
                      sessionOrders,
                      finalCharges, // Pass the final charges map
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Map<String, OrderItem> _aggregateOrders(List<DocumentSnapshot> orders) {
    final aggregatedItems = <String, OrderItem>{};

    for (var orderDoc in orders) {
      final orderData = orderDoc.data() as Map<String, dynamic>;
      if (orderData['isPaid'] != true) {
        final items =
        List<Map<String, dynamic>>.from(orderData['items'] ?? []);
        for (var itemMap in items) {
          final item = OrderItem.fromMap(itemMap, _allMenuItems);
          if (aggregatedItems.containsKey(item.uniqueId)) {
            aggregatedItems[item.uniqueId]!.quantity += item.quantity;
          } else {
            aggregatedItems[item.uniqueId] = item;
          }
        }
      }
    }
    return aggregatedItems;
  }

  Widget _buildBillUI(
      BuildContext context,
      List<OrderItem> items,
      double subtotal,
      double discountAmount,
      double couponDiscount,
      double grandTotal,
      List<DocumentSnapshot> sessionOrders,
      Map<String, double> finalCharges, // NEW: Receive the final charges map
      ) {
    final theme = Theme.of(context);
    final formatter = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Items to be Billed', style: theme.textTheme.titleLarge),
              const Divider(),
              if (items.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24.0),
                  child: Center(
                      child:
                      Text('All items in this session have been paid.')),
                )
              else
                ...items.map((item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('${item.quantity}x',
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(item.menuItem.name,
                                  style: theme.textTheme.bodyMedium)),
                          Text(formatter.format(item.totalPrice),
                              style: theme.textTheme.bodyMedium),
                        ],
                      ),
                      if (item.selectedOptions.isNotEmpty)
                        Padding(
                          padding:
                          const EdgeInsets.only(left: 24.0, top: 4.0),
                          child: Text(
                            item.selectedOptions
                                .map((o) => o.optionName)
                                .join(', '),
                            style: theme.textTheme.bodySmall,
                          ),
                        )
                    ],
                  ),
                )),
              const SizedBox(height: 24),
              _buildSummaryRow('Subtotal', subtotal, theme, isTotal: true),
              const Divider(height: 32),
              Text('Discounts & Charges', style: theme.textTheme.titleLarge),
              const SizedBox(height: 16),

              // --- DISCOUNT INPUTS ---
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _discountController,
                      decoration: const InputDecoration(
                          labelText: 'Staff Discount (%)',
                          hintText: 'e.g., 10',
                          suffixText: '%'),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 16),
                  TextButton(
                      onPressed: () => _discountController.text = '0',
                      child: const Text('Clear'))
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _couponController,
                      decoration: InputDecoration(
                          labelText: 'Coupon Code',
                          hintText: 'e.g., SAVE20',
                          errorText: _couponError),
                      textCapitalization: TextCapitalization.characters,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                      onPressed: () => _applyCoupon(subtotal),
                      child: const Text('Apply')),
                ],
              ),
              // --- END DISCOUNT INPUTS ---


              const Divider(height: 32),

              // --- CHARGES INPUT (Ad-Hoc) ---
              Text('Ad-Hoc Charges (Optional)', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              _buildAdHocChargeInput(),
              // --- END CHARGES INPUT ---


              const Divider(height: 32),
              // --- FINAL BREAKDOWN SUMMARY ---
              Text('Final Breakdown', style: theme.textTheme.titleLarge),
              const Divider(height: 16),

              // 1. Subtotal
              _buildSummaryRow('Subtotal', subtotal, theme),

              // 2. Staff Discount (Shows as negative amount)
              _buildSummaryRow('Staff Discount', -discountAmount, theme),

              // 3. Coupon Discount (Shows as negative amount)
              if (_appliedCoupon != null)
                _buildSummaryRow('Coupon: ${_appliedCoupon!.code}', -couponDiscount, theme),

              // 4. Mandatory and Ad-Hoc Charges (Taxes/Charges added here)
              if (finalCharges.isNotEmpty) ...[
                const Divider(height: 16), // Separates discounts from charges
                ...finalCharges.entries.map((entry) {
                  return _buildSummaryRow(
                      entry.key, // e.g., 'Service Tax (5.0%)' or 'Ad-Hoc Charge'
                      entry.value, // The calculated positive charge amount
                      theme,
                      isTotal: false);
                }).toList(),
              ],
              // --- END FINAL BREAKDOWN SUMMARY ---


              const Divider(height: 32),
              _buildSummaryRow('Grand Total', grandTotal, theme,
                  isGrandTotal: true),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: items.isEmpty
                    ? null
                    : () => _showPaymentDialog(
                  grandTotal,
                  sessionOrders,
                  _discountPercentage,
                  _appliedCoupon?.code,
                  couponDiscount, // Pass the final coupon amount
                  finalCharges, // Pass the FINAL list of charges
                ),
                icon: const Icon(Icons.payment),
                label:
                Text('Process Payment: ${formatter.format(grandTotal)}'),
                style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 20)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // NEW: UI for Ad-Hoc Charge Input
  Widget _buildAdHocChargeInput() {
    final theme = Theme.of(context);
    return Column( // Wrap in column to add the label input
      children: [
        TextFormField(
          controller: _adHocChargeLabelController,
          decoration: const InputDecoration(
              labelText: 'Charge Label/Reason',
              hintText: 'e.g., Delivery Fee, Special Service'
          ),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextFormField(
                controller: _adHocChargeController,
                decoration: InputDecoration(
                    labelText: _adHocChargeType == 'percentage' ? 'Rate (%)' : 'Amount (₹)',
                    hintText: 'e.g., 5 or 50.00',
                    suffixText: _adHocChargeType == 'percentage' ? '%' : '₹'),
                keyboardType: TextInputType.number,
                validator: (val) => (val != null && val.isNotEmpty && double.tryParse(val) == null) ? 'Invalid number' : null,
              ),
            ),
            const SizedBox(width: 8),
            DropdownButton<String>(
              value: _adHocChargeType,
              items: const [
                DropdownMenuItem(value: 'percentage', child: Text('Percent')),
                DropdownMenuItem(value: 'fixed', child: Text('Fixed')),
              ],
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _adHocChargeType = val;
                  });
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.clear, size: 20),
              onPressed: () {
                // Clear both label and value
                _adHocChargeController.clear();
                _adHocChargeLabelController.clear();
              },
            )
          ],
        ),
      ],
    );
  }

  void _showPaymentDialog(
      double grandTotal,
      List<DocumentSnapshot> sessionOrders,
      double discountPercentage,
      String? couponCode,
      double couponDiscount, // NEW: Coupon discount amount
      Map<String, double> finalCharges, // NEW: Final charges map
      ) {
    showDialog(
      context: context,
      builder: (dialogContext) => _PaymentMethodDialog(
        grandTotal: grandTotal,
        onConfirm: (paymentMethod) async {
          Navigator.of(dialogContext).pop();
          await _markOrderAsPaid(
            sessionOrders,
            discountPercentage,
            couponCode,
            couponDiscount, // Pass coupon discount amount
            paymentMethod,
            grandTotal,
            finalCharges, // Pass the final charges map
          );
          if (mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) => BillTemplateScreen(
                  restaurantId: widget.restaurantId,
                  sessionKey: widget.sessionKey,
                  grandTotal: grandTotal,
                  paymentMethod: paymentMethod,
                ),
              ),
            );
          }
        },
      ),
    );
  }

  Future<void> _markOrderAsPaid(
      List<DocumentSnapshot> sessionOrders,
      double discountPercentage,
      String? couponCode,
      double couponDiscount, // NEW: Coupon discount amount
      String paymentMethod,
      double finalTotal,
      Map<String, double> finalCharges, // NEW: Receive final charges map
      ) async {
    final batch = FirebaseFirestore.instance.batch();

    // Create a list of charges suitable for Firestore storage
    final List<Map<String, dynamic>> chargesList = finalCharges.entries.map((e) => {
      'label': e.key,
      'amount': e.value,
    }).toList();

    // This line is corrected to handle cases where 'isPaid' might be null
    final unpaidOrders = sessionOrders.where((doc) => (doc.data() as Map<String, dynamic>)['isPaid'] != true).toList();

    for (var orderDoc in unpaidOrders) {
      batch.update(orderDoc.reference, {
        'isPaid': true,
        'billingDetails': {
          'discount': discountPercentage,
          'couponCode': couponCode,
          'couponDiscount': couponDiscount, // FIX: Store coupon discount amount
          'finalTotal': finalTotal,
          'paymentMethod': paymentMethod,
          'billedAt': FieldValue.serverTimestamp(),
          'appliedCharges': chargesList, // Store the applied charges
        }
      });
    }
    await batch.commit();
  }

  Widget _buildSummaryRow(String label, double amount, ThemeData theme,
      {bool isTotal = false, bool isGrandTotal = false}) {
    final formatter = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
    TextStyle style = theme.textTheme.titleMedium!;
    if (isGrandTotal) {
      style = theme.textTheme.headlineMedium!.copyWith(color: theme.primaryColor);
    } else if (isTotal) {
      style = theme.textTheme.titleLarge!;
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

// --- ADDED _StaticBackground Class ---
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
                theme.colorScheme.surface.withOpacity(isDark ? 0.3 : 0.2),
                450),
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