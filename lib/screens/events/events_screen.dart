import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:studentboard/providers/app_state.dart';
import 'package:studentboard/services/in_app_notification_toast.dart';
import 'package:studentboard/widgets/app_shell.dart';
import 'package:studentboard/widgets/campus_refresh.dart';

import 'package:studentboard/widgets/event_poster_card.dart';
import 'package:studentboard/widgets/event_poster_dashboard_style.dart';
import 'package:studentboard/utils/json_helpers.dart';

class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  String _filter = "all";

  String _fallbackImageUrl(Map<String, dynamic> event) {
    final title = event["title"]?.toString() ?? "";
    final category = event["category"]?.toString() ?? "general";
    final priority = event["priority"]?.toString() ?? "normal";
    final text = "$title $category $priority".toLowerCase();
    if (text.contains("exam") || text.contains("academic")) {
      return "https://images.unsplash.com/photo-1434030216411-0b793f4b4173?auto=format&fit=crop&w=1200&q=80";
    }
    if (text.contains("urgent") || text.contains("alert")) {
      return "https://images.unsplash.com/photo-1489515217757-5fd1be406fef?auto=format&fit=crop&w=1200&q=80";
    }
    if (text.contains("club") || text.contains("community")) {
      return "https://images.unsplash.com/photo-1528605248644-14dd04022da1?auto=format&fit=crop&w=1200&q=80";
    }
    if (text.contains("hackathon") || text.contains("event")) {
      return "https://images.unsplash.com/photo-1511578314322-379afb476865?auto=format&fit=crop&w=1200&q=80";
    }
    return "https://images.unsplash.com/photo-1492684223066-81342ee5ff30?auto=format&fit=crop&w=1200&q=80";
  }

  String _eventImageUrl(AppState app, Map<String, dynamic> event) {
    final poster = event["poster_path"]?.toString();
    if (poster != null &&
        poster.isNotEmpty &&
        app.api.serverOrigin.isNotEmpty) {
      return "${app.api.serverOrigin}$poster";
    }
    return _fallbackImageUrl(event);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final allEvents =
        app.events.map((e) => Map<String, dynamic>.from(e as Map)).toList()
          ..sort((a, b) {
            final at = DateTime.tryParse(a["start_time"]?.toString() ?? "");
            final bt = DateTime.tryParse(b["start_time"]?.toString() ?? "");
            if (at == null && bt == null) return 0;
            if (at == null) return 1;
            if (bt == null) return -1;
            return at.compareTo(bt);
          });
    final filtered = allEvents.where((event) {
      final id = eventIdFromJson(event);
      final registered = app.isRegisteredForEvent(id);
      if (_filter == "registered") return registered;
      if (_filter == "unregistered") return !registered;
      return true;
    }).toList();

    final cs = Theme.of(context).colorScheme;

    return AppShell(
      title: "Events",
      appBarActions: app.canManageEvents
          ? [
              IconButton(
                tooltip: "Create campus activity",
                onPressed: () => context.push("/admin/events/new"),
                icon: const Icon(Icons.add_circle_outline),
              ),
            ]
          : null,
      body: CampusRefreshIndicator(
        onRefresh: app.loadAll,
        child: CustomScrollView(
          physics: kCampusPullToRefreshPhysics,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              sliver: SliverToBoxAdapter(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilterChip(
                      label: const Text("All"),
                      selected: _filter == "all",
                      onSelected: (_) => setState(() => _filter = "all"),
                      selectedColor: cs.primaryContainer.withValues(
                        alpha: 0.65,
                      ),
                      checkmarkColor: cs.primary,
                      labelStyle: TextStyle(
                        fontWeight: _filter == "all"
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: _filter == "all"
                            ? cs.onPrimaryContainer
                            : cs.onSurface,
                      ),
                    ),
                    FilterChip(
                      label: const Text("Unregister"),
                      selected: _filter == "unregistered",
                      onSelected: (_) =>
                          setState(() => _filter = "unregistered"),
                      selectedColor: cs.surfaceContainerHighest,
                      labelStyle: TextStyle(
                        fontWeight: _filter == "unregistered"
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                    FilterChip(
                      label: const Text("Register"),
                      selected: _filter == "registered",
                      onSelected: (_) => setState(() => _filter = "registered"),
                      selectedColor: cs.surfaceContainerHighest,
                      labelStyle: TextStyle(
                        fontWeight: _filter == "registered"
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (filtered.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                  child: Text(
                    "No events match this filter.",
                    style: Theme.of(
                      context,
                    ).textTheme.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) =>
                      _eventPosterRow(context, app, filtered[index]),
                  childCount: filtered.length,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteDashboardActivity(
    BuildContext context,
    AppState app,
    int eventId,
    String title,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete this activity?"),
        content: Text(
          '"$title" will be removed from the campus dashboard for everyone. All registrations '
          "for this activity will be cleared. This cannot be undone.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Delete"),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final err = await app.deleteAdminEvent(eventId);
    if (!context.mounted) return;
    showCampusOperationSnackBar(
      context,
      err ?? "Activity deleted.",
      isError: err != null,
    );
  }

  Widget _eventPosterRow(
    BuildContext context,
    AppState app,
    Map<String, dynamic> event,
  ) {
    final id = eventIdFromJson(event);
    if (id == null) {
      return const SizedBox.shrink();
    }
    final allowReg = event["allow_registration"] != false;
    final title = event["title"]?.toString() ?? "";
    final description = event["description"]?.toString() ?? "";
    final imageUrl = _eventImageUrl(app, event);
    final regCount = registrationCountFromJson(event);
    final accent = dashboardEventCardAccent(event);
    final examTimetablePath = event["exam_timetable_path"]?.toString();
    final loc = event["location"]?.toString().trim() ?? "";

    final showStaffFooter = app.canEditDashboardActivity(event) ||
        app.canStaffManageThisEvent(event) ||
        app.canDeleteDashboardActivity(event);

    final cs = Theme.of(context).colorScheme;
    final posterBtnStyle = TextButton.styleFrom(
      foregroundColor: Colors.white,
      backgroundColor: Colors.black.withValues(alpha: 0.42),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
    final posterDelStyle = TextButton.styleFrom(
      foregroundColor: const Color(0xFFFFB4AB),
      backgroundColor: Colors.black.withValues(alpha: 0.42),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.14),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => context.push("/events/$id"),
                child: EventPosterCard(
                  key: ValueKey<String>("events-poster-$id"),
                  imageUrl: imageUrl,
                  title: title.isEmpty ? "Event" : title,
                  description: description,
                  accentColor: accent,
                  borderRadius: 16,
                  footer: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      eventPosterDashboardPillsWrap(
                        event,
                        allowRegistration: allowReg,
                        registrationCount: regCount,
                      ),
                      if ((examTimetablePath ?? "").isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(
                            children: [
                              Icon(
                                Icons.table_chart_outlined,
                                size: 18,
                                color: Colors.white.withValues(alpha: 0.92),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  "Exam timetable attached",
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.88),
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    shadows: const [
                                      Shadow(
                                        color: Color(0x99000000),
                                        blurRadius: 4,
                                        offset: Offset(0, 1),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (showStaffFooter) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (app.canEditDashboardActivity(event))
                              Tooltip(
                                message: "Edit activity",
                                child: TextButton.icon(
                                  style: posterBtnStyle,
                                  onPressed: () async {
                                    await context.push("/admin/events/$id/edit");
                                    if (!context.mounted) return;
                                    await app.loadAll();
                                  },
                                  icon: const Icon(Icons.edit_outlined, size: 18),
                                  label: const Text("Edit activity"),
                                ),
                              ),
                            if (app.canStaffManageThisEvent(event))
                              Tooltip(
                                message: "Registrations",
                                child: TextButton.icon(
                                  style: posterBtnStyle,
                                  onPressed: () => context.push("/admin/events/$id/registrations"),
                                  icon: const Icon(Icons.group_outlined, size: 18),
                                  label: const Text("Registrations"),
                                ),
                              ),
                            if (app.canDeleteDashboardActivity(event))
                              TextButton.icon(
                                style: posterDelStyle,
                                onPressed: () => _confirmDeleteDashboardActivity(
                                  context,
                                  app,
                                  id,
                                  title.isEmpty ? "Event" : title,
                                ),
                                icon: const Icon(Icons.delete_outline, size: 18),
                                label: const Text("Delete"),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (loc.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.place_outlined, size: 18, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      loc,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                          ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
