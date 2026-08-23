import 'package:flutter/material.dart';

enum LegalDocument { termsOfService, privacyPolicy }

class LegalDocumentSheet extends StatelessWidget {
  final LegalDocument document;

  const LegalDocumentSheet({super.key, required this.document});

  String get _title => switch (document) {
        LegalDocument.termsOfService => 'Terms of Service',
        LegalDocument.privacyPolicy => 'Privacy Policy',
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
                  'You are responsible for keeping your account credentials secure and for ensuring that the information, photos, recordings, and notes you add may be used by the app to provide its features.',
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
                  'Your information is used to operate your account, synchronize crop records, show reminders, generate crop-health guidance, and improve the continuity of your care history.',
            ),
            _LegalSection(
              heading: 'Third-party processing',
              body:
                  'When you use online features, relevant information may be sent to the app backend and its service providers for authentication, data storage, weather lookup, AI chat, image analysis, or voice transcription. Do not submit information you do not want processed by these services.',
            ),
            _LegalSection(
              heading: 'Your choices',
              body:
                  'You can avoid optional online features and manage crop records from the app. Account deletion, retention periods, and the operator contact details must be published before a public release.',
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
              Text('Effective date: July 26, 2026',
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
