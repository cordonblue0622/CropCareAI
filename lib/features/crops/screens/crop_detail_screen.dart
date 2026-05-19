import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:confetti/confetti.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_enums.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/image_reference.dart';
import '../../../core/utils/label_formatter.dart';
import '../../../data/local/database_helper.dart';
import '../../../data/models/chat_message_model.dart';
import '../../../data/models/chat_session_model.dart';
import '../../../data/models/crop_model.dart';
import '../../../data/models/diagnosis_model.dart';
import '../../../data/models/progress_update_model.dart';
import '../../../data/models/treatment_model.dart';
import '../../../data/models/treatment_task_model.dart';
import '../../../data/remote/ai_backend_service.dart';
import '../../../data/remote/supabase_service.dart';
import '../../../services/health_score_service.dart';
import '../../../services/connectivity_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../../chat/screens/chat_screen.dart';
import '../../home/home_screen.dart';
import '../providers/crops_provider.dart';
import 'add_crop_screen.dart';
import '../../../shared/widgets/app_image_reference.dart';
import '../widgets/calendar_tracker.dart';
import '../widgets/health_score_graph.dart';

class CropDetailScreen extends StatefulWidget {
  final CropModel crop;
  final int? initialTabIndex; // 0..3 to override default tab
  final DateTime?
      initialSelectedDate; // for calendar deep-linking from notifications

  const CropDetailScreen({
    super.key,
    required this.crop,
    this.initialTabIndex,
    this.initialSelectedDate,
  });

  @override
  State<CropDetailScreen> createState() => _CropDetailScreenState();
}

class _CropDetailScreenState extends State<CropDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  late CropModel _crop;

  List<DiagnosisModel> _diagnoses = [];
  List<TreatmentModel> _treatments = [];
  List<TreatmentTaskModel> _tasks = [];
  List<ProgressUpdateModel> _progress = [];
  List<ChatMessageModel> _chatHistory = [];
  bool _loading = true;

  DateTime _selectedDate = _todayDate();

  static DateTime _todayDate() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  List<HealthScorePoint> get _healthCurve =>
      HealthScoreService.compute14DayCurve(
        tasks: _tasks,
        diagnoses: _diagnoses,
        now: DateTime.now(),
      );

  @override
  void initState() {
    super.initState();
    _crop = widget.crop;
    _tabs = TabController(
      length: 4,
      vsync: this,
      initialIndex: widget.initialTabIndex?.clamp(0, 3) ?? 0,
    );
    if (widget.initialSelectedDate != null) {
      final d = widget.initialSelectedDate!;
      _selectedDate = DateTime(d.year, d.month, d.day);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<T> _runOrFallback<T>(Future<T> Function() action, T fallback) async {
    try {
      return await action();
    } catch (_) {
      return fallback;
    }
  }

  List<T> _safeParseRows<T>(
    Iterable<Map<String, dynamic>> rows,
    T Function(Map<String, dynamic> row) parser,
  ) {
    final parsed = <T>[];
    for (final row in rows) {
      try {
        parsed.add(parser(row));
      } catch (_) {
        // Ignore malformed rows so one bad record does not block the screen.
      }
    }
    return parsed;
  }

  List<Map<String, dynamic>> _mergeRowsById(
    List<Map<String, dynamic>> localRows,
    List<Map<String, dynamic>> remoteRows,
  ) {
    final merged = <String, Map<String, dynamic>>{};
    for (final row in localRows) {
      final id = (row['id'] as String?)?.trim();
      if (id == null || id.isEmpty) {
        continue;
      }
      merged[id] = Map<String, dynamic>.from(row);
    }
    for (final row in remoteRows) {
      final id = (row['id'] as String?)?.trim();
      if (id == null || id.isEmpty) {
        continue;
      }
      merged[id] = Map<String, dynamic>.from(row);
    }
    return merged.values.toList(growable: false);
  }

  Future<void> _loadData() async {
    final db = context.read<DatabaseHelper>();
    final svc = context.read<SupabaseService>();

    try {
      final localDx = await db.queryDiagnosesForCrop(_crop.id);
      final localTx = await db.queryTreatmentsForCrop(_crop.id);
      final localProgress = await db.queryProgressUpdatesForCrop(_crop.id);
      final localTasks = await db.queryTasksForCrop(_crop.id);
      final localSessions = await db.queryChatSessionsByCrop(_crop.id);

      final remoteDx = await _runOrFallback(
        () => svc.getDiagnosesByCrop(_crop.id),
        <Map<String, dynamic>>[],
      );
      final remoteTx = await _runOrFallback(
        () => svc.getTreatmentsByCrop(_crop.id),
        <Map<String, dynamic>>[],
      );
      final remoteProgress = await _runOrFallback(
        () => svc.getProgressUpdates(_crop.id),
        <Map<String, dynamic>>[],
      );

      final rawDx = _mergeRowsById(localDx, remoteDx);
      final rawTx = _mergeRowsById(localTx, remoteTx);
      final rawProgress = _mergeRowsById(localProgress, remoteProgress);

      final diagnoses = _safeParseRows(rawDx, DiagnosisModel.fromMap);
      final treatments = _safeParseRows(rawTx, TreatmentModel.fromMap);
      final progress = _safeParseRows(rawProgress, ProgressUpdateModel.fromMap)
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      final taskRowsById = <String, Map<String, dynamic>>{};
      for (final row in localTasks) {
        final id = (row['id'] as String?)?.trim();
        if (id != null && id.isNotEmpty) {
          taskRowsById[id] = Map<String, dynamic>.from(row);
        }
      }
      for (final treatment in treatments) {
        final rawTasks = await _runOrFallback(
          () => svc.getTreatmentTasks(treatment.id),
          <Map<String, dynamic>>[],
        );
        for (final row in rawTasks) {
          final id = (row['id'] as String?)?.trim();
          if (id != null && id.isNotEmpty) {
            taskRowsById[id] = Map<String, dynamic>.from(row);
          }
        }
      }
      final allTasks = _safeParseRows(
        taskRowsById.values,
        TreatmentTaskModel.fromMap,
      );
      allTasks.sort((a, b) {
        final dueCompare = a.dueAt.compareTo(b.dueAt);
        if (dueCompare != 0) return dueCompare;
        return (a.taskOrder ?? 0).compareTo(b.taskOrder ?? 0);
      });

      final remoteSessions = await _runOrFallback(
        () => svc.getChatSessionsByCrop(_crop.id),
        <Map<String, dynamic>>[],
      );
      final rawSessions = _mergeRowsById(localSessions, remoteSessions);
      final sessions = _safeParseRows(rawSessions, ChatSessionModel.fromMap);
      final messageRowsById = <String, Map<String, dynamic>>{};
      for (final session in sessions) {
        final localMessages = await db.queryChatMessages(session.id);
        for (final row in localMessages) {
          final id = (row['id'] as String?)?.trim();
          if (id != null && id.isNotEmpty) {
            messageRowsById[id] = Map<String, dynamic>.from(row);
          }
        }
        final rawMessages = await _runOrFallback(
          () => svc.getChatMessages(session.id),
          <Map<String, dynamic>>[],
        );
        for (final row in rawMessages) {
          final id = (row['id'] as String?)?.trim();
          if (id != null && id.isNotEmpty) {
            messageRowsById[id] = Map<String, dynamic>.from(row);
          }
        }
      }
      final allMessages = _safeParseRows(
        messageRowsById.values,
        ChatMessageModel.fromMap,
      )..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      final historyMessages = allMessages
          .where((message) => message.role != MessageRole.system)
          .toList(growable: false);

      if (!mounted) return;
      setState(() {
        _diagnoses = diagnoses;
        _treatments = treatments;
        _tasks = allTasks;
        _progress = progress;
        _chatHistory = historyMessages;
        _loading = false;
      });
      // Re-analyse any offline check-ins that are still pending GPT analysis.
      unawaited(_analyzePendingCheckIns());
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  /// Finds progress updates saved offline (progressStatus == insufficientData
  /// with a stored image) and, when online, sends them to GPT for analysis,
  /// then updates the stored record and the crop's health score.
  Future<void> _analyzePendingCheckIns() async {
    final pending = _progress
        .where(
          (u) =>
              u.progressStatus == ProgressStatus.insufficientData &&
              u.imageUrl != null &&
              u.imageUrl!.isNotEmpty &&
              isInlineImageDataUrl(u.imageUrl),
        )
        .toList();
    if (pending.isEmpty) return;

    final connectivity = context.read<ConnectivityService>();
    final isOnline = await connectivity.isConnected;
    if (!isOnline) return;

    final aiBackend = context.read<AiBackendService>();
    final cropsProvider = context.read<CropsProvider>();

    for (final update in pending) {
      if (!mounted) return;
      final imageBytes = decodeInlineImageDataUrl(update.imageUrl);
      if (imageBytes == null) continue;

      try {
        final aiResponse = await aiBackend.assessCropHealth(
          cropType: _crop.cropType.name,
          diseaseName:
              update.detectedDiseaseName?.trim().isNotEmpty == true
                  ? update.detectedDiseaseName!
                  : _crop.cropName,
          imageBytes: imageBytes.toList(),
          imageMimeType: 'image/jpeg',
          previousAssessment: update.note,
          currentHealthScore: _crop.latestHealthScore,
        );

        if (!aiResponse.accepted) continue;

        final newStatus = _parseProgressStatus(aiResponse.progressStatus);
        final updatedRecord = ProgressUpdateModel(
          id: update.id,
          cropId: update.cropId,
          treatmentId: update.treatmentId,
          diagnosisId: update.diagnosisId,
          userId: update.userId,
          updateSource: update.updateSource,
          note: aiResponse.assessment.trim().isNotEmpty
              ? aiResponse.assessment
              : update.note,
          imageUrl: update.imageUrl,
          videoUrl: update.videoUrl,
          observedSymptoms: update.observedSymptoms,
          detectedDiseaseName: update.detectedDiseaseName,
          detectedSeverity: update.detectedSeverity,
          progressStatus: newStatus,
          healthScore: aiResponse.healthScore,
          completedTaskCount: update.completedTaskCount,
          missedTaskCount: update.missedTaskCount,
          updateDate: update.updateDate,
          syncVersion: update.syncVersion,
          isDeleted: update.isDeleted,
          createdAt: update.createdAt,
          updatedAt: DateTime.now(),
        );

        await cropsProvider.saveProgressUpdate(updatedRecord, syncNow: false);

        // Update crop health score if this is the most recent update.
        final isMostRecent =
            _progress.isNotEmpty && _progress.first.id == update.id;
        if (isMostRecent && mounted) {
          await cropsProvider.updateCropHealthScore(
            _crop.id,
            aiResponse.healthScore,
            newStatus,
            syncNow: false,
          );
        }

        if (mounted) {
          setState(() {
            final idx = _progress.indexWhere((u) => u.id == updatedRecord.id);
            if (idx != -1) _progress[idx] = updatedRecord;
            if (isMostRecent) {
              _crop = _crop.copyWith(
                latestHealthScore: aiResponse.healthScore,
                latestProgressStatus: newStatus,
              );
            }
          });
        }
      } catch (_) {
        // Skip this update — will retry on next load.
      }
    }

    if (mounted) {
      unawaited(cropsProvider.flushPendingSync());
    }
  }

  /// Converts a raw backend progress-status string to [ProgressStatus],
  /// handling aliases returned by the GPT backend (e.g. "declining").
  ProgressStatus _parseProgressStatus(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'improving':
        return ProgressStatus.improving;
      case 'declining':
      case 'critical':
      case 'worsening':
        return ProgressStatus.worsening;
      case 'insufficient_data':
        return ProgressStatus.insufficientData;
      case 'stable':
      default:
        return ProgressStatus.stable;
    }
  }

  List<FlSpot> get _sparklineSpots {
    final sorted = [..._progress]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final last7 =
        sorted.length > 7 ? sorted.sublist(sorted.length - 7) : sorted;
    if (last7.isEmpty) {
      final baseline = (_crop.latestHealthScore ?? 0).toDouble();
      return [
        FlSpot(0, baseline),
        FlSpot(1, baseline),
      ];
    }
    return last7
        .asMap()
        .entries
        .map((e) =>
            FlSpot(e.key.toDouble(), (e.value.healthScore ?? 0).toDouble()))
        .toList();
  }

  String? get _latestCropImageUrl {
    for (final update in _progress) {
      final imageUrl = update.imageUrl?.trim();
      if (imageUrl != null && imageUrl.isNotEmpty) {
        return imageUrl;
      }
    }
    for (final diagnosis in _diagnoses) {
      final imageUrl = diagnosis.imageUrl?.trim();
      if (imageUrl != null && imageUrl.isNotEmpty) {
        return imageUrl;
      }
    }
    for (final message in _chatHistory.reversed) {
      final imageUrl = message.imageUrl?.trim();
      if (imageUrl != null && imageUrl.isNotEmpty) {
        return imageUrl;
      }
    }
    return null;
  }

  TreatmentModel? _treatmentForTask(TreatmentTaskModel task) {
    for (final treatment in _treatments) {
      if (treatment.id == task.treatmentId) {
        return treatment;
      }
    }
    return _treatments.isNotEmpty ? _treatments.first : null;
  }

  DiagnosisModel? _diagnosisForTask(TreatmentTaskModel task) {
    final treatment = _treatmentForTask(task);
    if (treatment?.diagnosisId != null) {
      for (final diagnosis in _diagnoses) {
        if (diagnosis.id == treatment!.diagnosisId) {
          return diagnosis;
        }
      }
    }
    return _diagnoses.isNotEmpty ? _diagnoses.first : null;
  }

  ProgressUpdateModel? _latestProgressUpdateForTask(TreatmentTaskModel task) {
    final treatmentId = task.treatmentId;
    final sorted = [..._progress]
      ..sort((a, b) => b.updateDate.compareTo(a.updateDate));

    for (final update in sorted) {
      if (update.isDeleted) {
        continue;
      }
      if (treatmentId.isNotEmpty &&
          update.treatmentId != null &&
          update.treatmentId != treatmentId) {
        continue;
      }
      final hasUsefulContext =
          (update.imageUrl?.trim().isNotEmpty ?? false) ||
          (update.note?.trim().isNotEmpty ?? false) ||
          update.healthScore != null;
      if (hasUsefulContext) {
        return update;
      }
    }
    return null;
  }

  Future<void> _showCheckInSheetForTask(TreatmentTaskModel task) async {
    final cropsProvider = context.read<CropsProvider>();
    final activeTreatment = _treatmentForTask(task);
    final previousUpdate = _latestProgressUpdateForTask(task);
    double? submittedScore;
    ProgressStatus? submittedStatus;
    ProgressUpdateModel? submittedUpdate;
    final didSubmit = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CheckInSheet(
        crop: _crop,
        allTasks: _tasks,
        checkedTasks: [task],
        activeTreatment: _treatmentForTask(task),
        latestDiagnosis: _diagnosisForTask(task),
        previousUpdate: previousUpdate,
        onSubmitted: (newScore, newStatus, update) async {
          submittedScore = newScore;
          submittedStatus = newStatus;
          submittedUpdate = update;
          final completedAt = update.createdAt;
          await cropsProvider.saveProgressUpdate(update, syncNow: false);
          await cropsProvider.updateCropHealthScore(
            _crop.id,
            newScore,
            newStatus,
            syncNow: false,
          );
          if (!mounted) return;
          setState(() {
            _crop = _crop.copyWith(
              latestHealthScore: newScore,
              latestProgressStatus: newStatus,
              lastCheckedAt: completedAt,
            );
            _tasks = _tasks
                .map((currentTask) => currentTask.id == task.id
                    ? currentTask.copyWith(
                        status: TaskStatus.completed,
                        completedAt: completedAt,
                        updatedAt: completedAt,
                      )
                    : currentTask)
                .toList();
            _progress = [update, ..._progress]
              ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
          });
          unawaited(cropsProvider.flushPendingSync());
        },
      ),
    );

    if (didSubmit == true && mounted) {
      await _showTaskCelebration(task.title);

      final latestScore = submittedScore;
      final latestStatus = submittedStatus;
      final latestUpdate = submittedUpdate;

      if (activeTreatment != null &&
          latestScore != null &&
          latestStatus != null &&
          latestUpdate != null &&
          _isTreatmentTimelineComplete(activeTreatment.id)) {
        await _handleCompletedTreatmentTimeline(
          treatment: activeTreatment,
          latestScore: latestScore,
          latestStatus: latestStatus,
          latestUpdate: latestUpdate,
        );
        return;
      }
    }
  }

  bool _isTreatmentTimelineComplete(String treatmentId) {
    final treatmentTasks = _tasks
        .where((task) => task.treatmentId == treatmentId && !task.isDeleted)
        .toList(growable: false);
    return treatmentTasks.isNotEmpty &&
        treatmentTasks.every((task) => task.status == TaskStatus.completed);
  }

  bool _hasDownwardTrend({
    required double latestScore,
    required ProgressStatus latestStatus,
  }) {
    if (latestStatus == ProgressStatus.worsening) {
      return true;
    }

    final scoredUpdates = _progress
        .where((update) => update.healthScore != null)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    if (scoredUpdates.length < 2) {
      return false;
    }

    final previousScore = scoredUpdates[scoredUpdates.length - 2].healthScore!;
    return latestScore < previousScore - 3;
  }

  bool _isHealedOutcome({
    required double latestScore,
    required ProgressStatus latestStatus,
  }) {
    return latestScore >= 90 &&
        !_hasDownwardTrend(
          latestScore: latestScore,
          latestStatus: latestStatus,
        );
  }

  Future<void> _handleCompletedTreatmentTimeline({
    required TreatmentModel treatment,
    required double latestScore,
    required ProgressStatus latestStatus,
    required ProgressUpdateModel latestUpdate,
  }) async {
    final cropsProvider = context.read<CropsProvider>();
    final healed = _isHealedOutcome(
      latestScore: latestScore,
      latestStatus: latestStatus,
    );

    if (healed) {
      final completionNote =
          'Treatment timeline completed successfully with a ${latestScore.toStringAsFixed(0)} health score and a ${latestStatus.value} trend.';
      await cropsProvider.completeTreatmentTimeline(
        crop: _crop,
        treatment: treatment,
        healed: true,
        completionNote: completionNote,
      );
      if (!mounted) return;

      setState(() {
        _crop = _crop.copyWith(
          status: CropStatus.archived,
          lastCheckedAt: latestUpdate.createdAt,
          updatedAt: latestUpdate.createdAt,
        );
        _treatments = _treatments
            .map((current) => current.id == treatment.id
                ? current.copyWith(
                    status: TreatmentStatus.completed,
                    endedAt: latestUpdate.createdAt,
                    reassessmentRequired: false,
                    notes: completionNote,
                    updatedAt: latestUpdate.createdAt,
                  )
                : current)
            .toList();
      });

      final action = await showDialog<_CompletionDialogAction>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _TreatmentCompletedDialog(
          cropName: _crop.cropName,
          latestScore: latestScore,
        ),
      );
      if (!mounted) return;
      await _handleCompletionAction(action ?? _CompletionDialogAction.done);
      return;
    }

    final suggestion = await _requestTreatmentExtensionSuggestion(
      treatment: treatment,
      latestScore: latestScore,
      latestStatus: latestStatus,
      latestUpdate: latestUpdate,
    );
    if (!mounted) return;

    final suggestedActions = _suggestedExtensionActions(suggestion);
    final reassessmentAction = await showDialog<_ReassessmentDialogAction>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _TreatmentReassessmentDialog(
        cropName: _crop.cropName,
        latestScore: latestScore,
        isDownwardTrend: _hasDownwardTrend(
          latestScore: latestScore,
          latestStatus: latestStatus,
        ),
        explanation: suggestion?.answer.isNotEmpty == true
            ? suggestion!.answer
            : _defaultReassessmentExplanation(
                latestScore: latestScore,
                latestStatus: latestStatus,
              ),
        suggestedActions: suggestedActions,
        sources: suggestion?.sources ?? const [],
        canExtend: suggestedActions.isNotEmpty,
      ),
    );
    if (!mounted) return;

    if (reassessmentAction == _ReassessmentDialogAction.extend &&
        suggestedActions.isNotEmpty) {
      final extension = await cropsProvider.extendTreatmentTracking(
        crop: _crop,
        currentTreatment: treatment,
        treatmentSteps: suggestedActions,
        explanation: suggestion?.answer.isNotEmpty == true
            ? suggestion!.answer
            : _defaultReassessmentExplanation(
                latestScore: latestScore,
                latestStatus: latestStatus,
              ),
        sources: suggestion?.sources ?? const [],
      );
      if (!mounted || extension == null) return;

      setState(() {
        _crop = extension.crop;
        _treatments = [
          extension.treatment,
          ..._treatments.map(
            (current) => current.id == treatment.id
                ? extension.previousTreatment
                : current,
          ),
        ];
        _tasks = [..._tasks, ...extension.tasks]
          ..sort((a, b) {
            final dueCompare = a.dueAt.compareTo(b.dueAt);
            if (dueCompare != 0) return dueCompare;
            return (a.taskOrder ?? 0).compareTo(b.taskOrder ?? 0);
          });
        _selectedDate = _todayDate();
      });

      _tabs.animateTo(1);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Treatment tracking extended with a new recovery plan.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (reassessmentAction == _ReassessmentDialogAction.moveToCompleted) {
      final completionNote = suggestion?.answer.isNotEmpty == true
          ? suggestion!.answer
          : _defaultReassessmentExplanation(
              latestScore: latestScore,
              latestStatus: latestStatus,
            );
      await cropsProvider.completeTreatmentTimeline(
        crop: _crop,
        treatment: treatment,
        healed: false,
        completionNote: completionNote,
      );
      if (!mounted) return;

      setState(() {
        _crop = _crop.copyWith(
          status: CropStatus.archived,
          lastCheckedAt: latestUpdate.createdAt,
          updatedAt: latestUpdate.createdAt,
        );
        _treatments = _treatments
            .map((current) => current.id == treatment.id
                ? current.copyWith(
                    status: TreatmentStatus.needsReassessment,
                    endedAt: latestUpdate.createdAt,
                    reassessmentRequired: true,
                    notes: completionNote,
                    updatedAt: latestUpdate.createdAt,
                  )
                : current)
            .toList();
      });

      final action = await showDialog<_CompletionDialogAction>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _TreatmentArchivedDialog(cropName: _crop.cropName),
      );
      if (!mounted) return;
      await _handleCompletionAction(action ?? _CompletionDialogAction.done);
    }
  }

  Future<AiBackendChatResponse?> _requestTreatmentExtensionSuggestion({
    required TreatmentModel treatment,
    required double latestScore,
    required ProgressStatus latestStatus,
    required ProgressUpdateModel latestUpdate,
  }) async {
    try {
      return await context.read<AiBackendService>().suggestTreatmentExtension(
            cropType: _crop.cropType.value,
            cropName: _crop.cropName,
            diseaseName: treatment.diseaseName,
            currentHealthScore: latestScore,
            progressStatus: latestStatus,
            latestNote: latestUpdate.note,
          );
    } catch (_) {
      return null;
    }
  }

  List<String> _suggestedExtensionActions(AiBackendChatResponse? suggestion) {
    if (suggestion == null) {
      return const [];
    }

    final normalized = <String>[];
    for (final action in suggestion.recommendedActions) {
      final trimmed = action.trim();
      if (trimmed.isNotEmpty && !normalized.contains(trimmed)) {
        normalized.add(trimmed);
      }
    }
    if (normalized.isNotEmpty) {
      return normalized;
    }

    for (final rawLine in suggestion.answer.split(RegExp(r'[\r\n]+'))) {
      final cleaned = rawLine
          .replaceFirst(RegExp(r'^[-•*\d\.)\s]+'), '')
          .trim();
      if (cleaned.isEmpty ||
          cleaned.toLowerCase().startsWith('source') ||
          cleaned.length < 10 ||
          normalized.contains(cleaned)) {
        continue;
      }
      normalized.add(cleaned);
      if (normalized.length == 6) {
        break;
      }
    }

    return normalized;
  }

  String _defaultReassessmentExplanation({
    required double latestScore,
    required ProgressStatus latestStatus,
  }) {
    final scoreLabel = latestScore.toStringAsFixed(0);
    if (_hasDownwardTrend(
      latestScore: latestScore,
      latestStatus: latestStatus,
    )) {
      return 'The treatment timeline is complete, but the latest health score dropped to $scoreLabel and the crop is trending downward. Review new treatment options before closing this crop.';
    }

    return 'The treatment timeline is complete, but the crop has not fully recovered yet. The latest health score is $scoreLabel and it still needs follow-up care to reach a healed state.';
  }

  Future<void> _handleCompletionAction(_CompletionDialogAction action) async {
    if (!mounted) return;

    if (action == _CompletionDialogAction.dashboard) {
      HomeScreen.tabSelection.value = 0;
    }

    Navigator.of(context).pop();
  }

  Future<void> _showTaskCelebration(String taskTitle) async {
    if (!mounted) return;
    var dialogOpen = true;
    showGeneralDialog<void>(
      context: context,
      barrierLabel: 'Task completed',
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.35),
      transitionDuration: const Duration(milliseconds: 350),
      pageBuilder: (_, __, ___) => _TaskCelebrationDialog(taskTitle: taskTitle),
      transitionBuilder: (_, animation, __, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutBack,
          reverseCurve: Curves.easeIn,
        );
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(scale: curved, child: child),
        );
      },
    ).whenComplete(() {
      dialogOpen = false;
    });
    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted || !dialogOpen) return;
    Navigator.of(context, rootNavigator: true).pop();
  }

  Future<void> _onTaskToggled(TreatmentTaskModel task) async {
    if (task.status == TaskStatus.completed) {
      return;
    }

    final taskDate = DateTime(task.dueAt.year, task.dueAt.month, task.dueAt.day);
    final today = _todayDate();

    if (taskDate.isAfter(today)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'This task can only be completed on ${DateFormat('MMM d').format(task.dueAt)} or later.',
          ),
        ),
      );
      return;
    }

    setState(() => _selectedDate = taskDate);
    _tabs.animateTo(1);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Open the Daily Plan tab to upload your update for this task.'),
      ),
    );
  }

  Color _statusColor(CropStatus s) {
    switch (s) {
      case CropStatus.healthy:
        return AppColors.primary;
      case CropStatus.recovering:
        return Colors.orange;
      case CropStatus.critical:
        return Colors.red;
      default:
        return AppColors.primaryMedium;
    }
  }

  @override
  Widget build(BuildContext context) {
    final score = _crop.latestHealthScore ?? 0;
    final spots = _sparklineSpots;
    final headerImageUrl = _latestCropImageUrl;

    return Scaffold(
      backgroundColor: AppColors.backgroundCream,
      body: NestedScrollView(
        headerSliverBuilder: (_, __) => [
          SliverAppBar(
            expandedHeight: 265,
            pinned: true,
            backgroundColor: AppColors.primaryDark,
            foregroundColor: Colors.white,
            actions: [
              IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => AddCropScreen(existing: _crop)),
                ),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  if (headerImageUrl != null)
                    AppImageReference(
                      imageRef: headerImageUrl,
                      fit: BoxFit.cover,
                      placeholder: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [AppColors.primaryDark, AppColors.primary],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                      ),
                      errorWidget: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [AppColors.primaryDark, AppColors.primary],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                      ),
                    )
                  else
                    Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [AppColors.primaryDark, AppColors.primary],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                    ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.black.withOpacity(0.48),
                          Colors.black.withOpacity(0.22),
                          AppColors.primaryDark.withOpacity(0.78),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0.0, 0.45, 1.0],
                      ),
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.black.withOpacity(0.22),
                          Colors.transparent,
                        ],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                    ),
                  ),
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 56, 20, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.18),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.18),
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  _crop.cropType.name[0].toUpperCase(),
                                  style: const TextStyle(
                                      fontSize: 26,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(_crop.cropName,
                                        style: const TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.white)),
                                    if (_crop.plotCode != null)
                                      Text('PLOT ${_crop.plotCode}',
                                          style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 12)),
                                  ]),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: _statusColor(_crop.status)
                                    .withOpacity(0.92),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _crop.status.name.toUpperCase(),
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 10),
                              ),
                            ),
                          ]),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.24),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.16),
                              ),
                            ),
                            child: Row(children: [
                              Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text('Health Score',
                                          style: TextStyle(
                                              color: Colors.white70,
                                              fontSize: 11)),
                                      Text(
                                        '${score.toStringAsFixed(0)}%',
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 24,
                                            fontWeight: FontWeight.w800),
                                      ),
                                      const SizedBox(height: 4),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(3),
                                        child: LinearProgressIndicator(
                                          value: score / 100,
                                          minHeight: 5,
                                          backgroundColor:
                                              Colors.white.withOpacity(0.25),
                                          valueColor:
                                              const AlwaysStoppedAnimation(
                                                  Colors.white),
                                        ),
                                      ),
                                    ]),
                              ),
                              const SizedBox(width: 16),
                              SizedBox(
                                width: 104,
                                height: 64,
                                child: _HeaderTrendCard(spots: spots),
                              ),
                            ]),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            bottom: TabBar(
              controller: _tabs,
              indicatorColor: Colors.white,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white60,
              labelStyle:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              tabs: const [
                Tab(text: 'Overview'),
                Tab(text: 'Daily Plan'),
                Tab(text: 'Progress'),
                Tab(text: 'Diagnoses'),
              ],
            ),
          ),
        ],
        body: SafeArea(
          top: false,
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.primary))
              : TabBarView(
                  controller: _tabs,
                  children: [
                    _OverviewTab(
                      crop: _crop,
                      diagnoses: _diagnoses,
                      chatHistory: _chatHistory,
                    ),
                    _DailyPlanTab(
                      crop: _crop,
                      tasks: _tasks,
                      treatments: _treatments,
                      onTaskComplete: _showCheckInSheetForTask,
                    ),
                    _ProgressTab(
                      tasks: _tasks,
                      diagnoses: _diagnoses,
                      progress: _progress,
                      healthCurve: _healthCurve,
                      selectedDate: _selectedDate,
                      onDateSelected: (d) => setState(() => _selectedDate = d),
                      onTaskSelected: _onTaskToggled,
                    ),
                    _DiagnosesTab(
                      diagnoses: _diagnoses,
                      chatHistory: _chatHistory,
                      crop: _crop,
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

// ─── Overview Tab ─────────────────────────────────────────────────────────

class _OverviewTab extends StatelessWidget {
  final CropModel crop;
  final List<DiagnosisModel> diagnoses;
  final List<ChatMessageModel> chatHistory;

  const _OverviewTab({
    required this.crop,
    required this.diagnoses,
    required this.chatHistory,
  });

  String _compactSummary(String? raw) {
    final text = (raw ?? '').trim();
    if (text.isEmpty) {
      return 'No initial diagnosis summary has been saved for this crop yet.';
    }

    final collapsed = text.replaceAll(RegExp(r'\s+'), ' ');
    final sentenceBreak = collapsed.indexOf(RegExp(r'[.!?] '));
    final candidate = sentenceBreak != -1
        ? collapsed.substring(0, sentenceBreak + 1)
        : collapsed;

    if (candidate.length <= 180) {
      return candidate;
    }

    return '${candidate.substring(0, 177).trimRight()}...';
  }

  @override
  Widget build(BuildContext context) {
    final latestDx = diagnoses.isNotEmpty ? diagnoses.first : null;
    ChatMessageModel? firstAssistantMessage;
    for (final message in chatHistory) {
      if (message.role == MessageRole.assistant &&
          message.content.trim().isNotEmpty) {
        firstAssistantMessage = message;
        break;
      }
    }
    final conditionSummary = latestDx?.summary?.trim().isNotEmpty == true
        ? _compactSummary(latestDx!.summary)
        : firstAssistantMessage?.content.trim().isNotEmpty == true
            ? _compactSummary(firstAssistantMessage!.content)
            : crop.notes?.trim().isNotEmpty == true
                ? _compactSummary(crop.notes)
                : _compactSummary(null);

    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.of(context).padding.bottom,
      ),
      children: [
        if (latestDx != null) ...[
          const _SectionHeader('Condition Summary'),
          const SizedBox(height: 8),
          _DiagnosisSummaryCard(
            diagnosis: latestDx,
            summaryOverride: conditionSummary,
          ),
          const SizedBox(height: 16),
        ],
        if (latestDx == null) ...[
          const _SectionHeader('Initial Condition'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              conditionSummary,
              style: const TextStyle(
                color: AppColors.textGray,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        const _SectionHeader('Crop Details'),
        const SizedBox(height: 8),
        _InfoCard(items: [
          _InfoRow(
            icon: Icons.location_on,
            label: 'Location',
            value: crop.locationLabel?.trim().isNotEmpty == true
                ? crop.locationLabel!
                : 'Not set',
          ),
          _InfoRow(
            icon: Icons.category,
            label: 'Crop Type',
            value: crop.cropType.name[0].toUpperCase() +
                crop.cropType.name.substring(1),
          ),
          if (crop.plotCode != null)
            _InfoRow(
                icon: Icons.grid_view,
                label: 'Plot Code',
                value: crop.plotCode!),
          _InfoRow(
            icon: Icons.calendar_today,
            label: 'Planted',
            value: crop.plantedAt != null
                ? DateFormat('MMMM d, yyyy').format(crop.plantedAt!)
                : 'Not recorded',
          ),
          if (crop.lastCheckedAt != null)
            _InfoRow(
              icon: Icons.check_circle_outline,
              label: 'Last Checked',
              value: DateFormat('MMM d, y HH:mm').format(crop.lastCheckedAt!),
            ),
        ]),
        if (crop.notes != null && crop.notes!.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(12)),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Notes',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 8),
              Text(crop.notes!,
                  style:
                      const TextStyle(color: AppColors.textGray, height: 1.5)),
            ]),
          ),
        ],
      ],
    );
  }
}

class _DiagnosisSummaryCard extends StatelessWidget {
  final DiagnosisModel diagnosis;
  final String? summaryOverride;
  const _DiagnosisSummaryCard({
    required this.diagnosis,
    this.summaryOverride,
  });

  Color get _severityColor {
    switch (diagnosis.severity) {
      case Severity.mild:
        return Colors.green;
      case Severity.moderate:
        return Colors.orange;
      case Severity.severe:
        return Colors.red;
      default:
        return AppColors.textGray;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: _severityColor, width: 4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(humanizeDiseaseLabel(diagnosis.diseaseName),
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _severityColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _severityColor.withOpacity(0.4)),
            ),
            child: Text(
              diagnosis.severity.name.toUpperCase(),
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _severityColor),
            ),
          ),
        ]),
        if ((summaryOverride ?? diagnosis.summary)?.isNotEmpty == true) ...[
          const SizedBox(height: 8),
          Text(summaryOverride ?? diagnosis.summary!,
              style: const TextStyle(
                  color: AppColors.textGray, fontSize: 13, height: 1.4)),
        ],
        const SizedBox(height: 6),
        Text(DateFormat('MMM d, yyyy').format(diagnosis.diagnosedAt),
            style:
                const TextStyle(color: AppColors.textLightGray, fontSize: 12)),
      ]),
    );
  }
}

// ─── Daily Plan Tab ───────────────────────────────────────────────────────

class _DailyPlanTab extends StatelessWidget {
  final CropModel crop;
  final List<TreatmentTaskModel> tasks;
  final List<TreatmentModel> treatments;
  final Future<void> Function(TreatmentTaskModel task) onTaskComplete;

  const _DailyPlanTab({
    required this.crop,
    required this.tasks,
    required this.treatments,
    required this.onTaskComplete,
  });

  @override
  Widget build(BuildContext context) {
    final activeTreatment = treatments.isNotEmpty ? treatments.first : null;
    final orderedTasks = [...tasks]..sort((a, b) {
        final dueCompare = a.dueAt.compareTo(b.dueAt);
        if (dueCompare != 0) return dueCompare;
        return (a.taskOrder ?? 0).compareTo(b.taskOrder ?? 0);
      });
    final completedCount = orderedTasks
        .where((task) => task.status == TaskStatus.completed)
        .length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        if (activeTreatment != null) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primaryDark, AppColors.primary],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(children: [
              const Icon(Icons.medical_services, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(activeTreatment.treatmentTitle,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14)),
                      Text(
                        'Day ${_daysSince(activeTreatment)} of '
                        '${activeTreatment.expectedDurationDays ?? '?'}',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12),
                      ),
                    ]),
              ),
            ]),
          ),
          const SizedBox(height: 16),
        ],
        const _SectionHeader("Today's Tasks"),
        const SizedBox(height: 4),
        Text(
          '$completedCount/${orderedTasks.length} completed',
          style: const TextStyle(color: AppColors.textGray, fontSize: 13),
        ),
        const SizedBox(height: 6),
        const Text(
          'Tap the task circle to submit a photo check-in and mark it done.',
          style: TextStyle(
            color: AppColors.textLightGray,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 12),
        if (orderedTasks.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(12)),
            child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.task_alt, size: 40, color: AppColors.primary),
                  SizedBox(height: 8),
                  Text('No tasks yet',
                      style:
                          TextStyle(color: AppColors.textGray, fontSize: 15)),
                  SizedBox(height: 4),
                  Text(
                    'Tasks are created when you add a diagnosis to My Crops',
                    style:
                        TextStyle(color: AppColors.textLightGray, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ]),
          )
        else
          ...orderedTasks.map((task) => _TaskCard(
                task: task,
                onComplete: () => onTaskComplete(task),
              )),
      ],
    );
  }

  int _daysSince(TreatmentModel t) {
    if (t.startedAt == null) return 1;
    return DateTime.now().difference(t.startedAt!).inDays + 1;
  }
}

class _TaskCard extends StatelessWidget {
  final TreatmentTaskModel task;
  final Future<void> Function() onComplete;

  const _TaskCard({
    required this.task,
    required this.onComplete,
  });

  @override
  Widget build(BuildContext context) {
    final isCompleted = task.status == TaskStatus.completed;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final taskDay = DateTime(task.dueAt.year, task.dueAt.month, task.dueAt.day);
    final isFutureTask = taskDay.isAfter(today);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isCompleted ? AppColors.primary.withOpacity(0.07) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCompleted
              ? AppColors.primary.withOpacity(0.4)
              : Colors.grey[200]!,
        ),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          onTap: isCompleted || isFutureTask
              ? null
              : () {
                  onComplete();
                },
          borderRadius: BorderRadius.circular(999),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            width: 24,
            height: 24,
            margin: const EdgeInsets.only(top: 1, right: 12),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isCompleted ? AppColors.primary : Colors.transparent,
              border: Border.all(
                color: isCompleted ? AppColors.primary : Colors.grey[400]!,
                width: 2,
              ),
            ),
            child: isCompleted
                ? const Icon(Icons.check, color: Colors.white, size: 14)
                : null,
          ),
        ),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              task.title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isCompleted ? AppColors.textGray : AppColors.textDark,
                decoration: isCompleted
                    ? TextDecoration.lineThrough
                    : TextDecoration.none,
              ),
            ),
            if (task.description != null && task.description!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                task.description!,
                style: TextStyle(
                  fontSize: 12,
                  color: isCompleted
                      ? AppColors.textLightGray
                      : AppColors.textGray,
                  height: 1.4,
                ),
              ),
            ],
            const SizedBox(height: 4),
            Row(children: [
              Icon(
                isCompleted ? Icons.task_alt : Icons.schedule,
                size: 12,
                color:
                    isCompleted ? AppColors.primary : AppColors.textLightGray,
              ),
              const SizedBox(width: 4),
              Text(
                isCompleted
                    ? 'Completed ${task.completedAt != null ? DateFormat('MMM d').format(task.completedAt!) : 'today'}'
                    : isFutureTask
                        ? 'Available: ${DateFormat('MMM d').format(task.dueAt)}'
                        : 'Due: ${DateFormat('MMM d').format(task.dueAt)}',
                style: TextStyle(
                  fontSize: 11,
                  color: isCompleted
                      ? AppColors.primary
                      : isFutureTask
                          ? Colors.orange
                          : AppColors.textLightGray,
                ),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }
}

// ─── Progress Tab ─────────────────────────────────────────────────────────

class _ProgressTab extends StatelessWidget {
  final List<TreatmentTaskModel> tasks;
  final List<DiagnosisModel> diagnoses;
  final List<ProgressUpdateModel> progress;
  final List<HealthScorePoint> healthCurve;
  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateSelected;
  final ValueChanged<TreatmentTaskModel> onTaskSelected;

  const _ProgressTab({
    required this.tasks,
    required this.diagnoses,
    required this.progress,
    required this.healthCurve,
    required this.selectedDate,
    required this.onDateSelected,
    required this.onTaskSelected,
  });

  @override
  Widget build(BuildContext context) {
    final evolutionEntries = _visualEvolutionEntries();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        CalendarTracker(
          tasks: tasks,
          selectedDate: selectedDate,
          onDateSelected: onDateSelected,
          onTaskToggled: onTaskSelected,
        ),
        const SizedBox(height: 16),
        _buildAiAnalysisCard(),
        const SizedBox(height: 16),
        HealthScoreGraph(
          points: healthCurve,
          selectedDate: selectedDate,
          onPointTap: onDateSelected,
        ),
        const SizedBox(height: 16),
        const _SectionHeader('Visual Evolution'),
        const SizedBox(height: 8),
        if (evolutionEntries.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(12)),
            child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.timeline,
                      size: 40, color: AppColors.textLightGray),
                  SizedBox(height: 8),
                  Text('No check-ins yet',
                      style:
                          TextStyle(color: AppColors.textGray, fontSize: 15)),
                  SizedBox(height: 4),
                  Text(
                    'Upload photo check-ins from the Daily Plan tab to build the treatment timeline.',
                    style:
                        TextStyle(color: AppColors.textLightGray, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ]),
          )
        else
          SizedBox(
            height: 230,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: evolutionEntries.length,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (_, index) => _VisualEvolutionCard(
                entry: evolutionEntries[index],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildAiAnalysisCard() {
    // Find the most recent progress update that has a real AI assessment
    // (i.e. not an offline/pending stub).
    final latestUpdate = progress
        .where((u) =>
            u.progressStatus != ProgressStatus.insufficientData &&
            u.note != null &&
            u.note!.trim().isNotEmpty)
        .fold<ProgressUpdateModel?>(
          null,
          (prev, u) =>
              prev == null || u.updateDate.isAfter(prev.updateDate) ? u : prev,
        );

    final assessment = latestUpdate?.note;
    final score = latestUpdate?.healthScore;
    final status = latestUpdate?.progressStatus;
    final updateDate = latestUpdate?.updateDate;

    Color scoreColor(double s) {
      if (s >= 70) return Colors.green;
      if (s >= 40) return Colors.orange;
      return Colors.red;
    }

    String statusLabel(ProgressStatus s) {
      switch (s) {
        case ProgressStatus.improving:
          return 'Improving';
        case ProgressStatus.worsening:
          return 'Needs Attention';
        case ProgressStatus.stable:
          return 'Stable';
        default:
          return '';
      }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.psychology_outlined,
                  color: AppColors.primary, size: 18),
              const SizedBox(width: 8),
              const Text(
                'AI Analysis',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const Spacer(),
              if (updateDate != null)
                Text(
                  DateFormat('MMM d, y').format(updateDate),
                  style: const TextStyle(
                      color: AppColors.textGray, fontSize: 12),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (assessment != null) ...[
            Text(
              assessment,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textDark, height: 1.4),
            ),
            if (score != null || status != null) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (score != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: scoreColor(score).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${score.toStringAsFixed(0)}% health',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: scoreColor(score),
                        ),
                      ),
                    ),
                  if (status != null && status != ProgressStatus.insufficientData)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        statusLabel(status),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ] else
            const Text(
              'No AI analysis yet. Complete a daily check-in to see the latest assessment here.',
              style:
                  TextStyle(fontSize: 13, color: AppColors.textGray, height: 1.4),
            ),
        ],
      ),
    );
  }

  List<_VisualEvolutionEntry> _visualEvolutionEntries() {
    final rowsByDay = <DateTime, _VisualEvolutionEntry>{};

    final sortedDiagnoses = [...diagnoses]
      ..sort((a, b) => a.diagnosedAt.compareTo(b.diagnosedAt));
    for (final diagnosis in sortedDiagnoses) {
      final imageRef = diagnosis.imageUrl?.trim();
      if (imageRef == null || imageRef.isEmpty) {
        continue;
      }
      final day = DateTime(
        diagnosis.diagnosedAt.year,
        diagnosis.diagnosedAt.month,
        diagnosis.diagnosedAt.day,
      );
      rowsByDay[day] = _VisualEvolutionEntry(
        date: day,
        imageRef: imageRef,
        headline: humanizeDiseaseLabel(diagnosis.diseaseName),
        caption: diagnosis.summary?.trim(),
      );
      break;
    }

    final sortedProgress = [...progress]
      ..sort((a, b) => a.updateDate.compareTo(b.updateDate));
    for (final update in sortedProgress) {
      final imageRef = update.imageUrl?.trim();
      if (imageRef == null || imageRef.isEmpty) {
        continue;
      }
      final day = DateTime(
        update.updateDate.year,
        update.updateDate.month,
        update.updateDate.day,
      );
      rowsByDay[day] = _VisualEvolutionEntry(
        date: day,
        imageRef: imageRef,
        headline: _statusLabel(update.progressStatus),
        caption: update.note?.trim().isNotEmpty == true
            ? update.note!.trim()
            : update.detectedDiseaseName?.trim(),
      );
    }

    final entries = rowsByDay.values.toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    if (entries.isEmpty) {
      return const [];
    }

    final firstDay = entries.first.date;
    return entries
        .map(
          (entry) => entry.copyWith(
            dayNumber: entry.date.difference(firstDay).inDays + 1,
            isToday: DateUtils.isSameDay(entry.date, DateTime.now()),
          ),
        )
        .toList(growable: false);
  }

  String _statusLabel(ProgressStatus status) {
    switch (status) {
      case ProgressStatus.improving:
        return 'Improving';
      case ProgressStatus.worsening:
        return 'Needs Attention';
      case ProgressStatus.stable:
        return 'Stable';
      default:
        return 'Update';
    }
  }
}

class _VisualEvolutionEntry {
  final DateTime date;
  final String imageRef;
  final String headline;
  final String? caption;
  final int dayNumber;
  final bool isToday;

  const _VisualEvolutionEntry({
    required this.date,
    required this.imageRef,
    required this.headline,
    this.caption,
    this.dayNumber = 1,
    this.isToday = false,
  });

  _VisualEvolutionEntry copyWith({
    int? dayNumber,
    bool? isToday,
  }) {
    return _VisualEvolutionEntry(
      date: date,
      imageRef: imageRef,
      headline: headline,
      caption: caption,
      dayNumber: dayNumber ?? this.dayNumber,
      isToday: isToday ?? this.isToday,
    );
  }
}

class _VisualEvolutionCard extends StatelessWidget {
  final _VisualEvolutionEntry entry;

  const _VisualEvolutionCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            child: AppImageReference(
              imageRef: entry.imageRef,
              width: double.infinity,
              height: 150,
              fit: BoxFit.cover,
              placeholder: Container(
                height: 150,
                color: Colors.grey[200],
                child: const Center(
                  child: Icon(Icons.image, color: Colors.grey),
                ),
              ),
              errorWidget: Container(
                height: 150,
                color: Colors.grey[200],
                child: const Center(
                  child: Icon(Icons.broken_image, color: Colors.grey),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.isToday
                      ? 'DAY ${entry.dayNumber} (TODAY)'
                      : 'DAY ${entry.dayNumber}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                    color: entry.isToday ? AppColors.primaryDark : AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  entry.headline,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  DateFormat('MMM d, yyyy').format(entry.date),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textGray,
                  ),
                ),
                if (entry.caption != null && entry.caption!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    entry.caption!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      color: AppColors.textGray,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  final ProgressUpdateModel update;
  const _ProgressCard({required this.update});

  Color get _statusColor {
    switch (update.progressStatus) {
      case ProgressStatus.improving:
        return Colors.green;
      case ProgressStatus.worsening:
        return Colors.red;
      case ProgressStatus.stable:
        return Colors.orange;
      default:
        return AppColors.textGray;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: _statusColor, width: 4)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (update.imageUrl != null && update.imageUrl!.isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: AppImageReference(
              imageRef: update.imageUrl!,
              width: 64,
              height: 64,
              fit: BoxFit.cover,
              placeholder: Container(
                  width: 64,
                  height: 64,
                  color: Colors.grey[200],
                  child: const Icon(Icons.image, color: Colors.grey)),
              errorWidget: Container(
                  width: 64,
                  height: 64,
                  color: Colors.grey[200],
                  child: const Icon(Icons.broken_image, color: Colors.grey)),
            ),
          )
        else
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.image_not_supported,
                color: Colors.grey, size: 28),
          ),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(
                '${(update.healthScore ?? 0).toStringAsFixed(0)}%',
                style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: AppColors.textDark),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  update.progressStatus.name,
                  style: TextStyle(
                      fontSize: 11,
                      color: _statusColor,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ]),
            const SizedBox(height: 4),
            Text(
              DateFormat('MMM d, yyyy  HH:mm').format(update.createdAt),
              style:
                  const TextStyle(fontSize: 12, color: AppColors.textLightGray),
            ),
            if ((update.detectedDiseaseName ?? '').isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                humanizeDiseaseLabel(update.detectedDiseaseName!),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textDark,
                ),
              ),
            ],
            if (update.completedTaskCount > 0 ||
                update.missedTaskCount > 0) ...[
              const SizedBox(height: 6),
              Text(
                'Tasks completed: ${update.completedTaskCount} • Missed: ${update.missedTaskCount}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textGray,
                ),
              ),
            ],
            if (update.note != null && update.note!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(update.note!,
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textGray, height: 1.4),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis),
            ],
          ]),
        ),
      ]),
    );
  }
}

// ─── Diagnoses Tab ────────────────────────────────────────────────────────

class _DiagnosesTab extends StatelessWidget {
  final List<DiagnosisModel> diagnoses;
  final List<ChatMessageModel> chatHistory;
  final CropModel crop;

  const _DiagnosesTab({
    required this.diagnoses,
    required this.chatHistory,
    required this.crop,
  });

  Color _severityColor(Severity s) {
    switch (s) {
      case Severity.mild:
        return Colors.green;
      case Severity.moderate:
        return Colors.orange;
      case Severity.severe:
        return Colors.red;
      default:
        return AppColors.textGray;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasDiagnoses = diagnoses.isNotEmpty;
    final hasHistory = chatHistory.isNotEmpty;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            children: [
              // ── Latest diagnoses section ──
              if (hasDiagnoses) ...[
                const _SectionHeader('AI Diagnoses'),
                const SizedBox(height: 8),
                ...diagnoses.map((d) => InkWell(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChatScreen(
                            cropId: crop.id,
                            startFreshSession: false,
                          ),
                        ),
                      ),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border(
                            left: BorderSide(
                                color: _severityColor(d.severity), width: 4)),
                      ),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Expanded(
                                child: Text(humanizeDiseaseLabel(d.diseaseName),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15)),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _severityColor(d.severity)
                                      .withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                      color: _severityColor(d.severity)
                                          .withOpacity(0.4)),
                                ),
                                child: Text(
                                  d.severity.name.toUpperCase(),
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: _severityColor(d.severity)),
                                ),
                              ),
                            ]),
                            if (d.confidenceScore != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Confidence: ${(d.confidenceScore! * 100).toStringAsFixed(1)}%',
                                style: const TextStyle(
                                    fontSize: 12, color: AppColors.textGray),
                              ),
                            ],
                            const SizedBox(height: 4),
                            Text(
                              DateFormat('MMM d, yyyy').format(d.diagnosedAt),
                              style: const TextStyle(
                                  fontSize: 12, color: AppColors.textLightGray),
                            ),
                            if (d.summary != null && d.summary!.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(d.summary!,
                                  style: const TextStyle(
                                      color: AppColors.textGray,
                                      fontSize: 13,
                                      height: 1.4),
                                  maxLines: 4,
                                  overflow: TextOverflow.ellipsis),
                            ],
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Text('View conversation',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.w600)),
                                const SizedBox(width: 4),
                                Icon(Icons.chevron_right,
                                    size: 16, color: AppColors.primary),
                              ],
                            ),
                          ]),
                      ),
                    )),
                const SizedBox(height: 8),
              ],

              // ── Chat history section ──
              if (hasHistory) ...[
                const _SectionHeader('Conversation History'),
                const SizedBox(height: 8),
                ...chatHistory.map((msg) => _ChatBubble(message: msg)),
                const SizedBox(height: 8),
              ],

              if (!hasDiagnoses && !hasHistory)
                const SizedBox(
                  height: 260,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.biotech_outlined,
                            size: 56, color: AppColors.textLightGray),
                        SizedBox(height: 12),
                        Text('No history yet',
                            style: TextStyle(
                                color: AppColors.textGray, fontSize: 16)),
                        SizedBox(height: 4),
                        Text(
                          'Start a chat to get AI advice for this crop',
                          style: TextStyle(
                              color: AppColors.textLightGray, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),

        // ── Crop Chat Field ──
        _CropChatBar(crop: crop),
      ],
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final ChatMessageModel message;
  const _ChatBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == MessageRole.user;
    return Padding(
      padding: EdgeInsets.only(
        bottom: 10,
        left: isUser ? 40 : 0,
        right: isUser ? 0 : 40,
      ),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(
              width: 28,
              height: 28,
              margin: const EdgeInsets.only(top: 2, right: 6),
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.smart_toy, color: Colors.white, size: 16),
            ),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isUser ? AppColors.primary : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(14),
                  topRight: const Radius.circular(14),
                  bottomLeft: Radius.circular(isUser ? 14 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 14),
                ),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 4,
                      offset: const Offset(0, 2)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (message.imageUrl != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: AppImageReference(
                        imageRef: message.imageUrl!,
                        width: 180,
                        fit: BoxFit.cover,
                      ),
                    ),
                  if (message.imageUrl != null && message.content.isNotEmpty)
                    const SizedBox(height: 6),
                  if (message.content.isNotEmpty)
                    Text(
                      message.content,
                      style: TextStyle(
                        color: isUser ? Colors.white : AppColors.textDark,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('MMM d  HH:mm').format(message.createdAt),
                    style: TextStyle(
                      fontSize: 10,
                      color: isUser ? Colors.white60 : AppColors.textLightGray,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Inline chat bar that opens ChatScreen for this specific crop.
class _CropChatBar extends StatelessWidget {
  final CropModel crop;
  const _CropChatBar({required this.crop});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 8,
              offset: const Offset(0, -2)),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChatScreen(
                    cropId: crop.id,
                    cropName: crop.cropName,
                    startFreshSession: false,
                  ),
                ),
              ),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(24),
                  border:
                      Border.all(color: AppColors.primary.withOpacity(0.25)),
                ),
                child: Text(
                  'Ask AI about ${crop.cropName}…',
                  style:
                      const TextStyle(color: AppColors.textGray, fontSize: 14),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChatScreen(
                  cropId: crop.id,
                  cropName: crop.cropName,
                  startFreshSession: false,
                ),
              ),
            ),
            borderRadius: BorderRadius.circular(24),
            child: Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.chat_bubble_outline,
                  color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Check-in Bottom Sheet ─────────────────────────────────────────────────

class _CheckInSheet extends StatefulWidget {
  final CropModel crop;
  final List<TreatmentTaskModel> allTasks;
  final List<TreatmentTaskModel> checkedTasks;
  final TreatmentModel? activeTreatment;
  final DiagnosisModel? latestDiagnosis;
  final ProgressUpdateModel? previousUpdate;
  final Future<void> Function(
    double score,
    ProgressStatus status,
    ProgressUpdateModel update,
  ) onSubmitted;

  const _CheckInSheet({
    required this.crop,
    required this.allTasks,
    required this.checkedTasks,
    required this.activeTreatment,
    required this.latestDiagnosis,
    required this.previousUpdate,
    required this.onSubmitted,
  });

  @override
  State<_CheckInSheet> createState() => _CheckInSheetState();
}

class _CheckInSheetState extends State<_CheckInSheet> {
  Uint8List? _photoBytes;
  final _noteCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final file =
        await picker.pickImage(source: ImageSource.camera, imageQuality: 75);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() => _photoBytes = bytes);
  }

  Future<void> _submit() async {
    if (_photoBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please take a photo before submitting.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      final user = context.read<AuthProvider>().currentUser;
      final aiBackend = context.read<AiBackendService>();
      final cropsProvider = context.read<CropsProvider>();
      final submittedAt = DateTime.now();
      final imageUrl = buildInlineImageDataUrl(_photoBytes!);

      final days = widget.activeTreatment?.startedAt != null
          ? DateTime.now().difference(widget.activeTreatment!.startedAt!).inDays
          : 0;

      late final double newScore;
      late final ProgressStatus newStatus;
      late final String assessment;
      final connectivity = context.read<ConnectivityService>();
      final isOnline = await connectivity.isConnected;
      if (!isOnline) {
        // Offline – store the photo without GPT analysis; score unchanged
        // until the user is back online and re-analysis runs.
        newScore = widget.crop.latestHealthScore ?? 50.0;
        newStatus = ProgressStatus.insufficientData;
        assessment = 'Offline check-in — AI analysis pending. Will be updated when online.';
      } else {
        // Avoid sending a huge base64 data URL as the previous reference —
        // only pass real remote URLs to keep the request payload small.
        final prevImgUrl = widget.previousUpdate?.imageUrl;
        final safePrevImgRef = (prevImgUrl != null && isInlineImageDataUrl(prevImgUrl))
            ? null
            : prevImgUrl;
        try {
          final aiResponse = await aiBackend.assessCropHealth(
            cropType: widget.crop.cropType.name,
            diseaseName:
                widget.activeTreatment?.diseaseName ?? widget.crop.cropName,
            daysSinceTreatment: days,
            imageBytes: _photoBytes!.toList(),
            imageMimeType: 'image/jpeg',
            previousImageReference: safePrevImgRef,
            previousAssessment: widget.previousUpdate?.note,
            previousProgressStatus: widget.previousUpdate?.progressStatus.value,
            previousUpdateDate:
                widget.previousUpdate?.updateDate.toIso8601String(),
            completedTasks: widget.checkedTasks.map((t) => t.title).toList(),
            note: _noteCtrl.text.trim().isNotEmpty ? _noteCtrl.text.trim() : null,
            currentHealthScore: widget.crop.latestHealthScore,
          );
          if (!aiResponse.accepted) {
            if (mounted) {
              setState(() => _submitting = false);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    aiResponse.rejectionReason ??
                        'This photo does not match your tracked crop well enough. Please retake the check-in photo.',
                  ),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
            return;
          }
          newScore = aiResponse.healthScore;
          newStatus = _progressStatusFromBackend(aiResponse.progressStatus);
          assessment = aiResponse.assessment;
        } catch (_) {
          // Online but AI call failed (timeout, server error, etc.).
          // Save the check-in and let _analyzePendingCheckIns re-analyse later.
          newScore = widget.crop.latestHealthScore ?? 50.0;
          newStatus = ProgressStatus.insufficientData;
          assessment = 'Check-in saved — AI analysis pending. Score will update automatically.';
        }
      }

      for (final task in widget.checkedTasks) {
        await cropsProvider.markTaskDone(
          task.id,
          recomputeHealthScore: false,
          syncNow: false,
        );
      }

      final progressUpdate = ProgressUpdateModel(
        id: submittedAt.millisecondsSinceEpoch.toString(),
        cropId: widget.crop.id,
        treatmentId: widget.activeTreatment?.id,
        diagnosisId: widget.latestDiagnosis?.id,
        userId: user?.id ?? '',
        updateSource: UpdateSource.image,
        healthScore: newScore,
        progressStatus: newStatus,
        detectedDiseaseName: widget.latestDiagnosis?.diseaseName ??
          widget.activeTreatment?.diseaseName,
        detectedSeverity: widget.latestDiagnosis?.severity,
        note: _noteCtrl.text.trim().isNotEmpty
            ? _noteCtrl.text.trim()
            : assessment,
        imageUrl: imageUrl,
        completedTaskCount: widget.checkedTasks.length,
        missedTaskCount: 0,
        updateDate: submittedAt,
        createdAt: submittedAt,
        updatedAt: submittedAt,
      );

      await widget.onSubmitted(newScore, newStatus, progressUpdate);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  ProgressStatus _progressStatusFromBackend(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'improving':
        return ProgressStatus.improving;
      case 'declining':
      case 'critical':
      case 'worsening':
        return ProgressStatus.worsening;
      case 'insufficient_data':
        return ProgressStatus.insufficientData;
      case 'stable':
      default:
        return ProgressStatus.stable;
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, sc) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 16),
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              Icon(Icons.add_a_photo, color: AppColors.primary),
              SizedBox(width: 10),
              Text('Daily Check-in',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ]),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              controller: sc,
              padding: const EdgeInsets.all(20),
              children: [
                if (widget.checkedTasks.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            const Icon(Icons.check_circle,
                                color: AppColors.primary, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              widget.checkedTasks.length == 1
                                  ? 'Task to complete today'
                                  : '${widget.checkedTasks.length} tasks to complete',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary,
                                  fontSize: 13),
                            ),
                          ]),
                          const SizedBox(height: 6),
                          ...widget.checkedTasks.map((t) => Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text('• ',
                                          style: TextStyle(
                                              color: AppColors.primary)),
                                      Expanded(
                                          child: Text(t.title,
                                              style: const TextStyle(
                                                  fontSize: 12,
                                                  color: AppColors.textGray))),
                                    ]),
                              )),
                        ]),
                  ),
                  const SizedBox(height: 16),
                ],
                const Text('Crop Photo *',
                    style:
                        TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: _pickPhoto,
                  child: Container(
                    height: 180,
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _photoBytes != null
                            ? AppColors.primary
                            : Colors.grey[300]!,
                        width: _photoBytes != null ? 2 : 1,
                      ),
                    ),
                    child: _photoBytes != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(13),
                            child:
                                Image.memory(_photoBytes!, fit: BoxFit.cover),
                          )
                        : const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.camera_alt,
                                  size: 40, color: AppColors.textLightGray),
                              SizedBox(height: 8),
                              Text('Tap to take a photo',
                                  style: TextStyle(
                                      color: AppColors.textGray, fontSize: 14)),
                              SizedBox(height: 4),
                              Text('Required for AI analysis',
                                  style: TextStyle(
                                      color: AppColors.textLightGray,
                                      fontSize: 12)),
                            ],
                          ),
                  ),
                ),
                if (_photoBytes != null) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _pickPhoto,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Retake'),
                  ),
                ],
                const SizedBox(height: 16),
                const Text('Notes (optional)',
                    style:
                        TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 8),
                TextField(
                  controller: _noteCtrl,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'How does the crop look today? Any changes?',
                    filled: true,
                    fillColor: Colors.grey[100],
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Text('Submit & Analyze',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

// ─── Shared Widgets ───────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) => Text(title,
      style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: AppColors.textDark));
}

class _InfoCard extends StatelessWidget {
  final List<_InfoRow> items;
  const _InfoCard({required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: items
            .map((row) => Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(children: [
                    Icon(row.icon, size: 18, color: AppColors.primary),
                    const SizedBox(width: 12),
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(row.label,
                              style: const TextStyle(
                                  fontSize: 11, color: AppColors.textGray)),
                          Text(row.value,
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textDark)),
                        ]),
                  ]),
                ))
            .toList(),
      ),
    );
  }
}

class _InfoRow {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow(
      {required this.icon, required this.label, required this.value});
}

class _HeaderTrendCard extends StatelessWidget {
  final List<FlSpot> spots;

  const _HeaderTrendCard({required this.spots});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.all(8),
      child: LineChart(
        LineChartData(
          gridData: const FlGridData(show: false),
          titlesData: const FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: Colors.white,
              barWidth: 2,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: Colors.white.withOpacity(0.15),
              ),
            ),
          ],
          minY: 0,
          maxY: 100,
        ),
      ),
    );
  }
}

class _TaskCelebrationDialog extends StatelessWidget {
  final String taskTitle;

  const _TaskCelebrationDialog({required this.taskTitle});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 280,
          margin: const EdgeInsets.symmetric(horizontal: 24),
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.16),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.85, end: 1.0),
                duration: const Duration(milliseconds: 450),
                curve: Curves.elasticOut,
                builder: (_, scale, child) => Transform.scale(
                  scale: scale,
                  child: child,
                ),
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.celebration,
                    color: AppColors.primary,
                    size: 36,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Nice work!',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '"$taskTitle" is now complete. Keep the momentum going.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: AppColors.textGray,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _CompletionDialogAction { done, dashboard }

enum _ReassessmentDialogAction { extend, moveToCompleted }

class _TreatmentCompletedDialog extends StatefulWidget {
  final String cropName;
  final double latestScore;

  const _TreatmentCompletedDialog({
    required this.cropName,
    required this.latestScore,
  });

  @override
  State<_TreatmentCompletedDialog> createState() =>
      _TreatmentCompletedDialogState();
}

class _TreatmentCompletedDialogState extends State<_TreatmentCompletedDialog> {
  late final ConfettiController _confetti;

  @override
  void initState() {
    super.initState();
    _confetti = ConfettiController(
      duration: const Duration(seconds: 3),
    )..play();
  }

  @override
  void dispose() {
    _confetti.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: ConfettiWidget(
                confettiController: _confetti,
                blastDirection: math.pi / 2,
                emissionFrequency: 0.05,
                numberOfParticles: 24,
                maxBlastForce: 14,
                minBlastForce: 5,
                gravity: 0.22,
                shouldLoop: false,
                colors: const [
                  Color(0xFFFFC727),
                  Color(0xFF6BCB77),
                  Color(0xFF4D96FF),
                  Color(0xFFFF6B6B),
                  Color(0xFFB980F0),
                ],
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.only(top: 36),
            padding: const EdgeInsets.fromLTRB(24, 36, 24, 24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFF9FBEF), Color(0xFFF2F8D7), Colors.white],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.14),
                  blurRadius: 30,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 92,
                  height: 92,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF8DCE3B), Color(0xFF5AA11E)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF8DCE3B).withOpacity(0.35),
                        blurRadius: 24,
                        spreadRadius: 6,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: Colors.white,
                    size: 54,
                  ),
                ),
                const SizedBox(height: 22),
                const Text(
                  'Well done!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    color: AppColors.primaryDark,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '${widget.cropName} completed its treatment plan with a ${widget.latestScore.toStringAsFixed(0)} health score. The crop is ready to move into your treated crops section.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.55,
                    color: AppColors.textGray,
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF5CC),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.favorite, color: AppColors.primary, size: 26),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Your plant is thriving thanks to your daily care.',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primaryDark,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(
                          _CompletionDialogAction.done,
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primaryDark,
                          side: const BorderSide(color: AppColors.primaryLight),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text('Done'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).pop(
                          _CompletionDialogAction.dashboard,
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text('Go to Dashboard'),
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
}

class _TreatmentReassessmentDialog extends StatelessWidget {
  final String cropName;
  final double latestScore;
  final bool isDownwardTrend;
  final String explanation;
  final List<String> suggestedActions;
  final List<String> sources;
  final bool canExtend;

  const _TreatmentReassessmentDialog({
    required this.cropName,
    required this.latestScore,
    required this.isDownwardTrend,
    required this.explanation,
    required this.suggestedActions,
    required this.sources,
    required this.canExtend,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 18, 24, 12),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      title: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.insights_rounded,
              color: Colors.orange,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              isDownwardTrend
                  ? 'Recovery needs more help'
                  : 'Treatment finished, but not healed yet',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$cropName closed the current timeline at ${latestScore.toStringAsFixed(0)} health score.',
              style: const TextStyle(
                color: AppColors.textGray,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                explanation,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: AppColors.textDark,
                ),
              ),
            ),
            if (suggestedActions.isNotEmpty) ...[
              const SizedBox(height: 18),
              const Text(
                'Suggested extended treatment',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 10),
              ...suggestedActions.asMap().entries.map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: AppColors.backgroundGreenLight,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '${entry.key + 1}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              entry.value,
                              style: const TextStyle(
                                fontSize: 13,
                                height: 1.45,
                                color: AppColors.textGray,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
            ],
            if (sources.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text(
                'Legit sources',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 8),
              ...sources.take(4).map(
                    (source) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.link_rounded,
                            size: 16,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              source,
                              style: const TextStyle(
                                fontSize: 12,
                                height: 1.4,
                                color: AppColors.textGray,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(
            _ReassessmentDialogAction.moveToCompleted,
          ),
          child: const Text('Move to Completed'),
        ),
        FilledButton(
          onPressed: canExtend
              ? () => Navigator.of(context).pop(
                    _ReassessmentDialogAction.extend,
                  )
              : null,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
          ),
          child: const Text('Extend Tracking'),
        ),
      ],
    );
  }
}

class _TreatmentArchivedDialog extends StatelessWidget {
  final String cropName;

  const _TreatmentArchivedDialog({required this.cropName});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Text(
        'Moved to Completed',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
      content: Text(
        '$cropName was moved to your completed crops section under the needs-help outcome so you can revisit it later if needed.',
        style: const TextStyle(height: 1.5, color: AppColors.textGray),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(_CompletionDialogAction.done),
          child: const Text('Done'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            _CompletionDialogAction.dashboard,
          ),
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          child: const Text('Go to Dashboard'),
        ),
      ],
    );
  }
}
