

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import '../billing_setup/bill_design_screen.dart';

class ManageBillDesignsScreen extends StatefulWidget {
  final String restaurantId;
  const ManageBillDesignsScreen({super.key, required this.restaurantId});

  @override
  State<ManageBillDesignsScreen> createState() =>
      _ManageBillDesignsScreenState();
}

class _ManageBillDesignsScreenState extends State<ManageBillDesignsScreen> {
  String? _restaurantName;
  String? _restaurantAddress;

  @override
  void initState() {
    super.initState();
    _fetchRestaurantDetails();
  }

  Future<void> _fetchRestaurantDetails() async {
    final doc = await FirebaseFirestore.instance
        .collection('restaurants')
        .doc(widget.restaurantId)
        .get();
    if (doc.exists && mounted) {
      setState(() {
        _restaurantName = doc.data()?['name'] ?? 'Your Restaurant';
        _restaurantAddress = doc.data()?['address'] ?? '123, Main Street';
      });
    }
  }

  void _navigateToDesignScreen(BillConfiguration? config) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => BillDesignScreen(
        restaurantId: widget.restaurantId,
        existingConfig: config,
      ),
    ));
  }

  Future<void> _setDefault(String configId) async {
    await FirebaseFirestore.instance
        .collection('restaurants')
        .doc(widget.restaurantId)
        .update({'defaultBillConfigId': configId});
  }

  Future<void> _deleteDesign(String configId) async {
    final bool? confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Design?'),
        content: const Text(
            'Are you sure you want to delete this bill design? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseFirestore.instance
          .collection('restaurants')
          .doc(widget.restaurantId)
          .collection('billConfigurations')
          .doc(configId)
          .delete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Manage Bill Designs'),
        backgroundColor: theme.scaffoldBackgroundColor.withOpacity(0.85),
        elevation: 0,
      ),
      body: Stack(
        children: [
          const _StaticBackground(),
          SafeArea(
            child: StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('restaurants')
                  .doc(widget.restaurantId)
                  .snapshots(),
              builder: (context, restaurantSnapshot) {
                if (!restaurantSnapshot.hasData || _restaurantName == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                final restaurantData =
                restaurantSnapshot.data!.data() as Map<String, dynamic>?;
                final defaultId =
                restaurantData?['defaultBillConfigId'] as String?;

                return StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('restaurants')
                      .doc(widget.restaurantId)
                      .collection('billConfigurations')
                      .orderBy('template')
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return _buildEmptyState();
                    }
                    final configs = snapshot.data!.docs
                        .map((doc) => BillConfiguration.fromFirestore(doc))
                        .toList();

                    return LayoutBuilder(builder: (context, constraints) {
                      final crossAxisCount =
                      (constraints.maxWidth / 400).floor().clamp(1, 4);

                      return AnimationLimiter(
                        child: GridView.builder(
                          padding: const EdgeInsets.all(24.0),
                          itemCount: configs.length,
                          gridDelegate:
                          SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: crossAxisCount,
                            crossAxisSpacing: 20,
                            mainAxisSpacing: 20,
                            childAspectRatio: 0.7,
                          ),
                          itemBuilder: (context, index) {
                            final config = configs[index];
                            return AnimationConfiguration.staggeredGrid(
                              position: index,
                              duration: const Duration(milliseconds: 375),
                              columnCount: crossAxisCount,
                              child: ScaleAnimation(
                                child: FadeInAnimation(
                                  child: BillPreviewCard(
                                    config: config,
                                    restaurantName: _restaurantName!,
                                    restaurantAddress: _restaurantAddress!,
                                    isDefault: config.id == defaultId,
                                    onSetDefault: () =>
                                        _setDefault(config.id),
                                    onEdit: () =>
                                        _navigateToDesignScreen(config),
                                    onDelete: () =>
                                        _deleteDesign(config.id),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    });
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _navigateToDesignScreen(null),
        child: const Icon(Icons.add),
        tooltip: 'Create New Bill Design',
      ),
    );
  }

  Widget _buildEmptyState() {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.style_outlined, size: 80, color: theme.dividerColor),
          const SizedBox(height: 24),
          Text('No Bill Designs', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 12),
          Text(
            'Tap the + button to create your first design.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }
}

class BillPreviewCard extends StatelessWidget {
  final BillConfiguration config;
  final String restaurantName;
  final String restaurantAddress;
  final bool isDefault;
  final VoidCallback onSetDefault;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const BillPreviewCard({
    super.key,
    required this.config,
    required this.restaurantName,
    required this.restaurantAddress,
    required this.isDefault,
    required this.onSetDefault,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final billTheme = BillTheme.getThemeByName(config.template);

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isDefault
                ? theme.primaryColor
                : theme.dividerColor.withOpacity(0.2),
            width: isDefault ? 3 : 1.5,
          ),
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
          children: [
            
            
            
            Expanded(
              child: ClipRect(
                child: AbsorbPointer(
                  child: FittedBox(
                    fit: BoxFit.contain,
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      width: 400,
                      child: BillTemplate(
                        theme: billTheme,
                        restaurantName: restaurantName,
                        restaurantAddress: restaurantAddress,
                        phone: config.contactPhone,
                        gst: config.gstNumber,
                        footer: config.footerNote,
                        notes: config.billNotes,
                        sampleItems: const [
                          {'name': 'Sample Item 1', 'qty': 1, 'price': 100.0},
                          {'name': 'Sample Item 2', 'qty': 2, 'price': 50.0},
                          {'name': 'Another Item with a long name', 'qty': 1, 'price': 120.0},
                          {'name': 'More Items', 'qty': 3, 'price': 25.0},
                        ],
                        subtotal: 495.0,
                        staffDiscount: 49.5,
                        couponDiscount: 0.0,
                        calculatedCharges: {'GST (5%)': 22.28},
                        total: 467.78,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              color: theme.colorScheme.surface.withOpacity(0.5),
              child: Row(
                children: [
                  Radio<bool>(
                    value: true,
                    groupValue: isDefault,
                    onChanged: (value) => onSetDefault(),
                    activeColor: theme.primaryColor,
                  ),
                  Expanded(
                    child: Text(
                      config.template,
                      style: theme.textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 22),
                    onPressed: onEdit,
                    tooltip: 'Edit Design',
                  ),
                  IconButton(
                    icon: Icon(Icons.delete_outline,
                        size: 22, color: theme.colorScheme.error),
                    onPressed: onDelete,
                    tooltip: 'Delete Design',
                  ),
                ],
              ),
            )
          ],
        ),
      ),
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