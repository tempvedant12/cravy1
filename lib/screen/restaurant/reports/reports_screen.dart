// lib/screen/restaurant/reports/reports_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cravy/screen/restaurant/menu/menu_screen.dart';
import 'package:flutter/material.dart';
import 'dart:ui'; // For Glassmorphism effects
import 'package:intl/intl.dart';
import 'dart:math';

// =======================================================
// TOP-LEVEL MODELS (No change)
// =======================================================

class SalesSummary {
  final double totalRevenue;
  final double averageBill;
  final int totalOrders;
  final double profitEstimate;
  SalesSummary({required this.totalRevenue, required this.averageBill, required this.totalOrders, required this.profitEstimate});
}

class ProductPerformance {
  final String itemName;
  final int unitsSold;
  final double totalSales;
  ProductPerformance({required this.itemName, required this.unitsSold, required this.totalSales});
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

class _ReportsScreenState extends State<ReportsScreen> with TickerProviderStateMixin {
  late Future<Map<String, dynamic>> _reportDataFuture;
  late TabController _tabController;
  DateTimeRange? _customDateRange;
  List<Widget> _tabs = [];
  final List<String> _tabPeriods = ['All', 'Today', 'This Week', 'This Month', 'This Year', 'Custom'];
  List<MenuItem> _allMenuItems = [];

  @override
  void initState() {
    super.initState();
    _tabs = _buildTabs();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _reportDataFuture = _loadData();
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        if (_tabPeriods[_tabController.index] == 'Custom') {
          _selectDateRange();
        } else {
          setState(() {
            _customDateRange = null;
            _tabs = _buildTabs();
            _reportDataFuture = _loadData();
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _loadData([String? period]) async {
    if (_allMenuItems.isEmpty) {
      await _fetchAllMenuItems();
    }
    return _fetchReportData(period ?? _tabPeriods[_tabController.index], customRange: _customDateRange);
  }

  Future<void> _fetchAllMenuItems() async {
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

  List<Widget> _buildTabs() {
    return [
      const Tab(text: 'All Time'),
      const Tab(text: 'Today'),
      const Tab(text: 'This Week'),
      const Tab(text: 'This Month'),
      const Tab(text: 'This Year'),
      Tab(
        text: _customDateRange != null
            ? '${DateFormat.yMd().format(_customDateRange!.start)} - ${DateFormat.yMd().format(_customDateRange!.end)}'
            : 'Custom',
      ),
    ];
  }

  void _resetCustomRange() {
    setState(() {
      _customDateRange = null;
      _tabs = _buildTabs();
      _tabController.index = 0;
      _reportDataFuture = _loadData();
    });
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
        _tabs = _buildTabs();
        _reportDataFuture = _loadData('Custom');
      });
    }
  }

  Future<Map<String, dynamic>> _fetchReportData(String period, {DateTimeRange? customRange}) async {
    DateTimeRange? dateRange = customRange;
    final now = DateTime.now();

    if (dateRange == null && period != 'All') {
      switch (period) {
        case 'Today':
          dateRange = DateTimeRange(start: DateTime(now.year, now.month, now.day), end: now);
          break;
        case 'This Week':
          final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
          dateRange = DateTimeRange(start: DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day), end: now);
          break;
        case 'This Month':
          dateRange = DateTimeRange(start: DateTime(now.year, now.month, 1), end: now);
          break;
        case 'This Year':
          dateRange = DateTimeRange(start: DateTime(now.year, 1, 1), end: now);
          break;
      }
    }


    Query salesQuery = FirebaseFirestore.instance
        .collection('restaurants')
        .doc(widget.restaurantId)
        .collection('orders')
        .where('isPaid', isEqualTo: true);

    if (dateRange != null) {
      salesQuery = salesQuery.where('billingDetails.billedAt', isGreaterThanOrEqualTo: dateRange.start)
          .where('billingDetails.billedAt', isLessThanOrEqualTo: dateRange.end.add(const Duration(days: 1)));
    }


    final salesSnapshot = await salesQuery.get();

    double totalRevenue = 0;
    final Map<String, int> productSales = {};
    final Map<String, double> orderTypeDistribution = {};
    final Map<String, List<DocumentSnapshot>> orderTypeDetails = {};
    final Map<String, double> categoryRevenue = {};
    final Map<String, double> dailyTimeSeriesRevenue = {};
    final menuItemsMap = {for (var item in _allMenuItems) item.id: item};

    // Group orders by bill number to count unique transactions
    final Map<String, List<QueryDocumentSnapshot>> bills = {};
    for (var doc in salesSnapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final billNumber = data['billingDetails']?['billNumber'] as String?;
      if (billNumber != null) {
        bills.putIfAbsent(billNumber, () => []).add(doc);
      }
    }
    int totalOrders = bills.length;


    for (var doc in salesSnapshot.docs) {
      final data = doc.data()as Map<String, dynamic>;
      final finalTotal = (data['billingDetails']?['finalTotal'] as num?)?.toDouble() ?? 0.0;
      totalRevenue += finalTotal;

      final billedAt = (data['billingDetails']?['billedAt'] as Timestamp?)?.toDate();
      if (billedAt != null) {
        final dateKey = DateFormat('MMM d').format(billedAt);
        dailyTimeSeriesRevenue.update(dateKey, (value) => value + finalTotal, ifAbsent: () => finalTotal);
      }

      final orderType = (data['orderType'] as String?) ?? 'Dine-In';
      orderTypeDistribution.update(orderType, (value) => value + 1, ifAbsent: () => 1);
      orderTypeDetails.putIfAbsent(orderType, () => []).add(doc);


      final items = List<Map<String, dynamic>>.from(data['items'] ?? []);
      for (var item in items) {
        final name = item['name'] as String;
        final qty = (item['quantity'] as num?)?.toInt() ?? 0;
        final menuName = item['menuName'] as String? ?? 'Unknown Menu';
        final productKey = '$name ($menuName)';
        productSales.update(productKey, (value) => value + qty, ifAbsent: () => qty);

        final itemPrice = (item['price'] as num?)?.toDouble() ?? 0.0;
        final itemTotal = (itemPrice * qty).toDouble();

        final menuItem = menuItemsMap[item['menuItemId']];
        String category = menuItem?.category ?? 'Other';
        final categoryKey = '$category ($menuName)';
        categoryRevenue.update(categoryKey, (value) => value + itemTotal, ifAbsent: () => itemTotal);
      }
    }

    final sortedTimeSeriesRevenue = Map.fromEntries(dailyTimeSeriesRevenue.entries.toList()
      ..sort((a, b) => DateFormat('MMM d').parse(a.key).compareTo(DateFormat('MMM d').parse(b.key))));

    final topSelling = productSales.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    // 2. Fetch Low Stock Data (Inventory)
    final inventorySnapshot = await FirebaseFirestore.instance
        .collection('restaurants')
        .doc(widget.restaurantId)
        .collection('inventory')
        .get();

    // 3. Fetch Supplier Data (Purchase Orders)
    final poSnapshot = await FirebaseFirestore.instance
        .collection('restaurants')
        .doc(widget.restaurantId)
        .collection('purchaseOrders')
        .where('status', isEqualTo: 'Completed')
        .where('amountPaid', isGreaterThan: 0)
        .get();

    final Map<String, double> supplierSpendings = {};
    for (var doc in poSnapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final supplierName = data['supplierName'] as String? ?? 'Unknown Supplier';
      final totalAmount = (data['amountPaid'] as num?)?.toDouble() ?? 0.0;
      supplierSpendings.update(supplierName, (value) => value + totalAmount, ifAbsent: () => totalAmount);
    }

    return {
      'salesSummary': SalesSummary(
        totalRevenue: totalRevenue, totalOrders: totalOrders,
        averageBill: totalOrders > 0 ? totalRevenue / totalOrders : 0,
        profitEstimate: totalRevenue * 0.35,
      ),
      'topSelling': topSelling.map((e) => ProductPerformance(itemName: e.key, unitsSold: e.value, totalSales: 0)).toList(),
      'lowStockCount': inventorySnapshot.docs.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final quantity = (data['quantity'] as num?)?.toDouble() ?? 0.0;
        final threshold = (data['lowStockThreshold'] as num?)?.toDouble() ?? 0.0;
        return quantity <= threshold;
      }).length,
      'recentPO': poSnapshot.docs.length,
      'timeSeriesRevenue': sortedTimeSeriesRevenue,
      'orderTypeDistribution': Map.fromEntries(orderTypeDistribution.entries.map((e) => MapEntry(e.key, e.value.toDouble()))),
      'orderTypeDetails': orderTypeDetails,
      'categoryRevenue': categoryRevenue,
      'supplierSpendings': supplierSpendings,
    };
  }
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF14141E) : Colors.grey[50],
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          const _PremiumBackground(),
          NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) {
              return [
                SliverAppBar(
                  title: const Text('Powerful Reports', style: TextStyle(fontWeight: FontWeight.w600)),
                  pinned: true,
                  floating: true,
                  snap: true,
                  forceElevated: innerBoxIsScrolled,
                  backgroundColor: isDark ? const Color(0xFF14141E).withOpacity(0.9) : Colors.white.withOpacity(0.95),
                  elevation: 0,
                  actions: [
                    if (_customDateRange != null)
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: _resetCustomRange,
                        tooltip: 'Reset Custom Range',
                      )
                  ],
                  bottom: TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    tabs: _tabs,
                  ),
                ),
              ];
            },
            body: FutureBuilder<Map<String, dynamic>>(
              future: _reportDataFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: Text('No data available.'));
                }

                final data = snapshot.data!;
                final summary = data['salesSummary'] as SalesSummary;
                final topSelling = data['topSelling'] as List<ProductPerformance>;
                final lowStockCount = data['lowStockCount'] as int;

                final timeSeriesRevenue = (data['timeSeriesRevenue'] as Map<String, double>?) ?? {};
                final orderTypeDistribution = (data['orderTypeDistribution'] as Map<String, double>?) ?? {};
                final orderTypeDetails = (data['orderTypeDetails'] as Map<String, List<DocumentSnapshot>>?) ?? {};
                final categoryRevenue = (data['categoryRevenue'] as Map<String, double>?) ?? {};
                final supplierSpendings = (data['supplierSpendings'] as Map<String, double>?) ?? {};

                final theme = Theme.of(context);
                final screenWidth = MediaQuery.of(context).size.width;
                final salesGridCount = screenWidth > 1200 ? 4 : (screenWidth > 600 ? 2 : 1);
                final chartGridCount = screenWidth > 800 ? 2 : 1;
                final productGridCount = screenWidth > 1000 ? 3 : 1;
                final supplierGridCount = screenWidth > 1000 ? 2 : 1;
                final chartAspectRatio = screenWidth > 800 ? 1.8 : 1.2;
                final productAspectRatio = screenWidth > 1000 ? 1.0 : 1.2;
                final supplierAspectRatio = screenWidth > 1000 ? 1.2 : 1.2;

                return ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20.0, 24.0, 20.0, 20.0),
                      child: GridView.count(
                        physics: const NeverScrollableScrollPhysics(),
                        shrinkWrap: true,
                        crossAxisCount: salesGridCount,
                        crossAxisSpacing: 20,
                        mainAxisSpacing: 20,
                        childAspectRatio: 1.5,
                        children: [
                          _GlassmorphicReportCard(
                            title: 'Total Revenue', value: '₹${NumberFormat.compactLong().format(summary.totalRevenue)}',
                            icon: Icons.attach_money, color: Colors.green,
                          ),
                          _GlassmorphicReportCard(
                            title: 'Total Orders', value: NumberFormat.compact().format(summary.totalOrders),
                            icon: Icons.receipt_long, color: Colors.blue,
                          ),
                          _GlassmorphicReportCard(
                            title: 'Avg. Bill Value', value: '₹${summary.averageBill.toStringAsFixed(2)}',
                            icon: Icons.trending_up, color: Colors.purple,
                          ),
                          _GlassmorphicReportCard(
                            title: 'Profit Estimate', value: '₹${NumberFormat.compactLong().format(summary.profitEstimate)}',
                            icon: Icons.bar_chart, color: Colors.orange,
                          ),
                        ],
                      ),
                    ),

                    _buildSectionHeader(theme, 'Sales & Order Breakdown', Icons.timeline_outlined),
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
                              onTap: () => _showDailyRevenueDetails(context, timeSeriesRevenue),
                            ),
                          ),
                          _GlassmorphicChartCard(
                            child: GestureDetector(
                              onTap: () => _showOrderTypeDetails(context, orderTypeDetails),
                              child: _PieChartContent(theme, 'Order Type Split', orderTypeDistribution, Colors.blue.shade500),
                            ),
                          ),
                        ],
                      ),
                    ),

                    _buildSectionHeader(theme, 'Product Performance & Inventory', Icons.local_dining_outlined),
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
                            title: 'Top 5 Selling Items',
                            items: topSelling,
                            onTap: () => _showTopSellingItemsDetails(context, topSelling),
                          ),
                          _GlassmorphicChartCard(
                            child: _CategoryBarContent(theme: theme, title: 'Sales by Item Group', data: categoryRevenue, color: Colors.purple.shade500),
                          ),
                          _GlassmorphicAlertCard(title: 'Inventory Alerts', value: '$lowStockCount Items', subtitle: 'Are below low-stock threshold.', color: Colors.red, icon: Icons.warning_amber_outlined),
                        ],
                      ),
                    ),

                    _buildSectionHeader(theme, 'Supplier & Cost Insights', Icons.local_shipping_outlined),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 80),
                      child: GridView.count(
                        physics: const NeverScrollableScrollPhysics(),
                        shrinkWrap: true,
                        crossAxisCount: supplierGridCount,
                        crossAxisSpacing: 20,
                        mainAxisSpacing: 20,
                        childAspectRatio: supplierAspectRatio,
                        children: [
                          _GlassmorphicChartCard(
                            child: GestureDetector(
                              onTap: () => _showSupplierSpendingDetails(context, supplierSpendings),
                              child: _SupplierSpendingBarContent(theme: theme, title: 'Supplier Spending Breakdown', data: supplierSpendings, color: Colors.teal.shade500),
                            ),
                          ),
                          _GlassmorphicAlertCard(title: 'Completed POs', value: '${data['recentPO'] ?? 0}', subtitle: 'Completed Purchase Orders.', color: Colors.lightGreen, icon: Icons.check_circle_outline),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showDailyRevenueDetails(BuildContext context, Map<String, double> dailyRevenue) {
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

  void _showOrderTypeDetails(BuildContext context, Map<String, List<DocumentSnapshot>> orderTypeDetails) {
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

  void _showTopSellingItemsDetails(BuildContext context, List<ProductPerformance> topSelling) {
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

  void _showSupplierSpendingDetails(BuildContext context, Map<String, double> supplierSpendings) {
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


  // =======================================================
  // HELPER METHODS (RESPONSIVENESS FIXES APPLIED HERE)
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

  Widget _PieChartContent(ThemeData theme, String title, Map<String, double> data, Color color) {
    final total = data.values.fold(0.0, (sum, item) => sum + item);
    final colors = [color, color.withOpacity(0.6), color.withOpacity(0.4), color.withOpacity(0.2), color.withOpacity(0.1)];

    final primaryEntry = data.entries.fold(const MapEntry('', 0.0), (a, b) => a.value > b.value ? a : b);
    final primaryPercentage = total > 0 ? (primaryEntry.value / total * 100) : 0;

    final List<MapEntry<String, double>> sortedEntries = data.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));


    const String explanation = 'Shows the percentage split of orders by type. Essential for capacity planning.';

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(explanation, style: theme.textTheme.bodySmall?.copyWith(color: theme.textTheme.bodyLarge?.color?.withOpacity(0.7)), softWrap: true),
          const Divider(height: 20),
          Expanded(
            child: Row(
              children: [
                Expanded( // <-- ADDED Expanded here to constrain the width
                  flex: 1, // Giving it a proportional width
                  child: LayoutBuilder(
                      builder: (context, constraints) {
                        // Determine chart size dynamically based on the available constraints
                        final chartSize = min(constraints.maxHeight, constraints.maxWidth) * 0.9;
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
                                      border: Border.all(color: primaryEntry.key.isEmpty ? Colors.grey.withOpacity(0.3) : color.withOpacity(0.3), width: 4)
                                  ),
                                ),
                                Text(
                                    primaryEntry.key.isEmpty ? '0%' : '${primaryPercentage.toStringAsFixed(0)}%',
                                    style: theme.textTheme.headlineMedium?.copyWith(color: color, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        );
                      }
                  ),
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
                            Container(width: 8, height: 8, decoration: BoxDecoration(color: colors[index % colors.length], shape: BoxShape.circle)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${e.key}: ${percent.toStringAsFixed(1)}%',
                                style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
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
    final currencyFormatter = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    final List<MapEntry<String, double>> sortedData = widget.data.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final itemsToShow = _isExpanded ? sortedData : sortedData.take(3).toList();

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title, style: widget.theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(explanation, style: widget.theme.textTheme.bodySmall?.copyWith(color: widget.theme.textTheme.bodyLarge?.color?.withOpacity(0.7)), softWrap: true),
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
                                child: Text(e.key, style: widget.theme.textTheme.bodyLarge),
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
                                        widthFactor: barWidth.clamp(0.0, 1.0).toDouble(),
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: widget.color,
                                            borderRadius: BorderRadius.circular(7),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  FittedBox(
                                    child: Text(
                                      currencyFormatter.format(e.value),
                                      style: widget.theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
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
              // FIX: Wrap the content Column in an AnimatedSize to ensure
              // the layout rebuilds correctly when the list appears.
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
                                          color:
                                          widget.color.withOpacity(0.1),
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
// PREMIUM TOP-LEVEL WIDGETS AND PAINTERS (MODIFIED)
// =======================================================

/// --- _GlassmorphicReportCard (FIXED: Uses Spacer to prevent overflow) ---
class _GlassmorphicReportCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _GlassmorphicReportCard({required this.title, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardColor = isDark ? Colors.white.withOpacity(0.05) : Colors.white.withOpacity(0.6);

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
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
                          color: theme.textTheme.bodyLarge?.color?.withOpacity(0.8),
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                // FIX: Replaced const SizedBox(height: 24) with Spacer to dynamically fill space
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
      ),
    );
  }
}

/// --- _GlassmorphicChartCard (No change) ---
class _GlassmorphicChartCard extends StatelessWidget {
  final Widget child;
  const _GlassmorphicChartCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardColor = isDark ? Colors.white.withOpacity(0.05) : Colors.white.withOpacity(0.6);

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
          ),
          child: RepaintBoundary( // ADDED RepaintBoundary
            child: child,
          ),
        ),
      ),
    );
  }
}

/// --- _GlassmorphicAlertCard (UPDATED with better design) ---
class _GlassmorphicAlertCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;

  const _GlassmorphicAlertCard({required this.title, required this.value, required this.subtitle, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardColor = isDark ? Colors.white.withOpacity(0.05) : Colors.white.withOpacity(0.6);

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Row( // Changed to Row for better layout
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.2),
                    shape: BoxShape.circle, // Use Circle for the icon
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
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: theme.textTheme.bodyLarge?.color?.withOpacity(0.8)),
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
                          color: theme.textTheme.bodyLarge?.color?.withOpacity(0.7),
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
      ),
    );
  }
}


/// --- _GlassmorphicListReportCard (UPDATED to accept ProductPerformance and be tappable) ---
class _GlassmorphicListReportCard extends StatelessWidget {
  final String title;
  final List<ProductPerformance> items;
  final VoidCallback onTap;

  const _GlassmorphicListReportCard({required this.title, required this.items, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardColor = isDark ? Colors.white.withOpacity(0.05) : Colors.white.withOpacity(0.6);

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
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
                  Text(title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  const Divider(height: 24),
                  Expanded(
                    child: items.isEmpty
                        ? Center(child: Text('No product sales yet.', style: theme.textTheme.bodyLarge))
                        : ListView.separated(
                      itemCount: items.length > 5 ? 5 : items.length, // Show top 5
                      separatorBuilder: (context, index) => Divider(color: theme.dividerColor.withOpacity(0.5), height: 1),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          leading: CircleAvatar(
                            radius: 16,
                            backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
                            child: Text(
                              '#${index + 1}',
                              style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ),
                          title: Text(item.itemName, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500)),
                          trailing: Text('${item.unitsSold} units', style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.bold)),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// --- _PremiumBackground (No change) ---
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
      chartData = {'Day 1': 0.0, 'Day 2': 0.0, 'Day 3': 0.0, 'Day 4': 0.0, 'Day 5': 0.0, 'Day 6': 0.0, 'Day 7': 0.0};
    }

    final maxValue = chartData.values.fold(0.0, (a, b) => max(a, b));
    final currencyFormatter = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

    const String explanation = 'Tracks your gross revenue by day within the selected range.';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(explanation, style: theme.textTheme.bodySmall?.copyWith(color: theme.textTheme.bodyLarge?.color?.withOpacity(0.7)), softWrap: true),
            const Divider(height: 20),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: chartData.entries.map((entry) {
                    final barHeightFactor = maxValue > 0 ? (entry.value / maxValue).clamp(0.0, 1.0) : 0.0;
                    return Container(
                      width: 60,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          FittedBox(
                            child: Text(
                              currencyFormatter.format(entry.value),
                              style: theme.textTheme.bodySmall?.copyWith(color: color, fontWeight: FontWeight.w600),
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
                          FittedBox(child: Text(entry.key, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
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

class _DailyRevenueDetailsSheet extends StatelessWidget {
  final Map<String, double> dailyRevenue;
  final ScrollController scrollController;

  const _DailyRevenueDetailsSheet({required this.dailyRevenue, required this.scrollController});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sortedEntries = dailyRevenue.entries.toList()
      ..sort((a, b) => DateFormat('MMM d').parse(b.key).compareTo(DateFormat('MMM d').parse(a.key)));
    final currencyFormatter = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Draggable handle and close button
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
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: theme.primaryColor),
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
          // Draggable handle and close button
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
                    final items = List<Map<String, dynamic>>.from(order['items'] ?? []);
                    return ExpansionTile(
                      title: Text('Order #${orders[index].id.substring(0, 6)}'),
                      subtitle: Text(
                        billedAt != null
                            ? DateFormat.yMMMd().add_jm().format(billedAt)
                            : 'No date',
                      ),
                      trailing: Text(
                        currencyFormatter.format(billingDetails['finalTotal'] ?? 0.0),
                        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      children: items.map((item) {
                        return ListTile(
                          title: Text("${item['quantity']}x ${item['name']}"),
                          trailing: Text(
                            currencyFormatter.format((item['price'] as num? ?? 0.0) * (item['quantity'] as num? ?? 0)),
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

  const _TopSellingItemsSheet({required this.topSellingItems, required this.scrollController});

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
          // Draggable handle and close button
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
                  title: Text(item.itemName, style: theme.textTheme.titleMedium),
                  trailing: Text(
                    '${item.unitsSold} units',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: theme.primaryColor),
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

  const _SupplierSpendingDetailsSheet({required this.supplierSpendings, required this.scrollController});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sortedEntries = supplierSpendings.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final currencyFormatter = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Draggable handle and close button
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
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: theme.primaryColor),
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