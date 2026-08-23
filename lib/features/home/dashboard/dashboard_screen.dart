import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/constants/app_enums.dart';
import '../../../core/utils/label_formatter.dart';
import '../../../data/local/database_helper.dart';
import '../../../data/models/user_model.dart';
import '../../../data/models/crop_model.dart';
import '../../../data/models/disease_knowledge_model.dart';
import '../../../data/models/treatment_task_model.dart';
import '../../../data/remote/supabase_service.dart';
import '../../../data/remote/weather_service.dart';
import '../../../shared/widgets/app_image_reference.dart';
import '../../auth/providers/auth_provider.dart';
import '../../crops/providers/crops_provider.dart';
import '../../notifications/providers/notifications_provider.dart';
import '../../notifications/screens/notifications_screen.dart';
import '../../crops/screens/crop_detail_screen.dart';
import '../../library/library_screen.dart';
import '../../chat/screens/chat_screen.dart';
import '../../account/nav_drawer.dart';

class DashboardScreen extends StatefulWidget {
  final VoidCallback? onOpenMyCrops;

  const DashboardScreen({super.key, this.onOpenMyCrops});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final WeatherService _weatherService = WeatherService();
  final TextEditingController _searchCtrl = TextEditingController();
  List<DiseaseKnowledgeModel> _diseases = [];
  FarmWeatherSnapshot? _weather;
  String? _weatherLocationQuery;
  String _searchQuery = '';
  bool _isLoadingWeather = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDiseases());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDiseases() async {
    final items = await context.read<CropsProvider>().fetchDiseaseKnowledge();
    if (mounted) setState(() => _diseases = items);
  }

  String? _resolveFarmLocation(UserModel? user, List<CropModel> activeCrops) {
    final userLocation = user?.weatherLocationQuery;
    if (userLocation != null && userLocation.isNotEmpty) {
      return userLocation;
    }

    for (final crop in activeCrops) {
      final location = crop.locationLabel?.trim();
      if (location != null && location.isNotEmpty) {
        return location;
      }
    }
    return null;
  }

  Future<void> _loadWeather(String locationQuery) async {
    if (!mounted) return;

    setState(() {
      _weatherLocationQuery = locationQuery;
      _isLoadingWeather = true;
      _weather = null;
    });

    final weather = await _weatherService.fetchCurrentConditions(locationQuery);

    if (!mounted) return;
    setState(() {
      _weather = weather;
      _isLoadingWeather = false;
    });
  }

  void _ensureWeatherLoaded(String? locationQuery) {
    final normalized = locationQuery?.trim();
    if (normalized == null || normalized.isEmpty) {
      if (_weather != null ||
          _weatherLocationQuery != null ||
          _isLoadingWeather) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() {
            _weather = null;
            _weatherLocationQuery = null;
            _isLoadingWeather = false;
          });
        });
      }
      return;
    }

    if (_weatherLocationQuery == normalized) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadWeather(normalized);
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

  List<DiseaseKnowledgeModel> _dashboardDiseases(CropsProvider crops) {
    final allActive = _diseases.where((item) => item.isActive).toList();
    if (allActive.isEmpty) return const [];

    final cropTypes = crops.activeCrops.map((crop) => crop.cropType).toSet();
    if (cropTypes.isEmpty) {
      return allActive.take(5).toList();
    }

    final filtered =
        allActive.where((item) => cropTypes.contains(item.cropType)).toList();
    return (filtered.isNotEmpty ? filtered : allActive).take(5).toList();
  }

  List<CropModel> _filterCrops(List<CropModel> crops) {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return crops;
    }

    return crops.where((crop) {
      final haystack = [
        crop.cropName,
        crop.cropType.name,
        crop.plotCode,
        crop.locationLabel,
        crop.notes,
      ].whereType<String>().join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList(growable: false);
  }

  List<CropModel> _recentActiveCrops(
    List<CropModel> crops, {
    int? limit,
  }) {
    final sorted = [...crops]..sort((a, b) {
        final updatedCompare = b.updatedAt.compareTo(a.updatedAt);
        if (updatedCompare != 0) {
          return updatedCompare;
        }
        return b.createdAt.compareTo(a.createdAt);
      });

    if (limit == null || sorted.length <= limit) {
      return sorted;
    }
    return sorted.take(limit).toList(growable: false);
  }

  List<DiseaseKnowledgeModel> _filterDiseases(
    List<DiseaseKnowledgeModel> diseases,
  ) {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return diseases;
    }

    return diseases.where((disease) {
      final haystack = [
        disease.diseaseName,
        disease.cropType.name,
        disease.description,
        disease.cautionNotes,
        disease.severityNotes,
      ].whereType<String>().join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList(growable: false);
  }

  String _diseaseRiskLabel(DiseaseKnowledgeModel disease) {
    final severity = disease.severityNotes?.trim();
    if (severity != null && severity.isNotEmpty) {
      return severity;
    }
    return disease.cropType.name.toUpperCase();
  }

  Color _diseaseAccentColor(DiseaseKnowledgeModel disease) {
    final details =
        '${disease.severityNotes ?? ''} ${disease.cautionNotes ?? ''}'
            .toLowerCase();
    if (details.contains('critical') ||
        details.contains('severe') ||
        details.contains('high')) {
      return Colors.redAccent;
    }
    if (details.contains('moderate')) {
      return Colors.orange;
    }
    if (details.contains('low') || details.contains('mild')) {
      return Colors.amber.shade700;
    }
    return AppColors.primaryLight;
  }

  _SmartTipContent _buildSmartTipContent({
    required CropsProvider crops,
    required NotificationsProvider notifs,
    required String? farmLocation,
  }) {
    if (notifs.missedTasks.isNotEmpty) {
      final task = notifs.missedTasks.first;
      final count = notifs.missedTasks.length;
      return _SmartTipContent(
        message:
            'You have $count overdue task${count == 1 ? '' : 's'}. Start with "${task.title}" to keep treatments on schedule.',
        actionLabel: 'VIEW TASKS',
        action: _SmartTipAction.openNotifications,
      );
    }

    if (notifs.todayTasks.isNotEmpty) {
      final task = notifs.todayTasks.first;
      final count = notifs.todayTasks.length;
      return _SmartTipContent(
        message:
            '$count task${count == 1 ? '' : 's'} due today. Prioritize "${task.title}" before the day ends.',
        actionLabel: 'VIEW TASKS',
        action: _SmartTipAction.openNotifications,
      );
    }

    CropModel? priorityCrop;
    for (final crop in crops.activeCrops) {
      if (crop.status == CropStatus.critical ||
          crop.status == CropStatus.recovering) {
        priorityCrop = crop;
        break;
      }
    }

    if (priorityCrop != null) {
      final status = priorityCrop.status.name.toUpperCase();
      return _SmartTipContent(
        message:
            '${priorityCrop.cropName} is currently marked $status. Review the latest diagnosis and treatment progress today.',
        actionLabel: 'OPEN LIBRARY',
        action: _SmartTipAction.openLibrary,
      );
    }

    if (_isLoadingWeather && farmLocation != null) {
      return _SmartTipContent(
        message:
            'Fetching live weather for $farmLocation to generate a location-based crop tip.',
      );
    }

    if (_weather != null && _weatherLocationQuery == farmLocation) {
      final focusCrop =
          crops.activeCrops.isNotEmpty ? crops.activeCrops.first : null;
      final cropLabel = focusCrop?.cropName ?? 'your crops';

      if (_weather!.isHumid) {
        return _SmartTipContent(
          message:
              'Humidity is ${_weather!.relativeHumidity}% in ${_weather!.locationLabel}. Check $cropLabel for fungal spots and moisture buildup today.',
          actionLabel: 'OPEN LIBRARY',
          action: _SmartTipAction.openLibrary,
        );
      }

      if (_weather!.isWet) {
        return _SmartTipContent(
          message:
              '${_weather!.conditionLabel[0].toUpperCase()}${_weather!.conditionLabel.substring(1)} are affecting ${_weather!.locationLabel}. Inspect drainage and leaf wetness around $cropLabel.',
          actionLabel: 'OPEN LIBRARY',
          action: _SmartTipAction.openLibrary,
        );
      }

      if (_weather!.temperatureC >= 32) {
        return _SmartTipContent(
          message:
              'Temperature is ${_weather!.temperatureC.toStringAsFixed(1)}°C in ${_weather!.locationLabel}. Water early and watch $cropLabel for heat stress.',
          actionLabel: 'OPEN LIBRARY',
          action: _SmartTipAction.openLibrary,
        );
      }

      return _SmartTipContent(
        message:
            'Current weather in ${_weather!.locationLabel} shows ${_weather!.conditionLabel} with ${_weather!.relativeHumidity}% humidity. Continue regular monitoring for ${focusCrop?.cropName ?? 'your active crops'}.',
        actionLabel: 'OPEN LIBRARY',
        action: _SmartTipAction.openLibrary,
      );
    }

    if (farmLocation == null || farmLocation.isEmpty) {
      return const _SmartTipContent(
        message:
            'Add a farm or crop location to enable live weather and humidity tips on this dashboard.',
      );
    }

    if (crops.activeCrops.isEmpty) {
      return _SmartTipContent(
        message:
            'No active crops yet. Add your first crop to start receiving field-specific tips for $farmLocation.',
      );
    }

    return _SmartTipContent(
      message:
          'Live weather is unavailable for $farmLocation right now. Continue updating crop health and tasks to keep dashboard insights accurate.',
      actionLabel: 'OPEN LIBRARY',
      action: _SmartTipAction.openLibrary,
    );
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'GOOD MORNING';
    if (h < 17) return 'GOOD AFTERNOON';
    return 'GOOD EVENING';
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final crops = context.watch<CropsProvider>();
    final notifs = context.watch<NotificationsProvider>();
    final user = auth.currentUser;
    final farmLocation = _resolveFarmLocation(user, crops.activeCrops);
    _ensureWeatherLoaded(farmLocation);
    final filteredActiveCrops = _filterCrops(crops.activeCrops);
    final dashboardActiveCrops =
        _recentActiveCrops(filteredActiveCrops, limit: 5);
    final allRecentActiveCrops = _recentActiveCrops(crops.activeCrops);
    final filteredDiseases = _filterDiseases(_dashboardDiseases(crops));
    final hasSearchQuery = _searchQuery.trim().isNotEmpty;
    final smartTip = _buildSmartTipContent(
      crops: crops,
      notifs: notifs,
      farmLocation: farmLocation,
    );
    final firstName =
        (user?.fullName ?? user?.displayName ?? 'Farmer').split(' ').first;

    return Scaffold(
      backgroundColor: AppColors.backgroundCream,
      drawer: const NavDrawer(),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () async {
          if (user != null) {
            await Future.wait([
              crops.fetchCrops(user.id),
              notifs.fetchAll(user.id),
              _loadDiseases(),
            ]);
            final refreshedLocation =
                _resolveFarmLocation(auth.currentUser, crops.activeCrops);
            if (refreshedLocation != null && refreshedLocation.isNotEmpty) {
              await _loadWeather(refreshedLocation);
            }
          }
        },
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              floating: true,
              pinned: false,
              backgroundColor: AppColors.backgroundCream,
              automaticallyImplyLeading: false,
              titleSpacing: 0,
              title: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(children: [
                  Builder(
                    builder: (ctx) => GestureDetector(
                      onTap: () => Scaffold.of(ctx).openDrawer(),
                      child: CircleAvatar(
                        radius: 20,
                        backgroundColor: AppColors.primaryLight,
                        backgroundImage: user?.avatarUrl != null
                            ? CachedNetworkImageProvider(user!.avatarUrl!)
                            : null,
                        child: user?.avatarUrl == null
                            ? Text(firstName[0].toUpperCase(),
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold))
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(children: [
                          Text(_greeting(),
                              style: const TextStyle(
                                  fontSize: 10,
                                  color: AppColors.textGray,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.5)),
                          if (notifs.missedTasks.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                  color: Colors.red,
                                  borderRadius: BorderRadius.circular(4)),
                              child: const Text('ACTION REQUIRED',
                                  style: TextStyle(
                                      fontSize: 8,
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ]),
                        Row(children: [
                          Text('$firstName!',
                              style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textDark)),
                        ]),
                      ],
                    ),
                  ),
                  Stack(children: [
                    IconButton(
                      icon: const Icon(Icons.notifications_outlined,
                          color: AppColors.textDark),
                      onPressed: () => _pushNotifications(context),
                    ),
                    if (notifs.unreadCount > 0)
                      Positioned(
                        right: 8,
                        top: 8,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                              color: Colors.red, shape: BoxShape.circle),
                        ),
                      ),
                  ]),
                ]),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // Search
                  _SearchBar(
                    controller: _searchCtrl,
                    onChanged: (value) =>
                        setState(() => _searchQuery = value.trimLeft()),
                    onClear: () {
                      _searchCtrl.clear();
                      setState(() => _searchQuery = '');
                    },
                  ),
                  const SizedBox(height: 24),

                  // Farm Vitality
                  _SectionHeader(
                    title: 'Farm Vitality',
                    sub: 'Combined Crop Performance',
                    onViewAll: allRecentActiveCrops.isEmpty
                        ? null
                        : () =>
                            _showVitalityDialog(context, allRecentActiveCrops),
                  ),
                  const SizedBox(height: 12),
                  _buildVitality(crops, dashboardActiveCrops),
                  const SizedBox(height: 24),

                  // Active Crops
                  _SectionHeader(
                    title: 'Active Crops',
                    onViewAll: widget.onOpenMyCrops,
                  ),
                  const SizedBox(height: 12),
                  _buildActiveCrops(context, dashboardActiveCrops),
                  const SizedBox(height: 24),

                  if (hasSearchQuery &&
                      dashboardActiveCrops.isEmpty &&
                      filteredDiseases.isEmpty)
                    _emptyState(
                      Icons.search_off_rounded,
                      'No crops or diseases match "${_searchQuery.trim()}".',
                    ),
                  if (hasSearchQuery &&
                      dashboardActiveCrops.isEmpty &&
                      filteredDiseases.isEmpty)
                    const SizedBox(height: 24),

                  // Today's Tasks
                  _TodayTasksCard(
                    notifs: notifs,
                    onViewAll: () => _pushNotifications(context),
                  ),
                  const SizedBox(height: 24),

                  // Smart Tip
                  _SmartTipCard(
                    message: smartTip.message,
                    actionLabel: smartTip.actionLabel,
                    onLearnMore: switch (smartTip.action) {
                      _SmartTipAction.openNotifications => () =>
                          _pushNotifications(context),
                      _SmartTipAction.openLibrary => () =>
                          _pushLibrary(context),
                      _SmartTipAction.none => null,
                    },
                  ),
                  const SizedBox(height: 24),

                  // Common Diseases
                  _SectionHeader(
                    title: 'Common Diseases',
                    sub: farmLocation != null ? '📍 $farmLocation' : null,
                    onViewAll: () => _pushLibrary(context),
                  ),
                  const SizedBox(height: 12),
                  _buildDiseases(context, filteredDiseases),
                ]),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'dashboard_crop_doctor_fab',
        onPressed: () => _openChat(context),
        tooltip: 'Open crop doctor',
        backgroundColor: AppColors.buttonOrange,
        child: const Icon(
          Icons.energy_savings_leaf_rounded,
          color: Colors.white,
          size: 24,
        ),
      ),
    );
  }

  void _openChat(BuildContext ctx) => Navigator.push(
      ctx,
      MaterialPageRoute(
          builder: (_) => const ChatScreen(startFreshSession: true)));
  void _pushNotifications(BuildContext ctx) => Navigator.push(
      ctx, MaterialPageRoute(builder: (_) => const NotificationsScreen()));
  void _pushLibrary(BuildContext ctx) => Navigator.push(
      ctx, MaterialPageRoute(builder: (_) => const LibraryScreen()));

  Widget _buildVitality(
    CropsProvider crops,
    List<CropModel> activeCrops,
  ) {
    if (crops.isLoading) {
      return const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(
              child: CircularProgressIndicator(color: AppColors.primary)));
    }
    if (activeCrops.isEmpty) {
      return _emptyState(Icons.energy_savings_leaf_outlined, 'No crops yet.');
    }
    return SizedBox(
      height: 152,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: activeCrops.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) => _VitalityCard(
          crop: activeCrops[i],
          onTap: () => _openCropProgress(context, activeCrops[i]),
        ),
      ),
    );
  }

  Future<void> _openCropProgress(BuildContext ctx, CropModel crop) async {
    await Navigator.push(
      ctx,
      MaterialPageRoute(
        builder: (_) => CropDetailScreen(crop: crop, initialTabIndex: 2),
      ),
    );
    if (!mounted) return;
    final user = context.read<AuthProvider>().currentUser;
    if (user != null) {
      await context.read<CropsProvider>().fetchCrops(user.id);
    }
  }

  Future<void> _showVitalityDialog(
    BuildContext context,
    List<CropModel> crops,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Expanded(
                    child: Text(
                      'All Active Crop Vitality',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textDark,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Tap any crop to open its tracked progress.',
                style: TextStyle(fontSize: 12, color: AppColors.textGray),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: crops.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, index) {
                    final crop = crops[index];
                    final score = crop.latestHealthScore ?? 0;
                    final trend = switch (crop.latestProgressStatus) {
                      ProgressStatus.improving => 'Improving',
                      ProgressStatus.worsening => 'Needs attention',
                      ProgressStatus.stable => 'Stable',
                      _ => 'Tracking',
                    };
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        crop.cropName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textDark,
                        ),
                      ),
                      subtitle: Text(
                        '${crop.cropType.name.toUpperCase()} • $trend',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textGray,
                        ),
                      ),
                      trailing: Text(
                        '${score.toStringAsFixed(0)}%',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textDark,
                        ),
                      ),
                      onTap: () async {
                        Navigator.of(dialogContext).pop();
                        await _openCropProgress(context, crop);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActiveCrops(BuildContext ctx, List<CropModel> activeCrops) {
    if (activeCrops.isEmpty) {
      return _emptyState(Icons.grass, 'No active crops.');
    }
    return SizedBox(
      height: 148,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: activeCrops.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) {
          final crop = activeCrops[i];
          return GestureDetector(
            onTap: () async {
              await Navigator.push(
                ctx,
                MaterialPageRoute(builder: (_) => CropDetailScreen(crop: crop)),
              );
              if (!mounted) return;
              final user = context.read<AuthProvider>().currentUser;
              if (user != null) {
                await context.read<CropsProvider>().fetchCrops(user.id);
              }
            },
            child: _ActiveCropCard(
              crop: crop,
              previewImageFuture: _previewImageFor(crop.id),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDiseases(BuildContext ctx, List<DiseaseKnowledgeModel> items) {
    if (items.isEmpty) {
      return Container(
        height: 160,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.menu_book_rounded,
              color: AppColors.primary,
              size: 28,
            ),
            const SizedBox(height: 10),
            const Text(
              'No disease knowledge synced yet.',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 4),
            const Expanded(
              child: Text(
                'Import or sync your disease dataset to show real crop risks in this section.',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textGray,
                  height: 1.35,
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomLeft,
              child: TextButton(
                onPressed: () => _pushLibrary(ctx),
                child: const Text('Open Library'),
              ),
            ),
          ],
        ),
      );
    }
    return SizedBox(
      height: 160,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) => _DiseaseCard(
          name: humanizeDiseaseLabel(items[i].diseaseName),
          risk: _diseaseRiskLabel(items[i]),
          color: _diseaseAccentColor(items[i]),
          onTap: () => _pushLibrary(ctx),
        ),
      ),
    );
  }

  Widget _emptyState(IconData icon, String msg) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Column(children: [
          Icon(icon, color: AppColors.textLightGray, size: 40),
          const SizedBox(height: 8),
          Text(msg, style: const TextStyle(color: AppColors.textGray)),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? sub;
  final VoidCallback? onViewAll;
  const _SectionHeader({required this.title, this.sub, this.onViewAll});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textDark)),
          if (sub != null)
            Text(sub!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 12, color: AppColors.textGray)),
        ]),
      ),
      if (onViewAll != null)
        TextButton(
          onPressed: onViewAll,
          child: const Text('View All',
              style: TextStyle(color: AppColors.primary, fontSize: 13)),
        ),
    ]);
  }
}

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const _SearchBar({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search crops or diseases',
        prefixIcon:
            const Icon(Icons.search, color: AppColors.textGray, size: 20),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                onPressed: onClear,
                icon: const Icon(Icons.close, color: AppColors.textGray),
              ),
        filled: true,
        fillColor: AppColors.backgroundWhite,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
    );
  }
}

class _VitalityCard extends StatelessWidget {
  final CropModel crop;
  final VoidCallback onTap;
  const _VitalityCard({required this.crop, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final score = crop.latestHealthScore ?? 0;
    String trendLabel = 'Stable';
    Color trendColor = AppColors.textGray;
    IconData trendIcon = Icons.trending_flat_rounded;
    if (crop.latestProgressStatus == ProgressStatus.improving) {
      trendLabel = 'Improving';
      trendColor = AppColors.primary;
      trendIcon = Icons.trending_up_rounded;
    } else if (crop.latestProgressStatus == ProgressStatus.worsening) {
      trendLabel = 'Needs attention';
      trendColor = Colors.red;
      trendIcon = Icons.trending_down_rounded;
    }
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 168,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(crop.cropType.name.toUpperCase(),
              style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textGray,
                  letterSpacing: 0.5)),
          const SizedBox(height: 4),
          Text(
            crop.cropName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 8),
          Text('${score.toStringAsFixed(0)}%',
              style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textDark)),
          const Spacer(),
          SizedBox(
            height: 32,
            child: CustomPaint(
              painter: _SparklinePainter(score: score),
              size: Size.infinite,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(trendIcon, size: 13, color: trendColor),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  trendLabel,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: trendColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ]),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final double score;
  const _SparklinePainter({required this.score});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.primary
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final s = score.clamp(1.0, 99.0);
    final pts = [
      Offset(0, size.height * (1 - (s - 10) / 100).clamp(0.0, 1.0)),
      Offset(
          size.width * 0.25, size.height * (1 - (s + 5) / 100).clamp(0.0, 1.0)),
      Offset(
          size.width * 0.5, size.height * (1 - (s - 5) / 100).clamp(0.0, 1.0)),
      Offset(
          size.width * 0.75, size.height * (1 - (s + 3) / 100).clamp(0.0, 1.0)),
      Offset(size.width, size.height * (1 - s / 100).clamp(0.0, 1.0)),
    ];
    final path = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (var i = 1; i < pts.length; i++) {
      path.lineTo(pts[i].dx, pts[i].dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_SparklinePainter o) => o.score != score;
}

class _ActiveCropCard extends StatelessWidget {
  final CropModel crop;
  final Future<String?> previewImageFuture;

  const _ActiveCropCard({
    required this.crop,
    required this.previewImageFuture,
  });

  Color _color(CropStatus s) {
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
    return Container(
      width: 140,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: crop.status == CropStatus.recovering
            ? Border.all(color: Colors.orange, width: 2)
            : null,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Stack(children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            child: SizedBox(
              height: 100,
              width: double.infinity,
              child: FutureBuilder<String?>(
                future: previewImageFuture,
                builder: (context, snapshot) {
                  final imageUrl = snapshot.data?.trim();
                  if (imageUrl != null && imageUrl.isNotEmpty) {
                    return AppImageReference(
                      imageRef: imageUrl,
                      fit: BoxFit.cover,
                      placeholder: _DashboardCropPlaceholder(crop: crop),
                      errorWidget: _DashboardCropPlaceholder(crop: crop),
                    );
                  }
                  return _DashboardCropPlaceholder(crop: crop);
                },
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: _color(crop.status),
                  borderRadius: BorderRadius.circular(8)),
              child: Text(crop.status.name.toUpperCase(),
                  style: const TextStyle(
                      fontSize: 9,
                      color: Colors.white,
                      fontWeight: FontWeight.bold)),
            ),
          ),
        ]),
        Padding(
          padding: const EdgeInsets.all(10),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(crop.cropName,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            if (crop.plotCode != null)
              Text(crop.plotCode!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(fontSize: 11, color: AppColors.textGray)),
          ]),
        ),
      ]),
    );
  }
}

class _DashboardCropPlaceholder extends StatelessWidget {
  final CropModel crop;

  const _DashboardCropPlaceholder({required this.crop});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.primaryLight.withOpacity(0.3),
      child: Center(
        child: Text(crop.cropType.name[0].toUpperCase(),
            style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: AppColors.primary.withOpacity(0.5))),
      ),
    );
  }
}

class _TodayTasksCard extends StatefulWidget {
  final NotificationsProvider notifs;
  final VoidCallback onViewAll;
  const _TodayTasksCard({required this.notifs, required this.onViewAll});

  @override
  State<_TodayTasksCard> createState() => _TodayTasksCardState();
}

class _TodayTasksCardState extends State<_TodayTasksCard> {
  static const int _collapsedVisibleCount = 5;
  bool _expanded = false;

  Future<void> _openTask(BuildContext context, TreatmentTaskModel task) async {
    final crops = context.read<CropsProvider>();
    CropModel? crop;

    for (final candidate in crops.activeCrops) {
      if (candidate.id == task.cropId) {
        crop = candidate;
        break;
      }
    }

    if (crop == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not find the linked crop for this task.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CropDetailScreen(
          crop: crop!,
          initialTabIndex: 1,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final todayTasks = widget.notifs.todayTasks;
    final missedTasks = widget.notifs.missedTasks;
    final totalCount = todayTasks.length + missedTasks.length;
    final showingAll = _expanded || totalCount <= _collapsedVisibleCount;
    final visibleMissed = showingAll
        ? missedTasks
        : missedTasks.take(_collapsedVisibleCount).toList(growable: false);
    final remainingSlots = showingAll
        ? todayTasks.length
        : (_collapsedVisibleCount - visibleMissed.length)
            .clamp(0, _collapsedVisibleCount);
    final visibleToday = showingAll
        ? todayTasks
        : todayTasks.take(remainingSlots).toList(growable: false);
    final hiddenCount = totalCount - visibleMissed.length - visibleToday.length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ─── Header ───────────────────────────────────────────────────────
        Row(children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
                color: AppColors.primaryLight.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.check_box_rounded,
                color: AppColors.primary, size: 18),
          ),
          const SizedBox(width: 8),
          const Text("Today's Tasks",
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark)),
          const SizedBox(width: 6),
          if (totalCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                  color:
                      missedTasks.isNotEmpty ? Colors.red : AppColors.primary,
                  borderRadius: BorderRadius.circular(10)),
              child: Text('$totalCount',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
            ),
          const Spacer(),
          if (totalCount > 0)
            GestureDetector(
              onTap: widget.onViewAll,
              child: const Text('View All',
                  style: TextStyle(
                      fontSize: 12,
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600)),
            ),
        ]),
        const SizedBox(height: 12),

        // ─── Empty state ──────────────────────────────────────────────────
        if (totalCount == 0)
          const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('No pending tasks for today. Great job! 🎉',
                  style: TextStyle(color: AppColors.textGray)))
        else ...[
          // ─── Missed tasks ──────────────────────────────────────────────
          if (missedTasks.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                const Icon(Icons.warning_amber_rounded,
                    size: 14, color: Colors.red),
                const SizedBox(width: 4),
                Text('${missedTasks.length} Overdue',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.red)),
              ]),
            ),
            ...visibleMissed.map((t) => _DashboardTaskRow(
                  task: t,
                  isMissed: true,
                  onDone: () => _openTask(context, t),
                )),
            if (visibleToday.isNotEmpty) const SizedBox(height: 8),
          ],

          // ─── Today's pending tasks ─────────────────────────────────────
          if (visibleToday.isNotEmpty) ...[
            if (missedTasks.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  const Icon(Icons.schedule,
                      size: 14, color: AppColors.primary),
                  const SizedBox(width: 4),
                  Text('${todayTasks.length} Due Today',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary)),
                ]),
              ),
            ...visibleToday.map((t) => _DashboardTaskRow(
                  task: t,
                  isMissed: false,
                  onDone: () => _openTask(context, t),
                )),
          ],
          if (hiddenCount > 0 ||
              (_expanded && totalCount > _collapsedVisibleCount)) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _expanded = !_expanded),
                icon: Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: AppColors.primary,
                ),
                label: Text(
                  _expanded ? 'Show less' : 'See more ($hiddenCount)',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ],
      ]),
    );
  }
}

class _DashboardTaskRow extends StatelessWidget {
  final TreatmentTaskModel task;
  final bool isMissed;
  final VoidCallback onDone;
  const _DashboardTaskRow(
      {required this.task, required this.isMissed, required this.onDone});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.backgroundCream,
        borderRadius: BorderRadius.circular(10),
        border: Border(
            left: BorderSide(
                color: isMissed ? Colors.red : AppColors.primary, width: 3)),
      ),
      child: Row(children: [
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(task.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDark)),
            const SizedBox(height: 2),
            Row(children: [
              Icon(
                isMissed ? Icons.warning_amber : Icons.schedule,
                size: 11,
                color: isMissed ? Colors.red : AppColors.textGray,
              ),
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  isMissed
                      ? 'Overdue — ${_dueDateLabel(task.dueAt)}'
                      : 'Due ${_dueTimeLabel(task.dueAt)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11,
                      color: isMissed ? Colors.red : AppColors.textGray),
                ),
              ),
            ]),
          ]),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: onDone,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
                color: isMissed ? Colors.orange : AppColors.primary,
                borderRadius: BorderRadius.circular(8)),
            child: const Text(
              'OPEN',
              style: TextStyle(
                  fontSize: 11,
                  color: Colors.white,
                  fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ]),
    );
  }

  String _dueTimeLabel(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return 'today at $h:$m';
  }

  String _dueDateLabel(DateTime dt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${months[dt.month - 1]} ${dt.day}';
  }
}

class _SmartTipCard extends StatelessWidget {
  final String message;
  final String? actionLabel;
  final VoidCallback? onLearnMore;

  const _SmartTipCard({
    required this.message,
    this.actionLabel,
    this.onLearnMore,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          color: AppColors.primary, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.lightbulb_outline, color: Colors.white70, size: 20),
          SizedBox(width: 8),
          Text('Smart Tip',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15)),
        ]),
        const SizedBox(height: 10),
        Text(
          message,
          style:
              const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
        ),
        if (onLearnMore != null && actionLabel != null) ...[
          const SizedBox(height: 14),
          OutlinedButton(
            onPressed: onLearnMore,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white, width: 1),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
            ),
            child: Text(actionLabel!,
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        ],
      ]),
    );
  }
}

enum _SmartTipAction { none, openLibrary, openNotifications }

class _SmartTipContent {
  final String message;
  final String? actionLabel;
  final _SmartTipAction action;

  const _SmartTipContent({
    required this.message,
    this.actionLabel,
    this.action = _SmartTipAction.none,
  });
}

class _DiseaseCard extends StatelessWidget {
  final String name;
  final String risk;
  final Color color;
  final VoidCallback onTap;
  const _DiseaseCard(
      {required this.name,
      required this.risk,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 140,
        decoration: BoxDecoration(
            color: AppColors.primaryDark,
            borderRadius: BorderRadius.circular(14)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.bug_report_outlined,
                    color: Colors.white54, size: 32),
                const Spacer(),
                Text(name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 14)),
                Text(risk,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ]),
        ),
      ),
    );
  }
}
