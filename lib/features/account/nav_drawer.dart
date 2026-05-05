import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../auth/providers/auth_provider.dart';
import '../crops/screens/crops_screen.dart';
import '../scan/diagnostic_history_screen.dart';
import '../library/library_screen.dart';
import '../notifications/screens/notifications_screen.dart';
import '../chat/screens/chat_screen.dart';

class NavDrawer extends StatelessWidget {
  const NavDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    final displayName =
        user?.displayName ?? user?.fullName ?? user?.email ?? 'Farmer';
    final initials = displayName
        .split(' ')
        .take(2)
        .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '')
        .join();

    return Drawer(
      backgroundColor: AppColors.backgroundCream,
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.primaryDark, AppColors.primary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.2),
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: Center(
                      child: Text(initials,
                          style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    user?.displayName ?? user?.fullName ?? 'Farmer',
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white),
                  ),
                  Text(
                    user?.email ?? '',
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    user?.formattedLocation ?? 'Location not set',
                    style: const TextStyle(fontSize: 11, color: Colors.white60),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // Farm Management section
            const _DrawerSectionLabel(label: 'Farm Management'),
            _DrawerItem(
              icon: Icons.energy_savings_leaf,
              label: 'My Crops',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const MyCropsScreen()));
              },
            ),
            _DrawerItem(
              icon: Icons.history,
              label: 'Diagnostic History',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const DiagnosticHistoryScreen()));
              },
            ),
            _DrawerItem(
              icon: Icons.menu_book,
              label: 'Disease Library',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const LibraryScreen()));
              },
            ),

            const Divider(indent: 16, endIndent: 16),

            // Support section
            const _DrawerSectionLabel(label: 'Support'),
            _DrawerItem(
              icon: Icons.chat_bubble_outline,
              label: 'AI Assistant',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const ChatScreen()));
              },
            ),
            _DrawerItem(
              icon: Icons.notifications_outlined,
              label: 'Notifications',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const NotificationsScreen()));
              },
            ),
            _DrawerItem(
              icon: Icons.help_outline,
              label: 'Help & FAQ',
              onTap: () => Navigator.pop(context),
            ),

            const Divider(indent: 16, endIndent: 16),

            // Preferences
            const _DrawerSectionLabel(label: 'Preferences'),
            _OfflineModeToggle(),

            const Divider(indent: 16, endIndent: 16),

            // Sign out
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red, size: 22),
              title: const Text('Sign Out',
                  style: TextStyle(
                      color: Colors.red, fontWeight: FontWeight.w600)),
              onTap: () async {
                Navigator.pop(context);
                await context.read<AuthProvider>().signOut();
              },
            ),

            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text('CropCare AI v1.0',
                  style:
                      TextStyle(fontSize: 11, color: AppColors.textLightGray)),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerSectionLabel extends StatelessWidget {
  final String label;
  const _DrawerSectionLabel({required this.label});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(label.toUpperCase(),
            style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.textLightGray,
                letterSpacing: 1)),
      );
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _DrawerItem(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppColors.primary, size: 22),
      title: Text(label,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      trailing: const Icon(Icons.chevron_right,
          color: AppColors.textLightGray, size: 18),
      onTap: onTap,
    );
  }
}

class _OfflineModeToggle extends StatefulWidget {
  @override
  State<_OfflineModeToggle> createState() => _OfflineModeToggleState();
}

class _OfflineModeToggleState extends State<_OfflineModeToggle> {
  bool _offline = false;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary: const Icon(Icons.wifi_off, color: AppColors.primary, size: 22),
      title: const Text('Offline Mode',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: const Text('Use local data when offline',
          style: TextStyle(fontSize: 12, color: AppColors.textGray)),
      value: _offline,
      activeThumbColor: AppColors.primary,
      onChanged: (v) => setState(() => _offline = v),
    );
  }
}
