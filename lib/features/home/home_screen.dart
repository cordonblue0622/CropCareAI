import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../auth/providers/auth_provider.dart';
import '../crops/providers/crops_provider.dart';
import '../notifications/providers/notifications_provider.dart';
import '../chat/providers/chat_provider.dart';
import 'dashboard/dashboard_screen.dart';
import '../crops/screens/crops_screen.dart';
import '../voice/voice_screen.dart';
import '../scan/scan_screen.dart';
import '../account/account_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  /// Allows pushed routes (ChatScreen, ScanResultScreen) to request a tab
  /// change on the mounted home screen without reusing a GlobalKey instance.
  static final ValueNotifier<int?> tabSelection = ValueNotifier<int?>(null);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  void switchTab(int index) {
    if (index == 2) {
      setTab(2);
      return;
    }
    setState(() => _currentIndex = index);
  }

  @override
  void initState() {
    super.initState();
    HomeScreen.tabSelection.addListener(_handleExternalTabSelection);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  @override
  void dispose() {
    HomeScreen.tabSelection.removeListener(_handleExternalTabSelection);
    super.dispose();
  }

  void _handleExternalTabSelection() {
    final index = HomeScreen.tabSelection.value;
    if (index == null || !mounted) {
      return;
    }
    HomeScreen.tabSelection.value = null;
    if (index == 2) {
      setTab(2);
      return;
    }
    setState(() => _currentIndex = index);
  }

  Future<void> _loadData() async {
    final userId = context.read<AuthProvider>().currentUser?.id;
    if (userId == null) return;

    await Future.wait([
      context.read<CropsProvider>().fetchCrops(userId),
      context.read<NotificationsProvider>().fetchAll(userId),
      context.read<ChatProvider>().fetchSessions(userId),
      context.read<ChatProvider>().loadKnowledgeBase(),
    ]);
  }

  Future<void> setTab(int index) async {
    if (index == 2) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ScanScreen()),
      );
      return;
    }

    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final unread = context.watch<NotificationsProvider>().unreadCount;

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          DashboardScreen(onOpenMyCrops: () => setTab(1)),
          const MyCropsScreen(),
          const ScanScreen(),
          const VoiceScreen(),
          const AccountScreen(),
        ],
      ),
      bottomNavigationBar: _BottomNav(
        currentIndex: _currentIndex,
        unreadCount: unread,
        onTap: (index) {
          setTab(index);
        },
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  final int currentIndex;
  final int unreadCount;
  final ValueChanged<int> onTap;

  const _BottomNav({
    required this.currentIndex,
    required this.unreadCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.primaryDark,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: SizedBox(
          height: 62,
          child: Row(
            children: [
              _NavItem(
                  icon: Icons.grid_view_rounded,
                  label: 'DASHBOARD',
                  index: 0,
                  current: currentIndex,
                  onTap: onTap),
              _NavItem(
                  icon: Icons.energy_savings_leaf_rounded,
                  label: 'MY CROPS',
                  index: 1,
                  current: currentIndex,
                  onTap: onTap),
              _FeaturedNavItem(
                icon: Icons.qr_code_scanner_rounded,
                label: 'SCAN',
                index: 2,
                current: currentIndex,
                onTap: onTap,
              ),
              _NavItem(
                  icon: Icons.mic,
                  label: 'VOICE',
                  index: 3,
                  current: currentIndex,
                  onTap: onTap),
              _NavItem(
                  icon: Icons.person_rounded,
                  label: 'ACCOUNT',
                  index: 4,
                  current: currentIndex,
                  onTap: onTap),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final int index;
  final int current;
  final ValueChanged<int> onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.index,
    required this.current,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final selected = index == current;
    return Expanded(
      child: GestureDetector(
        onTap: () => onTap(index),
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 3),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Icon(
                icon,
                size: 21,
                color: selected ? AppColors.primaryLight : Colors.white54,
              ),
              const SizedBox(height: 3),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: selected ? AppColors.primaryLight : Colors.white54,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeaturedNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final int index;
  final int current;
  final ValueChanged<int> onTap;

  const _FeaturedNavItem({
    required this.icon,
    required this.label,
    required this.index,
    required this.current,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final selected = index == current;

    return Expanded(
      child: GestureDetector(
        onTap: () => onTap(index),
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: SizedBox(
            height: 70,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.bottomCenter,
              children: [
                Positioned(
                  top: -12,
                  child: Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.primaryLight
                          : AppColors.primaryMedium,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withOpacity(0.96),
                        width: 4,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.18),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(
                      icon,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: selected ? AppColors.primaryLight : Colors.white54,
                      letterSpacing: 0.5,
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

/// A bottom navigation bar for screens that are pushed on top of [HomeScreen]
/// (e.g. ChatScreen, ScanResultScreen). Tapping a tab pops all pushed routes
/// back to [HomeScreen] and switches to the requested tab.
class AppPushedScreenBottomNav extends StatelessWidget {
  /// Pass -1 (or omit) when the current screen has no matching tab.
  final int currentIndex;

  const AppPushedScreenBottomNav({super.key, this.currentIndex = -1});

  void _onTap(BuildContext context, int index) {
    Navigator.of(context).popUntil((route) => route.isFirst);
    HomeScreen.tabSelection.value = index;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.primaryDark,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: SizedBox(
          height: 62,
          child: Row(
            children: [
              _NavItem(
                icon: Icons.grid_view_rounded,
                label: 'DASHBOARD',
                index: 0,
                current: currentIndex,
                onTap: (i) => _onTap(context, i),
              ),
              _NavItem(
                icon: Icons.energy_savings_leaf_rounded,
                label: 'MY CROPS',
                index: 1,
                current: currentIndex,
                onTap: (i) => _onTap(context, i),
              ),
              _FeaturedNavItem(
                icon: Icons.qr_code_scanner_rounded,
                label: 'SCAN',
                index: 2,
                current: currentIndex,
                onTap: (i) => _onTap(context, i),
              ),
              _NavItem(
                icon: Icons.mic,
                label: 'VOICE',
                index: 3,
                current: currentIndex,
                onTap: (i) => _onTap(context, i),
              ),
              _NavItem(
                icon: Icons.person_rounded,
                label: 'ACCOUNT',
                index: 4,
                current: currentIndex,
                onTap: (i) => _onTap(context, i),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
