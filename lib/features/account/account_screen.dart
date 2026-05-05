import 'package:flutter/material.dart';
import 'package:country_picker/country_picker.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/user_model.dart';
import '../auth/providers/auth_provider.dart';
import 'nav_drawer.dart';
import '../../../features/scan/diagnostic_history_screen.dart';
import '../../../features/library/library_screen.dart';
import '../../../shared/widgets/custom_text_field.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

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

    return Scaffold(
      backgroundColor: AppColors.backgroundCream,
      drawer: const NavDrawer(),
      appBar: AppBar(
        backgroundColor: AppColors.backgroundCream,
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu, color: AppColors.textDark),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: const Text('My Account',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined, color: AppColors.primary),
            onPressed: () => _showEditProfile(context, user),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Profile header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primaryDark, AppColors.primary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(children: [
              // Avatar
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.2),
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Center(
                  child: Text(initials,
                      style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                user?.displayName ?? user?.fullName ?? 'Farmer',
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.white),
              ),
              const SizedBox(height: 4),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text('LEAD AGRONOMIST',
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1)),
              ),
              const SizedBox(height: 8),
              Text(user?.email ?? '',
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ]),
          ),
          const SizedBox(height: 20),

          // Farm details card
          _SectionCard(
            title: 'Farm Details',
            children: [
              _RowItem(
                icon: Icons.badge_outlined,
                label: 'Farm ID',
                value: user != null
                    ? 'FARM-${user.id.substring(0, 8).toUpperCase()}'
                    : '-',
              ),
              _RowItem(
                icon: Icons.location_on_outlined,
                label: 'Location',
                value: user?.formattedLocation ?? 'Not set',
              ),
              _RowItem(
                icon: Icons.language,
                label: 'Country',
                value: user?.country ?? 'Not set',
              ),
              if (user?.phone != null)
                _RowItem(
                  icon: Icons.phone_outlined,
                  label: 'Phone',
                  value: user!.phone!,
                ),
            ],
          ),
          const SizedBox(height: 16),

          // Management section
          _SectionCard(
            title: 'Crop Management',
            children: [
              _NavItem(
                icon: Icons.history,
                label: 'Diagnostic History',
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const DiagnosticHistoryScreen())),
              ),
              _NavItem(
                icon: Icons.menu_book,
                label: 'Disease Library',
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const LibraryScreen())),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Support section
          _SectionCard(
            title: 'Support',
            children: [
              _NavItem(
                icon: Icons.help_outline,
                label: 'Help & FAQ',
                onTap: () {},
              ),
              _NavItem(
                icon: Icons.info_outline,
                label: 'About CropCare AI',
                onTap: () => _showAbout(context),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Sign out
          OutlinedButton.icon(
            onPressed: () => _confirmSignOut(context),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.red),
              foregroundColor: Colors.red,
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            icon: const Icon(Icons.logout),
            label: const Text('Sign Out',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _confirmSignOut(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await context.read<AuthProvider>().signOut();
            },
            child: const Text('Sign Out', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showAbout(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'CropCare AI',
      applicationVersion: '1.0.0',
      applicationLegalese: '© 2024 CropCare AI. All rights reserved.',
      children: const [
        Padding(
          padding: EdgeInsets.only(top: 12),
          child: Text(
            'AI-powered crop disease diagnosis for vegetable farmers.',
          ),
        ),
      ],
    );
  }

  void _showEditProfile(BuildContext context, UserModel? user) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditProfileSheet(user: user),
    );
  }
}

// ─── Helper Widgets ───────────────────────────────────────────────────────

class _EditProfileSheet extends StatefulWidget {
  final UserModel? user;

  const _EditProfileSheet({required this.user});

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _countryCtrl;
  late final TextEditingController _provinceCtrl;
  late final TextEditingController _municipalityCtrl;
  late final TextEditingController _barangayCtrl;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _countryCtrl = TextEditingController(text: widget.user?.country ?? '');
    _provinceCtrl = TextEditingController(text: widget.user?.province ?? '');
    _municipalityCtrl =
        TextEditingController(text: widget.user?.municipality ?? '');
    _barangayCtrl = TextEditingController(text: widget.user?.barangay ?? '');
  }

  @override
  void dispose() {
    _countryCtrl.dispose();
    _provinceCtrl.dispose();
    _municipalityCtrl.dispose();
    _barangayCtrl.dispose();
    super.dispose();
  }

  void _pickCountry() {
    showCountryPicker(
      context: context,
      showPhoneCode: false,
      onSelect: (Country country) {
        _countryCtrl.text = country.name;
      },
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    final messenger = ScaffoldMessenger.of(context);
    final auth = context.read<AuthProvider>();
    final ok = await auth.updateProfileLocation(
      country: _countryCtrl.text.trim(),
      province: _provinceCtrl.text.trim(),
      municipality: _municipalityCtrl.text.trim(),
      barangay: _barangayCtrl.text.trim(),
    );

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (ok) {
      Navigator.of(context).pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('Profile updated.')),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(auth.errorMessage ?? 'Could not update profile.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Material(
          color: AppColors.backgroundCream,
          borderRadius: BorderRadius.circular(24),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Edit Farm Location',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textDark,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Keep your farm location up to date so weather-based tips stay accurate.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textGray,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 20),
                    CustomTextField(
                      label: 'COUNTRY',
                      hint: 'Select country',
                      controller: _countryCtrl,
                      readOnly: true,
                      onTap: _pickCountry,
                      prefixIcon: const Icon(Icons.public_rounded,
                          color: AppColors.textLightGray, size: 20),
                      suffixIcon: const Icon(Icons.expand_more_rounded,
                          color: AppColors.textLightGray, size: 22),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Country is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    CustomTextField(
                      label: 'PROVINCE / STATE',
                      hint: 'Cebu',
                      controller: _provinceCtrl,
                      prefixIcon: const Icon(Icons.map_outlined,
                          color: AppColors.textLightGray, size: 20),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Province or state is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    CustomTextField(
                      label: 'MUNICIPALITY / CITY',
                      hint: 'Dalaguete',
                      controller: _municipalityCtrl,
                      prefixIcon: const Icon(Icons.location_city_outlined,
                          color: AppColors.textLightGray, size: 20),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Municipality or city is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    CustomTextField(
                      label: 'BARANGAY / VILLAGE',
                      hint: 'Mantalongon',
                      controller: _barangayCtrl,
                      prefixIcon: const Icon(Icons.place_outlined,
                          color: AppColors.textLightGray, size: 20),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _isSaving
                                ? null
                                : () => Navigator.of(context).pop(),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(50),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _isSaving ? null : _save,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(50),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: _isSaving
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text(
                                    'Save',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w700),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _SectionCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title,
          style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: AppColors.textGray)),
      const SizedBox(height: 8),
      Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(children: children),
      ),
    ]);
  }
}

class _RowItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _RowItem(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(children: [
        Icon(icon, size: 20, color: AppColors.primary),
        const SizedBox(width: 14),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(fontSize: 11, color: AppColors.textGray)),
          Text(value,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textDark)),
        ]),
      ]),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _NavItem(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppColors.primary, size: 22),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      trailing: const Icon(Icons.chevron_right, color: AppColors.textLightGray),
      onTap: onTap,
    );
  }
}
