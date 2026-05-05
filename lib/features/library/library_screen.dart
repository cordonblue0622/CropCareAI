import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/constants/app_enums.dart';
import '../../../data/models/disease_knowledge_model.dart';
import '../crops/providers/crops_provider.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  List<DiseaseKnowledgeModel> _all = [];
  List<DiseaseKnowledgeModel> _filtered = [];
  CropType? _filterType;
  String _search = '';
  bool _loading = true;
  bool _importing = false;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final data = await context.read<CropsProvider>().fetchDiseaseKnowledge();
      if (mounted) {
        setState(() {
          _all = data;
          _applyFilter();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _importDataset() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json', 'csv'],
      withData: true,
      dialogTitle: 'Select a disease dataset file',
    );

    if (!mounted || picked == null || picked.files.isEmpty) return;

    final file = picked.files.single;
    final bytes = file.bytes;
    if (bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to read the selected file. Try another file.'),
        ),
      );
      return;
    }

    setState(() => _importing = true);
    try {
      final summary = await context
          .read<CropsProvider>()
          .importDiseaseKnowledgeDataset(bytes: bytes, fileName: file.name);

      if (!mounted) return;

      setState(() {
        _all = context.read<CropsProvider>().diseaseKnowledge;
        _loading = false;
        _applyFilter();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Imported ${summary.importedRows} of ${summary.totalRows} dataset row(s).',
          ),
        ),
      );

      _showImportSummary(summary);
    } on FormatException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message.toString())),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Dataset import failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _importing = false);
      }
    }
  }

  Future<void> _showImportSummary(DiseaseDatasetImportSummary summary) {
    return showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Dataset Import Complete'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(summary.fileName,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Text('Imported rows: ${summary.importedRows}'),
              Text('Skipped rows: ${summary.skippedRows}'),
              if (summary.warnings.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('Warnings',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                ...summary.warnings.take(6).map(
                      (warning) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          warning,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textGray,
                          ),
                        ),
                      ),
                    ),
                if (summary.warnings.length > 6)
                  Text(
                    '+${summary.warnings.length - 6} more warning(s)',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textGray,
                    ),
                  ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _applyFilter() {
    _filtered = _all.where((kb) {
      final matchType = _filterType == null || kb.cropType == _filterType;
      final matchSearch = _search.isEmpty ||
          kb.diseaseName.toLowerCase().contains(_search.toLowerCase()) ||
          (kb.description?.toLowerCase().contains(_search.toLowerCase()) ??
              false);
      return matchType && matchSearch;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundCream,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundCream,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Disease Library',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            Text('Clinical Crop Care',
                style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textGray,
                    fontStyle: FontStyle.italic)),
          ],
        ),
        actions: [
          if (_importing)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: AppColors.primary,
                ),
              ),
            )
          else
            IconButton(
              tooltip: 'Import JSON or CSV dataset',
              icon: const Icon(Icons.upload_file, color: AppColors.primary),
              onPressed: _importDataset,
            ),
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.textGray),
            onPressed: _importing ? null : _loadData,
          ),
        ],
      ),
      body: Column(children: [
        // Search
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() {
              _search = v;
              _applyFilter();
            }),
            decoration: InputDecoration(
              hintText: 'Search diseases, symptoms...',
              prefixIcon: const Icon(Icons.search,
                  color: AppColors.textGray, size: 20),
              suffixIcon: _search.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() {
                          _search = '';
                          _applyFilter();
                        });
                      },
                    )
                  : null,
            ),
          ),
        ),

        // Filter chips
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _FilterChip(
                label: 'All Crops',
                selected: _filterType == null,
                onTap: () => setState(() {
                  _filterType = null;
                  _applyFilter();
                }),
              ),
              ...CropType.values.map((t) => _FilterChip(
                    label: t.name[0].toUpperCase() + t.name.substring(1),
                    selected: _filterType == t,
                    onTap: () => setState(() {
                      _filterType = t;
                      _applyFilter();
                    }),
                  )),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Results count
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Text(
              '${_filtered.length} disease${_filtered.length == 1 ? '' : 's'} found',
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textGray),
            ),
          ]),
        ),
        const SizedBox(height: 8),

        // List
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.primary))
              : _filtered.isEmpty
                  ? Center(
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                        const Icon(Icons.menu_book,
                            size: 56, color: AppColors.textLightGray),
                        const SizedBox(height: 12),
                        Text(
                          _all.isEmpty
                              ? 'No disease entries in database'
                              : 'No results found',
                          style: const TextStyle(
                              color: AppColors.textGray, fontSize: 15),
                        ),
                      ]))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                      itemCount: _filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) =>
                          _DiseaseCard(kb: _filtered[i]),
                    ),
        ),
      ]),
    );
  }
}

// ─── Disease Card ─────────────────────────────────────────────────────────

class _DiseaseCard extends StatefulWidget {
  final DiseaseKnowledgeModel kb;
  const _DiseaseCard({required this.kb});

  @override
  State<_DiseaseCard> createState() => _DiseaseCardState();
}

class _DiseaseCardState extends State<_DiseaseCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final kb = widget.kb;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.backgroundGreenLight,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                kb.cropType.name[0].toUpperCase() + kb.cropType.name.substring(1),
                style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(kb.diseaseName,
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textDark)),
            ),
          ]),
        ),
        if (kb.scientificName != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(kb.scientificName!,
                style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textGray,
                    fontStyle: FontStyle.italic)),
          ),
        if (kb.description != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              kb.description!,
              maxLines: _expanded ? null : 2,
              overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textGray, height: 1.4),
            ),
          ),

        // Expanded details
        if (_expanded) ...[
          if (kb.symptoms != null && kb.symptoms!.isNotEmpty) ...[
            const _SectionDivider(),
            _ExpandedSection(
                title: 'Symptoms',
                icon: Icons.visibility,
                items: kb.symptoms!),
          ],
          if (kb.treatmentSteps != null && kb.treatmentSteps!.isNotEmpty) ...[
            const _SectionDivider(),
            _ExpandedSection(
                title: 'Treatment',
                icon: Icons.medical_services,
                items: kb.treatmentSteps!,
                numbered: true),
          ],
          if (kb.preventionSteps != null &&
              kb.preventionSteps!.isNotEmpty) ...[
            const _SectionDivider(),
            _ExpandedSection(
                title: 'Prevention',
                icon: Icons.shield,
                items: kb.preventionSteps!),
          ],
          if (kb.estimatedRecoveryDays != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.backgroundGreenLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.schedule,
                      size: 15, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Text(
                      'Estimated recovery: ${kb.estimatedRecoveryDays} days',
                      style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          if (kb.cautionNotes != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  const Icon(Icons.warning_amber,
                      size: 16, color: Colors.orange),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(kb.cautionNotes!,
                          style: const TextStyle(
                              fontSize: 12,
                              color: Colors.orange,
                              height: 1.4))),
                ]),
              ),
            ),
        ],

        // Toggle button
        TextButton(
          onPressed: () => setState(() => _expanded = !_expanded),
          style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              padding: const EdgeInsets.all(16)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(_expanded ? 'Show less' : 'View details',
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(width: 4),
            Icon(
                _expanded
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down,
                size: 18),
          ]),
        ),
      ]),
    );
  }
}

class _ExpandedSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<String> items;
  final bool numbered;
  const _ExpandedSection({
    required this.title,
    required this.icon,
    required this.items,
    this.numbered = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 15, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(title,
              style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: AppColors.textDark)),
        ]),
        const SizedBox(height: 6),
        ...items.asMap().entries.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                numbered
                    ? Container(
                        width: 20,
                        height: 20,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.backgroundGreenLight),
                        child: Center(
                            child: Text('${e.key + 1}',
                                style: const TextStyle(
                                    fontSize: 10,
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.bold))),
                      )
                    : Container(
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.only(top: 5, right: 10),
                        decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.primary),
                      ),
                Expanded(
                    child: Text(e.value,
                        style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textGray,
                            height: 1.4))),
              ]),
            )),
      ]),
    );
  }
}

class _SectionDivider extends StatelessWidget {
  const _SectionDivider();

  @override
  Widget build(BuildContext context) => const Padding(
      padding: EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Divider(height: 1, color: AppColors.backgroundCream));
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.textGray,
          ),
        ),
      ),
    );
  }
}
