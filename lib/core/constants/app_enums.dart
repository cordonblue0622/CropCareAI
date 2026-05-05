// =========================================================
// CropCare AI – Dart enums mirroring PostgreSQL enum types
// =========================================================

// ─── Crop Type ───────────────────────────────────────────────────────────────
enum CropType { tomato, pechay, pepper, eggplant, squash }

extension CropTypeX on CropType {
  String get value => name; // all names already match the DB values
  static CropType fromValue(String v) =>
      CropType.values.firstWhere((e) => e.name == v);
}

// ─── Diagnosis Mode ───────────────────────────────────────────────────────────
enum DiagnosisMode { offline, online }

extension DiagnosisModeX on DiagnosisMode {
  String get value => name;
  static DiagnosisMode fromValue(String v) =>
      DiagnosisMode.values.firstWhere((e) => e.name == v);
}

// ─── Crop Status ──────────────────────────────────────────────────────────────
enum CropStatus { healthy, monitoring, recovering, critical, archived }

extension CropStatusX on CropStatus {
  String get value => name;
  static CropStatus fromValue(String v) =>
      CropStatus.values.firstWhere((e) => e.name == v);
}

// ─── Severity ─────────────────────────────────────────────────────────────────
enum Severity { healthy, mild, moderate, severe }

extension SeverityX on Severity {
  String get value => name;
  static Severity fromValue(String v) =>
      Severity.values.firstWhere((e) => e.name == v);
}

// ─── Progress Status ──────────────────────────────────────────────────────────
enum ProgressStatus { improving, stable, worsening, insufficientData }

extension ProgressStatusX on ProgressStatus {
  String get value {
    if (this == ProgressStatus.insufficientData) return 'insufficient_data';
    return name;
  }

  static ProgressStatus fromValue(String v) {
    if (v == 'insufficient_data') return ProgressStatus.insufficientData;
    return ProgressStatus.values.firstWhere((e) => e.name == v);
  }
}

// ─── Treatment Status ─────────────────────────────────────────────────────────
enum TreatmentStatus { planned, ongoing, completed, stopped, needsReassessment }

extension TreatmentStatusX on TreatmentStatus {
  String get value {
    if (this == TreatmentStatus.needsReassessment) return 'needs_reassessment';
    return name;
  }

  static TreatmentStatus fromValue(String v) {
    if (v == 'needs_reassessment') return TreatmentStatus.needsReassessment;
    return TreatmentStatus.values.firstWhere((e) => e.name == v);
  }
}

// ─── Task Status ──────────────────────────────────────────────────────────────
enum TaskStatus { pending, completed, missed, skipped }

extension TaskStatusX on TaskStatus {
  String get value => name;
  static TaskStatus fromValue(String v) =>
      TaskStatus.values.firstWhere((e) => e.name == v);
}

// ─── Update Source ────────────────────────────────────────────────────────────
enum UpdateSource { manual, image, video, voice, system }

extension UpdateSourceX on UpdateSource {
  String get value => name;
  static UpdateSource fromValue(String v) =>
      UpdateSource.values.firstWhere((e) => e.name == v);
}

// ─── Message Role ─────────────────────────────────────────────────────────────
enum MessageRole { user, assistant, system }

extension MessageRoleX on MessageRole {
  String get value => name;
  static MessageRole fromValue(String v) =>
      MessageRole.values.firstWhere((e) => e.name == v);
}

// ─── Notification Type ────────────────────────────────────────────────────────
enum NotificationType { taskReminder, treatmentReminder, progressAlert, general }

extension NotificationTypeX on NotificationType {
  String get value {
    switch (this) {
      case NotificationType.taskReminder:
        return 'task_reminder';
      case NotificationType.treatmentReminder:
        return 'treatment_reminder';
      case NotificationType.progressAlert:
        return 'progress_alert';
      case NotificationType.general:
        return 'general';
    }
  }

  static NotificationType fromValue(String v) {
    switch (v) {
      case 'task_reminder':
        return NotificationType.taskReminder;
      case 'treatment_reminder':
        return NotificationType.treatmentReminder;
      case 'progress_alert':
        return NotificationType.progressAlert;
      default:
        return NotificationType.general;
    }
  }
}
