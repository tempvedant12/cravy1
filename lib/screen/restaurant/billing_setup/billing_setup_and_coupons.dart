

import 'package:flutter/material.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';

import 'manage_bill_designs_screen.dart';
import 'manage_coupon_screen.dart';


class BillingSetupAndCouponsScreen extends StatelessWidget {
  final String restaurantId;

  const BillingSetupAndCouponsScreen({super.key, required this.restaurantId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    
    final List<Map<String, dynamic>> setupItems = [
      {
        'icon': Icons.style_outlined,
        'title': 'Bill Designs',
        'subtitle': 'Customize templates for printed and digital bills.',
        'screen': ManageBillDesignsScreen(restaurantId: restaurantId),
      },
      {
        'icon': Icons.local_offer_outlined,
        'title': 'Manage Coupons',
        'subtitle': 'Create and manage discount codes for customers.',
        'screen': ManageCouponScreen(restaurantId: restaurantId),
      },
    ];

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Billing Setup'),
        backgroundColor: theme.scaffoldBackgroundColor.withOpacity(0.85),
        elevation: 0,
      ),
      body: Stack(
        children: [
          const _StaticBackground(),
          SafeArea(
            child: AnimationLimiter(
              child: ListView.builder(
                padding: const EdgeInsets.all(24.0),
                itemCount: setupItems.length,
                itemBuilder: (BuildContext context, int index) {
                  final item = setupItems[index];
                  return AnimationConfiguration.staggeredList(
                    position: index,
                    duration: const Duration(milliseconds: 375),
                    child: SlideAnimation(
                      verticalOffset: 50.0,
                      child: FadeInAnimation(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 20.0),
                          child: _SetupCard(
                            icon: item['icon'],
                            title: item['title'],
                            subtitle: item['subtitle'],
                            onTap: () {
                              Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => item['screen'],
                              ));
                            },
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}


class _SetupCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SetupCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  State<_SetupCard> createState() => _SetupCardState();
}

class _SetupCardState extends State<_SetupCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(20.0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: _isHovered
                  ? theme.primaryColor.withOpacity(0.5)
                  : Colors.white.withOpacity(0.2),
              width: 1.5,
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
          child: Row(
            children: [
              Icon(widget.icon, size: 32, color: theme.primaryColor),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.subtitle,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded, size: 18),
            ],
          ),
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