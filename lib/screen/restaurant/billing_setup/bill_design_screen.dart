import 'package:cravy/screen/restaurant/orders/bill_template_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

class BillConfiguration {
  final String id;
  final String gstNumber;
  final String contactPhone;
  final String footerNote;
  final String billNotes;
  final List<CustomChargeModel> customCharges;
  final String template;
  final double paperWidth; // New
  final double fontSize; // New

  BillConfiguration({
    required this.id,
    required this.gstNumber,
    required this.contactPhone,
    required this.footerNote,
    required this.billNotes,
    required this.customCharges,
    required this.template,
    this.paperWidth = 58.0, // New
    this.fontSize = 8.0, // New
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
      customCharges:
      chargesData.map((map) => CustomChargeModel.fromMap(map)).toList(),
      template: data['template'] ?? 'Standard',
      paperWidth: (data['paperWidth'] as num?)?.toDouble() ?? 58.0, // New
      fontSize: (data['fontSize'] as num?)?.toDouble() ?? 8.0, // New
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'gstNumber': gstNumber,
      'contactPhone': contactPhone,
      'footerNote': footerNote,
      'billNotes': billNotes,
      'customCharges': customCharges.map((c) => c.toMap()).toList(),
      'template': template,
      'paperWidth': paperWidth, // New
      'fontSize': fontSize, // New
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
  final TextEditingController _paperWidthController = TextEditingController();
  final TextEditingController _fontSizeController = TextEditingController();

  String _template = 'Standard';
  double _paperWidth = 58.0;
  double _fontSize = 8.0;


  bool _isLoading = true;
  List<CustomChargeModel> _customCharges = [];

  String _restaurantName = 'Your Restaurant Name';
  String _restaurantAddress = '123, Your Address, City';

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    // Add listeners to trigger rebuilds on text change
    _gstController.addListener(_rebuildPreview);
    _phoneController.addListener(_rebuildPreview);
    _footerNotesController.addListener(_rebuildPreview);
    _billNotesController.addListener(_rebuildPreview);
    _paperWidthController.addListener(() {
      setState(() {
        _paperWidth = double.tryParse(_paperWidthController.text) ?? 58.0;
      });
    });
    _fontSizeController.addListener(() {
      setState(() {
        _fontSize = double.tryParse(_fontSizeController.text) ?? 8.0;
      });
    });
  }

  @override
  void dispose() {
    // Remove listeners to prevent memory leaks
    _gstController.removeListener(_rebuildPreview);
    _phoneController.removeListener(_rebuildPreview);
    _footerNotesController.removeListener(_rebuildPreview);
    _billNotesController.removeListener(_rebuildPreview);
    _paperWidthController.dispose();
    _fontSizeController.dispose();

    _gstController.dispose();
    _phoneController.dispose();
    _footerNotesController.dispose();
    _billNotesController.dispose();
    super.dispose();
  }

  void _rebuildPreview() {
    setState(() {});
  }


  Future<void> _loadInitialData() async {
    if (widget.existingConfig != null) {
      final config = widget.existingConfig!;
      _gstController.text = config.gstNumber;
      _phoneController.text = config.contactPhone;
      _footerNotesController.text = config.footerNote;
      _billNotesController.text = config.billNotes;
      _customCharges = config.customCharges;
      _template = config.template;
      _paperWidth = config.paperWidth;
      _fontSize = config.fontSize;
    } else {
      _footerNotesController.text = 'Thank you! Please visit again.';
    }

    _paperWidthController.text = _paperWidth.toStringAsFixed(0);
    _fontSizeController.text = _fontSize.toStringAsFixed(1);


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
    // No need to validate the form here as the save button is global.
    // The formKey is only for the first tab now.
    setState(() => _isLoading = true);

    final config = BillConfiguration(
      id: widget.existingConfig?.id ?? '',
      gstNumber: _gstController.text.trim(),
      contactPhone: _phoneController.text.trim(),
      footerNote: _footerNotesController.text.trim(),
      billNotes: _billNotesController.text.trim(),
      customCharges: _customCharges,
      template: _template,
      paperWidth: _paperWidth,
      fontSize: _fontSize,
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
            : TabBarView(
          children: [
            // Design Tab
            Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(24.0),
                children: [
                  _buildConfigurationSection(),
                  const SizedBox(height: 40),
                  _buildCustomChargesSection(),
                ],
              ),
            ),
            // Preview Tab
            _buildBillPreview(),
          ],
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
              validator: (value) =>
              value!.trim().isEmpty ? 'This field is required' : null,
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
  Widget _buildAppearanceSection() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Appearance & Layout',
                style: Theme.of(context).textTheme.titleLarge),
            Text('Test print features and align billing with your printer size requirements.',
                style: Theme.of(context).textTheme.titleSmall),
            const Divider(height: 24),


            // Template Dropdown
            DropdownButtonFormField<String>(
              value: _template,
              decoration: const InputDecoration(
                labelText: 'Template',
                icon: Icon(Icons.style_outlined),
              ),
              items: [
                'Standard',
                'Compact',
                'Bold Header',
                'Minimalist',
                'Centered Total',
                'Detailed Items'
              ]
                  .map((label) =>
                  DropdownMenuItem(value: label, child: Text(label)))
                  .toList(),
              onChanged: (value) {
                setState(() {
                  _template = value!;
                });
              },
            ),
            const SizedBox(height: 20),
            // Paper Width and Font Size Inputs
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _paperWidthController,
                    decoration: const InputDecoration(
                      labelText: 'Paper Width',
                      suffixText: 'mm',
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _fontSizeController,
                    decoration: const InputDecoration(
                      labelText: 'Font Size',
                      suffixText: 'pt',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildBillPreview() {
    final sampleItems = [
      {
        'name': 'Classic Burger (Extra Cheese)',
        'qty': 1,
        'price': 290.0,
        'options': ''
      },
      {'name': 'Fries & Coke Combo', 'qty': 2, 'price': 150.0, 'options': ''},
    ];
    final double subtotal = sampleItems.fold(
        0.0, (sum, item) => sum + (item['price'] as num) * (item['qty'] as num));
    final double staffDiscount = subtotal * 0.10;
    final double couponDiscount = subtotal * 0.05;
    double total = subtotal - staffDiscount - couponDiscount;

    final Map<String, double> calculatedCharges = {};
    for (var charge in _customCharges) {
      if (charge.isMandatory) {
        final chargeAmount = total * (charge.rate / 100.0);
        calculatedCharges[
        '${charge.label} (${charge.rate.toStringAsFixed(1)}%)'] =
            chargeAmount;
        total += chargeAmount;
      }
    }

    final billData = {
      'restaurantName': _restaurantName,
      'restaurantAddress': _restaurantAddress,
      'phone': _phoneController.text,
      'gst': _gstController.text,
      'footer': _footerNotesController.text,
      'notes': _billNotesController.text,
      'billItems': sampleItems,
      'subtotal': subtotal,
      'staffDiscount': staffDiscount,
      'couponDiscount': couponDiscount,
      'calculatedCharges': calculatedCharges,
      'total': total,
      'billNumber': 'PREVIEW',
      'sessionKey': 'Sample',
      'paymentMethod': 'Cash',
      'template': _template,
      'paperWidth': _paperWidth,
      'fontSize': _fontSize,
    };

    return Scaffold(
      backgroundColor: Colors.grey[300],
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final pdfData = await generatePdfOnIsolate(billData);
          await Printing.layoutPdf(onLayout: (format) async => pdfData);
        },
        label: const Text('Test Print'),
        icon: const Icon(Icons.print),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 24.0),
        children: [
          _buildAppearanceSection(),
          const SizedBox(height: 24),
          Center(
            child: SizedBox(
              width: _paperWidth * 4,
              height: 600,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: PdfPreview(
                  key: ValueKey(billData.toString()),
                  build: (format) => generatePdfOnIsolate(billData),
                  useActions: false,
                  allowSharing: false,
                  allowPrinting: false,
                  canChangeOrientation: false,
                  canChangePageFormat: false,
                  canDebug: false,
                  pdfPreviewPageDecoration: const BoxDecoration(),
                ),
              ),
            ),
          ),
        ],
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
                      icon: const Icon(Icons.delete_outline,
                          size: 20, color: Colors.red),
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
        _rebuildPreview();
      });
    }
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
    _labelController =
        TextEditingController(text: widget.initialCharge?.label ?? '');
    _rateController = TextEditingController(
        text: widget.initialCharge?.rate.toString() ?? '0.0');
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
      title:
      Text(widget.initialCharge == null ? 'Add New Charge' : 'Edit Charge'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _labelController,
                decoration:
                const InputDecoration(labelText: 'Charge/Tax Label'),
                validator: (val) =>
                val!.trim().isEmpty ? 'Enter a label' : null,
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
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        ElevatedButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}