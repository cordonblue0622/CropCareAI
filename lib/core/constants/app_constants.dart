class AppConstants {
  AppConstants._();

  // ─── Supabase ─────────────────────────────────────────────────────────────
  // Publishable client configuration from Supabase Project Settings → API.
  static const String supabaseUrl = 'https://dyolfgaabpcibwkphxgo.supabase.co';
  static const String supabaseAnonKey =
      'sb_publishable_pGlOzhxq3XFUFg4KKQhJFg_2D6Gd9pg';

  // ─── Google OAuth ─────────────────────────────────────────────────────────
  // OAuth client IDs are public client identifiers, not client secrets.
  static const String googleWebClientId =
      '411826613527-oqsj420bgp309pfd1n5fum62orni43go.apps.googleusercontent.com';
  static const String googleIosClientId = 'YOUR_GOOGLE_IOS_CLIENT_ID';

  // ─── Authentication ──────────────────────────────────────────────────────
  // Register this callback in Supabase Auth URL Configuration.
  static const String passwordResetRedirectUrl = String.fromEnvironment(
    'PASSWORD_RESET_REDIRECT_URL',
    defaultValue: 'cropcareai://auth/reset-password',
  );

  static const String emailConfirmationRedirectUrl = String.fromEnvironment(
    'EMAIL_CONFIRMATION_REDIRECT_URL',
    defaultValue: 'cropcareai://auth/callback',
  );

  // ─── Weather API ───────────────────────────────────────────────────────────
  // Optional. Set with --dart-define=WEATHER_API_KEY=... to enable weather data.
  static const String weatherApiKey = String.fromEnvironment(
    'WEATHER_API_KEY',
    defaultValue: '',
  );

  // ─── AI Backend ───────────────────────────────────────────────────────────
  // Override with --dart-define=AI_BACKEND_BASE_URL=http://host:8000
  static const String aiBackendBaseUrl = String.fromEnvironment(
    'AI_BACKEND_BASE_URL',
    defaultValue: '',
  );
  static const String aiBackendAndroidBaseUrl = String.fromEnvironment(
    'AI_BACKEND_ANDROID_BASE_URL',
    defaultValue: 'https://cropcareai-nxn4.onrender.com',
  );

  // Shipped on-device classifier (PlantVillage EfficientNetV2S, 38 labels).
  // The accepted crop types are inferred from the bundled label file at runtime.
  static const String temporaryScannerModelAsset =
      'assets/models/plant_disease_efficientnetv2s.tflite';
  static const String temporaryScannerLabelsAsset =
      'assets/models/plant_disease_efficientnetv2s_labels.txt';

  static const double temporaryScannerMinConfidence = 0.45;
  static const double temporaryScannerProvisionalConfidence = 0.35;
  static const double temporaryScannerProvisionalCropFamilyConfidence = 0.55;
  static const double temporaryScannerAcceptedConfidence = 0.60;
  static const double temporaryScannerHintedAcceptedConfidence = 0.30;
  static const double temporaryScannerAcceptedMargin = 0.15;

  // ─── Local Database ───────────────────────────────────────────────────────
  static const String dbName = 'cropcare_ai.db';
  static const int dbVersion = 5;

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
  static const String diseaseTreatmentDayStepsTable =
      'disease_treatment_day_steps';

  // ─── SharedPreferences Keys ───────────────────────────────────────────────
  static const String keyOnboardingDone = 'onboarding_done';
  static const String keyLastSyncedAt = 'last_synced_at';
}
