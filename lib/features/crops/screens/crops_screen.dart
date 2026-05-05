import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/constants/app_enums.dart';
import '../../../data/models/crop_model.dart';
import '../../../data/remote/supabase_service.dart';
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
  final Map<String, Future<String?>> _previewImageFutures = {};

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

  Future<String?> _previewImageFor(String cropId) {
    return _previewImageFutures.putIfAbsent(
      cropId,
      () => context.read<SupabaseService>().getLatestCropImageUrl(cropId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final crops = context.watch<CropsProvider>();
    final user = context.watch<AuthProvider>().currentUser;
    final filtered = _filtered(crops.activeCrops);

    return Scaffold(
      backgroundColor: AppColors.backgroundCream,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundCream,
        title: const Text('My Crops',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: AppColors.primary, size: 28),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AddCropScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.filter_list, color: AppColors.textGray),
            onPressed: () => _showFilterSheet(context),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () async {
          setState(() => _previewImageFutures.clear());
          if (user != null) await crops.fetchCrops(user.id);
        },
        child: Column(children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
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
              padding: const EdgeInsets.symmetric(horizontal: 16),
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

          // List
          Expanded(
            child: crops.isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary))
                : filtered.isEmpty
                    ? _emptyState(context)
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 16),
                        itemBuilder: (_, i) => GestureDetector(
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => CropDetailScreen(crop: filtered[i]),
                              ),
                            );
                            if (!mounted) return;
                            setState(() {
                              _previewImageFutures.remove(filtered[i].id);
                            });
                          },
                          child: _CropCard(
                            crop: filtered[i],
                            previewImageFuture: _previewImageFor(filtered[i].id),
                          ),
                        ),
                      ),
          ),
        ]),
      ),
    );
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

  Widget _emptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.energy_savings_leaf_outlined,
              color: AppColors.textLightGray, size: 64),
          const SizedBox(height: 16),
          const Text('No crops found',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark)),
          const SizedBox(height: 8),
          const Text('Add your first crop to get started',
              style: TextStyle(color: AppColors.textGray)),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const AddCropScreen())),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
            ),
            icon: const Icon(Icons.add),
            label: const Text('Add Crop'),
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
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? AppColors.primary : Colors.transparent),
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

  const _CropCard({
    required this.crop,
    required this.previewImageFuture,
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

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Image
        Stack(children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: SizedBox(
              height: 160,
              width: double.infinity,
              child: FutureBuilder<String?>(
                future: previewImageFuture,
                builder: (context, snapshot) {
                  final imageUrl = snapshot.data?.trim();
                  if (imageUrl != null && imageUrl.isNotEmpty) {
                    return CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => _CropImagePlaceholder(crop: crop),
                      errorWidget: (_, __, ___) => _CropImagePlaceholder(crop: crop),
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
                  color: _statusColor(crop.status).withOpacity(0.9),
                  borderRadius: BorderRadius.circular(8)),
              child: Text(crop.status.name.toUpperCase(),
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
