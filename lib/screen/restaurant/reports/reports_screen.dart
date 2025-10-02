// lib/screen/restaurant/reports/reports_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
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

class _ReportsScreenState extends State<ReportsScreen> {
  late Future<Map<String, dynamic>> _reportDataFuture;
  DateTimeRange _selectedDateRange = DateTimeRange(start: DateTime.now().subtract(const Duration(days: 30)), end: DateTime.now());

  @override
  void initState() {
    super.initState();
    _reportDataFuture = _fetchReportData();
  }

  Future<Map<String, dynamic>> _fetchReportData() async {
    // 1. Fetch Sales Data (Data fetching logic is correct and remains unchanged)
    final salesSnapshot = await FirebaseFirestore.instance
        .collection('restaurants')
        .doc(widget.restaurantId)
        .collection('orders')
        .where('isPaid', isEqualTo: true)
        .where('billingDetails.billedAt', isGreaterThanOrEqualTo: _selectedDateRange.start)
        .where('billingDetails.billedAt', isLessThanOrEqualTo: _selectedDateRange.end.add(const Duration(days: 1)))
        .get();

    double totalRevenue = 0;
    int totalOrders = salesSnapshot.docs.length;
    final Map<String, int> productSales = {};
    final Map<String, double> dailyRevenue = {};
    final Map<String, double> orderTypeDistribution = {};
    final Map<String, double> categoryRevenue = {};
    final Map<String, double> dailyTimeSeriesRevenue = {};

    for (var doc in salesSnapshot.docs) {
      final data = doc.data();
      final finalTotal = (data['billingDetails']?['finalTotal'] as num?)?.toDouble() ?? 0.0;
      totalRevenue += finalTotal;

      final billedAt = (data['billingDetails']?['billedAt'] as Timestamp?)?.toDate();
      if (billedAt != null) {
        final dayOfWeek = DateFormat('EEE').format(billedAt);
        dailyRevenue.update(dayOfWeek, (value) => value + finalTotal, ifAbsent: () => finalTotal);

        final dateKey = DateFormat('MMM d').format(billedAt);
        dailyTimeSeriesRevenue.update(dateKey, (value) => value + finalTotal, ifAbsent: () => finalTotal);
      }

      final orderType = (data['orderType'] as String?) ?? 'Dine-In';
      orderTypeDistribution.update(orderType, (value) => value + 1, ifAbsent: () => 1);

      final items = List<Map<String, dynamic>>.from(data['items'] ?? []);
      for (var item in items) {
        final name = item['name'] as String;
        final qty = (item['quantity'] as num?)?.toInt() ?? 0;
        productSales.update(name, (value) => value + qty, ifAbsent: () => qty);

        final itemPrice = (item['price'] as num?)?.toDouble() ?? 0.0;
        final itemTotal = (itemPrice * qty).toDouble();

        // **INFERRED CATEGORY REVENUE (Heuristic):**
        String category = 'Other';
        if (name.contains('Burger') || name.contains('Pizza') || name.contains('Main')) {
          category = 'Main Course';
        } else if (name.contains('Fries') || name.contains('Appetizer') || name.contains('Starter')) {
          category = 'Appetizers';
        } else if (name.contains('Coke') || name.contains('Juice') || name.contains('Beverage')) {
          category = 'Beverages';
        } else if (name.contains('Cake') || name.contains('Pudding') || name.contains('Dessert')) {
          category = 'Desserts';
        }

        categoryRevenue.update(category, (value) => value + itemTotal, ifAbsent: () => itemTotal);
      }
    }

    final sortedDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final Map<String, double> sortedDailyPayments = Map.fromEntries(
      dailyRevenue.entries.toList()
          .where((entry) => sortedDays.contains(entry.key))
          .map((entry) => MapEntry(entry.key, entry.value)),
    );
    for (var day in sortedDays) {
      sortedDailyPayments.putIfAbsent(day, () => 0.0);
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
      final data = doc.data();
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
      'topSelling': topSelling.take(5).map((e) => ProductPerformance(itemName: e.key, unitsSold: e.value, totalSales: 0)).toList(),
      'lowStockCount': inventorySnapshot.docs.where((doc) {
        final data = doc.data();
        final quantity = (data['quantity'] as num?)?.toDouble() ?? 0.0;
        final threshold = (data['lowStockThreshold'] as num?)?.toDouble() ?? 0.0;
        return quantity <= threshold;
      }).length,
      'recentPO': poSnapshot.docs.length,
      'timeSeriesRevenue': sortedTimeSeriesRevenue,
      'orderTypeDistribution': Map.fromEntries(orderTypeDistribution.entries.map((e) => MapEntry(e.key, e.value.toDouble()))),
      'categoryRevenue': categoryRevenue,
      'supplierSpendings': supplierSpendings,
      'dailyPayments': sortedDailyPayments,
    };
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context, firstDate: DateTime(2020), lastDate: DateTime.now(), initialDateRange: _selectedDateRange,
    );
    if (picked != null && picked != _selectedDateRange) {
      setState(() {
        _selectedDateRange = picked;
        _reportDataFuture = _fetchReportData();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;

    // Responsive grid counts
    final salesGridCount = screenWidth > 1200 ? 4 : (screenWidth > 600 ? 2 : 1);
    final chartGridCount = screenWidth > 1400 ? 3 : (screenWidth > 800 ? 2 : 1);
    final productGridCount = screenWidth > 1000 ? 3 : 1;
    final supplierGridCount = screenWidth > 1000 ? 2 : 1;

    // Responsive aspect ratios
    final chartAspectRatio = screenWidth > 800 ? 1.8 : 1.2;
    final productAspectRatio = screenWidth > 1000 ? 1.0 : 2.0;
    final supplierAspectRatio = screenWidth > 1000 ? 1.2 : 2.0;


    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF14141E) : Colors.grey[50],
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          const _PremiumBackground(),
          FutureBuilder<Map<String, dynamic>>(
            future: _reportDataFuture,
            builder: (context, snapshot) {
              final theme = Theme.of(context);
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
              final categoryRevenue = (data['categoryRevenue'] as Map<String, double>?) ?? {};
              final supplierSpendings = (data['supplierSpendings'] as Map<String, double>?) ?? {};
              final dailyPayments = (data['dailyPayments'] as Map<String, double>?) ?? {};


              return CustomScrollView(
                slivers: [
                  SliverAppBar(
                    title: const Text('Powerful Reports', style: TextStyle(fontWeight: FontWeight.w600)),
                    pinned: true,
                    backgroundColor: isDark ? const Color(0xFF14141E).withOpacity(0.9) : Colors.white.withOpacity(0.95),
                    elevation: 0,
                    actions: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: OutlinedButton.icon(
                          onPressed: _selectDateRange,
                          icon: const Icon(Icons.calendar_today_outlined, size: 18),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: theme.colorScheme.primary.withOpacity(0.5)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          label: Text('${DateFormat.yMMMd().format(_selectedDateRange.start)} - ${DateFormat.MMMd().format(_selectedDateRange.end)}'),
                        ),
                      ),
                      const SizedBox(width: 16),
                    ],
                  ),

                  // 1. Sales Summary Cards
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20.0, 24.0, 20.0, 20.0),
                    sliver: SliverGrid.count(
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

                  // 2. Main Sales & Order Breakdown (Charts)
                  SliverToBoxAdapter(
                    child: _buildSectionHeader(theme, 'Sales & Order Breakdown', Icons.timeline_outlined),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    sliver: SliverGrid.count(
                      crossAxisCount: chartGridCount,
                      crossAxisSpacing: 20,
                      mainAxisSpacing: 20,
                      childAspectRatio: chartAspectRatio,
                      children: [
                        _GlassmorphicChartCard(
                          child: _TimeSeriesChartContent(theme, 'Daily Revenue Over Time', timeSeriesRevenue, Colors.green.shade500),
                        ),
                        _GlassmorphicChartCard(
                          child: _PieChartContent(theme, 'Order Type Split', orderTypeDistribution, Colors.blue.shade500),
                        ),
                        _GlassmorphicChartCard(
                          child: _DailyPaymentsBarContent(theme, 'Daily Payment Volume', dailyPayments, Colors.indigo.shade500),
                        ),
                      ],
                    ),
                  ),

                  // 3. Product Performance & Inventory
                  SliverToBoxAdapter(
                    child: _buildSectionHeader(theme, 'Product Performance & Inventory', Icons.local_dining_outlined),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    sliver: SliverGrid.count(
                      crossAxisCount: productGridCount,
                      crossAxisSpacing: 20,
                      mainAxisSpacing: 20,
                      childAspectRatio: productAspectRatio,
                      children: [
                        _GlassmorphicListReportCard(title: 'Top 5 Selling Items', items: topSelling.map((p) => '${p.itemName} (${p.unitsSold} units)').toList()),
                        _GlassmorphicChartCard(
                          child: _CategoryBarContent(theme, 'Sales by Item Group', categoryRevenue, Colors.purple.shade500),
                        ),
                        _GlassmorphicAlertCard(title: 'Inventory Alerts', value: '$lowStockCount Items', subtitle: 'Are below low-stock threshold.', color: Colors.red, icon: Icons.warning_amber_outlined),
                      ],
                    ),
                  ),

                  // 4. Supplier & Cost Insights
                  SliverToBoxAdapter(
                    child: _buildSectionHeader(theme, 'Supplier & Cost Insights', Icons.local_shipping_outlined),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 80),
                    sliver: SliverGrid.count(
                      crossAxisCount: supplierGridCount,
                      crossAxisSpacing: 20,
                      mainAxisSpacing: 20,
                      childAspectRatio: supplierAspectRatio,
                      children: [
                        _GlassmorphicChartCard(
                          child: _SupplierSpendingBarContent(theme, 'Supplier Spending Breakdown', supplierSpendings, Colors.teal.shade500),
                        ),
                        _GlassmorphicAlertCard(title: 'Completed POs', value: '${data['recentPO'] ?? 0}', subtitle: 'Completed Purchase Orders.', color: Colors.lightGreen, icon: Icons.check_circle_outline),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
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

  Widget _TimeSeriesChartContent(ThemeData theme, String title, Map<String, double> data, Color color) {
    if (data.isEmpty) {
      data = {'Day 1': 0.0, 'Day 2': 0.0, 'Day 3': 0.0};
    }

    final maxValue = data.values.fold(0.0, (a, b) => max(a, b));
    final currencyFormatter = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

    final List<double> values = data.values.toList();
    final List<String> labels = data.keys.toList();

    final int segmentCount = max(1, values.length - 1);

    const String explanation = 'Tracks your gross revenue by day within the selected range.';

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
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28.0, 4.0, 8.0, 4.0),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final double chartHeight = constraints.maxHeight;

                  return Stack(
                    children: [
                      // Y-Axis Labels (Left)
                      Positioned(top: 0, left: -28, child: Text(currencyFormatter.format(maxValue), style: theme.textTheme.bodySmall)),
                      Positioned(top: chartHeight / 2 - 10, left: -28, child: Text(currencyFormatter.format(maxValue / 2), style: theme.textTheme.bodySmall)),
                      Positioned(bottom: 0, left: -28, child: Text(currencyFormatter.format(0), style: theme.textTheme.bodySmall)),

                      // Chart Area (Line)
                      CustomPaint(
                        size: Size(constraints.maxWidth, chartHeight),
                        painter: _LineChartPainter(values: values, maxValue: maxValue, color: color, segmentCount: segmentCount),
                      ),

                      // X-Axis Labels (Bottom)
                      Positioned(
                        bottom: -20,
                        left: 0,
                        right: 0,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(labels.first, style: theme.textTheme.bodySmall),
                            if (labels.length > 2)
                              Text(labels[labels.length ~/ 2], style: theme.textTheme.bodySmall),
                            if (labels.length > 1)
                              Text(labels.last, style: theme.textTheme.bodySmall),
                          ],
                        ),
                      ),
                    ],
                  );
                },
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
                // FIX: Removed the problematic Expanded widget from here.
                LayoutBuilder(
                    builder: (context, constraints) {
                      // FIX: Determine chart size dynamically based on the available space (usually 1/3 of the row space)
                      final chartSize = min(constraints.maxHeight, constraints.maxWidth * 0.5) - 10;
                      return Center(
                        child: Container(
                          // FIX: Explicitly set the size of the container based on calculation
                          width: constraints.maxWidth * 0.4, // Allocate roughly 40% of the horizontal space for the chart
                          height: constraints.maxHeight,
                          child: Center(
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
                        ),
                      );
                    }
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

  Widget _DailyPaymentsBarContent(ThemeData theme, String title, Map<String, double> data, Color color) {
    final sortedKeys = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final dataForChart = Map.fromEntries(sortedKeys.map((day) => MapEntry(day, data[day] ?? 0.0)));
    final maxValue = dataForChart.values.fold(0.0, (a, b) => max(a, b));
    final currencyFormatter = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

    const String explanation = 'Visualizes total transaction value processed each day. Helps identify peak sales days.';

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(explanation, style: theme.textTheme.bodySmall?.copyWith(color: theme.textTheme.bodyLarge?.color?.withOpacity(0.7)), softWrap: true),
          const Divider(height: 24),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: dataForChart.entries.map((e) {
                final barHeightFactor = maxValue > 0 ? (e.value / maxValue).clamp(0.0, 1.0) : 0.0;
                return Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      FittedBox(
                        child: Text(
                          currencyFormatter.format(e.value),
                          style: theme.textTheme.bodySmall?.copyWith(color: color, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Expanded(
                        child: Container(
                          // FIX: Removed fixed width: 24, rely on constraints
                          constraints: const BoxConstraints(maxWidth: 30),
                          height: double.infinity,
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
                      FittedBox(child: Text(e.key, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }


  Widget _CategoryBarContent(ThemeData theme, String title, Map<String, double> data, Color color) {
    final maxRevenue = data.values.fold(0.0, (a, b) => max(a, b));
    const String explanation = 'Compares total revenue generated by each item group.';
    final currencyFormatter = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    final List<MapEntry<String, double>> sortedData = data.entries.toList()..sort((a, b) => b.value.compareTo(a.value));


    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(explanation, style: theme.textTheme.bodySmall?.copyWith(color: theme.textTheme.bodyLarge?.color?.withOpacity(0.7)), softWrap: true),
          const Divider(height: 24),
          Expanded(
            child: ListView.builder(
              itemCount: sortedData.length,
              itemBuilder: (context, index) {
                final e = sortedData[index];
                final barWidth = maxRevenue > 0 ? (e.value / maxRevenue) : 0;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FittedBox(
                          child: Text(e.key, style: theme.textTheme.bodyLarge)
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              height: 14,
                              alignment: Alignment.centerLeft,
                              decoration: BoxDecoration(
                                color: color.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(7),
                              ),
                              child: FractionallySizedBox(
                                widthFactor: barWidth.clamp(0.0, 1.0).toDouble(),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: color,
                                    borderRadius: BorderRadius.circular(7),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          FittedBox(
                            child: Text(currencyFormatter.format(e.value), style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _SupplierSpendingBarContent(ThemeData theme, String title, Map<String, double> data, Color color) {
    final maxSpending = data.values.fold(0.0, (a, b) => max(a, b));
    final currencyFormatter = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    const String explanation = 'Identifies your largest suppliers by total spending.';
    final List<MapEntry<String, double>> sortedData = data.entries.toList()..sort((a, b) => b.value.compareTo(a.value));


    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(explanation, style: theme.textTheme.bodySmall?.copyWith(color: theme.textTheme.bodyLarge?.color?.withOpacity(0.7)), softWrap: true),
          const Divider(height: 24),
          Expanded(
            child: ListView.builder(
              itemCount: sortedData.length,
              itemBuilder: (context, index) {
                final e = sortedData[index];
                final barWidth = maxSpending > 0 ? (e.value / maxSpending) : 0;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FittedBox(
                        child: Text(e.key, style: theme.textTheme.bodyLarge),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              height: 16,
                              alignment: Alignment.centerLeft,
                              decoration: BoxDecoration(
                                color: color.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: FractionallySizedBox(
                                widthFactor: barWidth.clamp(0.0, 1.0).toDouble(),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: color,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          FittedBox(
                            child: Text(currencyFormatter.format(e.value), style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ],
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
          child: child,
        ),
      ),
    );
  }
}

/// --- _GlassmorphicAlertCard (FIXED: Uses Spacer to prevent overflow) ---
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, size: 30, color: color),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        title,
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                // FIX: Replaced const SizedBox(height: 24) with Spacer
                const Spacer(),
                FittedBox(
                  child: Text(
                    value,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.textTheme.bodyLarge?.color?.withOpacity(0.8),
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

/// --- _GlassmorphicListReportCard (No change needed) ---
class _GlassmorphicListReportCard extends StatelessWidget {
  final String title;
  final List<String> items;

  const _GlassmorphicListReportCard({required this.title, required this.items});

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
              children: [
                Text(title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                const Divider(height: 30),
                Expanded(
                  child: ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (context, index) => Divider(color: theme.dividerColor.withOpacity(0.5), height: 20),
                    itemBuilder: (context, index) {
                      return FittedBox(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '${index + 1}. ${items[index]}',
                          style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
                        ),
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

/// --- _LineChartPainter (No change needed) ---
class _LineChartPainter extends CustomPainter {
  final List<double> values;
  final double maxValue;
  final Color color;
  final int segmentCount;

  _LineChartPainter({required this.values, required this.maxValue, required this.color, required this.segmentCount});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;

    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [color.withOpacity(0.4), Colors.transparent],
      stops: const [0.0, 1.0],
    ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final fillPaint = Paint()
      ..shader = gradient
      ..style = PaintingStyle.fill;

    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path();
    final fillPath = Path();

    final double xStep = size.width / segmentCount;

    for (int i = 0; i < values.length; i++) {
      final double normalizedY = size.height * (1 - (values[i] / maxValue).clamp(0.0, 1.0));
      final double x = i * xStep;
      final Offset point = Offset(x, normalizedY);

      if (i == 0) {
        path.moveTo(point.dx, point.dy);
        fillPath.moveTo(point.dx, size.height);
        fillPath.lineTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
        fillPath.lineTo(point.dx, point.dy);
      }

      if (values.length <= 20) {
        canvas.drawCircle(point, 4, dotPaint);
        canvas.drawCircle(point, 2.5, Paint()..color = Colors.white);
      }
    }

    if (values.isNotEmpty) {
      fillPath.lineTo(size.width, size.height);
      fillPath.close();
    }

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, paint);

    final referenceLinePaint = Paint()
      ..color = color.withOpacity(0.15)
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(0, size.height), Offset(size.width, size.height), referenceLinePaint);
    canvas.drawLine(Offset(0, size.height / 2), Offset(size.width, size.height / 2), referenceLinePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    if (oldDelegate is _LineChartPainter) {
      return oldDelegate.values != values || oldDelegate.maxValue != maxValue;
    }
    return true;
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