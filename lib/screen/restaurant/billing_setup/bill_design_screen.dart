

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class BillConfiguration {
  final String id;
  final String gstNumber;
  final String contactPhone;
  final String footerNote;
  final String billNotes;
  final String template;
  final List<CustomChargeModel> customCharges;

  BillConfiguration({
    required this.id,
    required this.gstNumber,
    required this.contactPhone,
    required this.footerNote,
    required this.billNotes,
    required this.template,
    required this.customCharges,
  });

  factory BillConfiguration.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final chargesData = data['customCharges'] as List<dynamic>? ?? [];
    return BillConfiguration(
      id: doc.id,
      gstNumber: data['gstNumber'] ?? '',
      contactPhone: data['contactPhone'] ?? '',
      footerNote: data['footerNote'] ?? '',
      billNotes: data['billNotes'] ?? '',
      template: data['template'] ?? 'Standard',
      customCharges:
      chargesData.map((map) => CustomChargeModel.fromMap(map)).toList(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'gstNumber': gstNumber,
      'contactPhone': contactPhone,
      'footerNote': footerNote,
      'billNotes': billNotes,
      'template': template,
      'customCharges': customCharges.map((c) => c.toMap()).toList(),
    };
  }
}

class CustomChargeModel {
  final String label;
  final double rate;
  final bool isMandatory;

  CustomChargeModel({
    required this.label,
    required this.rate,
    this.isMandatory = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'label': label,
      'rate': rate,
      'isMandatory': isMandatory,
    };
  }

  factory CustomChargeModel.fromMap(Map<String, dynamic> map) {
    return CustomChargeModel(
      label: map['label'] ?? '',
      rate: (map['rate'] ?? 0.0).toDouble(),
      isMandatory: map['isMandatory'] ?? false,
    );
  }
}

class BillDesignScreen extends StatefulWidget {
  final String restaurantId;
  final BillConfiguration? existingConfig;

  const BillDesignScreen(
      {super.key, required this.restaurantId, this.existingConfig});

  @override
  State<BillDesignScreen> createState() => _BillDesignScreenState();
}

class _BillDesignScreenState extends State<BillDesignScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _gstController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _footerNotesController = TextEditingController();
  final TextEditingController _billNotesController = TextEditingController();

  String _selectedTemplate = 'Standard';
  bool _isLoading = true;
  List<CustomChargeModel> _customCharges = [];

  String _restaurantName = 'Your Restaurant Name';
  String _restaurantAddress = '123, Your Address, City';

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    
    if (widget.existingConfig != null) {
      final config = widget.existingConfig!;
      _gstController.text = config.gstNumber;
      _phoneController.text = config.contactPhone;
      _footerNotesController.text = config.footerNote;
      _billNotesController.text = config.billNotes;
      _selectedTemplate = config.template;
      _customCharges = config.customCharges;
    } else {
      _footerNotesController.text = 'Thank you! Please visit again.';
    }

    final doc = await FirebaseFirestore.instance
        .collection('restaurants')
        .doc(widget.restaurantId)
        .get();

    if (doc.exists && mounted) {
      final data = doc.data() as Map<String, dynamic>;
      setState(() {
        _restaurantName = data['name'] ?? 'Your Restaurant Name';
        _restaurantAddress = data['address'] ?? '123, Your Address, City';
        _isLoading = false;
      });
    } else if (mounted) {
      setState(() => _isLoading = false);
    }
  }


  Future<void> _saveBillingConfig() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);

      final config = BillConfiguration(
        id: widget.existingConfig?.id ?? '', 
        gstNumber: _gstController.text.trim(),
        contactPhone: _phoneController.text.trim(),
        footerNote: _footerNotesController.text.trim(),
        billNotes: _billNotesController.text.trim(),
        template: _selectedTemplate,
        customCharges: _customCharges,
      );

      final collection = FirebaseFirestore.instance
          .collection('restaurants')
          .doc(widget.restaurantId)
          .collection('billConfigurations');

      try {
        if (widget.existingConfig == null) {
          await collection.add(config.toMap());
        } else {
          await collection.doc(config.id).update(config.toMap());
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Bill design saved successfully!')),
          );
          Navigator.of(context).pop();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error saving design: ${e.toString()}')),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.existingConfig == null
              ? 'Create Bill Design'
              : 'Edit Bill Design'),
          actions: [
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _isLoading ? null : _saveBillingConfig,
              tooltip: 'Save Design',
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.edit_note_outlined), text: 'Design'),
              Tab(icon: Icon(Icons.visibility_outlined), text: 'Preview'),
            ],
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Form(
          key: _formKey,
          child: TabBarView(
            children: [
              ListView(
                padding: const EdgeInsets.all(24.0),
                children: [
                  _buildConfigurationSection(),
                  const SizedBox(height: 40),
                  _buildCustomChargesSection(),
                ],
              ),
              SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                    vertical: 24.0, horizontal: 12.0),
                child: Column(
                  children: [
                    Padding(
                      padding:
                      const EdgeInsets.symmetric(horizontal: 12.0),
                      child: _buildTemplateSelectionSection(),
                    ),
                    const SizedBox(height: 24),
                    _BillPreview(
                      restaurantName: _restaurantName,
                      restaurantAddress: _restaurantAddress,
                      gst: _gstController.text,
                      phone: _phoneController.text,
                      footer: _footerNotesController.text,
                      notes: _billNotesController.text,
                      customCharges: _customCharges,
                      template: _selectedTemplate,
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

  Widget _buildConfigurationSection() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Business & Contact Info',
                style: Theme.of(context).textTheme.titleLarge),
            const Divider(height: 24),
            TextFormField(
              controller: _gstController,
              decoration: const InputDecoration(
                  labelText: 'Tax/Registration No.',
                  hintText: 'e.g., GSTIN/VAT ID',
                  icon: Icon(Icons.badge_outlined)),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _phoneController,
              decoration: const InputDecoration(
                  labelText: 'Contact Phone',
                  icon: Icon(Icons.phone_outlined)),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _billNotesController,
              decoration: const InputDecoration(
                  labelText: 'Bill Notes (Optional)',
                  hintText: 'e.g., Wi-Fi: our_network',
                  icon: Icon(Icons.speaker_notes_outlined)),
              maxLines: 3,
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _footerNotesController,
              decoration: const InputDecoration(
                  labelText: 'Footer Message',
                  icon: Icon(Icons.note_outlined)),
              maxLines: 2,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomChargesSection() {
    final theme = Theme.of(context);
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Dynamic Taxes/Charges',
                      style: theme.textTheme.titleLarge),
                ),
                OutlinedButton.icon(
                  onPressed: () => _addOrEditCharge(),
                  icon: const Icon(Icons.add),
                  label: const Text('Add'),
                ),
              ],
            ),
            const Divider(height: 24),
            if (_customCharges.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Center(
                  child: Text(
                      'Add charges like VAT, Sales Tax, or Service Fee.',
                      style: theme.textTheme.bodyMedium),
                ),
              ),
            ..._customCharges.map((charge) {
              return ListTile(
                title: Text(charge.label),
                subtitle: Text('Rate: ${charge.rate.toStringAsFixed(1)}%'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(charge.isMandatory ? 'Mandatory' : 'Optional',
                        style: theme.textTheme.bodySmall),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                      onPressed: () =>
                          setState(() => _customCharges.remove(charge)),
                    ),
                  ],
                ),
                onTap: () => _addOrEditCharge(existingCharge: charge),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  void _addOrEditCharge({CustomChargeModel? existingCharge}) async {
    final result = await showDialog<CustomChargeModel>(
      context: context,
      builder: (context) =>
          _AddEditChargeDialog(initialCharge: existingCharge),
    );

    if (result != null) {
      setState(() {
        if (existingCharge != null) {
          final index = _customCharges.indexOf(existingCharge);
          _customCharges[index] = result;
        } else {
          _customCharges.add(result);
        }
      });
    }
  }

  Widget _buildTemplateSelectionSection() {
    final Map<String, BillTheme> templates = {
      'Standard': BillTheme.standard,
      'Minimalist': BillTheme.minimalist,
      'Modern': BillTheme.modern,
      'Cyberpunk': BillTheme.cyberpunk,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Select Bill Template',
            style: Theme.of(context).textTheme.titleLarge),
        const Divider(height: 24),
        SizedBox(
          height: 140,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: templates.length,
            itemBuilder: (context, index) {
              final title = templates.keys.elementAt(index);
              final theme = templates.values.elementAt(index);
              final isSelected = _selectedTemplate == title;

              return GestureDetector(
                onTap: () => setState(() => _selectedTemplate = title),
                child: TemplatePreviewCard(
                  title: title,
                  theme: theme,
                  isSelected: isSelected,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class TemplatePreviewCard extends StatelessWidget {
  final String title;
  final BillTheme theme;
  final bool isSelected;

  const TemplatePreviewCard({
    super.key,
    required this.title,
    required this.theme,
    required this.isSelected,
  });

  @override
  Widget build(BuildContext context) {
    final appTheme = Theme.of(context);
    return Container(
      width: 120,
      margin: const EdgeInsets.only(right: 16),
      child: Card(
        elevation: isSelected ? 8 : 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isSelected ? appTheme.primaryColor : appTheme.dividerColor,
            width: isSelected ? 3 : 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Container(
                  color: theme.background,
                  child: Icon(Icons.receipt_long, size: 40, color: theme.textColor),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(8.0),
                color: appTheme.cardColor,
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: appTheme.textTheme.bodyMedium?.copyWith(
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddEditChargeDialog extends StatefulWidget {
  final CustomChargeModel? initialCharge;
  const _AddEditChargeDialog({this.initialCharge});

  @override
  State<_AddEditChargeDialog> createState() => __AddEditChargeDialogState();
}

class __AddEditChargeDialogState extends State<_AddEditChargeDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _labelController;
  late TextEditingController _rateController;
  late bool _isMandatory;

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController(text: widget.initialCharge?.label ?? '');
    _rateController = TextEditingController(text: widget.initialCharge?.rate.toString() ?? '0.0');
    _isMandatory = widget.initialCharge?.isMandatory ?? false;
  }

  @override
  void dispose() {
    _labelController.dispose();
    _rateController.dispose();
    super.dispose();
  }

  void _save() {
    if (_formKey.currentState!.validate()) {
      final charge = CustomChargeModel(
        label: _labelController.text.trim(),
        rate: double.parse(_rateController.text),
        isMandatory: _isMandatory,
      );
      Navigator.of(context).pop(charge);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initialCharge == null ? 'Add New Charge' : 'Edit Charge'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _labelController,
                decoration: const InputDecoration(labelText: 'Charge/Tax Label'),
                validator: (val) => val!.trim().isEmpty ? 'Enter a label' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _rateController,
                decoration: const InputDecoration(labelText: 'Rate (%)'),
                keyboardType: TextInputType.number,
                validator: (val) {
                  final rate = double.tryParse(val!);
                  if (rate == null || rate < 0) return 'Invalid rate';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('Is Mandatory?'),
                value: _isMandatory,
                onChanged: (val) => setState(() => _isMandatory = val),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ElevatedButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

class BillTheme {
  final Color background;
  final Color textColor;
  final Color accentColor;
  final Color dividerColor;

  const BillTheme({
    required this.background,
    required this.textColor,
    required this.accentColor,
    required this.dividerColor,
  });

  static BillTheme getThemeByName(String name) {
    switch (name) {
      case 'Minimalist': return minimalist;
      case 'Modern': return modern;
      case 'Cyberpunk': return cyberpunk;
      default: return standard;
    }
  }

  static const BillTheme standard = BillTheme(background: Colors.white, textColor: Colors.black, accentColor: Colors.black, dividerColor: Colors.grey);
  static const BillTheme minimalist = BillTheme(background: Colors.white, textColor: Color(0xFF555555), accentColor: Color(0xFF111111), dividerColor: Color(0xFFEEEEEE));
  static const BillTheme modern = BillTheme(background: Color(0xFFF8F8F8), textColor: Color(0xFF333333), accentColor: Colors.deepOrange, dividerColor: Color(0xFFDDDDDD));
  static const BillTheme cyberpunk = BillTheme(background: Color(0xFF0A0A1A), textColor: Color(0xFFE0E0E0), accentColor: Color(0xFF00FFFF), dividerColor: Color(0xFF44475A));
}

class _BillPreview extends StatelessWidget {
  final String restaurantName;
  final String restaurantAddress;
  final String gst;
  final String phone;
  final String footer;
  final String notes;
  final List<CustomChargeModel> customCharges;
  final String template;

  const _BillPreview({
    required this.restaurantName,
    required this.restaurantAddress,
    required this.gst,
    required this.phone,
    required this.footer,
    required this.notes,
    required this.customCharges,
    required this.template,
  });

  @override
  Widget build(BuildContext context) {
    final billTheme = BillTheme.getThemeByName(template);
    final sampleItems = [
      {'name': 'Classic Burger (Extra Cheese)', 'qty': 1, 'price': 290.0},
      {'name': 'Fries & Coke Combo', 'qty': 2, 'price': 150.0},
    ];
    final double subtotal = sampleItems.fold(0.0, (sum, item) => sum + (item['price'] as num) * (item['qty'] as num));
    final double staffDiscount = subtotal * 0.10;
    final double couponDiscount = subtotal * 0.05;
    double total = subtotal - staffDiscount - couponDiscount;

    final Map<String, double> calculatedCharges = {};
    for (var charge in customCharges) {
      if (charge.isMandatory) {
        final chargeAmount = total * (charge.rate / 100.0);
        calculatedCharges['${charge.label} (${charge.rate.toStringAsFixed(1)}%)'] = chargeAmount;
        total += chargeAmount;
      }
    }

    return BillTemplate(
      theme: billTheme,
      restaurantName: restaurantName,
      restaurantAddress: restaurantAddress,
      phone: phone,
      gst: gst,
      footer: footer,
      notes: notes,
      sampleItems: sampleItems.cast<Map<String, Object>>(), 
      subtotal: subtotal,
      staffDiscount: staffDiscount,
      couponDiscount: couponDiscount,
      calculatedCharges: calculatedCharges,
      total: total,
    );
  }
}

class BillTemplate extends StatelessWidget {
  final BillTheme theme;
  final String restaurantName;
  final String restaurantAddress;
  final String phone;
  final String gst;
  final String footer;
  final String notes;
  final List<Map<String, Object>>? billItems;
  final List<Map<String, Object>>? sampleItems;
  final double subtotal;
  final double staffDiscount;
  final double couponDiscount; // <--- ADDED FIELD
  final Map<String, double> calculatedCharges;
  final double total;
  final String? billNumber;
  final String? sessionKey;
  final String? paymentMethod;

  const BillTemplate({
    super.key,
    required this.theme,
    required this.restaurantName,
    required this.restaurantAddress,
    required this.phone,
    required this.gst,
    required this.footer,
    required this.notes,
    this.billItems,
    this.sampleItems,
    required this.subtotal,
    required this.staffDiscount,
    required this.couponDiscount, // <--- ADDED FIELD
    required this.calculatedCharges,
    required this.total,
    this.billNumber,
    this.sessionKey,
    this.paymentMethod,
  }) : assert(billItems != null || sampleItems != null);

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
    final itemsToDisplay = billItems ?? sampleItems!;

    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(8),
      color: theme.background,
      child: Container(
        padding: const EdgeInsets.all(20.0),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: theme.dividerColor)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(restaurantName, textAlign: TextAlign.center, style: TextStyle(color: theme.accentColor, fontSize: 22, fontWeight: FontWeight.bold)),
            Text(restaurantAddress, textAlign: TextAlign.center, style: TextStyle(color: theme.textColor, fontSize: 14)),
            if (phone.isNotEmpty) Text('Phone: $phone', textAlign: TextAlign.center, style: TextStyle(color: theme.textColor, fontSize: 14)),
            if (gst.isNotEmpty) Text('Tax ID: $gst', textAlign: TextAlign.center, style: TextStyle(color: theme.textColor, fontSize: 14)),
            Divider(height: 30, thickness: 1.5, color: theme.dividerColor),
            _buildSummaryRow(theme, 'Bill No.', billNumber ?? '#SAMPLE123'),
            if (sessionKey != null) _buildSummaryRow(theme, 'Session ID', sessionKey!),
            _buildSummaryRow(theme, 'Date/Time', DateFormat.yMd().add_jm().format(DateTime.now())),
            Divider(height: 30, color: theme.dividerColor),
            Row(
              children: [
                Expanded(flex: 5, child: Text('ITEM', style: TextStyle(color: theme.textColor, fontWeight: FontWeight.bold))),
                Expanded(flex: 1, child: Text('QTY', textAlign: TextAlign.center, style: TextStyle(color: theme.textColor, fontWeight: FontWeight.bold))),
                Expanded(flex: 2, child: Text('PRICE', textAlign: TextAlign.right, style: TextStyle(color: theme.textColor, fontWeight: FontWeight.bold))),
              ],
            ),
            Divider(color: theme.dividerColor.withOpacity(0.5)),
            ...itemsToDisplay.map((item) {
              final String name = item['name'] as String;
              final int qty = item['qty'] as int;
              final double price = item['price'] as double;
              final String options = item['options'] as String? ?? '';

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(flex: 5, child: Text(name, style: TextStyle(color: theme.textColor))),
                        Expanded(flex: 1, child: Text(qty.toString(), textAlign: TextAlign.center, style: TextStyle(color: theme.textColor))),
                        Expanded(flex: 2, child: Text(formatter.format(price * qty), textAlign: TextAlign.right, style: TextStyle(color: theme.textColor))),
                      ],
                    ),
                    if (options.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 12.0, top: 2.0),
                        child: Text(options, style: TextStyle(color: theme.textColor.withOpacity(0.8), fontSize: 12)),
                      )
                  ],
                ),
              );
            }),
            Divider(height: 20, color: theme.dividerColor),
            _buildSummaryRow(theme, 'Subtotal', formatter.format(subtotal)),
            if (staffDiscount > 0) _buildSummaryRow(theme, 'Staff Discount', '- ${formatter.format(staffDiscount)}'),
            if (couponDiscount > 0) _buildSummaryRow(theme, 'Coupon Discount', '- ${formatter.format(couponDiscount)}'), // <--- NEW ROW
            Divider(color: theme.dividerColor.withOpacity(0.5)),
            ...calculatedCharges.entries.map((entry) => _buildSummaryRow(theme, entry.key, formatter.format(entry.value))),
            Divider(thickness: 1.5, height: 20, color: theme.dividerColor),
            _buildSummaryRow(theme, 'GRAND TOTAL', formatter.format(total), isTotal: true),
            if (paymentMethod != null) ...[
              const Divider(thickness: 1.5, height: 20),
              _buildSummaryRow(theme, 'Paid By', paymentMethod!),
            ],
            Divider(thickness: 1.5, height: 20, color: theme.dividerColor),
            if (notes.isNotEmpty) ...[
              Text('Notes:', style: TextStyle(color: theme.textColor, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(notes, style: TextStyle(color: theme.textColor, fontSize: 14)),
              const SizedBox(height: 20),
            ],
            Text(footer, textAlign: TextAlign.center, style: TextStyle(color: theme.textColor, fontStyle: FontStyle.italic)),
            const SizedBox(height: 20),
            Text('Managed with DineFlow', textAlign: TextAlign.center, style: TextStyle(color: theme.dividerColor, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(BillTheme theme, String label, String value, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: theme.textColor, fontWeight: isTotal ? FontWeight.bold : FontWeight.normal, fontSize: isTotal ? 16 : 14)),
          Text(value, style: TextStyle(color: isTotal ? theme.accentColor : theme.textColor, fontWeight: isTotal ? FontWeight.bold : FontWeight.normal, fontSize: isTotal ? 16 : 14)),
        ],
      ),
    );
  }
}
