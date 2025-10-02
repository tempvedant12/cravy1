

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';


class CouponModel {
  final String id;
  final String code;
  final String type; 
  final double value;
  final double minOrderAmount;

  CouponModel({
    required this.id,
    required this.code,
    required this.type,
    required this.value,
    required this.minOrderAmount,
  });

  factory CouponModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return CouponModel(
      id: doc.id,
      code: data['code'] ?? 'INVALID',
      type: data['type'] ?? 'percentage',
      value: (data['value'] ?? 0.0).toDouble(),
      minOrderAmount: (data['minOrderAmount'] ?? 0.0).toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'code': code,
      'type': type,
      'value': value,
      'minOrderAmount': minOrderAmount,
    };
  }
}



class ManageCouponScreen extends StatelessWidget {
  final String restaurantId;
  const ManageCouponScreen({super.key, required this.restaurantId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Manage Coupons'),
        backgroundColor: theme.scaffoldBackgroundColor.withOpacity(0.85),
        elevation: 0,
      ),
      body: Stack(
        children: [
          const _StaticBackground(),
          SafeArea(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('restaurants')
                  .doc(restaurantId)
                  .collection('coupons')
                  .orderBy('code')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return _buildEmptyState(context);
                }

                final coupons = snapshot.data!.docs
                    .map((doc) => CouponModel.fromFirestore(doc))
                    .toList();

                return AnimationLimiter(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 80),
                    itemCount: coupons.length,
                    itemBuilder: (context, index) {
                      final coupon = coupons[index];
                      return AnimationConfiguration.staggeredList(
                        position: index,
                        duration: const Duration(milliseconds: 375),
                        child: SlideAnimation(
                          verticalOffset: 50.0,
                          child: FadeInAnimation(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 16.0),
                              child: _CouponCard(
                                coupon: coupon,
                                onEdit: () => _showAddEditDialog(context, coupon),
                                onDelete: () => _deleteCoupon(context, coupon.id),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddEditDialog(context),
        child: const Icon(Icons.add),
        tooltip: 'Add New Coupon',
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.local_offer_outlined,
              size: 80, color: theme.dividerColor),
          const SizedBox(height: 24),
          Text('No Coupons Found',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineMedium),
          const SizedBox(height: 12),
          Text(
            'Tap the + button to create your first coupon code.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }

  void _showAddEditDialog(BuildContext context, [CouponModel? coupon]) {
    showDialog(
      context: context,
      builder: (ctx) => _AddEditCouponDialog(
        restaurantId: restaurantId,
        coupon: coupon,
      ),
    );
  }

  Future<void> _deleteCoupon(BuildContext context, String couponId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirm Delete'),
        content: const Text('Are you sure you want to delete this coupon? This action cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Delete',
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseFirestore.instance
          .collection('restaurants')
          .doc(restaurantId)
          .collection('coupons')
          .doc(couponId)
          .delete();
    }
  }
}


class _CouponCard extends StatelessWidget {
  final CouponModel coupon;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _CouponCard({
    required this.coupon,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPercentage = coupon.type == 'percentage';
    final discountValue = isPercentage
        ? '${coupon.value.toStringAsFixed(0)}%'
        : '₹${coupon.value.toStringAsFixed(2)}';

    return GestureDetector(
      onTap: onEdit,
      child: Container(
        padding: const EdgeInsets.all(20.0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(0.2), width: 1.5),
          gradient: LinearGradient(
            colors: [
              theme.colorScheme.surface.withOpacity(0.3),
              theme.colorScheme.surface.withOpacity(0.1),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.local_offer_outlined, color: theme.primaryColor, size: 28),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    coupon.code,
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                Text(
                  discountValue,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.primaryColor,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Min. Order: ₹${coupon.minOrderAmount.toStringAsFixed(2)}',
                  style: theme.textTheme.bodyLarge,
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: onEdit,
                      tooltip: 'Edit Coupon',
                    ),
                    IconButton(
                      icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
                      onPressed: onDelete,
                      tooltip: 'Delete Coupon',
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}


class _AddEditCouponDialog extends StatefulWidget {
  final String restaurantId;
  final CouponModel? coupon;

  const _AddEditCouponDialog({required this.restaurantId, this.coupon});

  @override
  State<_AddEditCouponDialog> createState() => __AddEditCouponDialogState();
}

class __AddEditCouponDialogState extends State<_AddEditCouponDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _codeController;
  late TextEditingController _valueController;
  late TextEditingController _minAmountController;
  late String _type;

  @override
  void initState() {
    super.initState();
    _codeController = TextEditingController(text: widget.coupon?.code ?? '');
    _valueController =
        TextEditingController(text: widget.coupon?.value.toString() ?? '');
    _minAmountController = TextEditingController(
        text: widget.coupon?.minOrderAmount.toString() ?? '0.0');
    _type = widget.coupon?.type ?? 'percentage';
  }

  @override
  void dispose() {
    _codeController.dispose();
    _valueController.dispose();
    _minAmountController.dispose();
    super.dispose();
  }

  Future<void> _saveCoupon() async {
    if (_formKey.currentState!.validate()) {
      final couponData = {
        'code': _codeController.text.trim().toUpperCase(),
        'type': _type,
        'value': double.parse(_valueController.text),
        'minOrderAmount': double.parse(_minAmountController.text),
      };

      final collection = FirebaseFirestore.instance
          .collection('restaurants')
          .doc(widget.restaurantId)
          .collection('coupons');

      if (widget.coupon == null) {
        await collection.add(couponData);
      } else {
        await collection.doc(widget.coupon!.id).update(couponData);
      }
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.coupon == null ? 'Add Coupon' : 'Edit Coupon'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _codeController,
                decoration: const InputDecoration(
                    labelText: 'Coupon Code',
                    prefixIcon: Icon(Icons.confirmation_number_outlined)),
                textCapitalization: TextCapitalization.characters,
                validator: (val) =>
                val!.trim().isEmpty ? 'Enter a code' : null,
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                value: _type,
                decoration: const InputDecoration(
                    labelText: 'Discount Type',
                    prefixIcon: Icon(Icons.arrow_drop_down_circle_outlined)),
                items: const [
                  DropdownMenuItem(
                      value: 'percentage', child: Text('Percentage (%)')),
                  DropdownMenuItem(
                      value: 'fixed', child: Text('Fixed Amount (₹)')),
                ],
                onChanged: (val) => setState(() => _type = val!),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _valueController,
                decoration: InputDecoration(
                    labelText:
                    _type == 'percentage' ? 'Value (%)' : 'Value (₹)',
                    prefixIcon: const Icon(Icons.sell_outlined)),
                keyboardType: TextInputType.number,
                validator: (val) {
                  final number = double.tryParse(val!);
                  if (number == null || number <= 0) return 'Invalid value';
                  if (_type == 'percentage' && number > 100)
                    return 'Max 100%';
                  return null;
                },
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _minAmountController,
                decoration: const InputDecoration(
                    labelText: 'Minimum Order Amount (₹)',
                    prefixIcon: Icon(Icons.shopping_cart_checkout_outlined)),
                keyboardType: TextInputType.number,
                validator: (val) =>
                double.tryParse(val!) == null ? 'Invalid amount' : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        ElevatedButton(onPressed: _saveCoupon, child: const Text('Save')),
      ],
    );
  }
}



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
                theme.colorScheme.surface.withOpacity(isDark ? 0.3 : 0.2), 450),
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