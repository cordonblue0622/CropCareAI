import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/constants/app_enums.dart';
import '../../../data/local/database_helper.dart';
import '../../../data/models/crop_model.dart';
import '../../../data/remote/supabase_service.dart';
import '../../../shared/widgets/app_image_reference.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/crops_provider.dart';
import 'crop_detail_screen.dart';
import 'add_crop_screen.dart';

class MyCropsScreen extends StatefulWidget {
  const MyCropsScreen({super.key});

  @override
  State<MyCropsScreen> createState() => _MyCropsScreenState();
}

class _MyCropsScreenState extends State<MyCropsScreen> {
  CropType? _filterType;
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();
  _CropsSectionMode _sectionMode = _CropsSectionMode.active;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<CropModel> _filtered(List<CropModel> all) {
    return all.where((c) {
      final matchesType = _filterType == null || c.cropType == _filterType;
      final matchesSearch = _searchQuery.isEmpty ||
          c.cropName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          (c.plotCode?.toLowerCase().contains(_searchQuery.toLowerCase()) ??
              false);
      return matchesType && matchesSearch;
    }).toList();
  }

  bool get _hasActiveFilters =>
      _filterType != null || _searchQuery.trim().isNotEmpty;

  void _clearFilters() {
    _searchCtrl.clear();
    setState(() {
      _filterType = null;
      _searchQuery = '';
    });
  }

  Future<String?> _previewImageFor(String cropId) async {
    final localImage =
        await context.read<DatabaseHelper>().getLatestCropImageUrl(cropId);
    if (localImage != null) {
      return localImage;
    }
    return context.read<SupabaseService>().getLatestCropImageUrl(cropId);
  }

  @override
  Widget build(BuildContext context) {
    final crops = context.watch<CropsProvider>();
    final user = context.watch<AuthProvider>().currentUser;
    final activeCrops = _filtered(crops.activeCrops);
    final completedCrops = _filtered(crops.completedCrops);
    final hasActiveFilters = _hasActiveFilters;
    final healedCrops = completedCrops.where(_isHealedCompletedCrop).toList();
    final needsHelpCrops =
        completedCrops.where((crop) => !_isHealedCompletedCrop(crop)).toList();

    return Scaffold(
      backgroundColor: AppColors.backgroundCream,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text('My Crops',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 20)),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AddCropScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.filter_list, color: Colors.white),
            onPressed: () => _showFilterSheet(context),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () async {
          if (user != null) await crops.fetchCrops(user.id);
        },
        child: Column(children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: InputDecoration(
                hintText: 'Search your plots...',
                prefixIcon: const Icon(Icons.search,
                    color: AppColors.textGray, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _searchQuery = '');
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
              padding: const EdgeInsets.symmetric(horizontal: 18),
              children: [
                _FilterChip(
                    label: 'All',
                    selected: _filterType == null,
                    onTap: () => setState(() => _filterType = null)),
                ...CropType.values.map((t) => _FilterChip(
                    label: t.name[0].toUpperCase() + t.name.substring(1),
                    selected: _filterType == t,
                    onTap: () => setState(() => _filterType = t))),
              ],
            ),
          ),
          const SizedBox(height: 12),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                Expanded(
                  child: _SectionChip(
                    label: 'Active Crops',
                    count: activeCrops.length,
                    selected: _sectionMode == _CropsSectionMode.active,
                    onTap: () => setState(
                      () => _sectionMode = _CropsSectionMode.active,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _SectionChip(
                    label: 'Treated Crops',
                    count: completedCrops.length,
                    selected: _sectionMode == _CropsSectionMode.completed,
                    onTap: () => setState(
                      () => _sectionMode = _CropsSectionMode.completed,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // List
          Expanded(
            child: crops.isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary))
                : _sectionMode == _CropsSectionMode.active
                    ? activeCrops.isEmpty
                        ? _emptyState(
                            context,
                            title: hasActiveFilters
                                ? 'No crops match your filters'
                                : 'No active crops found',
                            subtitle: hasActiveFilters
                                ? 'Clear your search and crop type filter to see all crops.'
                                : 'Add your first crop to begin tracking its health.',
                            showAddAction: !hasActiveFilters,
                            onClearFilters:
                                hasActiveFilters ? _clearFilters : null,
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(18, 0, 18, 112),
                            itemCount: activeCrops.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12),
                            itemBuilder: (_, i) => GestureDetector(
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        CropDetailScreen(crop: activeCrops[i]),
                                  ),
                                );
                              },
                              child: _CropCard(
                                crop: activeCrops[i],
                                previewImageFuture:
                                    _previewImageFor(activeCrops[i].id),
                              ),
                            ),
                          )
                    : completedCrops.isEmpty
                        ? _emptyState(
                            context,
                            title: hasActiveFilters
                                ? 'No treated crops match your filters'
                                : 'No treated crops yet',
                            subtitle: hasActiveFilters
                                ? 'Clear your search and crop type filter to see treated crops.'
                                : 'Finished treatment timelines will appear here.',
                            showAddAction: false,
                            onClearFilters:
                                hasActiveFilters ? _clearFilters : null,
                          )
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(18, 0, 18, 112),
                            children: [
                              if (healedCrops.isNotEmpty) ...[
                                _CompletionSectionHeader(
                                  title: 'Fully Healed',
                                  subtitle:
                                      'Recovered crops with strong final health scores.',
                                  count: healedCrops.length,
                                  color: AppColors.primary,
                                ),
                                const SizedBox(height: 12),
                                ...healedCrops.map(
                                  (crop) => Padding(
                                    padding: const EdgeInsets.only(bottom: 16),
                                    child: GestureDetector(
                                      onTap: () async {
                                        await Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                CropDetailScreen(crop: crop),
                                          ),
                                        );
                                      },
                                      child: _CropCard(
                                        crop: crop,
                                        previewImageFuture:
                                            _previewImageFor(crop.id),
                                        statusLabel: 'HEALED',
                                        statusColor: AppColors.primary,
                                        completionSummary:
                                            'Treatment completed with a health score above 90.',
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                              if (needsHelpCrops.isNotEmpty) ...[
                                _CompletionSectionHeader(
                                  title: 'Needs Help',
                                  subtitle:
                                      'Completed timelines that still need follow-up attention.',
                                  count: needsHelpCrops.length,
                                  color: Colors.orange,
                                ),
                                const SizedBox(height: 12),
                                ...needsHelpCrops.map(
                                  (crop) => Padding(
                                    padding: const EdgeInsets.only(bottom: 16),
                                    child: GestureDetector(
                                      onTap: () async {
                                        await Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                CropDetailScreen(crop: crop),
                                          ),
                                        );
                                      },
                                      child: _CropCard(
                                        crop: crop,
                                        previewImageFuture:
                                            _previewImageFor(crop.id),
                                        statusLabel: 'NEEDS HELP',
                                        statusColor: Colors.orange,
                                        completionSummary:
                                            _completionSummaryFor(crop),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
          ),
        ]),
      ),
    );
  }

  bool _isHealedCompletedCrop(CropModel crop) {
    final score = crop.latestHealthScore ?? 0;
    return score >= 90 && crop.latestProgressStatus != ProgressStatus.worsening;
  }

  String _completionSummaryFor(CropModel crop) {
    if (crop.latestProgressStatus == ProgressStatus.worsening) {
      return 'Treatment finished, but the latest health trend moved downward.';
    }
    return 'Treatment finished below the healed threshold and may need more care.';
  }

  void _showFilterSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Filter by Crop Type',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                ActionChip(
                    label: const Text('All'),
                    onPressed: () {
                      setState(() => _filterType = null);
                      Navigator.pop(context);
                    }),
                ...CropType.values.map((t) => ActionChip(
                    label: Text(t.name[0].toUpperCase() + t.name.substring(1)),
                    onPressed: () {
                      setState(() => _filterType = t);
                      Navigator.pop(context);
                    })),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(
    BuildContext context, {
    required String title,
    required String subtitle,
    bool showAddAction = true,
    VoidCallback? onClearFilters,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.energy_savings_leaf_outlined,
              color: AppColors.textLightGray, size: 64),
          const SizedBox(height: 16),
          Text(title,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark)),
          const SizedBox(height: 8),
          Text(subtitle, style: const TextStyle(color: AppColors.textGray)),
          if (onClearFilters != null) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onClearFilters,
              icon: const Icon(Icons.filter_alt_off_outlined),
              label: const Text('Clear Filters'),
            ),
          ],
          if (showAddAction) ...[
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const AddCropScreen())),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
              ),
              icon: const Icon(Icons.add),
              label: const Text('Add Crop'),
            ),
          ],
        ],
      ),
    );
  }
}

enum _CropsSectionMode { active, completed }

class _SectionChip extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _SectionChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.backgroundGreenLight
              : AppColors.backgroundWhite,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.borderGreen,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryDark,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.primary
                    : AppColors.backgroundGreenLight,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: selected ? Colors.white : AppColors.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompletionSectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final int count;
  final Color color;

  const _CompletionSectionHeader({
    required this.title,
    required this.subtitle,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.eco_rounded, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: AppColors.textGray,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Filter Chip ──────────────────────────────────────────────────────────

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
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: selected ? AppColors.primary : AppColors.borderGreen),
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

// ─── Crop Card ────────────────────────────────────────────────────────────

class _CropCard extends StatelessWidget {
  final CropModel crop;
  final Future<String?> previewImageFuture;
  final String? statusLabel;
  final Color? statusColor;
  final String? completionSummary;

  const _CropCard({
    required this.crop,
    required this.previewImageFuture,
    this.statusLabel,
    this.statusColor,
    this.completionSummary,
  });

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

  Color _progressColor(double score) {
    if (score >= 70) return AppColors.primary;
    if (score >= 40) return Colors.orange;
    return Colors.red;
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} mins ago';
    if (diff.inHours < 24) return '${diff.inHours} hours ago';
    return DateFormat('MMM d').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final score = crop.latestHealthScore ?? 0;
    final badgeColor = statusColor ?? _statusColor(crop.status);
    final badgeLabel = statusLabel ?? crop.status.name.toUpperCase();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.backgroundWhite,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderGreen),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Image
        Stack(children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
            child: SizedBox(
              height: 160,
              width: double.infinity,
              child: FutureBuilder<String?>(
                future: previewImageFuture,
                builder: (context, snapshot) {
                  final imageUrl = snapshot.data?.trim();
                  if (imageUrl != null && imageUrl.isNotEmpty) {
                    return AppImageReference(
                      imageRef: imageUrl,
                      fit: BoxFit.cover,
                      placeholder: _CropImagePlaceholder(crop: crop),
                      errorWidget: _CropImagePlaceholder(crop: crop),
                    );
                  }
                  return _CropImagePlaceholder(crop: crop);
                },
              ),
            ),
          ),
          Positioned(
            top: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                  color: badgeColor.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(8)),
              child: Text(badgeLabel,
                  style: const TextStyle(
                      fontSize: 10,
                      color: Colors.white,
                      fontWeight: FontWeight.bold)),
            ),
          ),
        ]),

        Padding(
          padding: const EdgeInsets.all(14),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (crop.plotCode != null)
                Text(
                  'PLOT ${crop.plotCode}',
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textGray,
                      letterSpacing: 0.5),
                ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.more_vert,
                    size: 20, color: AppColors.textGray),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => _showOptions(context),
              ),
            ]),
            Text(crop.cropName,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textDark)),
            const SizedBox(height: 10),
            Row(children: [
              const Text('Growth Index',
                  style: TextStyle(fontSize: 13, color: AppColors.textGray)),
              const Spacer(),
              Text(
                '${score.toStringAsFixed(0)}%',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: _progressColor(score)),
              ),
            ]),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: score / 100,
                minHeight: 6,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation(_progressColor(score)),
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.access_time,
                  size: 13, color: AppColors.textLightGray),
              const SizedBox(width: 4),
              Text(
                'Updated ${_timeAgo(crop.updatedAt)}',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textLightGray),
              ),
            ]),
            if (completionSummary != null) ...[
              const SizedBox(height: 10),
              Text(
                completionSummary!,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: AppColors.textGray,
                ),
              ),
            ],
          ]),
        ),
      ]),
    );
  }

  void _showOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.edit, color: AppColors.primary),
            title: const Text('Edit Crop'),
            onTap: () => Navigator.pop(context),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.red),
            title:
                const Text('Delete Crop', style: TextStyle(color: Colors.red)),
            onTap: () {
              Navigator.pop(context);
              _confirmDelete(context);
            },
          ),
        ]),
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Crop'),
        content: Text('Remove "${crop.cropName}" from your farm?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await context.read<CropsProvider>().deleteCrop(crop.id);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

class _CropImagePlaceholder extends StatelessWidget {
  final CropModel crop;

  const _CropImagePlaceholder({required this.crop});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.primaryLight.withOpacity(0.2),
      child: Center(
        child: Text(
          crop.cropType.name[0].toUpperCase(),
          style: TextStyle(
            fontSize: 60,
            fontWeight: FontWeight.bold,
            color: AppColors.primary.withOpacity(0.3),
          ),
        ),
      ),
    );
  }
}
