import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_enums.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/label_formatter.dart';
import '../../../data/models/chat_message_model.dart';
import '../../../data/models/chat_session_model.dart';
import '../../../data/models/crop_model.dart';
import '../../../data/models/diagnosis_model.dart';
import '../../../data/models/progress_update_model.dart';
import '../../../data/models/treatment_model.dart';
import '../../../data/models/treatment_task_model.dart';
import '../../../data/remote/ai_backend_service.dart';
import '../../../data/remote/supabase_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../../chat/screens/chat_screen.dart';
import '../providers/crops_provider.dart';
import 'add_crop_screen.dart';
import '../../../services/health_score_service.dart';
import '../../../services/notification_service.dart';
import '../widgets/calendar_tracker.dart';
import '../widgets/health_score_graph.dart';

class CropDetailScreen extends StatefulWidget {
  final CropModel crop;
  final int? initialTabIndex;          // 0..3 to override default tab
  final DateTime? initialSelectedDate; // for calendar deep-linking from notifications

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

  List<HealthScorePoint> get _healthCurve => HealthScoreService.compute14DayCurve(
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

  Future<void> _loadData() async {
    final svc = context.read<SupabaseService>();
    final rawDx = await _runOrFallback(
      () => svc.getDiagnosesByCrop(_crop.id),
      <Map<String, dynamic>>[],
    );
    final rawTx = await _runOrFallback(
      () => svc.getTreatmentsByCrop(_crop.id),
      <Map<String, dynamic>>[],
    );
    final rawProgress = await _runOrFallback(
      () => svc.getProgressUpdates(_crop.id),
      <Map<String, dynamic>>[],
    );

    final treatments = rawTx.map(TreatmentModel.fromMap).toList();
    final allTasks = <TreatmentTaskModel>[];
    for (final treatment in treatments) {
      final rawTasks = await _runOrFallback(
        () => svc.getTreatmentTasks(treatment.id),
        <Map<String, dynamic>>[],
      );
      allTasks.addAll(rawTasks.map(TreatmentTaskModel.fromMap));
    }
    allTasks.sort((a, b) {
      final dueCompare = a.dueAt.compareTo(b.dueAt);
      if (dueCompare != 0) return dueCompare;
      return (a.taskOrder ?? 0).compareTo(b.taskOrder ?? 0);
    });

    final rawSessions = await _runOrFallback(
      () => svc.getChatSessionsByCrop(_crop.id),
      <Map<String, dynamic>>[],
    );
    final sessions = rawSessions.map(ChatSessionModel.fromMap).toList();
    final allMessages = <ChatMessageModel>[];
    for (final session in sessions) {
      final rawMessages = await _runOrFallback(
        () => svc.getChatMessages(session.id),
        <Map<String, dynamic>>[],
      );
      allMessages.addAll(rawMessages.map(ChatMessageModel.fromMap));
    }
    allMessages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final historyMessages = allMessages
        .where((message) => message.role != MessageRole.system)
        .toList();

    if (!mounted) return;
    setState(() {
      _diagnoses = rawDx.map(DiagnosisModel.fromMap).toList();
      _treatments = treatments;
      _tasks = allTasks;
      _progress = rawProgress.map(ProgressUpdateModel.fromMap).toList();
      _chatHistory = historyMessages;
      _loading = false;
    });
  }

  List<FlSpot> get _sparklineSpots {
    final sorted = [..._progress]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final last7 =
        sorted.length > 7 ? sorted.sublist(sorted.length - 7) : sorted;
    if (last7.isEmpty) {
      return [
        const FlSpot(0, 50),
        FlSpot(1, _crop.latestHealthScore ?? 50),
      ];
    }
    return last7
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), (e.value.healthScore ?? 0).toDouble()))
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

  Future<void> _showCheckInSheetForTask(TreatmentTaskModel task) async {
    final cropsProvider = context.read<CropsProvider>();
    final supabaseService = context.read<SupabaseService>();
    final didSubmit = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CheckInSheet(
        crop: _crop,
        checkedTasks: [task],
        activeTreatment: _treatmentForTask(task),
        latestDiagnosis: _diagnosisForTask(task),
        onSubmitted: (newScore, newStatus, update) async {
          final completedAt = update.createdAt;
          await cropsProvider.updateCropHealthScore(_crop.id, newScore, newStatus);
          await supabaseService.insertProgressUpdate(update.toMap());
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
        },
      ),
    );

    if (didSubmit == true && mounted) {
      await _showTaskCelebration(task.title);
    }
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
    if (task.status == TaskStatus.completed) return;

    // Optimistic update.
    final now = DateTime.now();
    setState(() {
      _tasks = _tasks.map((t) {
        if (t.id != task.id) return t;
        return t.copyWith(
          status: TaskStatus.completed,
          completedAt: now,
          updatedAt: now,
        );
      }).toList();
    });

    // Persist via provider.
    final cropsProvider = context.read<CropsProvider>();
    final updated = await cropsProvider.markTaskDone(task.id);
    if (!mounted) return;

    if (updated == null) {
      // Persistence failed — revert.
      setState(() {
        _tasks = _tasks.map((t) {
          if (t.id != task.id) return t;
          return t.copyWith(
            status: TaskStatus.pending,
            completedAt: null,
            updatedAt: now,
          );
        }).toList();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not mark task done. Try again.')),
      );
      return;
    }

    // Cancel any scheduled reminders for this task.
    // ignore: discarded_futures
    NotificationService.instance.cancelForTask(task.id);
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
                    CachedNetworkImage(
                      imageUrl: headerImageUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [AppColors.primaryDark, AppColors.primary],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                      ),
                      errorWidget: (_, __, ___) => Container(
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
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
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
                                        borderRadius:
                                            BorderRadius.circular(3),
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
              labelStyle: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600),
              tabs: const [
                Tab(text: 'Overview'),
                Tab(text: 'Daily Plan'),
                Tab(text: 'Progress'),
                Tab(text: 'Diagnoses'),
              ],
            ),
          ),
        ],
        body: _loading
            ? const Center(
                child: CircularProgressIndicator(
                    color: AppColors.primary))
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
                  SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        CalendarTracker(
                          tasks: _tasks,
                          selectedDate: _selectedDate,
                          onDateSelected: (d) =>
                              setState(() => _selectedDate = d),
                          onTaskToggled: _onTaskToggled,
                        ),
                        const SizedBox(height: 16),
                        HealthScoreGraph(
                          points: _healthCurve,
                          selectedDate: _selectedDate,
                          onPointTap: (d) =>
                              setState(() => _selectedDate = d),
                        ),
                      ],
                    ),
                  ),
                  _DiagnosesTab(
                    diagnoses: _diagnoses,
                    chatHistory: _chatHistory,
                    crop: _crop,
                  ),
                ],
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
        ? latestDx!.summary!.trim()
        : firstAssistantMessage?.content.trim().isNotEmpty == true
            ? firstAssistantMessage!.content.trim()
            : crop.notes?.trim().isNotEmpty == true
                ? crop.notes!.trim()
                : 'No initial diagnosis summary has been saved for this crop yet.';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (latestDx != null) ...[
          const _SectionHeader('Latest Diagnosis'),
          const SizedBox(height: 8),
          _DiagnosisSummaryCard(diagnosis: latestDx),
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
              value: DateFormat('MMM d, y HH:mm')
                  .format(crop.lastCheckedAt!),
            ),
        ]),
        if (crop.notes != null && crop.notes!.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12)),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Notes',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14)),
                  const SizedBox(height: 8),
                  Text(crop.notes!,
                      style: const TextStyle(
                          color: AppColors.textGray, height: 1.5)),
                ]),
          ),
        ],
      ],
    );
  }
}

class _DiagnosisSummaryCard extends StatelessWidget {
  final DiagnosisModel diagnosis;
  const _DiagnosisSummaryCard({required this.diagnosis});

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
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 15)),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _severityColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
              border:
                  Border.all(color: _severityColor.withOpacity(0.4)),
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
        if (diagnosis.summary != null &&
            diagnosis.summary!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(diagnosis.summary!,
              style: const TextStyle(
                  color: AppColors.textGray,
                  fontSize: 13,
                  height: 1.4)),
        ],
        const SizedBox(height: 6),
        Text(DateFormat('MMM d, yyyy').format(diagnosis.diagnosedAt),
            style: const TextStyle(
                color: AppColors.textLightGray, fontSize: 12)),
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
    final activeTreatment =
        treatments.isNotEmpty ? treatments.first : null;
    final orderedTasks = [...tasks]
      ..sort((a, b) {
        final dueCompare = a.dueAt.compareTo(b.dueAt);
        if (dueCompare != 0) return dueCompare;
        return (a.taskOrder ?? 0).compareTo(b.taskOrder ?? 0);
      });
    final completedCount =
        orderedTasks.where((task) => task.status == TaskStatus.completed).length;

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
                  const Icon(Icons.medical_services,
                      color: Colors.white, size: 20),
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
              style: const TextStyle(
                  color: AppColors.textGray, fontSize: 13),
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
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12)),
                child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.task_alt,
                          size: 40, color: AppColors.primary),
                      SizedBox(height: 8),
                      Text('No tasks yet',
                          style: TextStyle(
                              color: AppColors.textGray, fontSize: 15)),
                      SizedBox(height: 4),
                      Text(
                        'Tasks are created when you add a diagnosis to My Crops',
                        style: TextStyle(
                            color: AppColors.textLightGray,
                            fontSize: 12),
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
    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isCompleted
            ? AppColors.primary.withOpacity(0.07)
            : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCompleted
              ? AppColors.primary.withOpacity(0.4)
              : Colors.grey[200]!,
        ),
      ),
      child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
        InkWell(
          onTap: isCompleted ? null : () {
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
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isCompleted
                        ? AppColors.textGray
                        : AppColors.textDark,
                    decoration: isCompleted
                        ? TextDecoration.lineThrough
                        : TextDecoration.none,
                  ),
                ),
                if (task.description != null &&
                    task.description!.isNotEmpty) ...[
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
                    color: isCompleted
                        ? AppColors.primary
                        : AppColors.textLightGray,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    isCompleted
                        ? 'Completed ${task.completedAt != null ? DateFormat('MMM d').format(task.completedAt!) : 'today'}'
                        : 'Due: ${DateFormat('MMM d').format(task.dueAt)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: isCompleted
                          ? AppColors.primary
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
  final CropModel crop;
  final List<ProgressUpdateModel> progress;
  final List<FlSpot> sparklineSpots;

  const _ProgressTab({
    required this.crop,
    required this.progress,
    required this.sparklineSpots,
  });

  @override
  Widget build(BuildContext context) {
    final sorted = [...progress]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (sparklineSpots.length >= 2) ...[
          const _SectionHeader('Health Score Over Time'),
          const SizedBox(height: 12),
          Container(
            height: 180,
            padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14)),
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (v) => FlLine(
                    color: Colors.grey[200]!,
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  bottomTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      interval: 25,
                      getTitlesWidget: (v, _) => Text(
                        '${v.toInt()}%',
                        style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.textGray),
                      ),
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: sparklineSpots,
                    isCurved: true,
                    color: AppColors.primary,
                    barWidth: 2.5,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (_, __, ___, ____) =>
                          FlDotCirclePainter(
                        radius: 3,
                        color: AppColors.primary,
                        strokeColor: Colors.white,
                        strokeWidth: 1.5,
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          AppColors.primary.withOpacity(0.25),
                          AppColors.primary.withOpacity(0),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ],
                minY: 0,
                maxY: 100,
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        const _SectionHeader('Update History'),
        const SizedBox(height: 8),
        if (sorted.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12)),
            child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.timeline,
                      size: 40, color: AppColors.textLightGray),
                  SizedBox(height: 8),
                  Text('No check-ins yet',
                      style: TextStyle(
                          color: AppColors.textGray, fontSize: 15)),
                  SizedBox(height: 4),
                  Text(
                    'Submit a daily check-in from the Daily Plan tab',
                    style: TextStyle(
                        color: AppColors.textLightGray, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ]),
          )
        else
          ...sorted.map((p) => _ProgressCard(update: p)),
      ],
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
      child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
        if (update.imageUrl != null && update.imageUrl!.isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(
              imageUrl: update.imageUrl!,
              width: 64,
              height: 64,
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(
                  width: 64,
                  height: 64,
                  color: Colors.grey[200],
                  child: const Icon(Icons.image, color: Colors.grey)),
              errorWidget: (_, __, ___) => Container(
                  width: 64,
                  height: 64,
                  color: Colors.grey[200],
                  child: const Icon(Icons.broken_image,
                      color: Colors.grey)),
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
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
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
                  DateFormat('MMM d, yyyy  HH:mm')
                      .format(update.createdAt),
                  style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textLightGray),
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
                if (update.completedTaskCount > 0 || update.missedTaskCount > 0) ...[
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
                          fontSize: 13,
                          color: AppColors.textGray,
                          height: 1.4),
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
                ...diagnoses.map((d) => Container(
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
                                fontSize: 12,
                                color: AppColors.textGray),
                          ),
                        ],
                        const SizedBox(height: 4),
                        Text(
                          DateFormat('MMM d, yyyy').format(d.diagnosedAt),
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textLightGray),
                        ),
                        if (d.summary != null &&
                            d.summary!.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(d.summary!,
                              style: const TextStyle(
                                  color: AppColors.textGray,
                                  fontSize: 13,
                                  height: 1.4),
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis),
                        ],
                      ]),
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
                                color: AppColors.textGray,
                                fontSize: 16)),
                        SizedBox(height: 4),
                        Text(
                          'Start a chat to get AI advice for this crop',
                          style: TextStyle(
                              color: AppColors.textLightGray,
                              fontSize: 13),
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
              child: const Icon(Icons.smart_toy,
                  color: Colors.white, size: 16),
            ),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
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
                      child: CachedNetworkImage(
                        imageUrl: message.imageUrl!,
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
                    DateFormat('MMM d  HH:mm')
                        .format(message.createdAt),
                    style: TextStyle(
                      fontSize: 10,
                      color: isUser
                          ? Colors.white60
                          : AppColors.textLightGray,
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
      padding:
          const EdgeInsets.fromLTRB(12, 10, 12, 16),
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
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                      color: AppColors.primary.withOpacity(0.25)),
                ),
                child: Text(
                  'Ask AI about ${crop.cropName}…',
                  style: const TextStyle(
                      color: AppColors.textGray, fontSize: 14),
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
  final List<TreatmentTaskModel> checkedTasks;
  final TreatmentModel? activeTreatment;
  final DiagnosisModel? latestDiagnosis;
  final Future<void> Function(
    double score,
    ProgressStatus status,
    ProgressUpdateModel update,
  ) onSubmitted;

  const _CheckInSheet({
    required this.crop,
    required this.checkedTasks,
    required this.activeTreatment,
    required this.latestDiagnosis,
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
      final supabase = context.read<SupabaseService>();
      final aiBackend = context.read<AiBackendService>();
      final submittedAt = DateTime.now();

      final imageUrl = await supabase.uploadChatImage(
        userId: user?.id ?? 'unknown',
        messageId:
            'progress-${widget.crop.id}-${submittedAt.millisecondsSinceEpoch}',
        bytes: _photoBytes!.toList(),
      );

      final days = widget.activeTreatment?.startedAt != null
          ? DateTime.now()
              .difference(widget.activeTreatment!.startedAt!)
              .inDays
          : 0;

      final aiResponse = await aiBackend.assessCropHealth(
        cropType: widget.crop.cropType.name,
        diseaseName: widget.activeTreatment?.diseaseName ??
            widget.crop.cropName,
        daysSinceTreatment: days,
        imageBytes: _photoBytes!.toList(),
        imageMimeType: 'image/jpeg',
        completedTasks:
            widget.checkedTasks.map((t) => t.title).toList(),
        note: _noteCtrl.text.trim().isNotEmpty
            ? _noteCtrl.text.trim()
            : null,
        currentHealthScore: widget.crop.latestHealthScore,
      );

      final newScore = aiResponse.healthScore;
      final newStatus =
          ProgressStatusX.fromValue(aiResponse.progressStatus);

      for (final task in widget.checkedTasks) {
        await supabase.markTreatmentTaskCompleted(
          task.id,
          completedAt: submittedAt,
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
            : aiResponse.assessment,
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
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(20)),
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
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
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
                                padding:
                                    const EdgeInsets.only(top: 2),
                                child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text('• ',
                                          style: TextStyle(
                                              color:
                                                  AppColors.primary)),
                                      Expanded(
                                          child: Text(t.title,
                                              style: const TextStyle(
                                                  fontSize: 12,
                                                  color: AppColors
                                                      .textGray))),
                                    ]),
                              )),
                        ]),
                  ),
                  const SizedBox(height: 16),
                ],
                const Text('Crop Photo *',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
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
                            child: Image.memory(_photoBytes!,
                                fit: BoxFit.cover),
                          )
                        : const Column(
                            mainAxisAlignment:
                                MainAxisAlignment.center,
                            children: [
                              Icon(Icons.camera_alt,
                                  size: 40,
                                  color: AppColors.textLightGray),
                              SizedBox(height: 8),
                              Text('Tap to take a photo',
                                  style: TextStyle(
                                      color: AppColors.textGray,
                                      fontSize: 14)),
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
                    style: TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 8),
                TextField(
                  controller: _noteCtrl,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText:
                        'How does the crop look today? Any changes?',
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
                              fontSize: 15,
                              fontWeight: FontWeight.bold)),
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
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  child: Row(children: [
                    Icon(row.icon, size: 18, color: AppColors.primary),
                    const SizedBox(width: 12),
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(row.label,
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textGray)),
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
