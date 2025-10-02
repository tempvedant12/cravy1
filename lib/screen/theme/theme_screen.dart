import 'package:cravy/services/theme_manager.dart';
import 'package:cravy/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ThemeScreen extends StatelessWidget {
  const ThemeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeManager>(
      builder: (context, themeManager, child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Appearance'),
            centerTitle: true,
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              // Determine the number of columns based on screen width
              final crossAxisCount = (constraints.maxWidth / 280).floor().clamp(1, 6);
              // --- CHANGE: Calculate responsive horizontal padding ---
              final horizontalPadding = (constraints.maxWidth * 0.05).clamp(24.0, 100.0);

              // --- CHANGE: Removed Center and ConstrainedBox, using Padding instead ---
              return Padding(
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 32.0),
                child: GridView.builder(
                  itemCount: AppThemes.themes.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 20,
                    mainAxisSpacing: 20,
                    childAspectRatio: 1.4,
                  ),
                  itemBuilder: (context, index) {
                    final theme = AppThemes.themes[index];
                    final themeName = theme.extension<ThemeName>()!.name;

                    return _ThemeOptionCard(
                      title: themeName,
                      isSelected: themeManager.themeIndex == index,
                      themeData: theme,
                      onTap: () => themeManager.setTheme(index),
                    );
                  },
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _ThemeOptionCard extends StatefulWidget {
  final String title;
  final bool isSelected;
  final ThemeData themeData;
  final VoidCallback onTap;

  const _ThemeOptionCard({
    required this.title,
    required this.isSelected,
    required this.themeData,
    required this.onTap,
  });

  @override
  State<_ThemeOptionCard> createState() => _ThemeOptionCardState();
}

class _ThemeOptionCardState extends State<_ThemeOptionCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final currentTheme = Theme.of(context);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: widget.themeData.colorScheme.surface.withOpacity(0.5),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: widget.isSelected
                  ? widget.themeData.primaryColor
                  : (_isHovered
                  ? currentTheme.dividerColor.withOpacity(0.8)
                  : currentTheme.dividerColor),
              width: widget.isSelected || _isHovered ? 2.0 : 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Theme preview section
              Expanded(
                child: ClipRRect(
                  borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(15)),
                  child: Container(
                    color: widget.themeData.scaffoldBackgroundColor,
                    child: Stack(
                      children: [
                        Positioned(
                          top: 10,
                          left: 10,
                          child: _buildColorCircle(
                              widget.themeData.primaryColor,
                              size: 20),
                        ),
                        Positioned(
                          top: 15,
                          right: 30,
                          child: _buildColorCircle(
                              widget.themeData.colorScheme.surface,
                              size: 15),
                        ),
                        Positioned(
                          bottom: 10,
                          right: 10,
                          child: _buildColorCircle(
                              widget.themeData.textTheme.bodyLarge!.color!,
                              size: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Theme name and selection indicator
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: widget.themeData.colorScheme.surface,
                  borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(15)),
                ),
                child: Row(
                  children: [
                    Text(
                      widget.title,
                      style: currentTheme.textTheme.bodyLarge
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    if (widget.isSelected)
                      Icon(Icons.check_circle_rounded,
                          color: widget.themeData.primaryColor),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildColorCircle(Color color, {double size = 12}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withOpacity(0.5),
          width: 1.5,
        ),
      ),
    );
  }
}