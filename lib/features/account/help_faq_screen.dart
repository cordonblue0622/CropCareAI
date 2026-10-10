import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';

class HelpFaqScreen extends StatelessWidget {
  const HelpFaqScreen({super.key});

  static const String _supportEmail = 'cropcareai.team@gmail.com';

  Future<void> _emailSupport(
    BuildContext context, {
    required String subject,
    required String body,
  }) async {
    final uri = Uri.parse(
      'mailto:$_supportEmail?subject=${Uri.encodeComponent(subject)}'
      '&body=${Uri.encodeComponent(body)}',
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundCream,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text(
          'Help & FAQ',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.borderGreen),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _IconTile(icon: Icons.eco_outlined),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CropCare AI Guide',
                        style: TextStyle(
                          color: AppColors.textDark,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 5),
                      Text(
                        'Open a topic for step-by-step help with scans, crop records, treatment tracking, and account settings.',
                        style: TextStyle(
                          color: AppColors.textGray,
                          fontSize: 13,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const _GroupLabel('Diagnose & Track'),
          const _FaqCard(
            items: [
              _FaqItem(
                icon: Icons.document_scanner_outlined,
                title: 'How do I scan a crop photo?',
                steps: [
                  'Open Scan from the bottom navigation and choose the camera or photo-library option.',
                  'Photograph one affected leaf or plant area in clear, even light. Keep the symptoms in focus and avoid distant, dark, or blurry images.',
                  'Confirm the crop type when prompted, then submit the photo for analysis.',
                  'Review the detected condition, confidence, severity, safety notes, and recommended actions. AI results are estimates, so verify uncertain or severe cases with a qualified agricultural professional.',
                  'Use Diagnostic History in Account to revisit saved results.',
                ],
              ),
              _FaqItem(
                icon: Icons.add_circle_outline,
                title: 'How do I add a crop?',
                steps: [
                  'For a diagnosed crop, finish a scan or photo-assisted chat and choose Add to My Crops from the treatment card.',
                  'Enter a unique crop name and complete the requested crop and location details.',
                  'Save the crop. The diagnosis and any available treatment plan are linked to its record.',
                  'You can also open My Crops and use its add action to create a crop record without a diagnosis.',
                  'Open the crop later to edit its details, review diagnoses, or follow its daily plan.',
                ],
              ),
              _FaqItem(
                icon: Icons.task_alt_outlined,
                title: 'How do treatment tasks and check-ins work?',
                steps: [
                  'Open My Crops, select the crop, and open the Daily Plan tab.',
                  'Complete each action due for the active treatment day. Future tasks remain unavailable until their scheduled date.',
                  'After all actions for the day are complete, select Submit daily check-in.',
                  'Add the requested crop photo and notes, then submit once. The next treatment day unlocks after the current day check-in.',
                  'Use Progress to review the calendar, health trend, AI assessment, and visual history. A pending offline photo is assessed when connectivity returns.',
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          const _GroupLabel('Data & Connectivity'),
          const _FaqCard(
            items: [
              _FaqItem(
                icon: Icons.cloud_off_outlined,
                title: 'What works while I am offline?',
                steps: [
                  'Previously cached crop records, diagnoses, treatment tasks, and progress can remain available on the device.',
                  'Crop edits, task completion, and supported progress updates are saved locally and queued for sync.',
                  'Online AI chat, cloud-only data, weather, voice transcription, and fresh server analysis require a connection.',
                  'An offline photo check-in can appear as pending or insufficient data until the app reconnects and completes AI assessment.',
                  'Keep the app installed and do not clear its storage while changes are waiting to sync.',
                ],
              ),
              _FaqItem(
                icon: Icons.sync_outlined,
                title: 'How does synchronization work?',
                steps: [
                  'CropCare AI queues supported changes on your device when the server cannot be reached.',
                  'When connectivity returns and you are signed in, the app automatically pushes pending changes and checks for newer cloud records.',
                  'Keep the app open briefly after reconnecting so photos and larger updates have time to upload.',
                  'If another device does not show a recent change, reconnect both devices and reopen the relevant crop.',
                  'Do not repeatedly recreate the same crop while offline; each crop name must be unique.',
                ],
              ),
              _FaqItem(
                icon: Icons.wifi_find_outlined,
                title: 'The app says it is offline or will not sync',
                steps: [
                  'Confirm Wi-Fi or mobile data works in another app, then switch airplane mode off.',
                  'Open Android Settings from Account and allow the permissions CropCare AI needs for the action you are taking.',
                  'Return to CropCare AI, keep it open, and reopen the crop to trigger a fresh load.',
                  'If only AI features fail, the hosted service may be temporarily unavailable; your locally saved records should remain queued.',
                  'If the issue persists, use Report a problem below and include the affected crop, time, connection type, and exact message shown.',
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          const _GroupLabel('Account & Troubleshooting'),
          const _FaqCard(
            items: [
              _FaqItem(
                icon: Icons.manage_accounts_outlined,
                title: 'How do I update my profile or email?',
                steps: [
                  'Open Account and select Edit profile & farm details.',
                  'Update your name, phone, country, province, municipality, or barangay, then select Save.',
                  'If you change your email address, open the confirmation message sent to the new address. The change does not take effect until it is confirmed.',
                  'To change the profile photo, tap the avatar on the Account screen and choose an image.',
                  'If a confirmation email is missing, check spam or junk folders and verify that the address was typed correctly.',
                ],
              ),
              _FaqItem(
                icon: Icons.image_not_supported_outlined,
                title: 'A photo will not scan or upload',
                steps: [
                  'Check that camera or photo access is allowed in Android Settings.',
                  'Retake the image in good light with the symptoms centered and in focus.',
                  'Try one clear image first and wait for the current upload to finish before submitting again.',
                  'Verify your internet connection for online analysis. If offline, retry the scan when connected.',
                  'If the same image repeatedly fails, use Report a problem and include whether it came from the camera or photo library and the message shown.',
                ],
              ),
              _FaqItem(
                icon: Icons.notifications_none_outlined,
                title: 'I am not receiving reminders',
                steps: [
                  'Open Account and select Notification & device permissions.',
                  'In Android Settings, allow notifications for CropCare AI and confirm the app is not paused or restricted.',
                  'Check that the crop has an active treatment plan with upcoming tasks.',
                  'Review battery-saving settings if Android is delaying background notifications.',
                  'Return to the app and reopen the crop after changing device settings.',
                ],
              ),
            ],
          ),
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.primaryDark,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Still need help?',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Email the CropCare AI team with the details needed to investigate.',
                  style: TextStyle(color: Colors.white70, height: 1.4),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _emailSupport(
                          context,
                          subject: 'CropCare AI support request',
                          body: _supportBody,
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white54),
                        ),
                        icon: const Icon(Icons.mail_outline, size: 19),
                        label: const Text('Contact support'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _emailSupport(
                          context,
                          subject: 'CropCare AI problem report',
                          body: _problemBody,
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: AppColors.primaryDark,
                        ),
                        icon: const Icon(Icons.bug_report_outlined, size: 19),
                        label: const Text('Report problem'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static const String _supportBody = '''Hello CropCare AI Support,

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

  static const String _problemBody = '''Hello CropCare AI Support,

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
}

class _GroupLabel extends StatelessWidget {
  final String label;

  const _GroupLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: AppColors.textGray,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _FaqCard extends StatelessWidget {
  final List<_FaqItem> items;

  const _FaqCard({required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderGreen),
      ),
      child: Column(
        children: [
          for (var index = 0; index < items.length; index++) ...[
            items[index],
            if (index < items.length - 1) const Divider(height: 1, indent: 58),
          ],
        ],
      ),
    );
  }
}

class _FaqItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<String> steps;

  const _FaqItem({
    required this.icon,
    required this.title,
    required this.steps,
  });

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        leading: _IconTile(icon: icon),
        title: Text(
          title,
          style: const TextStyle(
            color: AppColors.textDark,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        iconColor: AppColors.primary,
        collapsedIconColor: AppColors.textGray,
        children: [
          for (var index = 0; index < steps.length; index++)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.backgroundGreenLight,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(
                        color: AppColors.primaryDark,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      steps[index],
                      style: const TextStyle(
                        color: AppColors.textMedium,
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _IconTile extends StatelessWidget {
  final IconData icon;

  const _IconTile({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: AppColors.backgroundGreenLight,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: AppColors.primary, size: 20),
    );
  }
}
