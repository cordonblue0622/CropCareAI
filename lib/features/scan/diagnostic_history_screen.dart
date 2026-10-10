import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/constants/app_enums.dart';
import '../../../data/models/diagnosis_model.dart';
import '../../../data/remote/supabase_service.dart';
import '../../../data/local/database_helper.dart';
import '../../../core/constants/app_constants.dart';
import '../../../services/sync_service.dart';
import '../auth/providers/auth_provider.dart';
import '../../../core/utils/label_formatter.dart';
import '../chat/screens/chat_screen.dart';

class DiagnosticHistoryScreen extends StatefulWidget {
  const DiagnosticHistoryScreen({super.key});

  @override
  State<DiagnosticHistoryScreen> createState() =>
      _DiagnosticHistoryScreenState();
}

class _DiagnosticHistoryScreenState extends State<DiagnosticHistoryScreen> {
  List<DiagnosisModel> _diagnoses = [];
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
        _loading = _diagnoses.isEmpty;
        _error = null;
      });
    }

    final db = context.read<DatabaseHelper>();
    final sync = context.read<SyncService>();
    final supabase = context.read<SupabaseService>();
    final localById = <String, DiagnosisModel>{};
    try {
      final localRows = await db.queryByUserId(
        AppConstants.diagnosesTable,
        user.id,
        includeDeleted: true,
      );
      for (final row in localRows) {
        final diagnosis = DiagnosisModel.fromMap(row);
        localById[diagnosis.id] = diagnosis;
      }
      if (mounted) {
        setState(() {
          _diagnoses = localById.values
              .where((diagnosis) => !diagnosis.isDeleted)
              .toList()
            ..sort((a, b) => b.diagnosedAt.compareTo(a.diagnosedAt));
          _loading = false;
        });
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
      final remoteRows = await supabase
          .getDiagnosesIncludingDeleted(user.id)
          .timeout(const Duration(seconds: 10));
      final pendingIds = (await db.getPendingSyncItems())
          .where((item) =>
              item['table_name'] == AppConstants.diagnosesTable &&
              (item['operation'] == 'UPSERT' ||
                  item['operation'] == 'SOFT_DELETE'))
          .map((item) => item['record_id'] as String?)
          .whereType<String>()
          .toSet();
      final merged = Map<String, DiagnosisModel>.from(localById);
      final remoteIds = <String>{};
      for (final row in remoteRows) {
        final remote = DiagnosisModel.fromMap(row);
        remoteIds.add(remote.id);
        final local = merged[remote.id];
        if (local == null ||
            (!pendingIds.contains(remote.id) &&
                !remote.updatedAt.isBefore(local.updatedAt))) {
          merged[remote.id] = remote;
        }
      }

      // Requeue local-only active rows: they should survive reinstall and be
      // visible to the admin console once the connection is available.
      var queuedLocalRows = false;
      for (final local in localById.values) {
        if (local.isDeleted ||
            remoteIds.contains(local.id) ||
            pendingIds.contains(local.id)) {
          continue;
        }
        await sync.queueUpsert(
          tableName: AppConstants.diagnosesTable,
          recordId: local.id,
          data: local.toMap(),
        );
        queuedLocalRows = true;
      }
      await db.upsertRows(
        AppConstants.diagnosesTable,
        merged.values.map((diagnosis) => diagnosis.toMap()),
      );
      if (queuedLocalRows) {
        await sync.syncAll().timeout(const Duration(seconds: 12));
      }

      if (mounted) {
        setState(() {
          _diagnoses = merged.values
              .where((diagnosis) => !diagnosis.isDeleted)
              .toList()
            ..sort((a, b) => b.diagnosedAt.compareTo(a.diagnosedAt));
          _loading = false;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          if (_diagnoses.isEmpty) _error = null;
        });
      }
    }
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
              : _diagnoses.isEmpty
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
                      itemCount: _diagnoses.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) {
                        final d = _diagnoses[i];
                        return InkWell(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatScreen(
                                cropId: d.cropId.isNotEmpty ? d.cropId : null,
                                initialDiagnosis: d,
                                startFreshSession: false,
                              ),
                            ),
                          ),
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
