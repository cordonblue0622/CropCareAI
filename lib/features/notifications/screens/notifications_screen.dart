import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/constants/app_enums.dart';
import '../../../data/models/notification_model.dart';
import '../../../data/models/treatment_task_model.dart';
import '../../auth/providers/auth_provider.dart';
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
                if (notifs.notifications
                    .where((n) => n.type == NotificationType.progressAlert && !n.isRead)
                    .isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(left: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                        color: Colors.red, borderRadius: BorderRadius.circular(10)),
                    child: Text(
                      '${notifs.notifications.where((n) => n.type == NotificationType.progressAlert && !n.isRead).length}',
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
                            n.type == NotificationType.progressAlert ||
                            n.type == NotificationType.general)
                        .toList(),
                    onMarkRead: notifs.markRead),
                _TasksTab(
                    todayTasks: notifs.todayTasks,
                    missedTasks: notifs.missedTasks,
                    onTaskDone: notifs.markTaskDone),
                _RemindersTab(
                    notifications: notifs.notifications
                        .where((n) =>
                            n.type == NotificationType.taskReminder ||
                            n.type == NotificationType.treatmentReminder)
                        .toList(),
                    onMarkRead: notifs.markRead),
              ],
            ),
    );
  }
}

// ─── Alerts Tab ───────────────────────────────────────────────────────────

class _AlertsTab extends StatelessWidget {
  final List<NotificationModel> notifications;
  final Future<void> Function(String) onMarkRead;
  const _AlertsTab({required this.notifications, required this.onMarkRead});

  @override
  Widget build(BuildContext context) {
    if (notifications.isEmpty) {
      return _emptyState(
          icon: Icons.check_circle_outline,
          message: 'No critical alerts',
          sub: 'Your crops are doing well!');
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: notifications.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        final n = notifications[i];
        final isCritical = n.type == NotificationType.progressAlert;
        return _AlertCard(
          notification: n,
          borderColor: isCritical ? Colors.red : Colors.orange,
          onMarkRead: onMarkRead,
          action: isCritical
              ? ElevatedButton.icon(
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.camera_alt, size: 16),
                  label: const Text('ANALYZE NOW',
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                )
              : null,
        );
      },
    );
  }
}

// ─── Tasks Tab ────────────────────────────────────────────────────────────

class _TasksTab extends StatelessWidget {
  final List<TreatmentTaskModel> todayTasks;
  final List<TreatmentTaskModel> missedTasks;
  final Future<void> Function(String) onTaskDone;
  const _TasksTab(
      {required this.todayTasks,
      required this.missedTasks,
      required this.onTaskDone});

  @override
  Widget build(BuildContext context) {
    if (todayTasks.isEmpty && missedTasks.isEmpty) {
      return _emptyState(
          icon: Icons.task_alt, message: 'No tasks due', sub: 'All caught up!');
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (missedTasks.isNotEmpty) ...[
          _SectionLabel(label: 'Missed Tasks', count: missedTasks.length, color: Colors.red),
          const SizedBox(height: 8),
          ...missedTasks.map((t) => _TaskCard(
                task: t,
                isMissed: true,
                onDone: onTaskDone,
              )),
          const SizedBox(height: 16),
        ],
        if (todayTasks.isNotEmpty) ...[
          _SectionLabel(label: "Today's Tasks", count: todayTasks.length, color: AppColors.primary),
          const SizedBox(height: 8),
          ...todayTasks.map((t) => _TaskCard(
                task: t,
                isMissed: false,
                onDone: onTaskDone,
              )),
        ],
      ],
    );
  }
}

// ─── Reminders Tab ────────────────────────────────────────────────────────

class _RemindersTab extends StatelessWidget {
  final List<NotificationModel> notifications;
  final Future<void> Function(String) onMarkRead;
  const _RemindersTab({required this.notifications, required this.onMarkRead});

  @override
  Widget build(BuildContext context) {
    if (notifications.isEmpty) {
      return _emptyState(
          icon: Icons.notifications_none,
          message: 'No reminders',
          sub: 'Reminders will appear here');
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: notifications.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) => _AlertCard(
        notification: notifications[i],
        borderColor: AppColors.primaryMedium,
        onMarkRead: onMarkRead,
      ),
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
  final Future<void> Function(String) onDone;
  const _TaskCard(
      {required this.task, required this.isMissed, required this.onDone});

  @override
  Widget build(BuildContext context) {
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
                : 'Due today ${DateFormat('HH:mm').format(task.dueAt)}',
            style: TextStyle(
                fontSize: 12,
                color: isMissed ? Colors.red : AppColors.textGray),
          ),
          const Spacer(),
          ElevatedButton(
            onPressed: () => onDone(task.id),
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  isMissed ? Colors.orange : AppColors.primary,
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(isMissed ? 'RESOLVE' : 'DONE',
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
