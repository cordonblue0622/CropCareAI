import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';

enum LegalDocument { termsOfService, privacyPolicy, aiSafetyNotice }

class LegalDocumentSheet extends StatelessWidget {
  final LegalDocument document;

  const LegalDocumentSheet({super.key, required this.document});

  String get _title => switch (document) {
        LegalDocument.termsOfService => 'Terms of Service',
        LegalDocument.privacyPolicy => 'Privacy Policy',
        LegalDocument.aiSafetyNotice => 'AI & Crop Safety Notice',
      };

  IconData get _documentIcon => switch (document) {
        LegalDocument.termsOfService => Icons.description_outlined,
        LegalDocument.privacyPolicy => Icons.privacy_tip_outlined,
        LegalDocument.aiSafetyNotice => Icons.health_and_safety_outlined,
      };

  Color get _documentColor => switch (document) {
        LegalDocument.termsOfService => AppColors.primary,
        LegalDocument.privacyPolicy => const Color(0xFF256A72),
        LegalDocument.aiSafetyNotice => const Color(0xFFB85C18),
      };

  IconData _sectionIcon(int index) {
    final icons = switch (document) {
      LegalDocument.termsOfService => const [
          Icons.eco_outlined,
          Icons.account_circle_outlined,
          Icons.psychology_outlined,
          Icons.cloud_outlined,
          Icons.verified_user_outlined,
          Icons.person_off_outlined,
          Icons.update_outlined,
          Icons.mail_outline,
        ],
      LegalDocument.privacyPolicy => const [
          Icons.inventory_2_outlined,
          Icons.manage_search_outlined,
          Icons.hub_outlined,
          Icons.handshake_outlined,
          Icons.lock_outline,
          Icons.gavel_outlined,
          Icons.tune_outlined,
          Icons.child_care_outlined,
          Icons.contact_support_outlined,
        ],
      LegalDocument.aiSafetyNotice => const [
          Icons.info_outline,
          Icons.fact_check_outlined,
          Icons.perm_media_outlined,
          Icons.emergency_outlined,
        ],
    };
    return icons[index];
  }

  List<_LegalSection> get _sections => switch (document) {
        LegalDocument.termsOfService => const [
            _LegalSection(
              heading: 'Using CropCare AI',
              body:
                  'CropCare AI helps you record crop conditions, organize care tasks, and receive general crop-health guidance. It does not replace advice from a qualified agricultural professional.',
            ),
            _LegalSection(
              heading: 'Your account and content',
              body:
                  'You must provide accurate information, protect your password and device, and promptly report suspected unauthorized access. You grant CropCare AI permission to process the information, photos, recordings, and notes you submit only as needed to provide and secure the service.',
            ),
            _LegalSection(
              heading: 'AI-assisted guidance',
              body:
                  'Disease detection and chat responses are informational estimates. Conditions in the field can differ from an app result, so confirm treatment choices, product labels, and local regulations before acting.',
            ),
            _LegalSection(
              heading: 'Availability',
              body:
                  'Some features need an internet connection, including cloud sync, weather information, AI chat, and voice transcription. Availability can depend on the third-party services that support those features.',
            ),
            _LegalSection(
              heading: 'Acceptable use',
              body:
                  'Do not misuse the service, attempt unauthorized access, upload unlawful or harmful content, interfere with other accounts, or use automated means to disrupt the app or its providers.',
            ),
            _LegalSection(
              heading: 'Account termination',
              body:
                  'You may permanently delete your account from My Account. We may restrict accounts used unlawfully or in ways that threaten the service or other users. Deletion cannot be undone.',
            ),
            _LegalSection(
              heading: 'Changes and responsibility',
              body:
                  'We may update these terms as the app changes and will identify the current version in the app. To the extent permitted by law, CropCare AI is not responsible for crop loss or indirect damage caused by relying on estimates without professional verification.',
            ),
            _LegalSection(
              heading: 'Contact',
              body:
                  'Questions about these terms may be sent to ${AppConstants.privacyContactEmail}. These terms are intended to operate under applicable laws of the Philippines.',
            ),
          ],
        LegalDocument.privacyPolicy => const [
            _LegalSection(
              heading: 'Information you provide',
              body:
                  'The app stores the account and farm details you enter, along with crop records, diagnoses, care tasks, chat messages, photos, and voice recordings or transcripts that you choose to submit.',
            ),
            _LegalSection(
              heading: 'How information is used',
              body:
                  'Your information is used to create and secure your account, synchronize crop records, show reminders, generate crop-health guidance, provide support, prevent abuse, and maintain the continuity of your care history.',
            ),
            _LegalSection(
              heading: 'Third-party processing',
              body:
                  'When you use online features, relevant information may be sent to the app backend and its service providers for authentication, data storage, weather lookup, AI chat, image analysis, or voice transcription. Do not submit information you do not want processed by these services.',
            ),
            _LegalSection(
              heading: 'Legal basis and sharing',
              body:
                  'Processing is based on providing the service you request, your consent for optional submissions, legitimate security needs, and legal obligations. We do not sell personal information. Data is shared only with service providers needed for authentication, hosting, storage, diagnostics, AI, weather, and communications, or when required by law.',
            ),
            _LegalSection(
              heading: 'Storage, security, and retention',
              body:
                  'Cloud data is protected using provider access controls and encrypted network connections. Local data is stored on your device. No system is completely secure. Account information is retained while your account is active and deleted when you use Delete Account, except limited records that must be retained for security, dispute resolution, or legal compliance.',
            ),
            _LegalSection(
              heading: 'Your data privacy rights',
              body:
                  'Subject to Republic Act No. 10173, the Data Privacy Act of 2012, and applicable rules, you may request access, correction, deletion or blocking, object to processing, withdraw consent where consent applies, request data portability where available, and lodge a complaint with the National Privacy Commission. You may also seek indemnification when provided by law.',
            ),
            _LegalSection(
              heading: 'Your controls',
              body:
                  'You can edit profile and crop information, avoid optional camera, microphone, and online features, or permanently delete your account and associated information from My Account. Device permissions can also be withdrawn in Android Settings.',
            ),
            _LegalSection(
              heading: 'Children and sensitive information',
              body:
                  'CropCare AI is not directed to children under 18. Do not submit government identifiers, financial information, medical records, or other sensitive personal information that is unnecessary for crop care.',
            ),
            _LegalSection(
              heading: 'Contact and complaints',
              body:
                  'For privacy requests, questions, or suspected data incidents, contact ${AppConstants.privacyContactEmail}. You may also contact the Philippine National Privacy Commission through its official channels.',
            ),
          ],
        LegalDocument.aiSafetyNotice => const [
            _LegalSection(
              heading: 'Informational assistance only',
              body:
                  'CropCare AI uses automated image analysis and generative AI. Results are estimates, may be incomplete or incorrect, and are not a substitute for an agronomist, plant pathologist, extension worker, or other qualified professional.',
            ),
            _LegalSection(
              heading: 'Before treating crops',
              body:
                  'Confirm the crop and symptoms, inspect multiple plants, follow pesticide and fertilizer labels, use protective equipment, observe pre-harvest intervals, and follow local agricultural and environmental rules. Seek expert help for severe, spreading, or uncertain conditions.',
            ),
            _LegalSection(
              heading: 'Photos, audio, and prompts',
              body:
                  'Only submit content needed for crop care. Avoid including faces, private conversations, addresses, identification documents, or other personal information in photos, recordings, and chat prompts.',
            ),
            _LegalSection(
              heading: 'Emergencies and harmful exposure',
              body:
                  'The app is not an emergency service. For suspected poisoning, unsafe chemical exposure, or immediate danger, contact local emergency services, poison control resources, or an appropriate health professional.',
            ),
          ],
      };

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final horizontalInset = size.width < 600 ? 14.0 : 40.0;

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: horizontalInset,
        vertical: 24,
      ),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 620,
          maxHeight: size.height * 0.86,
        ),
        child: Material(
          color: AppColors.backgroundCream,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(20, 18, 10, 18),
                decoration: BoxDecoration(
                  color: _documentColor,
                  border: Border(
                    bottom: BorderSide(
                      color: Colors.black.withValues(alpha: 0.08),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.22),
                        ),
                      ),
                      child: Icon(_documentIcon, color: Colors.white, size: 25),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Text(
                        _title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                      icon:
                          const Icon(Icons.close_rounded, color: Colors.white),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _documentColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(
                            color: _documentColor.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.calendar_today_outlined,
                              size: 14,
                              color: _documentColor,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Effective August 30, 2026',
                              style: TextStyle(
                                color: _documentColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      for (var index = 0;
                          index < _sections.length;
                          index++) ...[
                        _LegalSectionCard(
                          section: _sections[index],
                          icon: _sectionIcon(index),
                          color: _documentColor,
                        ),
                        if (index < _sections.length - 1)
                          const SizedBox(height: 10),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LegalSectionCard extends StatelessWidget {
  final _LegalSection section;
  final IconData icon;
  final Color color;

  const _LegalSectionCard({
    required this.section,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderGreen),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  section.heading,
                  style: const TextStyle(
                    color: AppColors.textDark,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  section.body,
                  style: const TextStyle(
                    color: AppColors.textMedium,
                    fontSize: 13,
                    height: 1.5,
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

class _LegalSection {
  final String heading;
  final String body;

  const _LegalSection({required this.heading, required this.body});
}
