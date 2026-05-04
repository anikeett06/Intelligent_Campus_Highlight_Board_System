import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:studentboard/providers/app_state.dart';
import 'package:studentboard/services/in_app_notification_toast.dart';
import 'package:studentboard/widgets/campus_refresh.dart';
import 'package:studentboard/widgets/app_shell.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _initialLoadDone = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prime());
  }

  Future<void> _prime() async {
    final app = context.read<AppState>();
    if (app.accessToken != null && app.notifications.isEmpty) {
      await app.refreshNotifications(emitPop: false);
    }
    if (mounted) setState(() => _initialLoadDone = true);
  }

  Future<void> _openUploadNoticeDialog(BuildContext context, AppState app) async {
    final titleCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    String priority = "normal";
    String audience = "students";
    final facultyMode = app.isFaculty;
    final submit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("Upload new notice"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: "Notice title"),
                ),
                TextField(
                  controller: bodyCtrl,
                  decoration: const InputDecoration(labelText: "Notice message"),
                  maxLines: 4,
                ),
                const SizedBox(height: 8),
                if (!facultyMode)
                  DropdownButtonFormField<String>(
                    initialValue: priority,
                    items: const [
                      DropdownMenuItem(value: "normal", child: Text("Normal")),
                      DropdownMenuItem(value: "urgent", child: Text("Urgent")),
                      DropdownMenuItem(value: "ongoing", child: Text("Ongoing")),
                      DropdownMenuItem(value: "upcoming", child: Text("Upcoming")),
                      DropdownMenuItem(value: "academic", child: Text("Academic")),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        setDialogState(() => priority = v);
                      }
                    },
                    decoration: const InputDecoration(labelText: "Priority"),
                  ),
                if (facultyMode)
                  DropdownButtonFormField<String>(
                    initialValue: audience,
                    items: const [
                      DropdownMenuItem(value: "students", child: Text("Send to students")),
                      DropdownMenuItem(value: "admins", child: Text("Send to admin")),
                      DropdownMenuItem(value: "both", child: Text("Send to student + admin")),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        setDialogState(() => audience = v);
                      }
                    },
                    decoration: const InputDecoration(labelText: "Send to"),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text("Cancel")),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(
                facultyMode
                    ? (audience == "admins"
                        ? "Send to admin"
                        : audience == "both"
                            ? "Send to student + admin"
                            : "Send to students")
                    : "Send to all students",
              ),
            ),
          ],
        ),
      ),
    );
    if (submit != true) {
      return;
    }
    final title = titleCtrl.text.trim();
    final body = bodyCtrl.text.trim();
    if (title.isEmpty || body.isEmpty) {
      if (context.mounted) {
        showCampusOperationSnackBar(context, "Please enter a title and message.", isError: true);
      }
      return;
    }
    final err = await app.broadcastNoticeToStudents(
      title: title,
      body: body,
      priority: priority,
      audience: audience,
    );
    if (!context.mounted) {
      return;
    }
    showCampusOperationSnackBar(
      context,
      err ?? "Notice sent successfully.",
      isError: err != null,
    );
  }

  List<Widget>? _markAllActions(AppState app) {
    if (app.unreadNotificationCount == 0) return null;
    return [
      IconButton(
        tooltip: "Mark all read",
        onPressed: () => unawaited(app.markAllNotificationsRead()),
        icon: const Icon(Icons.done_all),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final markActions = _markAllActions(app);
    final fromStudents = app.notifications.where((n) => (n["source_role"]?.toString() ?? "") == "student").toList();
    final fromAdmins = app.notifications.where((n) => (n["source_role"]?.toString() ?? "") == "admin").toList();
    /// Staff "new updates" tab: campus / system / faculty / admin — not student-originated (those go to From students).
    final staffNonStudentFeed = app.notifications.where((n) {
      if (n is! Map) return false;
      return (n["source_role"]?.toString() ?? "") != "student";
    }).toList();

    if (!app.isAdmin) {
      if (app.isFaculty) {
        return AppShell(
          title: "Notifications",
          appBarActions: markActions,
          body: DefaultTabController(
            length: 3,
            child: Column(
              children: [
                const TabBar(
                  tabs: [
                    Tab(text: "New notifications"),
                    Tab(text: "From students"),
                    Tab(text: "From admin"),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: FilledButton.icon(
                                onPressed: () => _openUploadNoticeDialog(context, app),
                                icon: const Icon(Icons.campaign_outlined),
                                label: const Text("Upload new notice"),
                              ),
                            ),
                          ),
                          Expanded(
                            child: _NotificationListView(
                              rows: staffNonStudentFeed,
                              app: app,
                              initialLoadDone: _initialLoadDone,
                            ),
                          ),
                        ],
                      ),
                      _NotificationListView(rows: fromStudents, app: app, initialLoadDone: _initialLoadDone),
                      _NotificationListView(rows: fromAdmins, app: app, initialLoadDone: _initialLoadDone),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }
      return AppShell(
        title: "Notifications",
        appBarActions: markActions,
        body: _NotificationListView(rows: app.notifications, app: app, initialLoadDone: _initialLoadDone),
      );
    }
    return AppShell(
      title: "Notifications",
      appBarActions: markActions,
      body: DefaultTabController(
        length: 2,
        child: Column(
          children: [
            const TabBar(
              tabs: [
                Tab(text: "New updates"),
                Tab(text: "From students"),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FilledButton.icon(
                            onPressed: () => _openUploadNoticeDialog(context, app),
                            icon: const Icon(Icons.campaign_outlined),
                            label: const Text("Upload new notice"),
                          ),
                        ),
                      ),
                      Expanded(
                        child: _NotificationListView(
                          rows: staffNonStudentFeed,
                          app: app,
                          initialLoadDone: _initialLoadDone,
                        ),
                      ),
                    ],
                  ),
                  _NotificationListView(rows: fromStudents, app: app, initialLoadDone: _initialLoadDone),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

bool _isUnread(Map<dynamic, dynamic> n) {
  final r = n["is_read"];
  return r == false || r == 0;
}

int? _parseNotificationId(Map<dynamic, dynamic> n) {
  final v = n["id"];
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? "");
}

String _relativeTime(Map<dynamic, dynamic> n) {
  final raw = n["created_at"];
  if (raw == null) return "";
  final DateTime? dt = raw is String ? DateTime.tryParse(raw) : (raw is DateTime ? raw : null);
  if (dt == null) return "";
  final local = dt.toLocal();
  final diff = DateTime.now().difference(local);
  if (diff.isNegative) return "Just now";
  if (diff.inSeconds < 45) return "Just now";
  if (diff.inMinutes < 60) return "${diff.inMinutes}m ago";
  if (diff.inHours < 24) return "${diff.inHours}h ago";
  if (diff.inDays < 7) return "${diff.inDays}d ago";
  return "${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}";
}

IconData _typeIcon(String? type, String priority) {
  final pr = priority.toLowerCase();
  final high = pr == "high" || pr == "urgent";
  switch (type?.toLowerCase() ?? "") {
    case "academic":
      return high ? Icons.school : Icons.menu_book_outlined;
    case "event":
      return high ? Icons.event_available : Icons.event_outlined;
    case "club":
      return Icons.groups_outlined;
    case "dashboard":
      return Icons.dashboard_outlined;
    case "system":
      return Icons.info_outline;
    default:
      return high ? Icons.priority_high : Icons.notifications_outlined;
  }
}

class _NotificationListView extends StatelessWidget {
  const _NotificationListView({
    required this.rows,
    required this.app,
    required this.initialLoadDone,
  });

  final List<dynamic> rows;
  final AppState app;
  final bool initialLoadDone;

  @override
  Widget build(BuildContext context) {
    Future<void> onRefresh() => app.loadAll();

    if (!initialLoadDone) {
      return LayoutBuilder(
        builder: (context, constraints) {
          return CampusRefreshIndicator(
            onRefresh: onRefresh,
            child: SingleChildScrollView(
              physics: kCampusPullToRefreshPhysics,
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: const Center(child: CircularProgressIndicator()),
              ),
            ),
          );
        },
      );
    }
    if (rows.isEmpty) {
      return LayoutBuilder(
        builder: (context, constraints) {
          return CampusRefreshIndicator(
            onRefresh: onRefresh,
            child: SingleChildScrollView(
              physics: kCampusPullToRefreshPhysics,
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      "No notifications yet.\nPull down to refresh.",
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.black54),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    }
    return CampusRefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        physics: kCampusPullToRefreshPhysics,
        padding: const EdgeInsets.all(12),
        itemCount: rows.length,
        itemBuilder: (context, index) {
          final raw = rows[index];
          if (raw is! Map) return const SizedBox.shrink();
          final n = raw;
          final id = _parseNotificationId(n);
          if (id == null) return const SizedBox.shrink();
          final title = n["title"]?.toString() ?? "";
          final body = (n["message"] ?? n["body"])?.toString() ?? "";
          final unread = _isUnread(n);
          final type = n["notification_type"]?.toString();
          final priority = n["priority"]?.toString() ?? "normal";
          final scheme = Theme.of(context).colorScheme;

          final card = Card(
            color: unread ? scheme.primaryContainer.withValues(alpha: 0.25) : null,
            child: InkWell(
              onTap: () {
                if (unread) {
                  unawaited(app.markNotificationRead(id));
                }
              },
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      _typeIcon(type, priority),
                      color: priority.toLowerCase() == "high" ? scheme.error : scheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  title,
                                  style: TextStyle(
                                    fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              Text(
                                _relativeTime(n),
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context).hintColor,
                                    ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(body, style: Theme.of(context).textTheme.bodyMedium),
                          if (type != null && type.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              children: [
                                Chip(
                                  label: Text(type, style: const TextStyle(fontSize: 12)),
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                if (priority.isNotEmpty && priority != "normal")
                                  Chip(
                                    label: Text(priority, style: const TextStyle(fontSize: 12)),
                                    visualDensity: VisualDensity.compact,
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Dismissible(
              key: ValueKey("n-$id"),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                color: scheme.errorContainer,
                child: Icon(Icons.delete_outline, color: scheme.onErrorContainer),
              ),
              onDismissed: (_) => unawaited(app.deleteNotification(id)),
              child: card,
            ),
          );
        },
      ),
    );
  }
}
