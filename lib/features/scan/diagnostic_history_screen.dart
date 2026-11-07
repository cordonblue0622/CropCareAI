import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/constants/app_enums.dart';
import '../../../data/models/diagnosis_model.dart';
import '../../../data/models/crop_model.dart';
import '../../../data/models/chat_message_model.dart';
import '../../../data/models/chat_session_model.dart';
import '../../../data/remote/supabase_service.dart';
import '../../../data/local/database_helper.dart';
import '../../../core/constants/app_constants.dart';
import '../../../services/sync_service.dart';
import '../auth/providers/auth_provider.dart';
import '../../../core/utils/label_formatter.dart';
import '../chat/screens/chat_screen.dart';
import '../crops/screens/crop_detail_screen.dart';
import '../crops/providers/crops_provider.dart';

class _DiagnosticHistoryEntry {
  final CropModel crop;
  final DiagnosisModel? diagnosis;
  final bool isCropAdded;

  const _DiagnosticHistoryEntry({
    required this.crop,
    this.diagnosis,
    this.isCropAdded = false,
  });

  String get id => isCropAdded ? 'crop-added-${crop.id}' : diagnosis!.id;
  DateTime get timestamp =>
      isCropAdded ? crop.createdAt : diagnosis!.diagnosedAt;
}

class DiagnosticHistoryScreen extends StatefulWidget {
  const DiagnosticHistoryScreen({super.key});

  @override
  State<DiagnosticHistoryScreen> createState() =>
      _DiagnosticHistoryScreenState();
}

class _DiagnosticHistoryScreenState extends State<DiagnosticHistoryScreen> {
  List<DiagnosisModel> _diagnoses = [];
  List<CropModel> _crops = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final user = context.read<AuthProvider>().currentUser;
    if (user == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    if (mounted) {
      setState(() {
        _loading = _diagnoses.isEmpty && _crops.isEmpty;
        _error = null;
      });
    }

    final db = context.read<DatabaseHelper>();
    final sync = context.read<SyncService>();
    final supabase = context.read<SupabaseService>();
    final cropsProvider = context.read<CropsProvider>();
    final localDiagnosesById = <String, DiagnosisModel>{};
    final localCropsById = <String, CropModel>{};
    try {
      final localDiagnosisRows = await db.queryByUserId(
        AppConstants.diagnosesTable,
        user.id,
        includeDeleted: true,
      );
      final localCropRows = await db.queryByUserId(
        AppConstants.cropsTable,
        user.id,
        includeDeleted: true,
      );
      for (final row in localDiagnosisRows) {
        final diagnosis = DiagnosisModel.fromMap(row);
        localDiagnosesById[diagnosis.id] = diagnosis;
      }
      for (final row in localCropRows) {
        final crop = CropModel.fromMap(row);
        localCropsById[crop.id] = crop;
      }
      _showSnapshot(localDiagnosesById.values, localCropsById.values);

      var restoredLocalDiagnosis = false;
      for (final crop
          in localCropsById.values.where((crop) => !crop.isDeleted)) {
        try {
          final sessions = (await db.queryChatSessionsByCrop(crop.id))
              .map(ChatSessionModel.fromMap)
              .where((session) => !session.isDeleted)
              .toList(growable: false);
          final messagesById = <String, ChatMessageModel>{};
          for (final session in sessions) {
            for (final row in await db.queryChatMessages(session.id)) {
              try {
                final message = ChatMessageModel.fromMap(row);
                messagesById[message.id] = message;
              } catch (_) {
                // A malformed cached message must not hide other history.
              }
            }
          }
          if (await cropsProvider.restoreCropDiagnosisFromLocalSuggestion(
            crop: crop,
            sessions: sessions,
            messages: messagesById.values,
          )) {
            restoredLocalDiagnosis = true;
          }
        } catch (_) {
          // Preserve the crop-added event if local conversation recovery fails.
        }
      }
      if (restoredLocalDiagnosis) {
        localDiagnosesById.clear();
        final recoveredRows = await db.queryByUserId(
          AppConstants.diagnosesTable,
          user.id,
          includeDeleted: true,
        );
        for (final row in recoveredRows) {
          final diagnosis = DiagnosisModel.fromMap(row);
          localDiagnosesById[diagnosis.id] = diagnosis;
        }
        _showSnapshot(localDiagnosesById.values, localCropsById.values);
      }
    } catch (_) {
      // The remote history below remains available when local storage is not.
    }

    try {
      await sync.syncAll().timeout(const Duration(seconds: 12));
    } catch (_) {
      // Keep the local history visible while failed uploads remain queued.
    }

    try {
      final pendingItems = await db.getPendingSyncItems();
      Set<String> pendingIdsFor(String table) => pendingItems
          .where((item) =>
              item['table_name'] == table &&
              (item['operation'] == 'UPSERT' ||
                  item['operation'] == 'SOFT_DELETE'))
          .map((item) => item['record_id'] as String?)
          .whereType<String>()
          .toSet();
      final pendingDiagnosisIds = pendingIdsFor(AppConstants.diagnosesTable);
      final pendingCropIds = pendingIdsFor(AppConstants.cropsTable);
      final remoteDiagnosisRows = await supabase
          .getDiagnosesIncludingDeleted(user.id)
          .timeout(const Duration(seconds: 10));
      final remoteCropRows = await supabase
          .getCropsIncludingDeleted(user.id)
          .timeout(const Duration(seconds: 10));
      final remoteDiagnosisIds = remoteDiagnosisRows
          .map((row) => row['id'] as String?)
          .whereType<String>()
          .toSet();
      final remoteCropIds = remoteCropRows
          .map((row) => row['id'] as String?)
          .whereType<String>()
          .toSet();

      final mergedDiagnoses = Map<String, DiagnosisModel>.from(
        localDiagnosesById,
      );
      for (final row in remoteDiagnosisRows) {
        final remote = DiagnosisModel.fromMap(row);
        final local = mergedDiagnoses[remote.id];
        if (local == null ||
            (!pendingDiagnosisIds.contains(remote.id) &&
                !remote.updatedAt.isBefore(local.updatedAt))) {
          mergedDiagnoses[remote.id] = remote;
        }
      }
      final mergedCrops = Map<String, CropModel>.from(localCropsById);
      for (final row in remoteCropRows) {
        final remote = CropModel.fromMap(row);
        final local = mergedCrops[remote.id];
        if (local == null ||
            (!pendingCropIds.contains(remote.id) &&
                !remote.updatedAt.isBefore(local.updatedAt))) {
          mergedCrops[remote.id] = remote;
        }
      }

      // Requeue local-only active rows without changing their stable IDs.
      var queuedLocalRows = false;
      for (final local in localDiagnosesById.values) {
        if (local.isDeleted ||
            remoteDiagnosisIds.contains(local.id) ||
            pendingDiagnosisIds.contains(local.id)) {
          continue;
        }
        await sync.queueUpsert(
          tableName: AppConstants.diagnosesTable,
          recordId: local.id,
          data: local.toMap(),
        );
        queuedLocalRows = true;
      }
      for (final local in localCropsById.values) {
        if (local.isDeleted ||
            remoteCropIds.contains(local.id) ||
            pendingCropIds.contains(local.id)) {
          continue;
        }
        await sync.queueUpsert(
          tableName: AppConstants.cropsTable,
          recordId: local.id,
          data: local.toMap()..['is_deleted'] = local.isDeleted,
        );
        queuedLocalRows = true;
      }
      await db.upsertRows(
        AppConstants.diagnosesTable,
        mergedDiagnoses.values.map((diagnosis) => diagnosis.toMap()),
      );
      await db.upsertRows(
        AppConstants.cropsTable,
        mergedCrops.values.map((crop) => crop.toMap()),
      );
      if (queuedLocalRows) {
        try {
          await sync.syncAll().timeout(const Duration(seconds: 12));
        } catch (_) {
          // The merged local snapshot remains visible for the next retry.
        }
      }

      _showSnapshot(mergedDiagnoses.values, mergedCrops.values);
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          if (_diagnoses.isEmpty && _crops.isEmpty) _error = null;
        });
      }
    }
  }

  void _showSnapshot(
    Iterable<DiagnosisModel> diagnoses,
    Iterable<CropModel> crops,
  ) {
    if (!mounted) return;
    setState(() {
      _diagnoses = diagnoses.where((diagnosis) => !diagnosis.isDeleted).toList()
        ..sort((a, b) => b.diagnosedAt.compareTo(a.diagnosedAt));
      _crops = crops.where((crop) => !crop.isDeleted).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _loading = false;
      _error = null;
    });
  }

  List<_DiagnosticHistoryEntry> _historyEntries() {
    final cropById = {for (final crop in _crops) crop.id: crop};
    final entries = <_DiagnosticHistoryEntry>[];
    for (final crop in _crops) {
      final creationDiagnoses = _diagnoses
          .where((diagnosis) =>
              diagnosis.cropId == crop.id &&
              !diagnosis.diagnosedAt.isAfter(crop.createdAt))
          .toList()
        ..sort((left, right) => right.diagnosedAt.compareTo(left.diagnosedAt));
      // The persisted crop row and created_at timestamp are the durable
      // Crop Added audit record. Link it to the diagnosis closest to creation
      // when that diagnosis exists, without inventing a diagnosis for manual
      // crop additions.
      entries.add(_DiagnosticHistoryEntry(
        crop: crop,
        diagnosis: creationDiagnoses.firstOrNull,
        isCropAdded: true,
      ));
    }
    for (final diagnosis in _diagnoses) {
      final crop = cropById[diagnosis.cropId];
      if (crop != null) {
        entries.add(_DiagnosticHistoryEntry(crop: crop, diagnosis: diagnosis));
      }
    }
    entries.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return entries;
  }

  void _openHistoryEntry(_DiagnosticHistoryEntry entry) {
    final diagnosis = entry.diagnosis;
    if (diagnosis != null && (diagnosis.chatSessionId ?? '').isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            cropId: diagnosis.cropId.isNotEmpty ? diagnosis.cropId : null,
            initialDiagnosis: diagnosis,
            startFreshSession: false,
          ),
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CropDetailScreen(
          crop: entry.crop,
          initialTabIndex: diagnosis == null ? 0 : 3,
        ),
      ),
    );
  }

  Widget _buildCropAddedCard(_DiagnosticHistoryEntry entry) {
    final crop = entry.crop;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        key: ValueKey(entry.id),
        onTap: () => _openHistoryEntry(entry),
        leading: const CircleAvatar(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          child: Icon(Icons.add),
        ),
        title: const Text(
          'Crop Added',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text('${crop.cropName} was added to My Crops.'),
        trailing: Text(DateFormat('MMM d, yyyy').format(crop.createdAt)),
      ),
    );
  }

  Color _severityColor(Severity s) {
    switch (s) {
      case Severity.mild:
        return AppColors.primary;
      case Severity.moderate:
        return Colors.orange;
      case Severity.severe:
        return Colors.deepOrange;
      default:
        return AppColors.textGray;
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = _historyEntries();
    return Scaffold(
      backgroundColor: AppColors.backgroundCream,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundCream,
        title: const Text('Diagnostic History',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.textGray),
            onPressed: _loadHistory,
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline,
                          color: Colors.red, size: 56),
                      const SizedBox(height: 12),
                      const Text('Failed to load history',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      Text(_error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: AppColors.textGray, fontSize: 13)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _loading = true;
                            _error = null;
                          });
                          _loadHistory();
                        },
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : entries.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.biotech_outlined,
                              size: 64, color: AppColors.textLightGray),
                          SizedBox(height: 16),
                          Text('No diagnoses yet',
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textDark)),
                          SizedBox(height: 8),
                          Text('Scan a crop leaf to get started',
                              style: TextStyle(color: AppColors.textGray)),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: entries.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) {
                        final entry = entries[i];
                        if (entry.isCropAdded) {
                          return _buildCropAddedCard(entry);
                        }
                        final d = entry.diagnosis!;
                        return InkWell(
                          onTap: () => _openHistoryEntry(entry),
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border(
                                left: BorderSide(
                                    color: _severityColor(d.severity),
                                    width: 4),
                              ),
                              boxShadow: [
                                BoxShadow(
                                    color: Colors.black.withOpacity(0.05),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2))
                              ],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    Expanded(
                                      child: Text(
                                          humanizeDiseaseLabel(d.diseaseName),
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 16,
                                              color: AppColors.textDark)),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: _severityColor(d.severity)
                                            .withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        d.severity.name.toUpperCase(),
                                        style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: _severityColor(d.severity)),
                                      ),
                                    ),
                                  ]),
                                  const SizedBox(height: 6),
                                  Row(children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: AppColors.backgroundGreenLight,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        d.diagnosisMode.name,
                                        style: const TextStyle(
                                            fontSize: 11,
                                            color: AppColors.primary,
                                            fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                    if (d.confidenceScore != null) ...[
                                      const SizedBox(width: 8),
                                      const Icon(Icons.analytics,
                                          size: 13, color: AppColors.textGray),
                                      const SizedBox(width: 3),
                                      Text(
                                        '${(d.confidenceScore! * 100).toStringAsFixed(1)}%',
                                        style: const TextStyle(
                                            fontSize: 13,
                                            color: AppColors.textGray),
                                      ),
                                    ],
                                    const Spacer(),
                                    const Icon(Icons.calendar_today,
                                        size: 13,
                                        color: AppColors.textLightGray),
                                    const SizedBox(width: 4),
                                    Text(
                                      DateFormat('MMM d, yyyy')
                                          .format(d.diagnosedAt),
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textLightGray),
                                    ),
                                    if (d.videoUrl != null &&
                                        d.videoUrl!.startsWith('expired:')) ...[
                                      const SizedBox(width: 6),
                                      const Icon(Icons.videocam_off,
                                          size: 13,
                                          color: AppColors.textLightGray),
                                      const SizedBox(width: 3),
                                      const Text(
                                        'Video expired',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: AppColors.textLightGray),
                                      ),
                                    ],
                                  ]),
                                  if (d.summary != null &&
                                      d.summary!.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(d.summary!,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontSize: 13,
                                            color: AppColors.textGray,
                                            height: 1.4)),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}
