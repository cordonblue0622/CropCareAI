import 'dart:async';

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
import 'widgets/farm_weather_sheet.dart';
import '../../library/library_screen.dart';
import '../../chat/screens/chat_screen.dart';
import '../../account/nav_drawer.dart';
import '../../onboarding/guided_tour/guided_tour_targets.dart';

class DashboardScreen extends StatefulWidget {
  final VoidCallback? onOpenMyCrops;
  final ScrollController? scrollController;

  const DashboardScreen({
    super.key,
    this.onOpenMyCrops,
    this.scrollController,
  });

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
  Timer? _weatherRefreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDiseases());
    _weatherRefreshTimer = Timer.periodic(const Duration(minutes: 30), (_) {
      final location = _weatherLocationQuery;
      if (location != null && location.isNotEmpty) _loadWeather(location);
    });
  }

  @override
  void dispose() {
    _weatherRefreshTimer?.cancel();
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

  Future<FarmWeatherSnapshot?> _loadWeather(String locationQuery) async {
    if (!mounted) return null;

    setState(() {
      _weatherLocationQuery = locationQuery;
      _isLoadingWeather = true;
    });

    final weather = await _weatherService.fetchCurrentConditions(locationQuery);

    if (!mounted) return weather;
    setState(() {
      _weather = weather;
      _isLoadingWeather = false;
    });
    return weather;
  }

  Future<void> _showWeatherForecast() async {
    final location =
        (_weatherLocationQuery ?? _weather?.locationLabel ?? '').trim();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.primaryDark.withValues(alpha: 0.36),
      builder: (_) => FarmWeatherSheet(
        locationQuery: location.isEmpty ? 'Farm location' : location,
        initialWeather: _weather,
        loadWeather: () => location.isEmpty
            ? Future<FarmWeatherSnapshot?>.value()
            : _loadWeather(location),
      ),
    );
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
      setState(() => _weather = null);
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
    if (allActive.isEmpty) return [];

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

  String _diseaseCropLabel(DiseaseKnowledgeModel disease) {
    final crop = disease.cropType.name;
    return '${crop[0].toUpperCase()}${crop.substring(1)} disease guide';
  }

  Widget _weatherGlyph(FarmWeatherSnapshot? weather) {
    if (_isLoadingWeather && weather == null) {
      return const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: Colors.white,
        ),
      );
    }

    final condition = weather?.conditionLabel.toLowerCase() ?? '';
    final code = weather?.weatherCode ?? -1;
    final isNight = weather != null && !weather.isDay;
    if (condition.contains('thunder') || code >= 95) {
      return const Stack(
        alignment: Alignment.center,
        children: [
          Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(
              Icons.cloud_outlined,
              color: Color(0xFFB9C1C9),
              size: 25,
            ),
          ),
          Padding(
            padding: EdgeInsets.only(top: 11, left: 2),
            child: Icon(
              Icons.flash_on_rounded,
              color: Color(0xFFFFC247),
              size: 15,
            ),
          ),
        ],
      );
    }
    if (condition.contains('snow') ||
        condition.contains('sleet') ||
        (code >= 71 && code <= 86)) {
      return const Stack(
        alignment: Alignment.center,
        children: [
          Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(
              Icons.cloud_outlined,
              color: Colors.white,
              size: 24,
            ),
          ),
          Padding(
            padding: EdgeInsets.only(top: 17),
            child: Icon(
              Icons.ac_unit,
              color: Color(0xFF8ED8F8),
              size: 11,
            ),
          ),
        ],
      );
    }
    if (condition.contains('rain') ||
        condition.contains('drizzle') ||
        condition.contains('shower') ||
        (code >= 51 && code <= 67) ||
        (code >= 80 && code <= 82)) {
      return const Stack(
        alignment: Alignment.center,
        children: [
          Padding(
            padding: EdgeInsets.only(top: 0),
            child: Icon(
              Icons.cloud_outlined,
              color: Color(0xFFB9C1C9),
              size: 24,
            ),
          ),
          Padding(
            padding: EdgeInsets.only(top: 18),
            child: Icon(
              Icons.water_drop_rounded,
              color: Color(0xFF56B4E9),
              size: 12,
            ),
          ),
        ],
      );
    }
    if (condition.contains('fog') ||
        condition.contains('mist') ||
        code == 45 ||
        code == 48) {
      return const Icon(
        Icons.cloud_outlined,
        color: Color(0xFFB9C1C9),
        size: 25,
      );
    }
    if (condition.contains('partly') ||
        condition.contains('mostly cloudy') ||
        condition.contains('mainly clear') ||
        condition.contains('few clouds') ||
        code == 1 ||
        code == 2) {
      return Stack(
        alignment: Alignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 7, bottom: 7),
            child: Icon(
              isNight ? Icons.nights_stay_outlined : Icons.wb_sunny_outlined,
              color:
                  isNight ? const Color(0xFFA9D6F5) : const Color(0xFFFFC247),
              size: 20,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 5, right: 5),
            child: Icon(
              Icons.cloud_outlined,
              color: condition.contains('mainly clear') ||
                      condition.contains('few clouds') ||
                      code == 1
                  ? Colors.white
                  : const Color(0xFFB9C1C9),
              size: 22,
            ),
          ),
        ],
      );
    }
    if (condition.contains('cloud') ||
        condition.contains('overcast') ||
        code == 3) {
      if (isNight) {
        return const Stack(
          alignment: Alignment.center,
          children: [
            Padding(
              padding: EdgeInsets.only(left: 7, bottom: 7),
              child: Icon(
                Icons.nights_stay_outlined,
                color: Color(0xFFA9D6F5),
                size: 19,
              ),
            ),
            Padding(
              padding: EdgeInsets.only(top: 5, right: 5),
              child: Icon(
                Icons.cloud_outlined,
                color: Color(0xFFB9C1C9),
                size: 23,
              ),
            ),
          ],
        );
      }
      return const Icon(
        Icons.cloud_outlined,
        color: Color(0xFFB9C1C9),
        size: 25,
      );
    }
    if (isNight) {
      return const Icon(
        Icons.nights_stay_outlined,
        color: Color(0xFFA9D6F5),
        size: 24,
      );
    }
    return const Icon(
      Icons.wb_sunny_rounded,
      color: Color(0xFFFFC247),
      size: 24,
    );
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
          controller: widget.scrollController,
          slivers: [
            SliverAppBar(
              floating: true,
              pinned: false,
              toolbarHeight: 76,
              backgroundColor: AppColors.primary,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(18),
                ),
              ),
              automaticallyImplyLeading: false,
              titleSpacing: 0,
              title: Padding(
                key: AppTourKeys.dashboardWelcome,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(children: [
                  Tooltip(
                    message: 'Open farm management menu',
                    child: InkWell(
                      onTap: () => showFarmManagementMenu(context),
                      customBorder: const CircleBorder(),
                      child: CircleAvatar(
                        radius: 18,
                        backgroundColor: AppColors.surfaceLime,
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
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0)),
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
                                  color: Colors.white)),
                        ]),
                      ],
                    ),
                  ),
                  Tooltip(
                    message: _weather == null
                        ? _isLoadingWeather
                            ? 'Loading farm weather'
                            : 'View farm weather forecast'
                        : '${_weather!.conditionLabel}, ${_weather!.temperatureC.toStringAsFixed(0)}°C',
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _showWeatherForecast,
                        customBorder: const CircleBorder(),
                        child: SizedBox(
                          width: 36,
                          height: 36,
                          child: Center(child: _weatherGlyph(_weather)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Stack(key: AppTourKeys.notifications, children: [
                    IconButton(
                      icon: const Icon(Icons.notifications_outlined,
                          color: Colors.white),
                      onPressed: () => _pushNotifications(context),
                    ),
                    if (notifs.unreadCount > 0)
                      Positioned(
                        right: 2,
                        top: 2,
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 17),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          height: 17,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(
                              color: AppColors.primaryDark,
                              width: 1.5,
                            ),
                          ),
                          child: Text(
                            notifs.unreadCount > 99
                                ? '99+'
                                : '${notifs.unreadCount}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                  ]),
                ]),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 112),
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
                  const SizedBox(height: 8),
                  KeyedSubtree(
                    key: AppTourKeys.dashboardOverview,
                    child: _buildVitality(
                      crops,
                      dashboardActiveCrops,
                      allRecentActiveCrops,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Active Crops
                  _SectionHeader(
                    title: 'Active Crops',
                    onViewAll: widget.onOpenMyCrops,
                  ),
                  const SizedBox(height: 8),
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
                    const SizedBox(height: 16),

                  // Today's Tasks
                  KeyedSubtree(
                    key: AppTourKeys.dailyTasks,
                    child: _TodayTasksCard(
                      notifs: notifs,
                      onViewAll: () => _pushNotifications(context),
                    ),
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
                  const SizedBox(height: 8),
                  _buildDiseases(context, filteredDiseases.take(3).toList()),
                ]),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        key: AppTourKeys.cropDoctor,
        heroTag: 'dashboard_crop_doctor_fab',
        onPressed: () => _openChat(context),
        tooltip: 'Open crop doctor',
        backgroundColor: AppColors.primaryDark,
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
    List<CropModel> allActiveCrops,
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
    return _FarmVitalityChart(
      crops: activeCrops,
      allActiveCrops: allActiveCrops,
      onCropTap: (crop) => _openCropProgress(context, crop),
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
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.primaryDark.withValues(alpha: 0.36),
      builder: (sheetContext) => _VitalitySheet(
        crops: crops,
        onCropTap: (crop) {
          Navigator.of(sheetContext).pop();
          _openCropProgress(context, crop);
        },
      ),
    );
  }

  Widget _buildActiveCrops(BuildContext ctx, List<CropModel> activeCrops) {
    if (activeCrops.isEmpty) {
      return _emptyState(Icons.grass, 'No active crops.');
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryDark.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: activeCrops.asMap().entries.map((entry) {
          final crop = entry.value;
          return Column(
            children: [
              _ActiveCropCard(
                crop: crop,
                previewImageFuture: _previewImageFor(crop.id),
                onTap: () async {
                  await Navigator.push(
                    ctx,
                    MaterialPageRoute(
                      builder: (_) => CropDetailScreen(crop: crop),
                    ),
                  );
                  if (!mounted) return;
                  final user = context.read<AuthProvider>().currentUser;
                  if (user != null) {
                    await context.read<CropsProvider>().fetchCrops(user.id);
                  }
                },
              ),
              if (entry.key < activeCrops.length - 1)
                const Divider(height: 1, indent: 82),
            ],
          );
        }).toList(growable: false),
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
    return Container(
      decoration: BoxDecoration(
        color: AppColors.backgroundWhite,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderGreen),
      ),
      child: Column(
        children: items.asMap().entries.map((entry) {
          final disease = entry.value;
          return Column(
            children: [
              _DiseaseCard(
                name: humanizeDiseaseLabel(disease.diseaseName),
                cropLabel: _diseaseCropLabel(disease),
                onTap: () => _pushLibrary(ctx),
              ),
              if (entry.key < items.length - 1)
                const Divider(height: 1, indent: 62),
            ],
          );
        }).toList(growable: false),
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
              style: TextStyle(color: AppColors.primary, fontSize: 12)),
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
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.borderGreen),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.borderGreen),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
    );
  }
}

class _VitalitySheet extends StatelessWidget {
  final List<CropModel> crops;
  final ValueChanged<CropModel> onCropTap;

  const _VitalitySheet({required this.crops, required this.onCropTap});

  @override
  Widget build(BuildContext context) {
    final measuredScores = crops
        .map((crop) => crop.latestHealthScore)
        .whereType<double>()
        .map((score) => score.clamp(0, 100).toDouble())
        .toList(growable: false);
    final averageScore = measuredScores.isEmpty
        ? null
        : measuredScores.reduce((total, score) => total + score) /
            measuredScores.length;

    return FractionallySizedBox(
      heightFactor: 0.86,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.white.withValues(alpha: 0.97),
              AppColors.surfaceMint.withValues(alpha: 0.9),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  margin: const EdgeInsets.only(top: 10),
                  decoration: BoxDecoration(
                    color: AppColors.textGray.withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.66),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.92),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primaryDark.withValues(alpha: 0.08),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      _VitalityRing(score: averageScore, size: 72),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Farm Vitality',
                              style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textDark,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              averageScore == null
                                  ? 'No crop health scores recorded yet'
                                  : 'Average across ${measuredScores.length} of ${crops.length} active crops',
                              style: const TextStyle(
                                fontSize: 12,
                                height: 1.35,
                                color: AppColors.textGray,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                        color: AppColors.textGray,
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
                  itemCount: crops.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 9),
                  itemBuilder: (_, index) => _VitalityCropRow(
                    crop: crops[index],
                    onTap: () => onCropTap(crops[index]),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VitalityCropRow extends StatelessWidget {
  final CropModel crop;
  final VoidCallback onTap;

  const _VitalityCropRow({required this.crop, required this.onTap});

  String get _trendLabel => switch (crop.latestProgressStatus) {
        ProgressStatus.improving => 'Improving',
        ProgressStatus.worsening => 'Needs attention',
        ProgressStatus.stable => 'Stable',
        ProgressStatus.insufficientData => 'Awaiting trend',
        null => 'Awaiting trend',
      };

  IconData get _trendIcon => switch (crop.latestProgressStatus) {
        ProgressStatus.improving => Icons.trending_up_rounded,
        ProgressStatus.worsening => Icons.trending_down_rounded,
        ProgressStatus.stable => Icons.trending_flat_rounded,
        ProgressStatus.insufficientData => Icons.more_horiz_rounded,
        null => Icons.more_horiz_rounded,
      };

  Color get _statusColor => switch (crop.status) {
        CropStatus.healthy => AppColors.primary,
        CropStatus.recovering => Colors.orange,
        CropStatus.critical => Colors.red,
        CropStatus.monitoring => const Color(0xFF3D6FB4),
        CropStatus.archived => AppColors.textGray,
      };

  @override
  Widget build(BuildContext context) {
    final statusLabel = crop.status.name[0].toUpperCase() +
        crop.status.name.substring(1).toLowerCase();

    return Material(
      color: Colors.white.withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              _VitalityRing(score: crop.latestHealthScore, size: 56),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      crop.cropName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      crop.cropType.name.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textGray,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 6,
                      runSpacing: 5,
                      children: [
                        _VitalityLabel(
                          icon: Icons.circle,
                          label: statusLabel,
                          color: _statusColor,
                        ),
                        _VitalityLabel(
                          icon: _trendIcon,
                          label: _trendLabel,
                          color: AppColors.textMedium,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textGray,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VitalityRing extends StatelessWidget {
  final double? score;
  final double size;

  const _VitalityRing({required this.score, required this.size});

  Color _scoreColor(double value) {
    if (value >= 70) return AppColors.primary;
    if (value >= 40) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    final normalized = score?.clamp(0, 100).toDouble();
    final color =
        normalized == null ? AppColors.textLightGray : _scoreColor(normalized);

    return Semantics(
      label: normalized == null
          ? 'Health score not recorded'
          : 'Health score ${normalized.toStringAsFixed(0)} percent',
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox.expand(
              child: CircularProgressIndicator(
                value: normalized == null ? 0 : normalized / 100,
                strokeWidth: size >= 70 ? 7 : 6,
                strokeCap: StrokeCap.round,
                backgroundColor: color.withValues(alpha: 0.14),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
            Text(
              normalized == null ? '--' : '${normalized.toStringAsFixed(0)}%',
              style: TextStyle(
                fontSize: size >= 70 ? 15 : 12,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VitalityLabel extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _VitalityLabel({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _FarmVitalityChart extends StatelessWidget {
  final List<CropModel> crops;
  final List<CropModel> allActiveCrops;
  final ValueChanged<CropModel> onCropTap;

  const _FarmVitalityChart({
    required this.crops,
    required this.allActiveCrops,
    required this.onCropTap,
  });

  static const _barColors = [
    Color(0xFF24A148),
    Color(0xFF0F91A3),
    Color(0xFFE76F51),
    Color(0xFFF2B134),
    Color(0xFF3D6FB4),
  ];

  @override
  Widget build(BuildContext context) {
    final measuredScores = allActiveCrops
        .map((crop) => crop.latestHealthScore)
        .whereType<double>()
        .map((score) => score.clamp(0, 100).toDouble())
        .toList(growable: false);
    final averageScore = measuredScores.isEmpty
        ? null
        : measuredScores.reduce((total, score) => total + score) /
            measuredScores.length;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.84),
            AppColors.surfaceMint.withValues(alpha: 0.42),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryDark.withValues(alpha: 0.10),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.58),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
            ),
            child: Row(
              children: [
                _VitalityRing(score: averageScore, size: 78),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Overall farm vitality',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textDark)),
                      const SizedBox(height: 4),
                      Text(
                        averageScore == null
                            ? 'Add a health check to begin tracking.'
                            : 'Average across ${measuredScores.length} of ${allActiveCrops.length} crops',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textGray),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 2.05,
            children: crops.take(4).map((crop) {
              final rawScore = crop.latestHealthScore;
              final score = rawScore?.clamp(0, 100).toDouble();
              final color = _barColors[crops.indexOf(crop) % _barColors.length];
              final status = switch (crop.latestProgressStatus) {
                ProgressStatus.improving => 'Improving',
                ProgressStatus.worsening => 'Needs attention',
                ProgressStatus.stable => 'Stable',
                _ => 'Awaiting check-in',
              };
              return InkWell(
                onTap: () => onCropTap(crop),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.58),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      _VitalityRing(score: score, size: 38),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(crop.cropName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textDark)),
                            const SizedBox(height: 2),
                            Text(status,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 9, color: color)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(growable: false),
          ),
        ],
      ),
    );
  }
}

class _ActiveCropCard extends StatelessWidget {
  final CropModel crop;
  final Future<String?> previewImageFuture;
  final VoidCallback onTap;

  const _ActiveCropCard({
    required this.crop,
    required this.previewImageFuture,
    required this.onTap,
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
    final score = crop.latestHealthScore;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 54,
              width: 54,
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
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(crop.cropName,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 3),
                Text(
                  [crop.cropType.name, crop.locationLabel]
                      .whereType<String>()
                      .where((value) => value.trim().isNotEmpty)
                      .join(' • '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(fontSize: 11, color: AppColors.textGray),
                ),
                const SizedBox(height: 5),
                Text(
                  crop.status.name.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    color: _color(crop.status),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (score != null)
            Text(
              '${score.toStringAsFixed(0)}%',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppColors.textDark,
              ),
            ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right_rounded,
              size: 20, color: AppColors.textGray),
        ]),
      ),
    );
  }
}

class _DashboardCropPlaceholder extends StatelessWidget {
  final CropModel crop;

  const _DashboardCropPlaceholder({required this.crop});

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (crop.cropType) {
      CropType.tomato => (Icons.circle_rounded, const Color(0xFFD94B3D)),
      CropType.pechay => (Icons.grass_rounded, const Color(0xFF3A8F55)),
      CropType.pepper => (Icons.spa_rounded, const Color(0xFFDC7A2D)),
      CropType.eggplant => (Icons.egg_rounded, const Color(0xFF72518A)),
      CropType.squash => (Icons.eco_rounded, const Color(0xFFD6942B)),
    };
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        gradient: LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.38),
            color.withValues(alpha: 0.18),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(icon, size: 31, color: color),
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
  static const int _collapsedVisibleCount = 3;
  int _page = 0;

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
    final pageCount = (totalCount / _collapsedVisibleCount).ceil();
    final safePage = pageCount == 0 ? 0 : _page.clamp(0, pageCount - 1).toInt();
    final allTasks = [...missedTasks, ...todayTasks];
    final pageTasks = allTasks
        .skip(safePage * _collapsedVisibleCount)
        .take(_collapsedVisibleCount)
        .toList(growable: false);
    final visibleMissed =
        pageTasks.where(missedTasks.contains).toList(growable: false);
    final visibleToday =
        pageTasks.where(todayTasks.contains).toList(growable: false);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.backgroundWhite,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderGreen),
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
        const SizedBox(height: 8),

        if (totalCount > 0) ...[
          Row(
            children: [
              Expanded(
                child: _TaskMetric(
                  label: 'Due today',
                  value: todayTasks.length,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _TaskMetric(
                  label: 'Overdue',
                  value: missedTasks.length,
                  color: missedTasks.isEmpty
                      ? AppColors.textGray
                      : const Color(0xFFD94841),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],

        // ─── Empty state ──────────────────────────────────────────────────
        if (totalCount == 0)
          const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('No pending tasks for today.',
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
          if (pageCount > 1) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: 'Previous tasks',
                  onPressed: safePage == 0
                      ? null
                      : () => setState(() => _page = safePage - 1),
                  icon: const Icon(Icons.chevron_left),
                ),
                Text('${safePage + 1} / $pageCount',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                TextButton(
                  onPressed: safePage < pageCount - 1
                      ? () => setState(() => _page = safePage + 1)
                      : () => setState(() => _page = 0),
                  child: Text(
                      safePage < pageCount - 1 ? 'See more' : 'Show first'),
                ),
                IconButton(
                  tooltip: 'Next tasks',
                  onPressed: safePage >= pageCount - 1
                      ? null
                      : () => setState(() => _page = safePage + 1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
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
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color:
            isMissed ? const Color(0xFFFFF2EE) : AppColors.backgroundGreenLight,
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
        IconButton.filled(
          onPressed: onDone,
          tooltip: 'Open task',
          style: IconButton.styleFrom(
            backgroundColor: isMissed ? Colors.orange : AppColors.primary,
            minimumSize: const Size(34, 34),
            maximumSize: const Size(34, 34),
            padding: EdgeInsets.zero,
          ),
          icon: const Icon(Icons.chevron_right_rounded,
              size: 20, color: Colors.white),
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

class _TaskMetric extends StatelessWidget {
  final String label;
  final int value;
  final Color color;

  const _TaskMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Text('$value',
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w800, color: color)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textGray)),
          ),
        ],
      ),
    );
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceLime,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderGreen),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.lightbulb_outline, color: AppColors.primary, size: 20),
          SizedBox(width: 8),
          Text('Smart Tip',
              style: TextStyle(
                  color: AppColors.textDark,
                  fontWeight: FontWeight.w700,
                  fontSize: 14)),
        ]),
        const SizedBox(height: 8),
        Text(
          message,
          style: const TextStyle(
            color: AppColors.textMedium,
            fontSize: 13,
            height: 1.5,
          ),
        ),
        if (onLearnMore != null && actionLabel != null) ...[
          const SizedBox(height: 14),
          OutlinedButton(
            onPressed: onLearnMore,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primaryDark,
              side: const BorderSide(color: AppColors.primary, width: 1),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
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
  final String cropLabel;
  final VoidCallback onTap;
  const _DiseaseCard(
      {required this.name, required this.cropLabel, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.backgroundGreenLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.biotech_outlined,
                  color: AppColors.primary, size: 21),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.textDark,
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
                  const SizedBox(height: 2),
                  Text(cropLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.textGray, fontSize: 11)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textGray, size: 20),
          ],
        ),
      ),
    );
  }
}
