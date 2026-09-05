import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../crops/screens/crops_screen.dart';
import '../scan/diagnostic_history_screen.dart';
import '../library/library_screen.dart';

enum _FarmMenuDestination { crops, history, library }

Future<void> showFarmManagementMenu(BuildContext context) async {
  final destination = await showModalBottomSheet<_FarmMenuDestination>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.primaryDark.withValues(alpha: 0.34),
    isScrollControlled: true,
    builder: (_) => const _FarmManagementMenu(),
  );

  if (!context.mounted || destination == null) return;
  await _openDestination(context, destination);
}

Future<void> _openDestination(
  BuildContext context,
  _FarmMenuDestination destination,
) {
  final Widget screen = switch (destination) {
    _FarmMenuDestination.crops => const MyCropsScreen(),
    _FarmMenuDestination.history => const DiagnosticHistoryScreen(),
    _FarmMenuDestination.library => const LibraryScreen(),
  };
  return Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => screen),
  );
}

class NavDrawer extends StatelessWidget {
  const NavDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.transparent,
      child: _FarmManagementMenu(
        fillAvailableHeight: true,
        onSelected: (destination) {
          Navigator.of(context).pop();
          _openDestination(context, destination);
        },
      ),
    );
  }
}

class _FarmManagementMenu extends StatelessWidget {
  final ValueChanged<_FarmMenuDestination>? onSelected;
  final bool fillAvailableHeight;

  const _FarmManagementMenu({
    this.onSelected,
    this.fillAvailableHeight = false,
  });

  void _select(BuildContext context, _FarmMenuDestination destination) {
    if (onSelected != null) {
      onSelected!(destination);
      return;
    }
    Navigator.of(context).pop(destination);
  }

  @override
  Widget build(BuildContext context) {
    final menu = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.96),
            AppColors.surfaceMint.withValues(alpha: 0.92),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: fillAvailableHeight
            ? null
            : const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
      ),
      child: SafeArea(
        top: fillAvailableHeight,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
          child: Column(
            mainAxisSize:
                fillAvailableHeight ? MainAxisSize.max : MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!fillAvailableHeight)
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 18),
                    decoration: BoxDecoration(
                      color: AppColors.textGray.withValues(alpha: 0.28),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.agriculture_rounded,
                  color: AppColors.primaryDark,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Farm Management',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Choose where you want to work.',
                style: TextStyle(fontSize: 12, color: AppColors.textGray),
              ),
              const SizedBox(height: 18),
              _MenuItem(
                icon: Icons.energy_savings_leaf_rounded,
                label: 'My Crops',
                description: 'View and manage active crop records',
                onTap: () => _select(context, _FarmMenuDestination.crops),
              ),
              const SizedBox(height: 8),
              _MenuItem(
                icon: Icons.history_rounded,
                label: 'Diagnostic History',
                description: 'Review previous crop assessments',
                onTap: () => _select(context, _FarmMenuDestination.history),
              ),
              const SizedBox(height: 8),
              _MenuItem(
                icon: Icons.menu_book_rounded,
                label: 'Disease Library',
                description: 'Browse crop disease guidance',
                onTap: () => _select(context, _FarmMenuDestination.library),
              ),
            ],
          ),
        ),
      ),
    );

    return fillAvailableHeight ? SizedBox.expand(child: menu) : menu;
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.label,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.68),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.backgroundGreenLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textGray,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textGray,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
