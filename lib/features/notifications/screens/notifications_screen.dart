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
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                        color: Colors.red, borderRadius: BorderRadius.circular(10)),
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
                    overdueTasks: notifs.missedTasks,
                    notifications: notifs.notifications
                        .where((n) =>
                            n.type == NotificationType.progressAlert ||
                            n.type == NotificationType.general)
                        .toList(),
                    onMarkRead: notifs.markRead,
                    onOpenTask: _openTask),
                _TasksTab(
                    todayTasks: notifs.todayTasks,
                    onOpenTask: _openTask),
                _RemindersTab(
                    tomorrowTasks: notifs.tomorrowTasks),
              ],
            ),
    );
  }
}

// ─── Alerts Tab ───────────────────────────────────────────────────────────

class _AlertsTab extends StatelessWidget {
  final List<TreatmentTaskModel> overdueTasks;
  final List<NotificationModel> notifications;
  final Future<void> Function(String) onMarkRead;
  final Future<void> Function(TreatmentTaskModel task) onOpenTask;

  const _AlertsTab({
    required this.overdueTasks,
    required this.notifications,
    required this.onMarkRead,
    required this.onOpenTask,
  });

  @override
  Widget build(BuildContext context) {
    if (overdueTasks.isEmpty && notifications.isEmpty) {
      return _emptyState(
          icon: Icons.check_circle_outline,
          message: 'No critical alerts',
          sub: 'Your crops are doing well!');
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (overdueTasks.isNotEmpty) ...[
          _SectionLabel(
            label: 'Overdue Tasks',
            count: overdueTasks.length,
            color: Colors.red,
          ),
          const SizedBox(height: 8),
          ...overdueTasks.map(
            (task) => _TaskCard(
              task: task,
              isMissed: true,
              actionLabel: 'OPEN DAILY PLAN',
              onAction: () => onOpenTask(task),
            ),
          ),
          if (notifications.isNotEmpty) const SizedBox(height: 16),
        ],
        if (notifications.isNotEmpty) ...[
          _SectionLabel(
            label: 'System Alerts',
            count: notifications.length,
            color: Colors.orange,
          ),
          const SizedBox(height: 8),
          ...notifications.map((n) {
            final isCritical = n.type == NotificationType.progressAlert;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _AlertCard(
                notification: n,
                borderColor: isCritical ? Colors.red : Colors.orange,
                onMarkRead: onMarkRead,
                action: isCritical
                    ? ElevatedButton.icon(
                        onPressed: () => onMarkRead(n.id),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.done, size: 16),
                        label: const Text('MARK READ',
                            style: TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 12)),
                      )
                    : null,
              ),
            );
          }),
        ],
      ],
    );
  }
}

// ─── Tasks Tab ────────────────────────────────────────────────────────────

class _TasksTab extends StatelessWidget {
  final List<TreatmentTaskModel> todayTasks;
  final Future<void> Function(TreatmentTaskModel task) onOpenTask;
  const _TasksTab({required this.todayTasks, required this.onOpenTask});

  @override
  Widget build(BuildContext context) {
    if (todayTasks.isEmpty) {
      return _emptyState(
          icon: Icons.task_alt, message: 'No tasks due', sub: 'All caught up!');
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionLabel(
            label: "Today's Tasks",
            count: todayTasks.length,
            color: AppColors.primary),
        const SizedBox(height: 8),
        ...todayTasks.map((t) => _TaskCard(
              task: t,
              isMissed: false,
              actionLabel: 'OPEN DAILY PLAN',
              onAction: () => onOpenTask(t),
            )),
      ],
    );
  }
}

// ─── Reminders Tab ────────────────────────────────────────────────────────

class _RemindersTab extends StatelessWidget {
  final List<TreatmentTaskModel> tomorrowTasks;
  const _RemindersTab({required this.tomorrowTasks});

  @override
  Widget build(BuildContext context) {
    if (tomorrowTasks.isEmpty) {
      return _emptyState(
          icon: Icons.notifications_none,
          message: 'No reminders',
          sub: 'Reminders will appear here');
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionLabel(
          label: 'Tomorrow',
          count: tomorrowTasks.length,
          color: AppColors.primaryMedium,
        ),
        const SizedBox(height: 8),
        ...tomorrowTasks.map(
          (task) => _TaskCard(
            task: task,
            isMissed: false,
            actionLabel: 'AVAILABLE TOMORROW',
            onAction: null,
          ),
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
  final Widget? action;
  const _AlertCard({
    required this.notification,
    required this.borderColor,
    required this.onMarkRead,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: notification.isRead ? Colors.white : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: borderColor, width: 4)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
                decoration: BoxDecoration(
                    shape: BoxShape.circle, color: borderColor),
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
              style:
                  const TextStyle(fontSize: 12, color: AppColors.textLightGray),
            ),
            const Spacer(),
            if (action != null) action!,
            if (!notification.isRead && action == null)
              TextButton(
                onPressed: () => onMarkRead(notification.id),
                style:
                    TextButton.styleFrom(foregroundColor: AppColors.primary),
                child: const Text('Mark read', style: TextStyle(fontSize: 12)),
              ),
          ]),
        ]),
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
            style: const TextStyle(
                fontWeight: FontWeight.w700, fontSize: 15)),
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(actionLabel,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700)),
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
    {required IconData icon,
    required String message,
    required String sub}) {
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
