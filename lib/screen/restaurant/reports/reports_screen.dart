// lib/screen/restaurant/reports/reports_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cravy/models/supplier_model.dart';
import 'package:cravy/screen/restaurant/menu/menu_screen.dart';
import 'package:cravy/screen/restaurant/staff/staff_and_roles_screen.dart';
import 'package:flutter/material.dart';
import 'dart:ui'; // For Glassmorphism effects
import 'package:intl/intl.dart';
import 'dart:math';

// =======================================================
// TOP-LEVEL MODELS
// =======================================================

class SalesSummary {
  final double totalRevenue;
  final double averageBill;
  final int totalOrders;
  final double profitEstimate; // This will now be based on Net Income
  SalesSummary(
      {required this.totalRevenue,
        required this.averageBill,
        required this.totalOrders,
        required this.profitEstimate});
}

class ProductPerformance {
  final String itemName;
  final int unitsSold;
  final double totalSales;
  ProductPerformance(
      {required this.itemName, required this.unitsSold, required this.totalSales});
}

// =======================================================
// MAIN SCREEN
// =======================================================

class ReportsScreen extends StatefulWidget {
  final String restaurantId;
  const ReportsScreen({super.key, required this.restaurantId});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen>
    with TickerProviderStateMixin {
  late Future<Map<String, dynamic>> _reportDataFuture;
  List<MenuItem> _allMenuItems = [];
  Map<String, String> _allMenus = {}; // Map<MenuName, MenuName>

  // --- Filter State ---
  String _selectedPeriod = 'Today';
  DateTimeRange? _customDateRange;
  String _selectedTransactionType = 'All';
  String _selectedMenuName = 'All'; // Filter by name, as it's saved on the order
  // --------------------

  TimeOfDay _businessDayStartTime = const TimeOfDay(hour: 0, minute: 0);
  bool _isLoadingSettings = true;

  @override
  void initState() {
    super.initState();
    _reportDataFuture = _loadData();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadInitialSettings() async {
    if (mounted) {
      setState(() => _isLoadingSettings = true);
    }
    try {
      // 1. Fetch Restaurant Settings (for day start time)
      final doc = await FirebaseFirestore.instance
          .collection('restaurants')
          .doc(widget.restaurantId)
          .get();

      if (doc.exists && doc.data()!.containsKey('businessDayStartTime')) {
        final timeString = doc.data()!['businessDayStartTime'] as String;
        final parts = timeString.split(':');
        _businessDayStartTime =
            TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
      } else {
        _businessDayStartTime = const TimeOfDay(hour: 0, minute: 0);
      }

      // 2. Fetch All Menu Items AND Menu Names
      if (_allMenuItems.isEmpty) {
        await _fetchAllMenuItemsAndMenus();
      }
    } catch (e) {
      print("Error loading report settings: $e");
    }
    if (mounted) {
      setState(() => _isLoadingSettings = false);
    }
  }

  Future<Map<String, dynamic>> _loadData() async {
    // Ensure settings are loaded before fetching report data
    if (_isLoadingSettings || _allMenuItems.isEmpty) {
      await _loadInitialSettings();
    }
    return _fetchReportData(
      _selectedPeriod,
      _selectedTransactionType,
      _selectedMenuName,
      customRange: _customDateRange,
    );
  }

  Future<void> _fetchAllMenuItemsAndMenus() async {
    final menusSnapshot = await FirebaseFirestore.instance
        .collection('restaurants')
        .doc(widget.restaurantId)
        .collection('menus')
        .get();

    final List<MenuItem> allItems = [];
    // Initialize with 'All'
    final Map<String, String> allMenus = {'All': 'All Menus'};

    for (var menuDoc in menusSnapshot.docs) {
      // Use menu NAME as the key for filtering, as this is what's on the order item
      allMenus[menuDoc['name']] = menuDoc['name'];
      final itemsSnapshot = await menuDoc.reference.collection('items').get();
      allItems.addAll(
          itemsSnapshot.docs.map((doc) => MenuItem.fromFirestore(doc)));
    }

    if (mounted) {
      setState(() {
        _allMenuItems = allItems;
        _allMenus = allMenus;
      });
    }
  }

  DateTimeRange _getBusinessDateRange(String period, TimeOfDay dayStartTime,
      {DateTimeRange? customRange}) {
    DateTime now = DateTime.now();
    DateTime todayBusinessStart = DateTime(
        now.year, now.month, now.day, dayStartTime.hour, dayStartTime.minute);

    if (now.isBefore(todayBusinessStart)) {
      todayBusinessStart = todayBusinessStart.subtract(const Duration(days: 1));
    }
    DateTime todayBusinessEnd =
    todayBusinessStart.add(const Duration(days: 1));

    switch (period) {
      case 'Today':
        return DateTimeRange(start: todayBusinessStart, end: todayBusinessEnd);
      case 'This Week':
        final daysToSubtract = todayBusinessStart.weekday -
            1; // 1 (Mon) - 1 = 0; 7 (Sun) - 1 = 6
        final startOfWeek =
        todayBusinessStart.subtract(Duration(days: daysToSubtract));
        return DateTimeRange(start: startOfWeek, end: todayBusinessEnd);
      case 'This Month':
        final startOfMonth = DateTime(todayBusinessStart.year,
            todayBusinessStart.month, 1, dayStartTime.hour, dayStartTime.minute);
        return DateTimeRange(start: startOfMonth, end: todayBusinessEnd);
      case 'This Year':
        final startOfYear = DateTime(todayBusinessStart.year, 1, 1,
            dayStartTime.hour, dayStartTime.minute);
        return DateTimeRange(start: startOfYear, end: todayBusinessEnd);
      case 'Custom':
        if (customRange != null) {
          final customStart = DateTime(
              customRange.start.year,
              customRange.start.month,
              customRange.start.day,
              dayStartTime.hour,
              dayStartTime.minute);
          final customEnd = DateTime(
              customRange.end.year,
              customRange.end.month,
              customRange.end.day,
              dayStartTime.hour,
              dayStartTime.minute)
              .add(const Duration(days: 1));
          return DateTimeRange(start: customStart, end: customEnd);
        }
        return DateTimeRange(start: todayBusinessStart, end: todayBusinessEnd);
      case 'All':
      default:
        return DateTimeRange(start: DateTime(2020), end: DateTime(2099));
    }
  }

  Future<List<Map<String, dynamic>>> _fetchStaffPayments(
      DateTimeRange dateRange) async {
    final List<Map<String, dynamic>> staffTransactions = [];
    final staffSnapshot = await FirebaseFirestore.instance
        .collection('restaurants')
        .doc(widget.restaurantId)
        .collection('staff')
        .get();

    for (final staffDoc in staffSnapshot.docs) {
      final paymentsSnapshot = await staffDoc.reference
          .collection('payments')
          .where('paidAt', isGreaterThanOrEqualTo: dateRange.start)
          .where('paidAt', isLessThan: dateRange.end)
          .get();
      for (final paymentDoc in paymentsSnapshot.docs) {
        final data = paymentDoc.data();
        staffTransactions.add({
          'name': (staffDoc.data())['name'] ?? 'Unknown',
          'amount': (data['amount'] as num?)?.toDouble() ?? 0.0,
        });
      }
    }
    return staffTransactions;
  }

  Future<Map<String, dynamic>> _fetchReportData(
      String period,
      String transactionType,
      String menuName, {
        DateTimeRange? customRange,
      }) async {
    DateTimeRange dateRange =
    _getBusinessDateRange(period, _businessDayStartTime, customRange: customRange);

    double totalSalesRevenue = 0;
    double totalSupplierCosts = 0;
    double totalStaffCosts = 0;
    int totalOrders = 0;
    final Map<String, int> productSales = {};
    final Map<String, double> orderTypeDistribution = {};
    final Map<String, List<DocumentSnapshot>> orderTypeDetails = {};
    final Map<String, double> categoryRevenue = {};
    final Map<String, double> dailyTimeSeriesRevenue = {};
    final Map<String, double> supplierSpendings = {};
    final Map<String, double> staffSpendings = {};
    final menuItemsMap = {for (var item in _allMenuItems) item.id: item};

    // --- 1. FETCH RESTAURANT SALES ---
    if (transactionType == 'All' || transactionType == 'Restaurant Sales') {
      Query salesQuery = FirebaseFirestore.instance
          .collection('restaurants')
          .doc(widget.restaurantId)
          .collection('orders')
          .where('isPaid', isEqualTo: true);

      if (period != 'All') {
        salesQuery = salesQuery
            .where('billingDetails.billedAt',
            isGreaterThanOrEqualTo: dateRange.start)
            .where('billingDetails.billedAt', isLessThan: dateRange.end);
      }

      final salesSnapshot = await salesQuery.get();
      final Map<String, List<QueryDocumentSnapshot>> bills = {};
      for (var doc in salesSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final key = data['billingDetails']?['billNumber'] as String? ??
            data['sessionKey'] as String? ??
            doc.id;
        bills.putIfAbsent(key, () => []).add(doc);
      }
      totalOrders = bills.length;

      for (var billGroup in bills.values) {
        final doc = billGroup.first;
        final data = doc.data() as Map<String, dynamic>;

        final finalTotal =
            (data['billingDetails']?['finalTotal'] as num?)?.toDouble() ?? 0.0;
        totalSalesRevenue += finalTotal;

        final billedAt =
        (data['billingDetails']?['billedAt'] as Timestamp?)?.toDate();
        if (billedAt != null) {
          DateTime businessDayStartForBill = DateTime(
              billedAt.year,
              billedAt.month,
              billedAt.day,
              _businessDayStartTime.hour,
              _businessDayStartTime.minute);
          if (billedAt.isBefore(businessDayStartForBill)) {
            businessDayStartForBill =
                businessDayStartForBill.subtract(const Duration(days: 1));
          }
          final dateKey = DateFormat('MMM d').format(businessDayStartForBill);
          dailyTimeSeriesRevenue.update(dateKey, (value) => value + finalTotal,
              ifAbsent: () => finalTotal);
        }

        final orderType = (data['orderType'] as String?) ?? 'Dine-In';
        orderTypeDistribution.update(orderType, (value) => value + 1,
            ifAbsent: () => 1);
        orderTypeDetails.putIfAbsent(orderType, () => []).add(doc);

        for (var orderDoc in billGroup) {
          final orderData = orderDoc.data() as Map<String, dynamic>;
          final items =
          List<Map<String, dynamic>>.from(orderData['items'] ?? []);
          for (var item in items) {
            final itemMenuName = item['menuName'] as String? ?? '';

            if (menuName != 'All' && itemMenuName != menuName) {
              continue;
            }

            final name = item['name'] as String;
            final qty = (item['quantity'] as num?)?.toInt() ?? 0;
            final productKey = '$name ($itemMenuName)';
            productSales.update(productKey, (value) => value + qty,
                ifAbsent: () => qty);

            final itemPrice = (item['price'] as num?)?.toDouble() ?? 0.0;
            final itemTotal = (itemPrice * qty).toDouble();

            final menuItem = menuItemsMap[item['menuItemId']];
            String category = menuItem?.category ?? 'Other';
            final categoryKey = '$category ($itemMenuName)';
            categoryRevenue.update(categoryKey, (value) => value + itemTotal,
                ifAbsent: () => itemTotal);
          }
        }
      }
    }

    // --- 2. FETCH SUPPLIER COSTS ---
    if (transactionType == 'All' || transactionType == 'Supplier Costs') {
      Query poQuery = FirebaseFirestore.instance
          .collection('restaurants')
          .doc(widget.restaurantId)
          .collection('purchaseOrders')
          .where('paymentStatus', isEqualTo: 'Paid');

      if (period != 'All') {
        poQuery = poQuery
            .where('orderDate', isGreaterThanOrEqualTo: dateRange.start)
            .where('orderDate', isLessThan: dateRange.end);
      }

      final poSnapshot = await poQuery.get();
      for (var doc in poSnapshot.docs) {
        final po = PurchaseOrder.fromFirestore(doc);
        final amount = po.amountPaid > 0 ? po.amountPaid : po.totalAmount;
        totalSupplierCosts += amount;
        supplierSpendings.update(po.supplierName, (value) => value + amount,
            ifAbsent: () => amount);
      }
    }

    // --- 3. FETCH STAFF COSTS ---
    if (transactionType == 'All' || transactionType == 'Staff Costs') {
      final staffPayments = await _fetchStaffPayments(dateRange);
      for (var payment in staffPayments) {
        final amount = payment['amount'] as double;
        final name = payment['name'] as String;
        totalStaffCosts += amount;
        staffSpendings.update(name, (value) => value + amount,
            ifAbsent: () => amount);
      }
    }

    // --- 4. PREPARE FINAL DATA ---
    final sortedTimeSeriesRevenue = Map.fromEntries(
        dailyTimeSeriesRevenue.entries.toList()
          ..sort((a, b) => DateFormat('MMM d')
              .parse(a.key)
              .compareTo(DateFormat('MMM d').parse(b.key))));

    final topSelling = productSales.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final inventorySnapshot = await FirebaseFirestore.instance
        .collection('restaurants')
        .doc(widget.restaurantId)
        .collection('inventory')
        .get();

// --- FIX: Calculate profit estimate based on SALES only ---
    double profitEstimate = totalSalesRevenue * 0.35;
// ---------------------------------------------------------

// Determine final revenue number
    double displayRevenue = 0;
// double profitEstimate = 0; // <-- REMOVED
    String revenueTitle = 'Total Revenue';

    if (transactionType == 'All') {
      // --- FIX: Change logic to be a SUM as requested ---
      displayRevenue = totalSalesRevenue + totalSupplierCosts + totalStaffCosts;
      revenueTitle = 'Total Transactions'; // <-- Rename title
    } else if (transactionType == 'Restaurant Sales') {
      displayRevenue = totalSalesRevenue;
      revenueTitle = 'Total Revenue (Sales)';
      // profitEstimate = totalSalesRevenue * 0.35; // <-- REMOVED (already calculated above)
    } else if (transactionType == 'Supplier Costs') {
      displayRevenue = totalSupplierCosts;
      revenueTitle = 'Total Supplier Costs';
    } else if (transactionType == 'Staff Costs') {
      displayRevenue = totalStaffCosts;
      revenueTitle = 'Total Staff Costs';
    }

    return {
      'salesSummary': SalesSummary(
        totalRevenue: displayRevenue,
        totalOrders: totalOrders,
        averageBill: totalOrders > 0 ? totalSalesRevenue / totalOrders : 0,
        profitEstimate: profitEstimate,
      ),
      'revenueTitle': revenueTitle,
      'topSelling': topSelling
          .map((e) => ProductPerformance(
          itemName: e.key, unitsSold: e.value, totalSales: 0))
          .toList(),
      'lowStockCount': inventorySnapshot.docs.where((doc) {
        final data = doc.data();
        final quantity = (data['quantity'] as num?)?.toDouble() ?? 0.0;
        final threshold =
            (data['lowStockThreshold'] as num?)?.toDouble() ?? 0.0;
        return quantity <= threshold;
      }).length,
      'timeSeriesRevenue': sortedTimeSeriesRevenue,
      'orderTypeDistribution': Map.fromEntries(orderTypeDistribution.entries
          .map((e) => MapEntry(e.key, e.value.toDouble()))),
      'orderTypeDetails': orderTypeDetails,
      'categoryRevenue': categoryRevenue,
      'supplierSpendings': supplierSpendings,
      'staffSpendings': staffSpendings,
    };
  }

  Future<void> _showDayStartTimePicker() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _businessDayStartTime,
      helpText: 'Select your business day start time',
    );
    if (picked != null && picked != _businessDayStartTime) {
      final formattedTime =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      await FirebaseFirestore.instance
          .collection('restaurants')
          .doc(widget.restaurantId)
          .update({'businessDayStartTime': formattedTime});

      setState(() {
        _businessDayStartTime = picked;
        _reportDataFuture = _loadData();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'Business day start time updated to ${picked.format(context)}')),
      );
    }
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _customDateRange,
    );
    if (picked != null) {
      setState(() {
        _customDateRange = picked;
        _selectedPeriod = 'Custom';
        _reportDataFuture = _loadData();
      });
    }
  }

  String _getAppBarTitle() {
    String title = 'Reports';
    String periodText = _selectedPeriod;
    if (_selectedPeriod == 'Custom' && _customDateRange != null) {
      periodText =
      '${DateFormat.yMd().format(_customDateRange!.start)} - ${DateFormat.yMd().format(_customDateRange!.end)}';
    }
    return '$title ($periodText)';
  }

  // --- NEW: Build the filter bar ---
  PreferredSizeWidget _buildFilterBar(ThemeData theme) {
    final bgColor = theme.scaffoldBackgroundColor.withOpacity(0.85);

    // Options for dropdowns
    final List<String> periodOptions = [
      'Today', 'This Week', 'This Month', 'This Year', 'All', 'Custom'
    ];
    final List<String> transactionTypeOptions = [
      'All', 'Restaurant Sales', 'Supplier Costs', 'Staff Costs'
    ];
    // Menu options are from _allMenus.keys

    return PreferredSize(
      preferredSize: const Size.fromHeight(80.0), // Increased height
      child: Container(
        color: bgColor,
        padding: const EdgeInsets.all(12.0),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              // --- 1. Date Range Filter ---
              _buildFilterDropdown(
                context: context,
                label: "Date Range",
                icon: Icons.date_range_outlined,
                value: _selectedPeriod,
                items: periodOptions.map((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(
                      value == 'Custom' && _customDateRange != null
                          ? '${DateFormat.yMd().format(_customDateRange!.start)} - ${DateFormat.yMd().format(_customDateRange!.end)}'
                          : value,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  if (newValue == 'Custom') {
                    _selectDateRange(); // This will set state and reload
                  } else {
                    setState(() {
                      _selectedPeriod = newValue!;
                      _customDateRange = null;
                      _reportDataFuture = _loadData();
                    });
                  }
                },
              ),
              const SizedBox(width: 12),

              // --- 2. Transaction Type Filter ---
              _buildFilterDropdown(
                context: context,
                label: "Transaction Type",
                icon: Icons.swap_horiz_outlined,
                value: _selectedTransactionType,
                items: transactionTypeOptions.map((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  setState(() {
                    _selectedTransactionType = newValue!;
                    _reportDataFuture = _loadData();
                  });
                },
              ),
              const SizedBox(width: 12),

              // --- 3. Menu Filter ---
              _buildFilterDropdown(
                context: context,
                label: "Menu (Product Reports)",
                icon: Icons.menu_book_outlined,
                value: _selectedMenuName,
                items: _allMenus.keys.map((String menuName) {
                  return DropdownMenuItem<String>(
                    value: menuName,
                    child: Text(menuName),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  setState(() {
                    _selectedMenuName = newValue!;
                    _reportDataFuture = _loadData();
                  });
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- NEW: Helper widget for styled dropdowns ---
  Widget _buildFilterDropdown({
    required BuildContext context,
    required String label,
    required String value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    return Container(
      width: 200, // Give them a fixed width
      padding: const EdgeInsets.only(left: 12, right: 8),
      child: DropdownButtonFormField<String>(
        value: value,
        items: items,
        onChanged: onChanged,
        isExpanded: true, // Allow text to fill
        decoration: InputDecoration(
          prefixIcon: Icon(icon, size: 18, color: theme.primaryColor),
          labelText: label,
          labelStyle:
          theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
          border: InputBorder.none, // Clean look
          filled: false, // <-- FIX: Remove inner background
          contentPadding: const EdgeInsets.fromLTRB(0, 16, 12, 16),
        ),
        dropdownColor: theme.colorScheme.surface,
        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold), // Style for selected item
        isDense: true,
        icon: const Icon(Icons.arrow_drop_down),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = Theme.of(context); // Get theme here

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF1414E) : Colors.grey[50],
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          const _PremiumBackground(),
          NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) {
              return [
                SliverAppBar(
                  title: Text(_getAppBarTitle(),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  pinned: true,
                  floating: true,
                  snap: true,
                  forceElevated: innerBoxIsScrolled,
                  backgroundColor:
                  theme.scaffoldBackgroundColor.withOpacity(0.85), // FIX
                  elevation: 0,
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.av_timer_outlined),
                      onPressed: _showDayStartTimePicker,
                      tooltip: 'Set Business Day Start Time',
                    ),
                  ],
                  bottom: _buildFilterBar(theme), // FIX
                ),
              ];
            },
            body: FutureBuilder<Map<String, dynamic>>(
              future: _reportDataFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting ||
                    _isLoadingSettings) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  print(snapshot.error); // For debugging
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: Text('No data available.'));
                }

                final data = snapshot.data!;
                final summary = data['salesSummary'] as SalesSummary;
                final revenueTitle = data['revenueTitle'] as String;
                final topSelling =
                data['topSelling'] as List<ProductPerformance>;
                final lowStockCount = data['lowStockCount'] as int;

                final timeSeriesRevenue =
                    (data['timeSeriesRevenue'] as Map<String, double>?) ?? {};
                final orderTypeDistribution =
                    (data['orderTypeDistribution'] as Map<String, double>?) ??
                        {};
                final orderTypeDetails =
                    (data['orderTypeDetails']
                    as Map<String, List<DocumentSnapshot>>?) ??
                        {};
                final categoryRevenue =
                    (data['categoryRevenue'] as Map<String, double>?) ?? {};
                final supplierSpendings =
                    (data['supplierSpendings'] as Map<String, double>?) ?? {};
                final staffSpendings =
                    (data['staffSpendings'] as Map<String, double>?) ?? {};

                final theme = Theme.of(context);
                final screenWidth = MediaQuery.of(context).size.width;
                final salesGridCount =
                screenWidth > 1200 ? 4 : (screenWidth > 600 ? 2 : 1);
                final chartGridCount = screenWidth > 800 ? 2 : 1;
                final productGridCount =
                screenWidth > 1000 ? 3 : (screenWidth > 600 ? 2 : 1);
                final costGridCount = screenWidth > 800 ? 2 : 1;
                final chartAspectRatio = screenWidth > 800 ? 1.8 : 1.2;
                final productAspectRatio = screenWidth > 1000 ? 1.0 : 1.2;
                final costAspectRatio = screenWidth > 800 ? 1.2 : 1.2;

                return ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    Padding(
                      padding:
                      const EdgeInsets.fromLTRB(20.0, 24.0, 20.0, 20.0),
                      child: GridView.count(
                        physics: const NeverScrollableScrollPhysics(),
                        shrinkWrap: true,
                        crossAxisCount: salesGridCount,
                        crossAxisSpacing: 20,
                        mainAxisSpacing: 20,
                        childAspectRatio: 1.5,
                        children: [
                          _GlassmorphicReportCard(
                            title: revenueTitle,
                            value:
                            '₹${NumberFormat.compactLong().format(summary.totalRevenue)}',
                            icon: Icons.attach_money,
                            color: Colors.green,
                          ),
                          _GlassmorphicReportCard(
                            title: 'Total Orders',
                            value: NumberFormat.compact()
                                .format(summary.totalOrders),
                            icon: Icons.receipt_long,
                            color: Colors.blue,
                          ),
                          _GlassmorphicReportCard(
                            title: 'Avg. Bill Value',
                            value: '₹${summary.averageBill.toStringAsFixed(2)}',
                            icon: Icons.trending_up,
                            color: Colors.purple,
                          ),
                          _GlassmorphicReportCard(
                            title: 'Profit Estimate',
                            value:
                            '₹${NumberFormat.compactLong().format(summary.profitEstimate)}',
                            icon: Icons.bar_chart,
                            color: Colors.orange,
                          ),
                        ],
                      ),
                    ),

                    // --- Conditionally show sales charts ---
                    if (_selectedTransactionType == 'All' ||
                        _selectedTransactionType == 'Restaurant Sales') ...[
                      _buildSectionHeader(theme, 'Sales & Order Breakdown',
                          Icons.timeline_outlined),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20.0),
                        child: GridView.count(
                          physics: const NeverScrollableScrollPhysics(),
                          shrinkWrap: true,
                          crossAxisCount: chartGridCount,
                          crossAxisSpacing: 20,
                          mainAxisSpacing: 20,
                          childAspectRatio: chartAspectRatio,
                          children: [
                            _GlassmorphicChartCard(
                              child: _DailyRevenueBarChart(
                                theme: theme,
                                title: 'Daily Revenue',
                                data: timeSeriesRevenue,
                                color: Colors.green.shade500,
                                onTap: () => _showDailyRevenueDetails(
                                    context, timeSeriesRevenue),
                              ),
                            ),
                            _GlassmorphicChartCard(
                              child: GestureDetector(
                                onTap: () => _showOrderTypeDetails(
                                    context, orderTypeDetails),
                                child: _PieChartContent(
                                    theme,
                                    'Order Type Split',
                                    orderTypeDistribution,
                                    Colors.blue.shade500),
                              ),
                            ),
                          ],
                        ),
                      ),
                      _buildSectionHeader(
                          theme,
                          'Product Performance & Inventory',
                          Icons.local_dining_outlined),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20.0),
                        child: GridView.count(
                          physics: const NeverScrollableScrollPhysics(),
                          shrinkWrap: true,
                          crossAxisCount: productGridCount,
                          crossAxisSpacing: 20,
                          mainAxisSpacing: 20,
                          childAspectRatio: productAspectRatio,
                          children: [
                            _GlassmorphicListReportCard(
                              title:
                              'Top Selling Items${_selectedMenuName != 'All' ? ' ($_selectedMenuName)' : ''}',
                              items: topSelling,
                              onTap: () => _showTopSellingItemsDetails(
                                  context, topSelling),
                            ),
                            _GlassmorphicChartCard(
                              child: _CategoryBarContent(
                                  theme: theme,
                                  title:
                                  'Sales by Group${_selectedMenuName != 'All' ? ' ($_selectedMenuName)' : ''}',
                                  data: categoryRevenue,
                                  color: Colors.purple.shade500),
                            ),
                            if (productGridCount > 2)
                              _GlassmorphicAlertCard(
                                  title: 'Inventory Alerts',
                                  value: '$lowStockCount Items',
                                  subtitle: 'Are below low-stock threshold.',
                                  color: Colors.red,
                                  icon: Icons.warning_amber_outlined),
                          ],
                        ),
                      ),
                    ],

                    // --- Conditionally show cost charts ---
                    if (_selectedTransactionType == 'All' ||
                        _selectedTransactionType == 'Supplier Costs' ||
                        _selectedTransactionType == 'Staff Costs') ...[
                      _buildSectionHeader(theme, 'Cost & Expense Insights',
                          Icons.local_shipping_outlined),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 80),
                        child: GridView.count(
                          physics: const NeverScrollableScrollPhysics(),
                          shrinkWrap: true,
                          crossAxisCount: costGridCount,
                          crossAxisSpacing: 20,
                          mainAxisSpacing: 20,
                          childAspectRatio: costAspectRatio,
                          children: [
                            if (_selectedTransactionType == 'All' ||
                                _selectedTransactionType == 'Supplier Costs')
                              _GlassmorphicChartCard(
                                child: GestureDetector(
                                  onTap: () => _showSupplierSpendingDetails(
                                      context, supplierSpendings),
                                  child: _SupplierSpendingBarContent(
                                      theme: theme,
                                      title: 'Supplier Spending',
                                      data: supplierSpendings,
                                      color: Colors.teal.shade500),
                                ),
                              ),
                            if (_selectedTransactionType == 'All' ||
                                _selectedTransactionType == 'Staff Costs')
                              _GlassmorphicChartCard(
                                child: GestureDetector(
                                  onTap: () => _showStaffSpendingDetails(
                                      context, staffSpendings),
                                  child: _StaffSpendingBarContent(
                                      theme: theme,
                                      title: 'Staff Spending',
                                      data: staffSpendings,
                                      color: Colors.amber.shade700),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ]
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showDailyRevenueDetails(
      BuildContext context, Map<String, double> dailyRevenue) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          expand: false,
          builder: (BuildContext context, ScrollController scrollController) {
            return _DailyRevenueDetailsSheet(
              dailyRevenue: dailyRevenue,
              scrollController: scrollController,
            );
          },
        );
      },
    );
  }

  void _showOrderTypeDetails(
      BuildContext context, Map<String, List<DocumentSnapshot>> orderTypeDetails) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (BuildContext context, ScrollController scrollController) {
            return _OrderTypeDetailsSheet(
              orderTypeDetails: orderTypeDetails,
            );
          },
        );
      },
    );
  }

  void _showTopSellingItemsDetails(
      BuildContext context, List<ProductPerformance> topSelling) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          expand: false,
          builder: (BuildContext context, ScrollController scrollController) {
            return _TopSellingItemsSheet(
              topSellingItems: topSelling,
              scrollController: scrollController,
            );
          },
        );
      },
    );
  }

  void _showSupplierSpendingDetails(
      BuildContext context, Map<String, double> supplierSpendings) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          expand: false,
          builder: (BuildContext context, ScrollController scrollController) {
            return _SupplierSpendingDetailsSheet(
              supplierSpendings: supplierSpendings,
              scrollController: scrollController,
            );
          },
        );
      },
    );
  }

  // --- NEW: Show Staff Spending Details ---
  void _showStaffSpendingDetails(
      BuildContext context, Map<String, double> staffSpendings) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          expand: false,
          builder: (BuildContext context, ScrollController scrollController) {
            return _StaffSpendingDetailsSheet(
              staffSpendings: staffSpendings,
              scrollController: scrollController,
            );
          },
        );
      },
    );
  }

  // =======================================================
  // HELPER METHODS
  // =======================================================

  Widget _buildSectionHeader(ThemeData theme, String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 40, 20, 16),
      child: Row(
        children: [
          Icon(icon, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: theme.textTheme.bodyLarge?.color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _PieChartContent(
      ThemeData theme, String title, Map<String, double> data, Color color) {
    final total = data.values.fold(0.0, (sum, item) => sum + item);
    final colors = [
      color,
      color.withOpacity(0.6),
      color.withOpacity(0.4),
      color.withOpacity(0.2),
      color.withOpacity(0.1)
    ];

    final primaryEntry =
    data.entries.fold(const MapEntry('', 0.0), (a, b) => a.value > b.value ? a : b);
    final primaryPercentage = total > 0 ? (primaryEntry.value / total * 100) : 0;

    final List<MapEntry<String, double>> sortedEntries = data.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    const String explanation =
        'Shows the percentage split of orders by type. Essential for capacity planning.';

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(explanation,
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.textTheme.bodyLarge?.color?.withOpacity(0.7)),
              softWrap: true),
          const Divider(height: 20),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  flex: 1,
                  child: LayoutBuilder(builder: (context, constraints) {
                    final chartSize =
                        min(constraints.maxHeight, constraints.maxWidth) * 0.9;
                    return Center(
                      child: SizedBox(
                        width: chartSize,
                        height: chartSize,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              width: chartSize,
                              height: chartSize,
                              decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: primaryEntry.key.isEmpty
                                          ? Colors.grey.withOpacity(0.3)
                                          : color.withOpacity(0.3),
                                      width: 4)),
                            ),
                            Text(
                                primaryEntry.key.isEmpty
                                    ? '0%'
                                    : '${primaryPercentage.toStringAsFixed(0)}%',
                                style: theme.textTheme.headlineMedium?.copyWith(
                                    color: color, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
                Expanded(
                  flex: 2,
                  child: ListView(
                    padding: const EdgeInsets.only(left: 10),
                    children: sortedEntries.asMap().entries.map((entry) {
                      final index = entry.key;
                      final e = entry.value;
                      final percent = total > 0 ? (e.value / total) * 100 : 0;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: Row(
                          children: [
                            Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                    color: colors[index % colors.length],
                                    shape: BoxShape.circle)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${e.key}: ${percent.toStringAsFixed(1)}%',
                                style: theme.textTheme.bodyLarge
                                    ?.copyWith(fontWeight: FontWeight.w500),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
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

class _CategoryBarContent extends StatefulWidget {
  final ThemeData theme;
  final String title;
  final Map<String, double> data;
  final Color color;

  const _CategoryBarContent({
    required this.theme,
    required this.title,
    required this.data,
    required this.color,
  });

  @override
  __CategoryBarContentState createState() => __CategoryBarContentState();
}

class __CategoryBarContentState extends State<_CategoryBarContent> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final maxRevenue = widget.data.values.fold(0.0, (a, b) => max(a, b));
    const String explanation = 'Compares total revenue generated by each item group.';
    final currencyFormatter =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    final List<MapEntry<String, double>> sortedData =
    widget.data.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final itemsToShow = _isExpanded ? sortedData : sortedData.take(3).toList();

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title,
              style: widget.theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(explanation,
              style: widget.theme.textTheme.bodySmall?.copyWith(
                  color:
                  widget.theme.textTheme.bodyLarge?.color?.withOpacity(0.7)),
              softWrap: true),
          const Divider(height: 24),
          Expanded(
            child: AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              child: Column(
                children: [
                  Expanded(
                    child: ListView.builder(
                      itemCount: itemsToShow.length,
                      itemBuilder: (context, index) {
                        final e = itemsToShow[index];
                        final barWidth = maxRevenue > 0 ? (e.value / maxRevenue) : 0;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              FittedBox(
                                child: Text(e.key,
                                    style: widget.theme.textTheme.bodyLarge),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Expanded(
                                    child: Container(
                                      height: 14,
                                      alignment: Alignment.centerLeft,
                                      decoration: BoxDecoration(
                                        color: widget.color.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(7),
                                      ),
                                      child: FractionallySizedBox(
                                        widthFactor:
                                        barWidth.clamp(0.0, 1.0).toDouble(),
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: widget.color,
                                            borderRadius:
                                            BorderRadius.circular(7),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  FittedBox(
                                    child: Text(
                                      currencyFormatter.format(e.value),
                                      style: widget
                                          .theme.textTheme.bodyMedium
                                          ?.copyWith(
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  if (sortedData.length > 3)
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _isExpanded = !_isExpanded;
                        });
                      },
                      child: Text(_isExpanded ? 'Show Less' : 'Show More'),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SupplierSpendingBarContent extends StatefulWidget {
  final ThemeData theme;
  final String title;
  final Map<String, double> data;
  final Color color;

  const _SupplierSpendingBarContent({
    required this.theme,
    required this.title,
    required this.data,
    required this.color,
  });

  @override
  __SupplierSpendingBarContentState createState() =>
      __SupplierSpendingBarContentState();
}

class __SupplierSpendingBarContentState
    extends State<_SupplierSpendingBarContent> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final maxSpending = widget.data.values.fold(0.0, (a, b) => max(a, b));
    final currencyFormatter =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    const String explanation =
        'Identifies your largest suppliers by total spending.';
    final List<MapEntry<String, double>> sortedData =
    widget.data.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final itemsToShow = _isExpanded ? sortedData : sortedData.take(3).toList();

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title,
              style: widget.theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(explanation,
              style: widget.theme.textTheme.bodySmall?.copyWith(
                  color:
                  widget.theme.textTheme.bodyLarge?.color?.withOpacity(0.7)),
              softWrap: true),
          const Divider(height: 24),
          if (itemsToShow.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  'No supplier spending data for this period.',
                  style: widget.theme.textTheme.bodyLarge,
                ),
              ),
            )
          else
            Expanded(
              child: AnimatedSize(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                alignment: Alignment.topCenter,
                child: Column(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        itemCount: itemsToShow.length,
                        itemBuilder: (context, index) {
                          final e = itemsToShow[index];
                          final barWidth =
                          maxSpending > 0 ? (e.value / maxSpending) : 0;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                FittedBox(
                                  child: Text(e.key,
                                      style: widget.theme.textTheme.bodyLarge),
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Container(
                                        height: 16,
                                        alignment: Alignment.centerLeft,
                                        decoration: BoxDecoration(
                                          color: widget.color.withOpacity(0.1),
                                          borderRadius:
                                          BorderRadius.circular(8),
                                        ),
                                        child: FractionallySizedBox(
                                          widthFactor: barWidth
                                              .clamp(0.0, 1.0)
                                              .toDouble(),
                                          child: Container(
                                            decoration: BoxDecoration(
                                              color: widget.color,
                                              borderRadius:
                                              BorderRadius.circular(8),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    FittedBox(
                                      child: Text(
                                        currencyFormatter.format(e.value),
                                        style: widget.theme.textTheme.bodyMedium
                                            ?.copyWith(
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    if (sortedData.length > 3)
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _isExpanded = !_isExpanded;
                          });
                        },
                        child: Text(_isExpanded ? 'Show Less' : 'Show More'),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// --- NEW: Staff Spending Bar Chart ---
class _StaffSpendingBarContent extends StatefulWidget {
  final ThemeData theme;
  final String title;
  final Map<String, double> data;
  final Color color;

  const _StaffSpendingBarContent({
    required this.theme,
    required this.title,
    required this.data,
    required this.color,
  });

  @override
  __StaffSpendingBarContentState createState() =>
      __StaffSpendingBarContentState();
}

class __StaffSpendingBarContentState extends State<_StaffSpendingBarContent> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final maxSpending = widget.data.values.fold(0.0, (a, b) => max(a, b));
    final currencyFormatter =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    const String explanation = 'Shows total payments made to staff members.';
    final List<MapEntry<String, double>> sortedData =
    widget.data.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final itemsToShow = _isExpanded ? sortedData : sortedData.take(3).toList();

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title,
              style: widget.theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(explanation,
              style: widget.theme.textTheme.bodySmall?.copyWith(
                  color:
                  widget.theme.textTheme.bodyLarge?.color?.withOpacity(0.7)),
              softWrap: true),
          const Divider(height: 24),
          if (itemsToShow.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  'No staff spending data for this period.',
                  style: widget.theme.textTheme.bodyLarge,
                ),
              ),
            )
          else
            Expanded(
              child: AnimatedSize(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                alignment: Alignment.topCenter,
                child: Column(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        itemCount: itemsToShow.length,
                        itemBuilder: (context, index) {
                          final e = itemsToShow[index];
                          final barWidth =
                          maxSpending > 0 ? (e.value / maxSpending) : 0;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                FittedBox(
                                  child: Text(e.key,
                                      style: widget.theme.textTheme.bodyLarge),
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Container(
                                        height: 16,
                                        alignment: Alignment.centerLeft,
                                        decoration: BoxDecoration(
                                          color: widget.color.withOpacity(0.1),
                                          borderRadius:
                                          BorderRadius.circular(8),
                                        ),
                                        child: FractionallySizedBox(
                                          widthFactor: barWidth
                                              .clamp(0.0, 1.0)
                                              .toDouble(),
                                          child: Container(
                                            decoration: BoxDecoration(
                                              color: widget.color,
                                              borderRadius:
                                              BorderRadius.circular(8),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    FittedBox(
                                      child: Text(
                                        currencyFormatter.format(e.value),
                                        style: widget.theme.textTheme.bodyMedium
                                            ?.copyWith(
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    if (sortedData.length > 3)
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _isExpanded = !_isExpanded;
                          });
                        },
                        child: Text(_isExpanded ? 'Show Less' : 'Show More'),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// =======================================================
// PREMIUM TOP-LEVEL WIDGETS AND PAINTERS
// =======================================================

class _GlassmorphicReportCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _GlassmorphicReportCard(
      {required this.title,
        required this.value,
        required this.icon,
        required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardColor =
    isDark ? Colors.white.withOpacity(0.05) : Colors.white.withOpacity(0.6);

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, size: 28, color: color),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color:
                        theme.textTheme.bodyLarge?.color?.withOpacity(0.8),
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              FittedBox(
                child: Text(
                  value,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: theme.textTheme.bodyLarge?.color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassmorphicChartCard extends StatelessWidget {
  final Widget child;
  const _GlassmorphicChartCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardColor =
    isDark ? Colors.white.withOpacity(0.05) : Colors.white.withOpacity(0.6);

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
        ),
        child: RepaintBoundary(
          child: child,
        ),
      ),
    );
  }
}

class _GlassmorphicAlertCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;

  const _GlassmorphicAlertCard(
      {required this.title,
        required this.value,
        required this.subtitle,
        required this.icon,
        required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardColor =
    isDark ? Colors.white.withOpacity(0.05) : Colors.white.withOpacity(0.6);

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 32, color: color),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: theme.textTheme.bodyLarge?.color
                              ?.withOpacity(0.8)),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      child: Text(
                        value,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: color,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color:
                        theme.textTheme.bodyLarge?.color?.withOpacity(0.7),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassmorphicListReportCard extends StatelessWidget {
  final String title;
  final List<ProductPerformance> items;
  final VoidCallback onTap;

  const _GlassmorphicListReportCard(
      {required this.title, required this.items, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardColor =
    isDark ? Colors.white.withOpacity(0.05) : Colors.white.withOpacity(0.6);

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const Divider(height: 24),
                Expanded(
                  child: items.isEmpty
                      ? Center(
                      child: Text('No product sales yet.',
                          style: theme.textTheme.bodyLarge))
                      : ListView.separated(
                    itemCount:
                    items.length > 5 ? 5 : items.length, // Show top 5
                    separatorBuilder: (context, index) => Divider(
                        color: theme.dividerColor.withOpacity(0.5),
                        height: 1),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor:
                          theme.colorScheme.primary.withOpacity(0.1),
                          child: Text(
                            '#${index + 1}',
                            style: TextStyle(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.bold,
                                fontSize: 12),
                          ),
                        ),
                        title: Text(item.itemName,
                            style: theme.textTheme.bodyLarge
                                ?.copyWith(fontWeight: FontWeight.w500)),
                        trailing: Text('${item.unitsSold} units',
                            style: theme.textTheme.bodyLarge?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.bold)),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PremiumBackground extends StatelessWidget {
  const _PremiumBackground();
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.primaryColor;
    final accentColor = theme.colorScheme.secondary;

    return Container(
      color: theme.scaffoldBackgroundColor,
      child: Stack(
        children: [
          Positioned(
            top: -100,
            left: -150,
            child: _buildShape(
                primaryColor.withOpacity(isDark ? 0.2 : 0.1), 350),
          ),
          Positioned(
            bottom: -150,
            right: -200,
            child: _buildShape(
                accentColor.withOpacity(isDark ? 0.2 : 0.1), 450),
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
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.3),
            blurRadius: 50,
            spreadRadius: 10,
          ),
        ],
      ),
    );
  }
}

class _DailyRevenueBarChart extends StatelessWidget {
  final ThemeData theme;
  final String title;
  final Map<String, double> data;
  final Color color;
  final VoidCallback onTap;

  const _DailyRevenueBarChart({
    required this.theme,
    required this.title,
    required this.data,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    var chartData = data;
    if (chartData.isEmpty) {
      chartData = {
        'Day 1': 0.0,
        'Day 2': 0.0,
        'Day 3': 0.0,
        'Day 4': 0.0,
        'Day 5': 0.0,
        'Day 6': 0.0,
        'Day 7': 0.0
      };
    }

    final maxValue = chartData.values.fold(0.0, (a, b) => max(a, b));
    final currencyFormatter =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

    const String explanation =
        'Tracks your gross revenue by day within the selected range.';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(explanation,
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.textTheme.bodyLarge?.color?.withOpacity(0.7)),
                softWrap: true),
            const Divider(height: 20),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: chartData.entries.map((entry) {
                    final barHeightFactor =
                    maxValue > 0 ? (entry.value / maxValue).clamp(0.0, 1.0) : 0.0;
                    return Container(
                      width: 60,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          FittedBox(
                            child: Text(
                              currencyFormatter.format(entry.value),
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: color, fontWeight: FontWeight.w600),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Expanded(
                            child: Container(
                              alignment: Alignment.bottomCenter,
                              child: FractionallySizedBox(
                                heightFactor: barHeightFactor,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: color.withOpacity(0.8),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          FittedBox(
                              child: Text(entry.key,
                                  style: theme.textTheme.bodyMedium
                                      ?.copyWith(fontWeight: FontWeight.w600))),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =======================================================
// DETAIL SHEETS
// =======================================================

class _DailyRevenueDetailsSheet extends StatelessWidget {
  final Map<String, double> dailyRevenue;
  final ScrollController scrollController;

  const _DailyRevenueDetailsSheet(
      {required this.dailyRevenue, required this.scrollController});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sortedEntries = dailyRevenue.entries.toList()
      ..sort((a, b) =>
          DateFormat('MMM d').parse(b.key).compareTo(DateFormat('MMM d').parse(a.key)));
    final currencyFormatter =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Daily Revenue Details', style: theme.textTheme.headlineSmall),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 24),
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              itemCount: sortedEntries.length,
              itemBuilder: (context, index) {
                final entry = sortedEntries[index];
                return ListTile(
                  title: Text(entry.key, style: theme.textTheme.titleMedium),
                  trailing: Text(
                    currencyFormatter.format(entry.value),
                    style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold, color: theme.primaryColor),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderTypeDetailsSheet extends StatefulWidget {
  final Map<String, List<DocumentSnapshot>> orderTypeDetails;

  const _OrderTypeDetailsSheet({required this.orderTypeDetails});

  @override
  __OrderTypeDetailsSheetState createState() => __OrderTypeDetailsSheetState();
}

class __OrderTypeDetailsSheetState extends State<_OrderTypeDetailsSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController =
        TabController(length: widget.orderTypeDetails.keys.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currencyFormatter =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Order Type Details', style: theme.textTheme.headlineSmall),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 24),
          TabBar(
            controller: _tabController,
            tabs: widget.orderTypeDetails.keys
                .map((type) => Tab(text: type))
                .toList(),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: widget.orderTypeDetails.keys.map((type) {
                final orders = widget.orderTypeDetails[type]!;
                return ListView.builder(
                  itemCount: orders.length,
                  itemBuilder: (context, index) {
                    final order = orders[index].data() as Map<String, dynamic>;
                    final billingDetails =
                        order['billingDetails'] as Map<String, dynamic>? ?? {};
                    final billedAt =
                    (billingDetails['billedAt'] as Timestamp?)?.toDate();
                    final items =
                    List<Map<String, dynamic>>.from(order['items'] ?? []);
                    return ExpansionTile(
                      title: Text('Order #${orders[index].id.substring(0, 6)}'),
                      subtitle: Text(
                        billedAt != null
                            ? DateFormat.yMMMd().add_jm().format(billedAt)
                            : 'No date',
                      ),
                      trailing: Text(
                        currencyFormatter
                            .format(billingDetails['finalTotal'] ?? 0.0),
                        style: theme.textTheme.bodyLarge
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      children: items.map((item) {
                        return ListTile(
                          title: Text("${item['quantity']}x ${item['name']}"),
                          trailing: Text(
                            currencyFormatter.format(
                                (item['price'] as num? ?? 0.0) *
                                    (item['quantity'] as num? ?? 0)),
                          ),
                        );
                      }).toList(),
                    );
                  },
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopSellingItemsSheet extends StatelessWidget {
  final List<ProductPerformance> topSellingItems;
  final ScrollController scrollController;

  const _TopSellingItemsSheet(
      {required this.topSellingItems, required this.scrollController});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Top Selling Items', style: theme.textTheme.headlineSmall),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 24),
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              itemCount: topSellingItems.length,
              itemBuilder: (context, index) {
                final item = topSellingItems[index];
                return ListTile(
                  leading: CircleAvatar(
                    child: Text('${index + 1}'),
                  ),
                  title:
                  Text(item.itemName, style: theme.textTheme.titleMedium),
                  trailing: Text(
                    '${item.unitsSold} units',
                    style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.primaryColor),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SupplierSpendingDetailsSheet extends StatelessWidget {
  final Map<String, double> supplierSpendings;
  final ScrollController scrollController;

  const _SupplierSpendingDetailsSheet(
      {required this.supplierSpendings, required this.scrollController});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sortedEntries = supplierSpendings.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final currencyFormatter =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Supplier Spending Details',
                    style: theme.textTheme.headlineSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 24),
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              itemCount: sortedEntries.length,
              itemBuilder: (context, index) {
                final entry = sortedEntries[index];
                return ListTile(
                  title: Text(entry.key, style: theme.textTheme.titleMedium),
                  trailing: Text(
                    currencyFormatter.format(entry.value),
                    style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold, color: theme.primaryColor),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// --- NEW: Staff Spending Details Sheet ---
class _StaffSpendingDetailsSheet extends StatelessWidget {
  final Map<String, double> staffSpendings;
  final ScrollController scrollController;

  const _StaffSpendingDetailsSheet(
      {required this.staffSpendings, required this.scrollController});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sortedEntries = staffSpendings.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final currencyFormatter =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Staff Spending Details',
                    style: theme.textTheme.headlineSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 24),
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              itemCount: sortedEntries.length,
              itemBuilder: (context, index) {
                final entry = sortedEntries[index];
                return ListTile(
                  title: Text(entry.key, style: theme.textTheme.titleMedium),
                  trailing: Text(
                    currencyFormatter.format(entry.value),
                    style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold, color: theme.primaryColor),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}