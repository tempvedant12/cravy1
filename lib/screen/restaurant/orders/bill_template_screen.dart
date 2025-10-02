// lib/screen/restaurant/orders/bill_template_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cravy/models/order_models.dart';
import 'package:cravy/screen/restaurant/billing_setup/bill_design_screen.dart';
import 'package:cravy/screen/restaurant/menu/menu_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:flutter/rendering.dart';
import 'dart:ui' as ui;
import 'dart:typed_data';

import '../billing_setup/manage_coupon_screen.dart';

class BillTemplateScreen extends StatefulWidget {
  final String restaurantId;
  final String sessionKey;
  final double grandTotal;
  final String paymentMethod;

  const BillTemplateScreen({
    super.key,
    required this.restaurantId,
    required this.sessionKey,
    required this.grandTotal,
    required this.paymentMethod,
  });

  @override
  State<BillTemplateScreen> createState() => _BillTemplateScreenState();
}

class _BillTemplateScreenState extends State<BillTemplateScreen> {
  Future<Map<String, dynamic>>? _detailsFuture;
  BillConfiguration? _selectedConfig;
  List<BillConfiguration> _allConfigs = [];
  final GlobalKey _billKey = GlobalKey();
  List<MenuItem> _allMenuItems = [];

  @override
  void initState() {
    super.initState();
    _detailsFuture = _fetchBillDetails();
  }

  Future<void> _printBill() async {
    try {
      final boundary =
      _billKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

      if (byteData == null) return;
      final Uint8List pngBytes = byteData.buffer.asUint8List();

      final pdf = pw.Document();
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.roll80,
          build: (pw.Context context) {
            return pw.Center(
              child: pw.Image(pw.MemoryImage(pngBytes)),
            );
          },
        ),
      );

      await Printing.layoutPdf(
        onLayout: (format) async => pdf.save(),
      );
    } catch (e) {
      if (mounted) {
        final errorMessage = 'Could not open print preview: $e';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage)),
        );
      }
    }
  }

  void _closeScreen() {

    Navigator.of(context).pop();
  }

  // --- NEW HELPER FUNCTION TO FETCH ALL MENU ITEMS CORRECTLY ---
  Future<List<MenuItem>> _fetchAllMenuItems(String restaurantId) async {
    final menusSnapshot = await FirebaseFirestore.instance
        .collection('restaurants')
        .doc(restaurantId)
        .collection('menus')
        .get();

    final List<MenuItem> allItems = [];
    for (var menuDoc in menusSnapshot.docs) {
      final itemsSnapshot = await menuDoc.reference.collection('items').get();
      allItems.addAll(itemsSnapshot.docs.map((doc) => MenuItem.fromFirestore(doc)));
    }
    return allItems;
  }
  // -------------------------------------------------------------

  Future<Map<String, dynamic>> _fetchBillDetails() async {
    final restaurantRef = FirebaseFirestore.instance
        .collection('restaurants')
        .doc(widget.restaurantId);

    // 1. Find the latest payment timestamp for this session
    final latestPaidOrderSnapshot = await restaurantRef
        .collection('orders')
        .where('sessionKey', isEqualTo: widget.sessionKey)
        .where('isPaid', isEqualTo: true)
        .orderBy('billingDetails.billedAt', descending: true)
        .limit(1)
        .get();

    Timestamp? latestBilledAt;
    if (latestPaidOrderSnapshot.docs.isNotEmpty) {
      latestBilledAt = (latestPaidOrderSnapshot.docs.first.data() as Map<String, dynamic>)['billingDetails']['billedAt'] as Timestamp?;
    }

    // 2. Prepare futures
    final List<Future> futures = [
      restaurantRef.get(),
      restaurantRef.collection('billConfigurations').get(),
      _fetchAllMenuItems(widget.restaurantId),
    ];

    // 3. Prepare order query (fetch only orders matching the latest transaction timestamp)
    Query orderQuery = restaurantRef
        .collection('orders')
        .where('sessionKey', isEqualTo: widget.sessionKey)
        .where('isPaid', isEqualTo: true);

    if (latestBilledAt != null) {
      // FIX: Filter orders by the precise timestamp of the last successful batch transaction
      orderQuery = orderQuery.where('billingDetails.billedAt', isEqualTo: latestBilledAt);
    }

    futures.add(orderQuery.get()); // Add the filtered order query

    final results = await Future.wait(futures);

    // Re-index results
    final restaurantDoc = results[0] as DocumentSnapshot;
    final configsSnapshot = results[1] as QuerySnapshot;
    _allMenuItems = results[2] as List<MenuItem>;
    final orderDocsSnapshot = results[3] as QuerySnapshot; // This is the filtered list


    final restaurantData = restaurantDoc.data() as Map<String, dynamic>? ?? {};
    final defaultBillConfigId =
    restaurantData['defaultBillConfigId'] as String?;

    // --- NEW: Fetch Coupon Details ---
    CouponModel? coupon;
    final orderDocs = orderDocsSnapshot.docs; // Use the newly filtered docs list
    if (orderDocs.isNotEmpty) {
      final billingDetails = (orderDocs.first.data() as Map<String, dynamic>)['billingDetails'] as Map<String, dynamic>? ?? {};
      final couponCode = billingDetails['couponCode'] as String?;
      if (couponCode != null && couponCode.isNotEmpty) {
        final couponSnapshot = await restaurantRef.collection('coupons').where('code', isEqualTo: couponCode).get();
        if (couponSnapshot.docs.isNotEmpty) {
          coupon = CouponModel.fromFirestore(couponSnapshot.docs.first);
        }
      }
    }
    // ---------------------------------

    final allConfigs = configsSnapshot.docs
        .map((doc) => BillConfiguration.fromFirestore(doc))
        .toList();

    return {
      'restaurantName': restaurantData['name'] ?? 'Restaurant Name Not Set',
      'restaurantAddress': restaurantData['address'] ?? 'Address Not Set',
      'billConfigs': allConfigs,
      'defaultBillConfigId': defaultBillConfigId,
      'orders': orderDocsSnapshot.docs,
      'coupon': coupon, // <--- RETURN COUPON
    };
  }

  Map<String, OrderItem> _aggregateOrders(List<QueryDocumentSnapshot> orders) {
    final aggregatedItems = <String, OrderItem>{};
    for (var orderDoc in orders) {
      final orderData = orderDoc.data() as Map<String, dynamic>;
      final items = List<Map<String, dynamic>>.from(orderData['items'] ?? []);
      for (var itemMap in items) {
        // FIX: The _allMenuItems is now guaranteed to have data if the fetch succeeded
        final item = OrderItem.fromMap(itemMap, _allMenuItems);
        if (aggregatedItems.containsKey(item.uniqueId)) {
          aggregatedItems[item.uniqueId]!.quantity += item.quantity;
        } else {
          aggregatedItems[item.uniqueId] = item;
        }
      }
    }
    return aggregatedItems;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Preview & Print Bill'),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _detailsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return Center(child: Text('Error loading bill data: ${snapshot.error}'));
          }
          if ((snapshot.data?['orders'] as List).isEmpty) {
            return const Center(child: Text('No paid orders found for this session.'));
          }

          final details = snapshot.data!;

          if (_allConfigs.isEmpty || _allConfigs.length != (details['billConfigs'] as List).length) {
            _allConfigs = details['billConfigs'] as List<BillConfiguration>;
            final defaultId = details['defaultBillConfigId'] as String?;
            if (_allConfigs.isNotEmpty) {
              _selectedConfig = _allConfigs.firstWhere((c) => c.id == defaultId, orElse: () => _allConfigs.first);
            }
          }

          return Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(12, 24, 12, 0),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 400),
                      child: Column(
                        children: [
                          if (_allConfigs.isNotEmpty) _buildDesignSelectorButton(context),
                          const SizedBox(height: 16),
                          RepaintBoundary(
                            key: _billKey,
                            child: _buildBillContent(context, details),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              _buildBottomBar(context),
            ],
          );
        },
      ),
    );
  }

  void _showDesignSelectionDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Choose a Bill Design'),
          contentPadding: const EdgeInsets.only(top: 20),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _allConfigs.length,
                    itemBuilder: (context, index) {
                      final config = _allConfigs[index];
                      return ListTile(
                        title: Text(config.template),
                        trailing: _selectedConfig?.id == config.id ? Icon(Icons.check_circle, color: Theme.of(context).primaryColor) : null,
                        onTap: () {
                          setState(() => _selectedConfig = config);
                          Navigator.of(dialogContext).pop();
                        },
                      );
                    },
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.add_circle_outline),
                  title: const Text('Add New Design'),
                  onTap: () {
                    Navigator.of(dialogContext).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => BillDesignScreen(restaurantId: widget.restaurantId),
                      ),
                    ).then((_) => setState(() => _detailsFuture = _fetchBillDetails()));
                  },
                )
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDesignSelectorButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0),
      child: OutlinedButton.icon(
        icon: const Icon(Icons.style_outlined),
        label: Text('Change Design: (${_selectedConfig?.template ?? 'N/A'})'),
        onPressed: () => _showDesignSelectionDialog(context),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(double.infinity, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget _buildBillContent(BuildContext context, Map<String, dynamic> details) {
    if (_selectedConfig == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('No bill designs found.'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (context) => BillDesignScreen(restaurantId: widget.restaurantId)),
                  ).then((_) => setState(() => _detailsFuture = _fetchBillDetails()));
                },
                child: const Text('Create First Design'),
              )
            ],
          ),
        ),
      );
    }

    final orderDocs = details['orders'] as List<QueryDocumentSnapshot>;
    final billTheme = BillTheme.getThemeByName(_selectedConfig!.template);
    // Get the billing details which contain the final calculated amounts
    final billingDetails = (orderDocs.first.data() as Map<String, dynamic>)['billingDetails'] as Map<String, dynamic>? ?? {};

    // --- MODIFIED CALCULATIONS: READ SAVED VALUES ---
    final aggregatedItems = _aggregateOrders(orderDocs).values.toList();
    final subtotal = aggregatedItems.fold(0.0, (sum, item) => sum + item.totalPrice);

    // 1. Read Staff Discount Percentage and calculate amount from subtotal
    final discountPercentage = (billingDetails['discount'] ?? 0.0).toDouble();
    final staffDiscountAmount = subtotal * discountPercentage;

    // 2. READ Coupon Discount Amount directly from saved details
    // This is the final amount applied in BillingScreen (which handles min order logic)
    final couponDiscountAmount = (billingDetails['couponDiscount'] ?? 0.0).toDouble();

    // 3. READ Applied Charges (Mandatory + Ad-Hoc) directly from saved details
    final List<dynamic> appliedChargesList = billingDetails['appliedCharges'] as List<dynamic>? ?? [];
    final Map<String, double> calculatedCharges = {};

    // Map the saved list of charges (mandatory and ad-hoc) back to the map expected by BillTemplate
    for (var chargeMap in appliedChargesList) {
      if (chargeMap is Map<String, dynamic>) {
        final label = chargeMap['label'] as String? ?? 'Charge';
        final amount = (chargeMap['amount'] as num? ?? 0.0).toDouble();
        calculatedCharges[label] = amount;
      }
    }
    // --- END MODIFIED CALCULATIONS ---

    final sampleItems = aggregatedItems.map((item) {
      String name = item.menuItem.name;
// ...
      return {'name': name, 'qty': item.quantity, 'price': item.singleItemPrice};
    }).toList();

    return BillTemplate(
      theme: billTheme,
      restaurantName: details['restaurantName'],
      restaurantAddress: details['restaurantAddress'],
      phone: _selectedConfig!.contactPhone,
      gst: _selectedConfig!.gstNumber,
      footer: _selectedConfig!.footerNote,
      notes: _selectedConfig!.billNotes,
      sampleItems: sampleItems.cast<Map<String, Object>>(),
      subtotal: subtotal,
      staffDiscount: staffDiscountAmount,
      couponDiscount: couponDiscountAmount, // Use the READ value
      calculatedCharges: calculatedCharges, // Use the READ value
      total: billingDetails['finalTotal'] ?? widget.grandTotal, // Use the final saved total
      billNumber: orderDocs.first.id.substring(0, 8).toUpperCase(),
      sessionKey: widget.sessionKey,
      paymentMethod: widget.paymentMethod,
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -5))],
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _printBill,
              icon: const Icon(Icons.print_outlined),
              label: const Text('Print Bill'),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _closeScreen,
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Done'),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
            ),
          ),
        ],
      ),
    );
  }
}