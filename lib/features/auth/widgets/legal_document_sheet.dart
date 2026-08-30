import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';

enum LegalDocument { termsOfService, privacyPolicy, aiSafetyNotice }

class LegalDocumentSheet extends StatelessWidget {
  final LegalDocument document;

  const LegalDocumentSheet({super.key, required this.document});

  String get _title => switch (document) {
        LegalDocument.termsOfService => 'Terms of Service',
        LegalDocument.privacyPolicy => 'Privacy Policy',
        LegalDocument.aiSafetyNotice => 'AI & Crop Safety Notice',
      };

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
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(_title),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Effective date: August 30, 2026',
                  style: theme.textTheme.bodySmall),
              const SizedBox(height: 16),
              for (final section in _sections) ...[
                Text(section.heading, style: theme.textTheme.titleSmall),
                const SizedBox(height: 6),
                Text(section.body),
                const SizedBox(height: 16),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _LegalSection {
  final String heading;
  final String body;

  const _LegalSection({required this.heading, required this.body});
}
