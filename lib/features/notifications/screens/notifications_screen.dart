import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/constants/app_enums.dart';
import '../../../data/models/crop_model.dart';
import '../../../data/models/notification_model.dart';
import '../../../data/models/treatment_task_model.dart';
import '../../auth/providers/auth_provider.dart';
import '../../crops/providers/crops_provider.dart';
import '../../crops/screens/crop_detail_screen.dart';
import '../providers/notifications_provider.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  int _alertPage = 0;
  int _taskPage = 0;
  int _reminderPage = 0;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _openTask(TreatmentTaskModel task) async {
    final crops = context.read<CropsProvider>();
    CropModel? crop;

    for (final candidate in crops.activeCrops) {
      if (candidate.id == task.cropId) {
        crop = candidate;
        break;
      }
    }

    crop ??= crops.crops.cast<CropModel?>().firstWhere(
          (candidate) => candidate?.id == task.cropId,
          orElse: () => null,
        );

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
          initialSelectedDate:
              DateTime(task.dueAt.year, task.dueAt.month, task.dueAt.day),
        ),
      ),
    );
  }

  Future<void> _openCropNotification(NotificationModel notification) async {
    final cropId = notification.cropId;
    if (cropId == null) return;
    final crops = context.read<CropsProvider>();
    CropModel? crop;
    for (final candidate in crops.crops) {
      if (candidate.id == cropId && !candidate.isDeleted) {
        crop = candidate;
        break;
      }
    }
    if (crop == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CropDetailScreen(crop: crop!, initialTabIndex: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final notifs = context.watch<NotificationsProvider>();
    final user = context.watch<AuthProvider>().currentUser;

    return Scaffold(
      backgroundColor: AppColors.backgroundCream,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundCream,
        title: const Text('Notifications',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
        actions: [
          if (notifs.unreadCount > 0)
            TextButton(
              onPressed: () async {
                // Mark all as read
                for (final n in notifs.unread) {
                  await notifs.markRead(n.id);
                }
              },
              child: const Text('Mark all read',
                  style: TextStyle(color: AppColors.primary, fontSize: 13)),
            ),
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.textGray),
            onPressed: () async {
              if (user != null) await notifs.fetchAll(user.id);
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textGray,
          tabs: [
            Tab(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Text('Alerts'),
                if (notifs.missedTasks.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(left: 4),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(10)),
                    child: Text(
                      '${notifs.missedTasks.length}',
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ),
              ]),
            ),
            const Tab(text: 'Tasks'),
            const Tab(text: 'Reminders'),
          ],
        ),
      ),
      body: notifs.isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : TabBarView(
              controller: _tabs,
              children: [
                _AlertsTab(
                    notifications: notifs.notifications
                        .where((n) =>
                            n.type == NotificationType.general ||
                            n.type == NotificationType.progressAlert)
                        .toList(),
                    page: _alertPage,
                    onPageChanged: (page) => setState(() => _alertPage = page),
                    onMarkRead: notifs.markRead,
                    onDelete: notifs.deleteNotification,
                    onOpenCrop: _openCropNotification),
                _TasksTab(
                    todayTasks: notifs.todayTasks,
                    missedTasks: notifs.missedTasks,
                    page: _taskPage,
                    onPageChanged: (page) => setState(() => _taskPage = page),
                    onOpenTask: _openTask),
                _RemindersTab(
                  tomorrowTasks: notifs.tomorrowTasks,
                  page: _reminderPage,
                  onPageChanged: (page) => setState(() => _reminderPage = page),
                ),
              ],
            ),
    );
  }
}

// ─── Alerts Tab ───────────────────────────────────────────────────────────

class _AlertsTab extends StatelessWidget {
  final List<NotificationModel> notifications;
  final int page;
  final ValueChanged<int> onPageChanged;
  final Future<void> Function(String) onMarkRead;
  final Future<void> Function(String) onDelete;
  final Future<void> Function(NotificationModel) onOpenCrop;

  const _AlertsTab({
    required this.notifications,
    required this.page,
    required this.onPageChanged,
    required this.onMarkRead,
    required this.onDelete,
    required this.onOpenCrop,
  });

  @override
  Widget build(BuildContext context) {
    if (notifications.isEmpty) {
      return _emptyState(
          icon: Icons.check_circle_outline,
          message: 'No critical alerts',
          sub: 'Your crops are doing well!');
    }
    const pageSize = 10;
    final pageCount = (notifications.length / pageSize).ceil();
    final safePage = page.clamp(0, pageCount - 1).toInt();
    final visible = notifications.skip(safePage * pageSize).take(pageSize);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionLabel(
            label: 'Notifications',
            count: notifications.length,
            color: Colors.orange),
        const SizedBox(height: 8),
        ...visible.map((n) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Dismissible(
                key: ValueKey(n.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  color: Colors.red,
                  child: const Icon(Icons.delete_outline, color: Colors.white),
                ),
                onDismissed: (_) => onDelete(n.id),
                child: _AlertCard(
                  notification: n,
                  borderColor: Colors.orange,
                  onMarkRead: onMarkRead,
                  onTap: n.type == NotificationType.progressAlert
                      ? () => onOpenCrop(n)
                      : null,
                ),
              ),
            )),
        if (pageCount > 1)
          _NotificationPager(
            page: safePage,
            pageCount: pageCount,
            onChanged: onPageChanged,
          ),
      ],
    );
  }
}

// ─── Tasks Tab ────────────────────────────────────────────────────────────

class _TasksTab extends StatelessWidget {
  final List<TreatmentTaskModel> todayTasks;
  final List<TreatmentTaskModel> missedTasks;
  final int page;
  final ValueChanged<int> onPageChanged;
  final Future<void> Function(TreatmentTaskModel task) onOpenTask;
  const _TasksTab({
    required this.todayTasks,
    required this.missedTasks,
    required this.page,
    required this.onPageChanged,
    required this.onOpenTask,
  });

  @override
  Widget build(BuildContext context) {
    final tasks = [...missedTasks, ...todayTasks];
    if (tasks.isEmpty) {
      return _emptyState(
          icon: Icons.task_alt, message: 'No tasks due', sub: 'All caught up!');
    }
    final pageCount = (tasks.length / 10).ceil();
    final safePage = page.clamp(0, pageCount - 1).toInt();
    final visibleTasks = tasks.skip(safePage * 10).take(10);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionLabel(
            label: "Crop Attention",
            count: tasks.length,
            color: AppColors.primary),
        const SizedBox(height: 8),
        ...visibleTasks.map((t) => _TaskCard(
              task: t,
              isMissed: missedTasks.contains(t),
              actionLabel: 'OPEN DAILY PLAN',
              onAction: () => onOpenTask(t),
            )),
        if (pageCount > 1)
          _NotificationPager(
            page: safePage,
            pageCount: pageCount,
            onChanged: onPageChanged,
          ),
      ],
    );
  }
}

class _NotificationPager extends StatelessWidget {
  final int page;
  final int pageCount;
  final ValueChanged<int> onChanged;

  const _NotificationPager({
    required this.page,
    required this.pageCount,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: page == 0 ? null : () => onChanged(page - 1),
            icon: const Icon(Icons.chevron_left),
          ),
          Text('${page + 1} / $pageCount',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          IconButton(
            onPressed: page >= pageCount - 1 ? null : () => onChanged(page + 1),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      );
}

// ─── Reminders Tab ────────────────────────────────────────────────────────

class _RemindersTab extends StatelessWidget {
  final List<TreatmentTaskModel> tomorrowTasks;
  final int page;
  final ValueChanged<int> onPageChanged;
  const _RemindersTab({
    required this.tomorrowTasks,
    required this.page,
    required this.onPageChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (tomorrowTasks.isEmpty) {
      return _emptyState(
          icon: Icons.notifications_none,
          message: 'No reminders',
          sub: 'Reminders will appear here');
    }
    const pageSize = 10;
    final pageCount = (tomorrowTasks.length / pageSize).ceil();
    final safePage = page.clamp(0, pageCount - 1).toInt();
    final visible = tomorrowTasks.skip(safePage * pageSize).take(pageSize);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionLabel(
          label: 'Tomorrow',
          count: tomorrowTasks.length,
          color: AppColors.primaryMedium,
        ),
        const SizedBox(height: 8),
        ...visible.map(
          (task) => _TaskCard(
            task: task,
            isMissed: false,
            actionLabel: 'AVAILABLE TOMORROW',
            onAction: null,
          ),
        ),
        if (pageCount > 1)
          _NotificationPager(
            page: safePage,
            pageCount: pageCount,
            onChanged: onPageChanged,
          ),
      ],
    );
  }
}

// ─── Shared widgets ───────────────────────────────────────────────────────

class _AlertCard extends StatelessWidget {
  final NotificationModel notification;
  final Color borderColor;
  final Future<void> Function(String) onMarkRead;
  final VoidCallback? onTap;
  const _AlertCard({
    required this.notification,
    required this.borderColor,
    required this.onMarkRead,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: notification.isRead ? const Color(0xFFF0F2F0) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: borderColor, width: 4)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(notification.title,
                    style: TextStyle(
                        fontWeight: notification.isRead
                            ? FontWeight.w600
                            : FontWeight.w800,
                        fontSize: 15,
                        color: AppColors.textDark)),
              ),
              if (!notification.isRead)
                Container(
                  width: 8,
                  height: 8,
                  decoration:
                      BoxDecoration(shape: BoxShape.circle, color: borderColor),
                ),
            ]),
            const SizedBox(height: 6),
            Text(notification.body,
                style: const TextStyle(
                    color: AppColors.textGray, fontSize: 13, height: 1.4)),
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.access_time,
                  size: 13, color: AppColors.textLightGray),
              const SizedBox(width: 4),
              Text(
                DateFormat('MMM d, HH:mm').format(notification.createdAt),
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textLightGray),
              ),
              const Spacer(),
              if (!notification.isRead)
                TextButton(
                  onPressed: () => onMarkRead(notification.id),
                  style:
                      TextButton.styleFrom(foregroundColor: AppColors.primary),
                  child:
                      const Text('Mark read', style: TextStyle(fontSize: 12)),
                ),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  final TreatmentTaskModel task;
  final bool isMissed;
  final String actionLabel;
  final VoidCallback? onAction;

  const _TaskCard({
    required this.task,
    required this.isMissed,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final isActionEnabled = onAction != null;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border(
            left: BorderSide(
                color: isMissed ? Colors.red : AppColors.primary, width: 4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(task.title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        if (task.description != null && task.description!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(task.description!,
              style: const TextStyle(
                  color: AppColors.textGray, fontSize: 13, height: 1.4)),
        ],
        const SizedBox(height: 8),
        Row(children: [
          Icon(
            isMissed ? Icons.warning_amber : Icons.schedule,
            size: 14,
            color: isMissed ? Colors.red : AppColors.textGray,
          ),
          const SizedBox(width: 4),
          Text(
            isMissed
                ? 'Due ${DateFormat('MMM d').format(task.dueAt)}'
                : isActionEnabled
                    ? 'Due today ${DateFormat('HH:mm').format(task.dueAt)}'
                    : 'Due tomorrow ${DateFormat('HH:mm').format(task.dueAt)}',
            style: TextStyle(
                fontSize: 12,
                color: isMissed
                    ? Colors.red
                    : isActionEnabled
                        ? AppColors.textGray
                        : AppColors.primaryMedium),
          ),
          const Spacer(),
          ElevatedButton(
            onPressed: onAction,
            style: ElevatedButton.styleFrom(
              backgroundColor: isActionEnabled
                  ? (isMissed ? Colors.orange : AppColors.primary)
                  : AppColors.textLightGray,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(actionLabel,
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        ]),
      ]),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _SectionLabel(
      {required this.label, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Text(label,
          style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: AppColors.textDark)),
      const SizedBox(width: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10)),
        child: Text('$count',
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.bold, color: color)),
      ),
    ]);
  }
}

Widget _emptyState(
    {required IconData icon, required String message, required String sub}) {
  return Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(icon, size: 56, color: AppColors.textLightGray),
      const SizedBox(height: 12),
      Text(message,
          style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark)),
      const SizedBox(height: 6),
      Text(sub,
          style: const TextStyle(color: AppColors.textGray, fontSize: 13)),
    ]),
  );
}
