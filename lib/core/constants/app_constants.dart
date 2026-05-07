class AppConstants {
  AppConstants._();

  // ─── Supabase ─────────────────────────────────────────────────────────────
  // TODO: Replace with your actual Supabase project URL and anon key.
  // Find these at: https://app.supabase.com → Project Settings → API
  static const String supabaseUrl = 'https://dyolfgaabpcibwkphxgo.supabase.co';
  static const String supabaseAnonKey =
      'sb_publishable_pGlOzhxq3XFUFg4KKQhJFg_2D6Gd9pg';

  // ─── Google OAuth ─────────────────────────────────────────────────────────
  // TODO: Replace with your Google OAuth Web Client ID
  // (from Google Cloud Console → APIs → Credentials)
  static const String googleWebClientId =
      '411826613527-oqsj420bgp309pfd1n5fum62orni43go.apps.googleusercontent.com';
  static const String googleIosClientId = 'YOUR_GOOGLE_IOS_CLIENT_ID';

  // ─── Weather API ───────────────────────────────────────────────────────────
  // Override with --dart-define=WEATHER_API_KEY=... for deployment.
  static const String weatherApiKey = String.fromEnvironment(
    'WEATHER_API_KEY',
    defaultValue: 'f1a9fa102397434db9403033261904',
  );

  // ─── AI Backend ───────────────────────────────────────────────────────────
  // Override with --dart-define=AI_BACKEND_BASE_URL=http://host:8000
  static const String aiBackendBaseUrl = String.fromEnvironment(
    'AI_BACKEND_BASE_URL',
    defaultValue: '',
  );

  // Shipped on-device classifier (cropcare_v2_subset_100, 13 labels).
  // The accepted crop types are inferred from labels_v2.txt at runtime.
  static const String temporaryScannerModelAsset =
      'assets/models/cropcare_efficientnet_v2.tflite';
  static const String temporaryScannerLabelsAsset =
      'assets/models/labels_v2.txt';

  static const double temporaryScannerMinConfidence = 0.45;
  static const double temporaryScannerAcceptedConfidence = 0.60;
  static const double temporaryScannerAcceptedMargin = 0.15;

  // ─── Local Database ───────────────────────────────────────────────────────
  static const String dbName = 'cropcare_ai.db';
  static const int dbVersion = 3;

  // ─── Table Names ──────────────────────────────────────────────────────────
  static const String usersTable = 'users';
  static const String syncQueueTable = 'sync_queue';
  static const String cropsTable = 'crops';
  static const String diagnosesTable = 'diagnoses';
  static const String treatmentsTable = 'treatments';
  static const String treatmentTasksTable = 'treatment_tasks';
  static const String progressUpdatesTable = 'progress_updates';
  static const String chatSessionsTable = 'chat_sessions';
  static const String chatMessagesTable = 'chat_messages';
  static const String notificationsTable = 'notifications';
  static const String diseaseKnowledgeTable = 'disease_knowledge_base';

  // ─── SharedPreferences Keys ───────────────────────────────────────────────
  static const String keyOnboardingDone = 'onboarding_done';
  static const String keyLastSyncedAt = 'last_synced_at';
}
