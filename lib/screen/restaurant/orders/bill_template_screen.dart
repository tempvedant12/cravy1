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
import 'dart:typed_data';

import '../billing_setup/manage_coupon_screen.dart';

// ====================================================================================
// PDF GENERATION LOGIC (Now with multiple templates)
// ====================================================================================

/// Main router function for PDF generation
Future<Uint8List> generatePdfOnIsolate(Map<String, dynamic> billData) async {
  final pdf = pw.Document();
  final font = await PdfGoogleFonts.notoSansRegular();

  // FIX: Use paperWidth from billData to set the page format
  final double paperWidth = (billData['paperWidth'] as num?)?.toDouble() ?? 58.0;
  final double baseFontSize = (billData['fontSize'] as num?)?.toDouble() ?? 8.0;

  final pageFormat = PdfPageFormat(paperWidth * PdfPageFormat.mm, double.infinity,
      marginLeft: 2 * PdfPageFormat.mm,
      marginRight: 2 * PdfPageFormat.mm,
      marginTop: 3 * PdfPageFormat.mm,
      marginBottom: 3 * PdfPageFormat.mm);

  final String templateName = billData['template'] as String? ?? 'Standard';

  pdf.addPage(
    pw.Page(
      pageFormat: pageFormat,
      build: (pw.Context context) {
        switch (templateName) {
          case 'Compact':
            return _buildCompactTemplate(context, billData, font, baseFontSize);
          case 'Bold Header':
            return _buildBoldHeaderTemplate(context, billData, font, baseFontSize);
          case 'Minimalist':
            return _buildMinimalistTemplate(context, billData, font, baseFontSize);
          case 'Centered Total':
            return _buildCenteredTotalTemplate(context, billData, font, baseFontSize);
          case 'Detailed Items':
            return _buildDetailedItemsTemplate(context, billData, font, baseFontSize);
          case 'Standard':
          default:
            return _buildStandardTemplate(context, billData, font, baseFontSize);
        }
      },
    ),
  );
  return pdf.save();
}

// Helper for building a summary row, used by all templates
pw.Widget _buildSummaryRow(String label, String value, pw.Font font,
    {pw.FontWeight? fontWeight, required double fontSize}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 1),
    child: pw.Row(
      children: [
        pw.Expanded(
          child: pw.Text(label,
              style: pw.TextStyle(
                  font: font, fontSize: fontSize, fontWeight: fontWeight)),
        ),
        pw.Text(value,
            style: pw.TextStyle(
                font: font, fontSize: fontSize, fontWeight: fontWeight)),
      ],
    ),
  );
}

// Common Header used by most templates
pw.Widget _buildHeader(Map<String, dynamic> billData, pw.Font font, double baseFontSize,
    {double? nameSize, pw.FontWeight nameWeight = pw.FontWeight.bold}) {
  return pw.Column(children: [
    if (billData['restaurantName'] != null &&
        billData['restaurantName'].isNotEmpty)
      pw.SizedBox(
        width: double.infinity,
        child: pw.Text(
          billData['restaurantName'],
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(font: font, fontSize: nameSize ?? baseFontSize + 3, fontWeight: nameWeight),
        ),
      ),
    pw.SizedBox(height: 2),
    if (billData['restaurantAddress'] != null &&
        billData['restaurantAddress'].isNotEmpty)
      pw.SizedBox(
        width: double.infinity,
        child: pw.Text(
          billData['restaurantAddress'],
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(font: font, fontSize: baseFontSize - 1),
        ),
      ),
    if (billData['phone'] != null && billData['phone'].isNotEmpty)
      pw.SizedBox(
        width: double.infinity,
        child: pw.Text(
          'Phone: ${billData['phone']}',
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(font: font, fontSize: baseFontSize - 1),
        ),
      ),
    if (billData['gst'] != null && billData['gst'].isNotEmpty)
      pw.SizedBox(
        width: double.infinity,
        child: pw.Text(
          'Tax ID: ${billData['gst']}',
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(font: font, fontSize: baseFontSize - 1),
        ),
      ),
  ]);
}

// Common Footer used by all templates
pw.Widget _buildFooter(Map<String, dynamic> billData, pw.Font font, double baseFontSize) {
  return pw.Column(children: [
    if (billData['footer'] != null && billData['footer'].isNotEmpty)
      pw.SizedBox(
        width: double.infinity,
        child: pw.Text(
          billData['footer'],
          textAlign: pw.TextAlign.center,
          style:
          pw.TextStyle(font: font, fontSize: baseFontSize, fontStyle: pw.FontStyle.italic),
        ),
      ),
    pw.SizedBox(height: 5),
    pw.SizedBox(
      width: double.infinity,
      child: pw.Text(
        'Managed with DineFlow',
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(font: font, fontSize: baseFontSize - 1),
      ),
    ),
  ]);
}

// --- TEMPLATE 1: Standard (Your Original Design) ---
pw.Widget _buildStandardTemplate(
    pw.Context context, Map<String, dynamic> billData, pw.Font font, double baseFontSize) {
  final formatter =
  NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      _buildHeader(billData, font, baseFontSize),
      pw.SizedBox(height: 4),
      if (billData['notes'] != null && billData['notes'].isNotEmpty)
        pw.SizedBox(
          width: double.infinity,
          child: pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 4),
            child: pw.Text(
              billData['notes'],
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                  font: font, fontSize: baseFontSize - 1, fontStyle: pw.FontStyle.italic),
            ),
          ),
        ),
      pw.Divider(height: 1, borderStyle: pw.BorderStyle.dashed),
      pw.SizedBox(height: 4),
      _buildSummaryRow('Bill No.', billData['billNumber'], font, fontSize: baseFontSize),
      _buildSummaryRow('Session', billData['sessionKey'], font, fontSize: baseFontSize),
      _buildSummaryRow(
          'Date', DateFormat('dd/MM/yy hh:mm a').format(DateTime.now()), font, fontSize: baseFontSize),
      pw.Divider(height: 8, borderStyle: pw.BorderStyle.dashed, thickness: 0.5),
      pw.Table.fromTextArray(
        border: null,
        cellPadding: const pw.EdgeInsets.symmetric(vertical: 1.5),
        cellAlignments: {
          0: pw.Alignment.centerLeft,
          1: pw.Alignment.center,
          2: pw.Alignment.centerRight,
        },
        headerStyle:
        pw.TextStyle(font: font, fontSize: baseFontSize, fontWeight: pw.FontWeight.bold),
        cellStyle: pw.TextStyle(font: font, fontSize: baseFontSize),
        columnWidths: {
          0: const pw.FlexColumnWidth(3.5),
          1: const pw.FlexColumnWidth(1),
          2: const pw.FlexColumnWidth(1.5),
        },
        headers: ['Item', 'Qty', 'Price'],
        data: (billData['billItems'] as List<Map<String, dynamic>>).map((item) {
          String itemName = item['name'];
          final String options = item['options'] ?? '';
          if (options.isNotEmpty) {
            itemName += '\n  └ ${options.replaceAll(', ', '\n  └ ')}';
          }
          return [
            itemName,
            item['qty'].toString(),
            formatter.format((item['price'] as double) * (item['qty'] as int)),
          ];
        }).toList(),
      ),
      pw.Divider(height: 8, borderStyle: pw.BorderStyle.dashed, thickness: 0.5),
      _buildSummaryRow('Subtotal', formatter.format(billData['subtotal']), font, fontSize: baseFontSize),
      if (billData['staffDiscount'] > 0)
        _buildSummaryRow('Staff Discount',
            "- ${formatter.format(billData['staffDiscount'])}", font, fontSize: baseFontSize),
      if (billData['couponDiscount'] > 0)
        _buildSummaryRow('Coupon Discount',
            "- ${formatter.format(billData['couponDiscount'])}", font, fontSize: baseFontSize),
      for (var entry in (billData['calculatedCharges'] as Map<String, double>).entries)
        _buildSummaryRow(entry.key, formatter.format(entry.value), font, fontSize: baseFontSize),
      pw.Divider(height: 8, thickness: 1),
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(
          children: [
            pw.Expanded(
              child: pw.Text('GRAND TOTAL',
                  style: pw.TextStyle(
                      font: font, fontSize: baseFontSize + 3, fontWeight: pw.FontWeight.bold)),
            ),
            pw.Text(formatter.format(billData['total']),
                style: pw.TextStyle(
                    font: font, fontSize: baseFontSize + 3, fontWeight: pw.FontWeight.bold)),
          ],
        ),
      ),
      pw.Divider(height: 8, thickness: 1),
      _buildSummaryRow('Paid By', billData['paymentMethod'], font, fontSize: baseFontSize),
      pw.SizedBox(height: 8),
      _buildFooter(billData, font, baseFontSize),
    ],
  );
}

// All other template builder functions are similar and have been updated to accept baseFontSize.
// ... (rest of the template builder functions with baseFontSize passed to text styles)

// --- TEMPLATE 2: Compact ---
pw.Widget _buildCompactTemplate(
    pw.Context context, Map<String, dynamic> billData, pw.Font font, double baseFontSize) {
  final formatter =
  NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
  final compactFontSize = baseFontSize - 1;
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      _buildHeader(billData, font, baseFontSize, nameSize: baseFontSize + 2),
      pw.SizedBox(height: 2),
      if (billData['notes'] != null && billData['notes'].isNotEmpty)
        pw.SizedBox(
          width: double.infinity,
          child: pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 2),
            child: pw.Text(
              billData['notes'],
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                  font: font, fontSize: compactFontSize - 1, fontStyle: pw.FontStyle.italic),
            ),
          ),
        ),
      pw.Divider(height: 1, borderStyle: pw.BorderStyle.dashed),
      pw.SizedBox(height: 2),
      _buildSummaryRow('Bill: ${billData['billNumber']}',
          DateFormat('dd/MM/yy hh:mm a').format(DateTime.now()), font,
          fontSize: compactFontSize),
      pw.Divider(height: 4, borderStyle: pw.BorderStyle.dashed, thickness: 0.5),
      pw.Table.fromTextArray(
        border: null,
        cellPadding: const pw.EdgeInsets.symmetric(vertical: 1),
        cellAlignments: {
          0: pw.Alignment.centerLeft,
          1: pw.Alignment.center,
          2: pw.Alignment.centerRight,
        },
        headerStyle:
        pw.TextStyle(font: font, fontSize: compactFontSize, fontWeight: pw.FontWeight.bold),
        cellStyle: pw.TextStyle(font: font, fontSize: compactFontSize),
        columnWidths: {
          0: const pw.FlexColumnWidth(3.5),
          1: const pw.FlexColumnWidth(1),
          2: const pw.FlexColumnWidth(1.5),
        },
        headers: ['Item', 'Qty', 'Price'],
        data: (billData['billItems'] as List<Map<String, dynamic>>).map((item) {
          String itemName = item['name'];
          final String options = item['options'] ?? '';
          if (options.isNotEmpty) {
            itemName += '\n  └ ${options.replaceAll(', ', '\n  └ ')}';
          }
          return [
            itemName,
            item['qty'].toString(),
            formatter.format((item['price'] as double) * (item['qty'] as int)),
          ];
        }).toList(),
      ),
      pw.Divider(height: 4, borderStyle: pw.BorderStyle.dashed, thickness: 0.5),
      _buildSummaryRow('Subtotal', formatter.format(billData['subtotal']), font, fontSize: compactFontSize),
      if (billData['staffDiscount'] > 0)
        _buildSummaryRow('Staff Discount',
            "- ${formatter.format(billData['staffDiscount'])}", font, fontSize: compactFontSize),
      if (billData['couponDiscount'] > 0)
        _buildSummaryRow('Coupon Discount',
            "- ${formatter.format(billData['couponDiscount'])}", font, fontSize: compactFontSize),
      for (var entry in (billData['calculatedCharges'] as Map<String, double>).entries)
        _buildSummaryRow(entry.key, formatter.format(entry.value), font, fontSize: compactFontSize),
      pw.Divider(height: 6, thickness: 1),
      _buildSummaryRow('GRAND TOTAL', formatter.format(billData['total']), font,
          fontSize: baseFontSize + 2, fontWeight: pw.FontWeight.bold),
      pw.Divider(height: 6, thickness: 1),
      _buildSummaryRow('Paid By', billData['paymentMethod'], font, fontSize: compactFontSize),
      pw.SizedBox(height: 6),
      _buildFooter(billData, font, baseFontSize),
    ],
  );
}

// --- TEMPLATE 3: Bold Header ---
pw.Widget _buildBoldHeaderTemplate(
    pw.Context context, Map<String, dynamic> billData, pw.Font font, double baseFontSize) {
  // This template is the same as standard, but with a different header style.
  final standardTemplate = _buildStandardTemplate(context, billData, font, baseFontSize) as pw.Column;
  standardTemplate.children[0] = _buildHeader(billData, font, baseFontSize, nameSize: baseFontSize + 6);
  return standardTemplate;
}

// --- TEMPLATE 4: Minimalist ---
pw.Widget _buildMinimalistTemplate(
    pw.Context context, Map<String, dynamic> billData, pw.Font font, double baseFontSize) {
  final formatter =
  NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      _buildHeader(billData, font, baseFontSize),
      pw.SizedBox(height: 4),
      if (billData['notes'] != null && billData['notes'].isNotEmpty)
        pw.SizedBox(
          width: double.infinity,
          child: pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 4),
            child: pw.Text(
              billData['notes'],
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                  font: font, fontSize: baseFontSize - 1, fontStyle: pw.FontStyle.italic),
            ),
          ),
        ),
      pw.SizedBox(height: 8),
      _buildSummaryRow('Bill No.', billData['billNumber'], font, fontSize: baseFontSize),
      _buildSummaryRow('Session', billData['sessionKey'], font, fontSize: baseFontSize),
      _buildSummaryRow(
          'Date', DateFormat('dd/MM/yy hh:mm a').format(DateTime.now()), font, fontSize: baseFontSize),
      pw.SizedBox(height: 8),
      pw.Table.fromTextArray(
        border: null,
        headerStyle:
        pw.TextStyle(font: font, fontSize: baseFontSize, fontWeight: pw.FontWeight.bold),
        cellStyle: pw.TextStyle(font: font, fontSize: baseFontSize),
        columnWidths: {
          0: const pw.FlexColumnWidth(3.5),
          1: const pw.FlexColumnWidth(1),
          2: const pw.FlexColumnWidth(1.5),
        },
        cellAlignments: {
          0: pw.Alignment.centerLeft,
          1: pw.Alignment.center,
          2: pw.Alignment.centerRight,
        },
        headers: ['Item', 'Qty', 'Price'],
        data: (billData['billItems'] as List<Map<String, dynamic>>).map((item) {
          String itemName = item['name'];
          final String options = item['options'] ?? '';
          if (options.isNotEmpty) {
            itemName += '\n  └ ${options.replaceAll(', ', '\n  └ ')}';
          }
          return [
            itemName,
            item['qty'].toString(),
            formatter.format((item['price'] as double) * (item['qty'] as int)),
          ];
        }).toList(),
      ),
      pw.SizedBox(height: 8),
      _buildSummaryRow('Subtotal', formatter.format(billData['subtotal']), font, fontSize: baseFontSize),
      if (billData['staffDiscount'] > 0)
        _buildSummaryRow('Staff Discount',
            "- ${formatter.format(billData['staffDiscount'])}", font, fontSize: baseFontSize),
      if (billData['couponDiscount'] > 0)
        _buildSummaryRow('Coupon Discount',
            "- ${formatter.format(billData['couponDiscount'])}", font, fontSize: baseFontSize),
      for (var entry in (billData['calculatedCharges'] as Map<String, double>).entries)
        _buildSummaryRow(entry.key, formatter.format(entry.value), font, fontSize: baseFontSize),
      pw.SizedBox(height: 8),
      _buildSummaryRow('GRAND TOTAL', formatter.format(billData['total']), font,
          fontSize: baseFontSize + 3, fontWeight: pw.FontWeight.bold),
      pw.SizedBox(height: 4),
      _buildSummaryRow('Paid By', billData['paymentMethod'], font, fontSize: baseFontSize),
      pw.SizedBox(height: 8),
      _buildFooter(billData, font, baseFontSize),
    ],
  );
}

// --- TEMPLATE 5: Centered Total ---
pw.Widget _buildCenteredTotalTemplate(
    pw.Context context, Map<String, dynamic> billData, pw.Font font, double baseFontSize) {
  final formatter =
  NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
  final standardTemplate = _buildStandardTemplate(context, billData, font, baseFontSize) as pw.Column;

  // Replace the Grand Total part
  final grandTotalWidget = pw.Center(
    child: pw.Column(children: [
      pw.Text('GRAND TOTAL',
          style: pw.TextStyle(
              font: font, fontSize: baseFontSize + 3, fontWeight: pw.FontWeight.bold)),
      pw.Text(
          formatter.format(billData['total']),
          style: pw.TextStyle(
              font: font, fontSize: baseFontSize + 6, fontWeight: pw.FontWeight.bold)),
    ]),
  );

  // Find and replace the widget
  int grandTotalIndex = standardTemplate.children.indexWhere((widget) => widget is pw.Padding && (widget.child as pw.Row).children.length > 1 && ((widget.child as pw.Row).children[0] as pw.Expanded).child is pw.Text && (((widget.child as pw.Row).children[0] as pw.Expanded).child as pw.Text).text == 'GRAND TOTAL');
  if (grandTotalIndex != -1) {
    standardTemplate.children[grandTotalIndex] = grandTotalWidget;
  }

  return standardTemplate;
}


// --- TEMPLATE 6: Detailed Items ---
pw.Widget _buildDetailedItemsTemplate(
    pw.Context context, Map<String, dynamic> billData, pw.Font font, double baseFontSize) {
  final formatter =
  NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
  final standardTemplate = _buildStandardTemplate(context, billData, font, baseFontSize) as pw.Column;

  // Replace the table
  final detailedTable = pw.Table.fromTextArray(
    border: null,
    cellPadding: const pw.EdgeInsets.symmetric(vertical: 1.5),
    headerStyle:
    pw.TextStyle(font: font, fontSize: baseFontSize - 1, fontWeight: pw.FontWeight.bold),
    cellStyle: pw.TextStyle(font: font, fontSize: baseFontSize - 1),
    cellAlignments: {
      0: pw.Alignment.centerLeft,
      1: pw.Alignment.center,
      2: pw.Alignment.centerRight,
      3: pw.Alignment.centerRight,
    },
    columnWidths: {
      0: const pw.FlexColumnWidth(2.5),
      1: const pw.FlexColumnWidth(1),
      2: const pw.FlexColumnWidth(1.5),
      3: const pw.FlexColumnWidth(1.5),
    },
    headers: ['Item', 'Qty', 'Rate', 'Total'],
    data: (billData['billItems'] as List<Map<String, dynamic>>).map((item) {
      String itemName = item['name'];
      final String options = item['options'] ?? '';
      if (options.isNotEmpty) {
        itemName += '\n  └ ${options.replaceAll(', ', '\n  └ ')}';
      }
      return [
        itemName,
        item['qty'].toString(),
        formatter.format(item['price']),
        formatter.format((item['price'] as double) * (item['qty'] as int)),
      ];
    }).toList(),
  );

  int tableIndex = standardTemplate.children.indexWhere((widget) => widget is pw.Table);
  if(tableIndex != -1) {
    standardTemplate.children[tableIndex] = detailedTable;
  }

  return standardTemplate;
}


// ====================================================================================
// WIDGET IMPLEMENTATION (With one correction)
// ====================================================================================

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
  List<MenuItem> _allMenuItems = [];

  @override
  void initState() {
    super.initState();
    _detailsFuture = _fetchBillDetails();
  }

  Map<String, dynamic> _gatherBillData(Map<String, dynamic> details) {
    final orderDocs = details['orders'] as List<QueryDocumentSnapshot>;
    final billingDetails =
        (orderDocs.first.data() as Map<String, dynamic>)['billingDetails']
        as Map<String, dynamic>? ??
            {};

    final billNumber = billingDetails['billNumber'] ?? orderDocs.first.id.substring(0, 8).toUpperCase();

    final aggregatedItems = _aggregateOrders(orderDocs).values.toList();
    final subtotal =
    aggregatedItems.fold(0.0, (sum, item) => sum + item.totalPrice);
    final discountPercentage = (billingDetails['discount'] ?? 0.0).toDouble();
    final staffDiscountAmount = subtotal * discountPercentage;
    final couponDiscountAmount =
    (billingDetails['couponDiscount'] ?? 0.0).toDouble();
    final List<dynamic> appliedChargesList =
        billingDetails['appliedCharges'] as List<dynamic>? ?? [];
    final Map<String, double> calculatedCharges = {};
    for (var chargeMap in appliedChargesList) {
      if (chargeMap is Map<String, dynamic>) {
        final label = chargeMap['label'] as String? ?? 'Charge';
        final amount = (chargeMap['amount'] as num? ?? 0.0).toDouble();
        calculatedCharges[label] = amount;
      }
    }
    final billItems = aggregatedItems.map((item) {
      return {
        'name': item.menuItem.name,
        'qty': item.quantity,
        'price': item.singleItemPrice,
        'options': item.selectedOptions.map((o) => o.optionName).join(', '),
      };
    }).toList();

    return {
      'restaurantName': details['restaurantName'],
      'restaurantAddress': details['restaurantAddress'],
      'phone': _selectedConfig!.contactPhone,
      'gst': _selectedConfig!.gstNumber,
      'footer': _selectedConfig!.footerNote,
      'notes': _selectedConfig!.billNotes,
      'template': _selectedConfig!.template,
      'paperWidth': _selectedConfig!.paperWidth,
      'fontSize': _selectedConfig!.fontSize,
      'billItems': billItems,
      'subtotal': subtotal,
      'staffDiscount': staffDiscountAmount,
      'couponDiscount': couponDiscountAmount,
      'calculatedCharges': calculatedCharges,
      'total': billingDetails['finalTotal'] ?? widget.grandTotal,
    'billNumber': billNumber,
      'sessionKey': widget.sessionKey,
      'paymentMethod': widget.paymentMethod,
    };
  }

  Future<void> _printBill() async {
    final details = await _detailsFuture;
    if (_selectedConfig == null || details == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Bill data is not ready or no design is selected.')),
      );
      return;
    }
    try {
      final billData = _gatherBillData(details);
      final pdfData = await compute(generatePdfOnIsolate, billData);
      await Printing.layoutPdf(onLayout: (format) async => pdfData);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open print preview: $e')),
        );
      }
    }
  }

  Future<void> _shareBill() async {
    final details = await _detailsFuture;
    if (_selectedConfig == null || details == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Bill data is not ready or no design is selected.')),
      );
      return;
    }
    try {
      final billData = _gatherBillData(details);
      final pdfData = await compute(generatePdfOnIsolate, billData);
      await Printing.sharePdf(
          bytes: pdfData, filename: 'bill-${billData['billNumber']}.pdf');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not share bill: $e')),
        );
      }
    }
  }

  void _closeScreen() {
    Navigator.of(context).pop();
  }

  Future<List<MenuItem>> _fetchAllMenuItems(String restaurantId) async {
    final menusSnapshot = await FirebaseFirestore.instance
        .collection('restaurants')
        .doc(restaurantId)
        .collection('menus')
        .get();
    final List<MenuItem> allItems = [];
    for (var menuDoc in menusSnapshot.docs) {
      final itemsSnapshot = await menuDoc.reference.collection('items').get();
      allItems.addAll(
          itemsSnapshot.docs.map((doc) => MenuItem.fromFirestore(doc)));
    }
    return allItems;
  }

  Future<Map<String, dynamic>> _fetchBillDetails() async {
    final restaurantRef = FirebaseFirestore.instance
        .collection('restaurants')
        .doc(widget.restaurantId);
    final latestPaidOrderSnapshot = await restaurantRef
        .collection('orders')
        .where('sessionKey', isEqualTo: widget.sessionKey)
        .where('isPaid', isEqualTo: true)
        .orderBy('billingDetails.billedAt', descending: true)
        .limit(1)
        .get();
    Timestamp? latestBilledAt;
    if (latestPaidOrderSnapshot.docs.isNotEmpty) {
      latestBilledAt = (latestPaidOrderSnapshot.docs.first.data()
      as Map<String, dynamic>)['billingDetails']['billedAt']
      as Timestamp?;
    }
    final List<Future> futures = [
      restaurantRef.get(),
      restaurantRef.collection('billConfigurations').get(),
      _fetchAllMenuItems(widget.restaurantId),
    ];
    Query orderQuery = restaurantRef
        .collection('orders')
        .where('sessionKey', isEqualTo: widget.sessionKey)
        .where('isPaid', isEqualTo: true);
    if (latestBilledAt != null) {
      orderQuery = orderQuery.where('billingDetails.billedAt',
          isEqualTo: latestBilledAt);
    }
    futures.add(orderQuery.get());
    final results = await Future.wait(futures);
    final restaurantDoc = results[0] as DocumentSnapshot;
    final configsSnapshot = results[1] as QuerySnapshot;
    _allMenuItems = results[2] as List<MenuItem>;
    final orderDocsSnapshot = results[3] as QuerySnapshot;
    final restaurantData = restaurantDoc.data() as Map<String, dynamic>? ?? {};
    final defaultBillConfigId =
    restaurantData['defaultBillConfigId'] as String?;
    CouponModel? coupon;
    final orderDocs = orderDocsSnapshot.docs;
    if (orderDocs.isNotEmpty) {
      final billingDetails =
          (orderDocs.first.data() as Map<String, dynamic>)['billingDetails']
          as Map<String, dynamic>? ??
              {};
      final couponCode = billingDetails['couponCode'] as String?;
      if (couponCode != null && couponCode.isNotEmpty) {
        final couponSnapshot = await restaurantRef
            .collection('coupons')
            .where('code', isEqualTo: couponCode)
            .get();
        if (couponSnapshot.docs.isNotEmpty) {
          coupon = CouponModel.fromFirestore(couponSnapshot.docs.first);
        }
      }
    }
    final allConfigs = configsSnapshot.docs
        .map((doc) => BillConfiguration.fromFirestore(doc))
        .toList();
    return {
      'restaurantName': restaurantData['name'] ?? 'Restaurant Name Not Set',
      'restaurantAddress': restaurantData['address'] ?? 'Address Not Set',
      'billConfigs': allConfigs,
      'defaultBillConfigId': defaultBillConfigId,
      'orders': orderDocsSnapshot.docs,
      'coupon': coupon,
    };
  }

  Map<String, OrderItem> _aggregateOrders(
      List<QueryDocumentSnapshot> orders) {
    final aggregatedItems = <String, OrderItem>{};
    for (var orderDoc in orders) {
      final orderData = orderDoc.data() as Map<String, dynamic>;
      final items = List<Map<String, dynamic>>.from(orderData['items'] ?? []);
      for (var itemMap in items) {
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
            return Center(
                child: Text('Error loading bill data: ${snapshot.error}'));
          }
          if ((snapshot.data?['orders'] as List).isEmpty) {
            return const Center(
                child: Text('No paid orders found for this session.'));
          }
          final details = snapshot.data!;
          if (_allConfigs.isEmpty ||
              _allConfigs.length != (details['billConfigs'] as List).length) {
            _allConfigs = details['billConfigs'] as List<BillConfiguration>;
            final defaultId = details['defaultBillConfigId'] as String?;
            if (_allConfigs.isNotEmpty) {
              _selectedConfig = _allConfigs.firstWhere((c) => c.id == defaultId,
                  orElse: () => _allConfigs.first);
            }
          }
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                child: _buildDesignSelectorButton(context),
              ),
              Expanded(
                child: _buildBillContent(context, details),
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
                        trailing: _selectedConfig?.id == config.id
                            ? Icon(Icons.check_circle,
                            color: Theme.of(context).primaryColor)
                            : null,
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
                    Navigator.of(context)
                        .push(
                      MaterialPageRoute(
                        builder: (context) =>
                            BillDesignScreen(restaurantId: widget.restaurantId),
                      ),
                    )
                        .then((_) =>
                        setState(() => _detailsFuture = _fetchBillDetails()));
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
    if (_allConfigs.isEmpty) return const SizedBox.shrink();
    return OutlinedButton.icon(
      icon: const Icon(Icons.style_outlined),
      label: Text('Change Design: (${_selectedConfig?.template ?? 'N/A'})'),
      onPressed: () => _showDesignSelectionDialog(context),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(double.infinity, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildBillContent(
      BuildContext context, Map<String, dynamic> details) {
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
                  Navigator.of(context)
                      .push(
                    MaterialPageRoute(
                        builder: (context) => BillDesignScreen(
                            restaurantId: widget.restaurantId)),
                  )
                      .then((_) =>
                      setState(() => _detailsFuture = _fetchBillDetails()));
                },
                child: const Text('Create First Design'),
              )
            ],
          ),
        ),
      );
    }
    final billData = _gatherBillData(details);

    return Container(
      color: Theme.of(context).scaffoldBackgroundColor.withAlpha(150),
      padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 16.0),
      child: Center(
        child: AspectRatio(
          aspectRatio: _selectedConfig!.paperWidth / 150, // Use configured width
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 8,
                  offset: Offset(0, 4),
                )
              ],
            ),
            child: PdfPreview(
              key: ValueKey(_selectedConfig!.id),
              build: (format) => compute(generatePdfOnIsolate, billData),
              useActions: false,
              allowSharing: false,
              allowPrinting: false,
              canChangeOrientation: false,
              canChangePageFormat: false,
              canDebug: false,
              pdfPreviewPageDecoration: const BoxDecoration(), // Remove default decoration to avoid conflict
            ),
          ),
        ),
      ),
    );
  }


  Widget _buildBottomBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: const [
          BoxShadow(
              color: Colors.black12, blurRadius: 10, offset: Offset(0, -5))
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _printBill,
                  icon: const Icon(Icons.print_outlined),
                  label: const Text('Print'),
                  style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16)),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _shareBill,
                  icon: const Icon(Icons.share),
                  label: const Text('Share'),
                  style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _closeScreen,
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Done'),
              style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16)),
            ),
          ),
        ],
      ),
    );
  }
}