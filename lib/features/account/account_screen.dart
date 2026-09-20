import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:country_picker/country_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/user_model.dart';
import 'deleted_crops_history_screen.dart';
import '../../../data/remote/ai_backend_service.dart';
import '../auth/providers/auth_provider.dart';
import '../auth/screens/login_screen.dart';
import '../auth/widgets/legal_document_sheet.dart';
import '../chat/providers/chat_provider.dart';
import '../crops/providers/crops_provider.dart';
import '../notifications/providers/notifications_provider.dart';
import '../../../features/scan/diagnostic_history_screen.dart';
import '../../../features/library/library_screen.dart';
import '../../../shared/widgets/custom_text_field.dart';
import '../../../services/notification_service.dart';
import 'help_faq_screen.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  static const String _supportEmail = 'cropcareai.team@gmail.com';

  Future<void> _openDeviceSettings(BuildContext context) async {
    final opened = await openAppSettings();
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open Android settings for CropCare AI.'),
        ),
      );
    }
  }

  Future<void> _showNotificationSoundSettings(BuildContext context) async {
    final service = NotificationService.instance;
    var enabled = await service.soundEnabled;
    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Notification sound'),
          content: SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Play a sound for reminders'),
            subtitle:
                const Text('Applies to upcoming, due, and overdue alerts.'),
            value: enabled,
            onChanged: (value) async {
              setDialogState(() => enabled = value);
              await service.setSoundEnabled(value);
              await service.scheduleForTasks(
                context.read<NotificationsProvider>().upcomingTasks,
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _emailSupport(
    BuildContext context, {
    required String subject,
    required String body,
  }) async {
    final uri = Uri(
      scheme: 'mailto',
      path: _supportEmail,
      queryParameters: {'subject': subject, 'body': body},
    );
    var launched = false;
    try {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      launched = false;
    }
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No email app is available. Email cropcareai.team@gmail.com directly.',
          ),
        ),
      );
    }
  }

  Future<void> _pickProfilePhoto(BuildContext context) async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      imageQuality: 88,
    );
    if (picked == null || !context.mounted) return;

    final bytes = await picked.readAsBytes();
    if (!context.mounted) return;
    final extension = picked.name.contains('.')
        ? picked.name.split('.').last.toLowerCase()
        : 'jpg';
    final contentType = switch (extension) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };
    final auth = context.read<AuthProvider>();
    final updated = await auth.updateAvatar(
      bytes: bytes,
      extension: extension,
      contentType: contentType,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(updated
            ? 'Profile photo updated.'
            : auth.errorMessage ?? 'Could not upload profile photo.'),
      ),
    );
  }

  Future<void> _signOut(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    final chat = context.read<ChatProvider>();
    final crops = context.read<CropsProvider>();
    final notifications = context.read<NotificationsProvider>();
    await auth.signOut();
    chat.clear();
    crops.clear();
    notifications.clear();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  void _showLegalDocument(BuildContext context, LegalDocument document) {
    showDialog<void>(
      context: context,
      builder: (_) => LegalDocumentSheet(document: document),
    );
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final confirmation = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Permanently Delete Account?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This permanently deletes your sign-in, profile, crops, diagnoses, treatments, tasks, progress, chats, notifications, and stored chat images. This cannot be undone.',
              ),
              const SizedBox(height: 16),
              const Text('Type DELETE to confirm.'),
              const SizedBox(height: 8),
              TextField(
                controller: confirmation,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                onChanged: (_) => setDialogState(() {}),
                decoration: const InputDecoration(hintText: 'DELETE'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: confirmation.text.trim() == 'DELETE'
                  ? () => Navigator.pop(dialogContext, true)
                  : null,
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Delete Permanently'),
            ),
          ],
        ),
      ),
    );
    confirmation.dispose();
    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final auth = context.read<AuthProvider>();
    final deleted = await auth.deleteAccount(context.read<AiBackendService>());
    if (!context.mounted) return;
    if (!deleted) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(auth.errorMessage ??
              'Your account could not be deleted. Please try again.'),
        ),
      );
      return;
    }

    context.read<ChatProvider>().clear();
    context.read<CropsProvider>().clear();
    context.read<NotificationsProvider>().clear();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    final displayName =
        user?.displayName ?? user?.fullName ?? user?.email ?? 'Farmer';
    final formattedLocation = user?.formattedLocation;
    final initials = displayName
        .split(' ')
        .take(2)
        .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '')
        .join();

    return Scaffold(
      backgroundColor: AppColors.backgroundCream,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        title: const Text('My Account',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 20)),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined, color: Colors.white),
            onPressed: () => _showEditProfile(context, user),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 112),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white.withValues(alpha: 0.88),
                  AppColors.surfaceMint.withValues(alpha: 0.68),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryDark.withValues(alpha: 0.07),
                  blurRadius: 18,
                  offset: const Offset(0, 7),
                ),
              ],
            ),
            child: Row(children: [
              GestureDetector(
                onTap: () => _pickProfilePhoto(context),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CircleAvatar(
                      radius: 34,
                      backgroundColor: AppColors.primary,
                      backgroundImage: user?.avatarUrl != null
                          ? CachedNetworkImageProvider(user!.avatarUrl!)
                          : null,
                      child: user?.avatarUrl == null
                          ? Text(initials,
                              style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white))
                          : null,
                    ),
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        width: 25,
                        height: 25,
                        decoration: BoxDecoration(
                          color: AppColors.primaryDark,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(Icons.camera_alt_rounded,
                            size: 13, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user?.displayName ?? user?.fullName ?? 'Farmer',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      user?.email ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textMedium,
                        fontSize: 13,
                      ),
                    ),
                    if (formattedLocation != null &&
                        formattedLocation.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on_outlined,
                            size: 15,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              formattedLocation,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textGray,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ]),
          ),
          const SizedBox(height: 20),
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
          _SectionCard(
            title: 'Settings & Preferences',
            children: [
              _NavItem(
                icon: Icons.manage_accounts_outlined,
                label: 'Edit profile & farm details',
                subtitle: 'Name, email, phone, and farm location',
                onTap: () => _showEditProfile(context, user),
              ),
              _NavItem(
                icon: Icons.notifications_active_outlined,
                label: 'Notification & device permissions',
                subtitle: 'Manage access in Android Settings',
                onTap: () => _openDeviceSettings(context),
              ),
              _NavItem(
                icon: Icons.volume_up_outlined,
                label: 'Notification sound',
                subtitle: 'Turn reminder sounds on or off',
                onTap: () => _showNotificationSoundSettings(context),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Crop Management',
            children: [
              _NavItem(
                icon: Icons.history,
                label: 'Diagnostic History',
                subtitle: 'Review previous crop scan results',
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const DiagnosticHistoryScreen())),
              ),
              _NavItem(
                icon: Icons.delete_sweep_outlined,
                label: 'Deleted Crop History',
                subtitle: 'Review removed crops and their audit dates',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const DeletedCropsHistoryScreen(),
                  ),
                ),
              ),
              _NavItem(
                icon: Icons.menu_book,
                label: 'Disease Library',
                subtitle: 'Browse crop conditions and guidance',
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const LibraryScreen())),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Support',
            children: [
              _NavItem(
                icon: Icons.help_outline,
                label: 'Help & FAQ',
                subtitle: 'Step-by-step guides and troubleshooting',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const HelpFaqScreen(),
                  ),
                ),
              ),
              _NavItem(
                icon: Icons.mail_outline,
                label: 'Contact support',
                subtitle: 'Ask the CropCare AI team for help',
                onTap: () => _emailSupport(
                  context,
                  subject: 'CropCare AI support request',
                  body: _supportEmailBody,
                ),
              ),
              _NavItem(
                icon: Icons.bug_report_outlined,
                label: 'Report a problem',
                subtitle: 'Send steps and device details by email',
                onTap: () => _emailSupport(
                  context,
                  subject: 'CropCare AI problem report',
                  body: _problemReportBody,
                ),
              ),
              _NavItem(
                icon: Icons.info_outline,
                label: 'About CropCare AI',
                subtitle: 'App purpose and version',
                onTap: () => _showAbout(context),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Legal & Privacy',
            children: [
              _NavItem(
                icon: Icons.description_outlined,
                label: 'Terms of Service',
                subtitle: 'Rules for using CropCare AI',
                onTap: () =>
                    _showLegalDocument(context, LegalDocument.termsOfService),
              ),
              _NavItem(
                icon: Icons.privacy_tip_outlined,
                label: 'Privacy Policy & Your Rights',
                subtitle: 'Data use, controls, and privacy rights',
                onTap: () =>
                    _showLegalDocument(context, LegalDocument.privacyPolicy),
              ),
              _NavItem(
                icon: Icons.health_and_safety_outlined,
                label: 'AI & Crop Safety Notice',
                subtitle: 'Important guidance before treatment',
                onTap: () =>
                    _showLegalDocument(context, LegalDocument.aiSafetyNotice),
              ),
            ],
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () => _confirmSignOut(context),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.red),
              foregroundColor: Colors.red,
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.logout),
            label: const Text('Sign Out',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: context.watch<AuthProvider>().isLoading
                ? null
                : () => _deleteAccount(context),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red.shade800,
              minimumSize: const Size(double.infinity, 48),
            ),
            icon: const Icon(Icons.delete_forever_outlined),
            label: const Text('Delete Account and Data'),
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
              await _signOut(context);
            },
            child: const Text('Sign Out', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showAbout(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Material(
            color: AppColors.backgroundCream,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 14, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppColors.backgroundGreenLight,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.eco_outlined,
                          color: AppColors.primary,
                          size: 27,
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'CropCare AI',
                              style: TextStyle(
                                color: AppColors.textDark,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              'Version 1.0.6',
                              style: TextStyle(
                                color: AppColors.textGray,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'CropCare AI helps vegetable farmers document crop conditions, organize treatment tasks, and review AI-assisted crop-health guidance.',
                    style: TextStyle(
                      color: AppColors.textMedium,
                      fontSize: 14,
                      height: 1.55,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.borderGreen),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.health_and_safety_outlined,
                          color: AppColors.primary,
                          size: 20,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'AI results are informational estimates. Confirm uncertain diagnoses and treatment decisions with a qualified agricultural professional.',
                            style: TextStyle(
                              color: AppColors.textGray,
                              fontSize: 12,
                              height: 1.45,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static const String _supportEmailBody = '''Hello CropCare AI Support,

What I need help with:
[Describe your question]

What I have already tried:
1. [First step]
2. [Second step]

Account email:
[Enter the email used for CropCare AI]

Device and Android version:
[Enter device details]

App version:
1.0.6''';

  static const String _problemReportBody = '''Hello CropCare AI Support,

Problem summary:
[Briefly describe the problem]

Steps to reproduce:
1. [First step]
2. [Second step]
3. [What happened]

Expected result:
[What you expected]

Exact error message:
[Enter the message or "None"]

Affected crop or feature:
[Enter crop name or feature]

Connection type:
[Wi-Fi, mobile data, or offline]

Date and time observed:
[Enter date and time]

Account email:
[Enter the email used for CropCare AI]

Device and Android version:
[Enter device details]

App version:
1.0.6''';

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
  late final TextEditingController _fullNameCtrl;
  late final TextEditingController _displayNameCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _countryCtrl;
  late final TextEditingController _provinceCtrl;
  late final TextEditingController _municipalityCtrl;
  late final TextEditingController _barangayCtrl;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _fullNameCtrl = TextEditingController(text: widget.user?.fullName ?? '');
    _displayNameCtrl =
        TextEditingController(text: widget.user?.displayName ?? '');
    _emailCtrl = TextEditingController(text: widget.user?.email ?? '');
    _phoneCtrl = TextEditingController(text: widget.user?.phone ?? '');
    _countryCtrl = TextEditingController(text: widget.user?.country ?? '');
    _provinceCtrl = TextEditingController(text: widget.user?.province ?? '');
    _municipalityCtrl =
        TextEditingController(text: widget.user?.municipality ?? '');
    _barangayCtrl = TextEditingController(text: widget.user?.barangay ?? '');
  }

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _displayNameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
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
    final ok = await auth.updateProfile(
      fullName: _fullNameCtrl.text.trim(),
      displayName: _displayNameCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
      country: _countryCtrl.text.trim(),
      province: _provinceCtrl.text.trim(),
      municipality: _municipalityCtrl.text.trim(),
      barangay: _barangayCtrl.text.trim(),
    );

    if (ok && _emailCtrl.text.trim() != widget.user?.email) {
      final emailChanged =
          await auth.requestEmailChange(_emailCtrl.text.trim());
      if (!emailChanged) {
        if (!mounted) return;
        setState(() => _isSaving = false);
        messenger.showSnackBar(
          SnackBar(
              content: Text(
                  auth.errorMessage ?? 'Could not request the email change.')),
        );
        return;
      }
    }

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (ok) {
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(_emailCtrl.text.trim() != widget.user?.email
              ? 'Profile updated. Check your email to confirm the new address.'
              : 'Profile updated.'),
        ),
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
                            'Edit Profile',
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
                      'Update your account details and farm location.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textGray,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 20),
                    CustomTextField(
                      label: 'FULL NAME',
                      hint: 'Your full name',
                      controller: _fullNameCtrl,
                      prefixIcon: const Icon(Icons.badge_outlined,
                          color: AppColors.textLightGray, size: 20),
                    ),
                    const SizedBox(height: 16),
                    CustomTextField(
                      label: 'DISPLAY NAME',
                      hint: 'Name shown in the app',
                      controller: _displayNameCtrl,
                      prefixIcon: const Icon(Icons.person_outline,
                          color: AppColors.textLightGray, size: 20),
                    ),
                    const SizedBox(height: 16),
                    CustomTextField(
                      label: 'EMAIL ADDRESS',
                      hint: 'farmer@example.com',
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      prefixIcon: const Icon(Icons.alternate_email,
                          color: AppColors.textLightGray, size: 20),
                      validator: (value) {
                        final email = value?.trim() ?? '';
                        if (!RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(email)) {
                          return 'Enter a valid email address';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'A confirmation email is required before a new address takes effect.',
                      style: TextStyle(fontSize: 11, color: AppColors.textGray),
                    ),
                    const SizedBox(height: 16),
                    CustomTextField(
                      label: 'PHONE',
                      hint: 'Optional phone number',
                      controller: _phoneCtrl,
                      keyboardType: TextInputType.phone,
                      prefixIcon: const Icon(Icons.phone_outlined,
                          color: AppColors.textLightGray, size: 20),
                    ),
                    const SizedBox(height: 16),
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
          color: Colors.white.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.92)),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryDark.withValues(alpha: 0.055),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          children: [
            for (var index = 0; index < children.length; index++) ...[
              children[index],
              if (index < children.length - 1)
                const Divider(height: 1, indent: 54, endIndent: 14),
            ],
          ],
        ),
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
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AppColors.backgroundGreenLight,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: AppColors.primary),
        ),
        const SizedBox(width: 14),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style:
                    const TextStyle(fontSize: 11, color: AppColors.textGray)),
            const SizedBox(height: 2),
            Text(value,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDark)),
          ]),
        ),
      ]),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;
  const _NavItem(
      {required this.icon,
      required this.label,
      this.subtitle,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: AppColors.backgroundGreenLight,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: AppColors.primary, size: 20),
      ),
      title: Text(
        label,
        style: const TextStyle(
          color: AppColors.textDark,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: const TextStyle(
                color: AppColors.textGray,
                fontSize: 11,
                height: 1.35,
              ),
            ),
      trailing: const Icon(Icons.chevron_right, color: AppColors.textLightGray),
      onTap: onTap,
    );
  }
}
