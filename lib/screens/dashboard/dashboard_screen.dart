import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:studentboard/providers/app_state.dart';
import 'package:studentboard/widgets/app_shell.dart';
import 'package:studentboard/widgets/campus_refresh.dart';
import 'package:studentboard/widgets/event_poster_card.dart';
import 'package:studentboard/widgets/event_poster_dashboard_style.dart';
import 'package:studentboard/services/in_app_notification_toast.dart';
import 'package:studentboard/utils/json_helpers.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String _eventFocus = "all";
  final PageController _carouselController = PageController(
    viewportFraction: 0.94,
  );
  Timer? _carouselTimer;
  int _carouselIndex = 0;
  int _carouselCount = 0;

  @override
  void initState() {
    super.initState();
    _carouselTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !_carouselController.hasClients || _carouselCount < 2) {
        return;
      }
      final next = (_carouselIndex + 1) % _carouselCount;
      setState(() => _carouselIndex = next);
      _carouselController.animateToPage(
        next,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _carouselTimer?.cancel();
    _carouselController.dispose();
    super.dispose();
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
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
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
    if (ok != true || !context.mounted) {
      return;
    }
    final err = await app.deleteAdminEvent(eventId);
    if (!context.mounted) {
      return;
    }
    showCampusOperationSnackBar(
      context,
      err ?? "Activity deleted.",
      isError: err != null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final grouped = app.dashboard;
    return AppShell(
      title: "Dashboard",
      appBarActions: app.canQuickAddDashboardActivity
          ? [
              IconButton(
                tooltip: app.isFaculty && !app.isAdmin
                    ? "Create academic dashboard activity"
                    : app.isStudentAdmin && !app.isAdmin
                    ? "Create non-academic campus activity"
                    : "Create dashboard activity",
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
            if (app.loadInProgress)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(bottom: 6),
                  child: LinearProgressIndicator(minHeight: 2),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              sliver: SliverToBoxAdapter(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!app.dashboardAcademicMode)
                      _nonAcademicDashboardSection(context, app, grouped)
                    else
                      _academicDashboardSection(context, app, grouped),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _nonAcademicDashboardSection(
    BuildContext context,
    AppState app,
    Map<String, dynamic> grouped,
  ) {
    final allItems = _allDashboardItems(grouped);
    final nonAcademic = allItems
        .where((e) => effectiveDashboardSegment(e) == "non_academic")
        .toList();
    // Trending highlights should reflect the editor toggle reliably, even if an item
    // doesn't land in the grouped dashboard buckets (urgent/ongoing/upcoming).
    final carouselItems = app.events
        .whereType<Map>()
        .map((raw) => Map<String, dynamic>.from(raw.map((k, v) => MapEntry(k.toString(), v))))
        .where((e) => effectiveDashboardSegment(e) == "non_academic")
        .where(eventShowInDashboard)
        .where(eventTrendingHighlight)
        .toList()
      ..sort((a, b) {
        final at = DateTime.tryParse(a["start_time"]?.toString() ?? "")?.toUtc();
        final bt = DateTime.tryParse(b["start_time"]?.toString() ?? "")?.toUtc();
        if (at == null && bt == null) return 0;
        if (at == null) return 1;
        if (bt == null) return -1;
        return bt.compareTo(at);
      });
    final carouselItemsTrimmed = carouselItems.take(5).toList();
    _carouselCount = carouselItemsTrimmed.length;
    if (_carouselCount > 0 && _carouselIndex >= _carouselCount) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_carouselController.hasClients) {
          _carouselController.jumpToPage(0);
        }
        setState(() => _carouselIndex = 0);
      });
    }
    final dotIndex = _carouselCount == 0
        ? 0
        : _carouselIndex.clamp(0, _carouselCount - 1);
    final baseList = nonAcademic.where((e) => !eventTrendingHighlight(e)).toList();
    final filtered = _eventFocus == "ongoing"
        ? baseList.where(isDashboardEventOngoing).toList()
        : _eventFocus == "upcoming"
            ? baseList.where(isDashboardEventUpcoming).toList()
            : List<Map<String, dynamic>>.from(baseList);
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Trending highlights",
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          "Featured on campus and what’s coming up",
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 14),
        if (carouselItemsTrimmed.isEmpty)
          const Text("No current event banners")
        else ...[
          SizedBox(
            height: 288,
            child: LayoutBuilder(
              builder: (context, bc) {
                return PageView.builder(
                  controller: _carouselController,
                  itemCount: carouselItemsTrimmed.length,
                  onPageChanged: (idx) => setState(() => _carouselIndex = idx),
                  itemBuilder: (context, idx) {
                    final item = carouselItemsTrimmed[idx];
                    final title = item["title"]?.toString() ?? "-";
                    final displayTitle = eventDashboardTeaserTitle(item);
                    final displayDescription = eventDashboardTeaserDescription(item);
                    final category = item["category"]?.toString() ?? "general";
                    final priority = item["priority"]?.toString() ?? "normal";
                    final heroPath = eventHeroImageStoragePath(item);
                    final imageUrl =
                        (heroPath != null &&
                            heroPath.isNotEmpty &&
                            app.api.serverOrigin.isNotEmpty)
                        ? "${app.api.serverOrigin}$heroPath"
                        : _imageForItem(
                            title: displayTitle,
                            category: category,
                            priority: priority,
                          );
                    final carouselEventId = eventIdFromJson(item);
                    final carAllowReg = item["allow_registration"] != false;
                    final carRegCount = registrationCountFromJson(item);
                    final accent = dashboardEventCardAccent(item);
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Center(
                        child: EventPosterCard(
                          key: ValueKey<String>("$imageUrl-$idx"),
                          imageUrl: imageUrl,
                          title: displayTitle,
                          description: displayDescription,
                          accentColor: accent,
                          maxHeight: 272,
                          maxWidth: bc.maxWidth,
                          borderRadius: 14,
                          titleMaxLines: 2,
                          descriptionMaxLines: 2,
                          topTrailing:
                              (app.canEditDashboardActivity(item) ||
                                      app.canDeleteDashboardActivity(item)) &&
                                  carouselEventId != null
                              ? Material(
                                  color: Colors.black.withValues(alpha: 0.45),
                                  borderRadius: BorderRadius.circular(20),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (app.canEditDashboardActivity(item))
                                        IconButton(
                                          tooltip: "Remove from trending",
                                          visualDensity: VisualDensity.compact,
                                          padding: const EdgeInsets.all(6),
                                          constraints: const BoxConstraints(
                                            minWidth: 36,
                                            minHeight: 36,
                                          ),
                                          icon: const Icon(
                                            Icons.trending_down,
                                            color: Colors.white,
                                            size: 20,
                                          ),
                                          onPressed: () async {
                                            final err = await app.setAdminEventTrendingHighlight(
                                              carouselEventId,
                                              trendingHighlight: false,
                                            );
                                            if (!context.mounted) return;
                                            showCampusOperationSnackBar(
                                              context,
                                              err ?? "Removed from trending highlights.",
                                              isError: err != null,
                                            );
                                          },
                                        ),
                                      if (app.canEditDashboardActivity(item))
                                        IconButton(
                                          tooltip: "Edit dashboard activity",
                                          visualDensity: VisualDensity.compact,
                                          padding: const EdgeInsets.all(6),
                                          constraints: const BoxConstraints(
                                            minWidth: 36,
                                            minHeight: 36,
                                          ),
                                          icon: const Icon(
                                            Icons.edit_outlined,
                                            color: Colors.white,
                                            size: 20,
                                          ),
                                          onPressed: () => context.push(
                                            "/admin/events/$carouselEventId/edit",
                                          ),
                                        ),
                                      if (app.canDeleteDashboardActivity(item))
                                        IconButton(
                                          tooltip: "Delete dashboard activity",
                                          visualDensity: VisualDensity.compact,
                                          padding: const EdgeInsets.all(6),
                                          constraints: const BoxConstraints(
                                            minWidth: 36,
                                            minHeight: 36,
                                          ),
                                          icon: const Icon(
                                            Icons.delete_outline,
                                            color: Colors.white,
                                            size: 20,
                                          ),
                                          onPressed: () =>
                                              _confirmDeleteDashboardActivity(
                                                context,
                                                app,
                                                carouselEventId,
                                                title.isEmpty ? "Event" : title,
                                              ),
                                        ),
                                    ],
                                  ),
                                )
                              : null,
                          footer: carAllowReg
                              ? Text(
                                  carRegCount == 0
                                      ? "No registrations yet"
                                      : "$carRegCount registered",
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.82),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    shadows: const [
                                      Shadow(
                                        color: Color(0x99000000),
                                        blurRadius: 6,
                                        offset: Offset(0, 1),
                                      ),
                                    ],
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              carouselItemsTrimmed.length,
              (i) => AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                height: 7,
                width: dotIndex == i ? 16 : 7,
                decoration: BoxDecoration(
                  color: dotIndex == i
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilterChip(
              label: const Text("All"),
              selected: _eventFocus == "all",
              onSelected: (_) => setState(() => _eventFocus = "all"),
              selectedColor: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.65),
              checkmarkColor: Theme.of(context).colorScheme.onPrimaryContainer,
              labelStyle: TextStyle(
                color: _eventFocus == "all" ? Theme.of(context).colorScheme.onPrimaryContainer : null,
                fontWeight: _eventFocus == "all" ? FontWeight.w700 : null,
              ),
            ),
            FilterChip(
              label: const Text("Ongoing"),
              selected: _eventFocus == "ongoing",
              onSelected: (_) => setState(() => _eventFocus = "ongoing"),
              selectedColor: EventPosterDashboardColors.ongoingBg,
              checkmarkColor: EventPosterDashboardColors.ongoingFg,
              labelStyle: TextStyle(
                color: _eventFocus == "ongoing" ? EventPosterDashboardColors.ongoingFg : null,
                fontWeight: _eventFocus == "ongoing" ? FontWeight.w700 : null,
              ),
            ),
            FilterChip(
              label: const Text("Upcoming"),
              selected: _eventFocus == "upcoming",
              onSelected: (_) => setState(() => _eventFocus = "upcoming"),
              selectedColor: EventPosterDashboardColors.upcomingBg,
              checkmarkColor: EventPosterDashboardColors.upcomingFg,
              labelStyle: TextStyle(
                color: _eventFocus == "upcoming" ? EventPosterDashboardColors.upcomingFg : null,
                fontWeight: _eventFocus == "upcoming" ? FontWeight.w700 : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (filtered.isEmpty)
          Text(
            _eventFocus == "ongoing"
                ? "No ongoing events right now."
                : _eventFocus == "upcoming"
                    ? "No upcoming events scheduled."
                    : "No events available.",
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          )
        else
          ...filtered.map(
            (e) => _announcementCard(context, app, e, dashboardEventCardAccent(e)),
          ),
        const SizedBox(height: 18),
        _lostFoundDashboardSection(context, app),
      ],
    );
  }

  Widget _academicDashboardSection(
    BuildContext context,
    AppState app,
    Map<String, dynamic> grouped,
  ) {
    final cs = Theme.of(context).colorScheme;
    final notices = app.academicNotices
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                "Notices",
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: EventPosterDashboardColors.academicFg,
                    ),
              ),
            ),
            if (app.canManageCampusShortcuts)
              FilledButton.tonalIcon(
                onPressed: () => _openCreateAcademicNoticeSheet(context, app),
                icon: const Icon(Icons.add),
                label: const Text("Add notice"),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (notices.isEmpty)
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                app.canManageCampusShortcuts
                    ? "No notices yet. Tap “Add notice” to publish a PDF, image, link or text update."
                    : "No academic notices have been published yet.",
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          )
        else
          ...notices.map((n) => _academicNoticeCard(context, app, n)),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () => app.setDashboardAcademicMode(false),
          icon: const Icon(Icons.celebration_outlined),
          label: const Text("Back to non-academic dashboard"),
        ),
      ],
    );
  }

  Widget _academicNoticeCard(
    BuildContext context,
    AppState app,
    Map<String, dynamic> notice,
  ) {
    final cs = Theme.of(context).colorScheme;
    final id = (notice["id"] is int) ? notice["id"] as int : int.tryParse("${notice["id"]}") ?? 0;
    final title = (notice["title"] ?? "").toString().trim();
    final body = (notice["body"] ?? "").toString().trim();
    final filePath = (notice["file_path"] ?? "").toString().trim();
    final fileKind = (notice["file_kind"] ?? "").toString().trim().toLowerCase();
    final thumbPath = (notice["file_thumbnail_path"] ?? "").toString().trim();
    final linkUrl = (notice["link_url"] ?? "").toString().trim();
    final author = (notice["created_by_name"] ?? "").toString().trim();
    final expiresAt = DateTime.tryParse(notice["expires_at"]?.toString() ?? "")?.toLocal();

    final base = app.api.serverOrigin;
    final fileUrl = (filePath.isNotEmpty && base.isNotEmpty) ? "$base$filePath" : null;
    final thumbUrl = (thumbPath.isNotEmpty && base.isNotEmpty) ? "$base$thumbPath" : null;

    Future<void> handleTap() async {
      if (fileUrl != null) {
        await launchUrl(Uri.parse(fileUrl), mode: LaunchMode.externalApplication);
        return;
      }
      if (linkUrl.isNotEmpty) {
        await launchUrl(Uri.parse(linkUrl), mode: LaunchMode.externalApplication);
        return;
      }
    }

    final hasContent = fileUrl != null || linkUrl.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: hasContent ? handleTap : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (fileKind == "image" && fileUrl != null)
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Image.network(
                    fileUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, e, s) => Container(
                      color: cs.surfaceContainerHighest,
                      alignment: Alignment.center,
                      child: const Icon(Icons.broken_image_outlined),
                    ),
                  ),
                )
              else if (fileKind == "pdf" && thumbUrl != null)
                Stack(
                  children: [
                    AspectRatio(
                      aspectRatio: 16 / 11,
                      child: Container(
                        color: cs.surfaceContainerHighest,
                        alignment: Alignment.center,
                        child: Image.network(
                          thumbUrl,
                          fit: BoxFit.contain,
                          errorBuilder: (_, e, s) => Container(
                            color: cs.surfaceContainerHighest,
                            alignment: Alignment.center,
                            child: Icon(Icons.picture_as_pdf, size: 48, color: cs.error),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 12,
                      top: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.picture_as_pdf, size: 14, color: Colors.white),
                            SizedBox(width: 6),
                            Text(
                              "PDF",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 11,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (fileKind == "pdf")
                          Padding(
                            padding: const EdgeInsets.only(right: 10, top: 2),
                            child: Icon(Icons.picture_as_pdf, color: cs.error),
                          )
                        else if (linkUrl.isNotEmpty && fileKind != "image")
                          Padding(
                            padding: const EdgeInsets.only(right: 10, top: 2),
                            child: Icon(Icons.link, color: cs.primary),
                          ),
                        Expanded(
                          child: Text(
                            title.isEmpty ? "Untitled notice" : title,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ),
                        if (app.canManageCampusShortcuts)
                          IconButton(
                            tooltip: "Delete notice",
                            icon: Icon(Icons.delete_outline, color: cs.error),
                            onPressed: () => _confirmDeleteAcademicNotice(context, app, id, title),
                          ),
                      ],
                    ),
                    if (body.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        body,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: cs.onSurface,
                              height: 1.4,
                            ),
                      ),
                    ],
                    if (fileKind == "pdf" && fileUrl != null) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(Icons.open_in_new, size: 16, color: cs.primary),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              "Tap to open the PDF",
                              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                    color: cs.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (linkUrl.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(Icons.open_in_new, size: 16, color: cs.primary),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              linkUrl,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                    color: cs.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (author.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        "Posted by $author",
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                      ),
                    ],
                    if (expiresAt != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.schedule, size: 14, color: cs.onSurfaceVariant),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              "Auto-removes on ${_formatNoticeExpiry(expiresAt)}",
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                            ),
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
  }

  static String _formatNoticeExpiry(DateTime dt) {
    final y = dt.year.toString().padLeft(4, "0");
    final m = dt.month.toString().padLeft(2, "0");
    final d = dt.day.toString().padLeft(2, "0");
    final hh = dt.hour.toString().padLeft(2, "0");
    final mm = dt.minute.toString().padLeft(2, "0");
    return "$y-$m-$d $hh:$mm";
  }

  Future<void> _confirmDeleteAcademicNotice(
    BuildContext context,
    AppState app,
    int id,
    String title,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete this notice?"),
        content: Text(
          title.isEmpty
              ? "This notice will be removed for everyone."
              : "“$title” will be removed for everyone.",
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
    final err = await app.deleteAcademicNotice(id);
    if (!context.mounted) return;
    showCampusOperationSnackBar(context, err ?? "Notice deleted.", isError: err != null);
  }

  Future<void> _openCreateAcademicNoticeSheet(BuildContext context, AppState app) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final media = MediaQuery.of(ctx);
        return Padding(
          padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
          child: _AcademicNoticeForm(app: app, parentContext: context),
        );
      },
    );
  }

  Widget _announcementCard(
    BuildContext context,
    AppState app,
    Map<String, dynamic> item,
    Color accent,
  ) {
    final eventId = eventIdFromJson(item);
    final title = item["title"]?.toString() ?? "-";
    final displayTitle = eventDashboardTeaserTitle(item);
    final displayDescription = eventDashboardTeaserDescription(item);
    final category = item["category"]?.toString() ?? "general";
    final priority = item["priority"]?.toString() ?? "normal";
    final allowReg = item["allow_registration"] != false;
    final regCount = registrationCountFromJson(item);
    final examTimetablePath = item["exam_timetable_path"]?.toString();
    final heroPath = eventHeroImageStoragePath(item);
    final imageUrl =
        (heroPath != null &&
            heroPath.isNotEmpty &&
            app.api.serverOrigin.isNotEmpty)
        ? "${app.api.serverOrigin}$heroPath"
        : _imageForItem(title: displayTitle, category: category, priority: priority);

    final btnStyle = TextButton.styleFrom(
      foregroundColor: Colors.white,
      backgroundColor: Colors.black.withValues(alpha: 0.42),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
    final delStyle = TextButton.styleFrom(
      foregroundColor: const Color(0xFFFFB4AB),
      backgroundColor: Colors.black.withValues(alpha: 0.42),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DecoratedBox(
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
            onTap: eventId == null
                ? null
                : () => context.push("/events/$eventId"),
            child: EventPosterCard(
              key: ValueKey<String>(imageUrl),
              imageUrl: imageUrl,
              title: displayTitle,
              description: displayDescription,
              accentColor: accent,
              borderRadius: 16,
              footer: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  eventPosterDashboardPillsWrap(
                    item,
                    allowRegistration: allowReg,
                    registrationCount: regCount,
                  ),
                  if (examTimetablePath != null && examTimetablePath.isNotEmpty)
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
                  if ((app.canEditDashboardActivity(item) ||
                          app.canDeleteDashboardActivity(item)) &&
                      eventId != null) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (app.canEditDashboardActivity(item))
                          Tooltip(
                            message: "Edit dashboard activity",
                            child: TextButton.icon(
                              style: btnStyle,
                              onPressed: () =>
                                  context.push("/admin/events/$eventId/edit"),
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              label: const Text("Edit activity"),
                            ),
                          ),
                        if (app.canDeleteDashboardActivity(item))
                          TextButton.icon(
                            style: delStyle,
                            onPressed: () => _confirmDeleteDashboardActivity(
                              context,
                              app,
                              eventId,
                              title,
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
    );
  }

  String _imageForItem({
    required String title,
    required String category,
    required String priority,
  }) {
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

  List<Map<String, dynamic>> _allDashboardItems(Map<String, dynamic> grouped) {
    final out = <Map<String, dynamic>>[];
    final seen = <int>{};
    const keys = ["urgent", "ongoing", "upcoming", "academic"];
    for (final key in keys) {
      final rawBucket = grouped[key];
      final List<dynamic> rows = rawBucket is List<dynamic>
          ? rawBucket
          : rawBucket is List
          ? List<dynamic>.from(rawBucket)
          : const <dynamic>[];
      for (final raw in rows) {
        if (raw is! Map) continue;
        final item = Map<String, dynamic>.from(
          raw.map((k, v) => MapEntry(k.toString(), v)),
        );
        final id = eventIdFromJson(item);
        if (id != null && seen.contains(id)) {
          continue;
        }
        if (id != null) {
          seen.add(id);
        }
        out.add(item);
      }
    }
    out.sort((a, b) {
      final at = DateTime.tryParse(a["start_time"]?.toString() ?? "");
      final bt = DateTime.tryParse(b["start_time"]?.toString() ?? "");
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    });
    return out;
  }

  Widget _lostFoundDashboardSection(BuildContext context, AppState app) {
    final cs = Theme.of(context).colorScheme;
    final items = app.lostFound
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where((m) {
          final s = (m["status"] ?? "").toString().toLowerCase();
          return s != "resolved" && s != "claimed" && s != "closed";
        })
        .toList();
    items.sort((a, b) {
      final at = DateTime.tryParse(a["created_at"]?.toString() ?? "");
      final bt = DateTime.tryParse(b["created_at"]?.toString() ?? "");
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    });
    final banners = items.where((m) {
      final p = m["image_path"]?.toString() ?? "";
      return p.isNotEmpty;
    }).take(8).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                "Lost & Found",
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            TextButton.icon(
              onPressed: () => context.push("/lost-found"),
              icon: const Icon(Icons.chevron_right),
              label: const Text("View all"),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (banners.isEmpty)
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                "No lost items reported with photos right now.",
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          )
        else
          SizedBox(
            height: 210,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: banners.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) => _lostFoundBanner(context, app, banners[index]),
            ),
          ),
      ],
    );
  }

  Widget _lostFoundBanner(BuildContext context, AppState app, Map<String, dynamic> item) {
    final cs = Theme.of(context).colorScheme;
    final title = (item["title"] ?? "").toString().trim();
    final loc = (item["location"] ?? "").toString().trim();
    final imagePath = (item["image_path"] ?? "").toString().trim();
    final base = app.api.serverOrigin;
    final imageUrl = (imagePath.isNotEmpty && base.isNotEmpty) ? "$base$imagePath" : null;

    return SizedBox(
      width: 220,
      child: Material(
        color: cs.surface,
        elevation: 0,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push("/lost-found"),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (imageUrl != null)
                Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, e, s) => Container(
                    color: cs.surfaceContainerHighest,
                    alignment: Alignment.center,
                    child: const Icon(Icons.broken_image_outlined),
                  ),
                )
              else
                Container(color: cs.surfaceContainerHighest),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.78),
                      ],
                      stops: const [0.45, 1.0],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 10,
                top: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.search, size: 14, color: Colors.white),
                      SizedBox(width: 6),
                      Text(
                        "LOST ITEM",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 10.5,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title.isEmpty ? "Lost item" : title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        height: 1.2,
                      ),
                    ),
                    if (loc.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.place_outlined, size: 14, color: Colors.white),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              loc,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
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
  }
}

class _AcademicNoticeForm extends StatefulWidget {
  const _AcademicNoticeForm({required this.app, required this.parentContext});

  final AppState app;
  final BuildContext parentContext;

  @override
  State<_AcademicNoticeForm> createState() => _AcademicNoticeFormState();
}

class _AcademicNoticeFormState extends State<_AcademicNoticeForm> {
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _bodyCtrl = TextEditingController();
  final TextEditingController _linkCtrl = TextEditingController();
  PlatformFile? _picked;
  String? _fileLabel;
  bool _busy = false;
  String? _errorText;
  DateTime? _expiresAt;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    _linkCtrl.dispose();
    super.dispose();
  }

  String _formatExpiry(DateTime dt) {
    final local = dt.toLocal();
    final y = local.year.toString().padLeft(4, "0");
    final m = local.month.toString().padLeft(2, "0");
    final d = local.day.toString().padLeft(2, "0");
    final hh = local.hour.toString().padLeft(2, "0");
    final mm = local.minute.toString().padLeft(2, "0");
    return "$y-$m-$d $hh:$mm";
  }

  Future<void> _pickExpiryDateTime() async {
    final now = DateTime.now();
    final base = _expiresAt ?? now.add(const Duration(days: 7));
    final initialDate = base.isBefore(now) ? now : base;
    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: now,
      lastDate: DateTime(now.year + 5),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialDate),
    );
    if (time == null || !mounted) return;
    final dt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (!dt.isAfter(DateTime.now())) {
      setState(() => _errorText = "Expiry must be in the future.");
      return;
    }
    setState(() {
      _expiresAt = dt;
      _errorText = null;
    });
  }

  Future<void> _pickFile() async {
    final res = await FilePicker.pickFiles(
      withData: kIsWeb,
      type: FileType.custom,
      allowedExtensions: const ["pdf", "jpg", "jpeg", "png", "webp", "gif"],
    );
    if (!mounted || res == null || res.files.isEmpty) return;
    setState(() {
      _picked = res.files.single;
      _fileLabel = _picked!.name;
    });
  }

  Future<void> _submit() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      setState(() => _errorText = "A heading is required.");
      return;
    }
    setState(() {
      _busy = true;
      _errorText = null;
    });
    final err = await widget.app.createAcademicNotice(
      title: title,
      body: _bodyCtrl.text.trim().isEmpty ? null : _bodyCtrl.text.trim(),
      linkUrl: _linkCtrl.text.trim().isEmpty ? null : _linkCtrl.text.trim(),
      expiresAt: _expiresAt,
      file: _picked,
    );
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _busy = false;
        _errorText = err;
      });
      return;
    }
    Navigator.of(context).pop();
    if (!widget.parentContext.mounted) return;
    showCampusOperationSnackBar(widget.parentContext, "Notice published.");
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            "New academic notice",
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _titleCtrl,
            enabled: !_busy,
            decoration: const InputDecoration(
              labelText: "Heading *",
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _bodyCtrl,
            enabled: !_busy,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: "Notice text (optional)",
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _linkCtrl,
            enabled: !_busy,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: "Link URL (optional, https://…)",
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _pickFile,
                  icon: const Icon(Icons.attach_file),
                  label: Text(_fileLabel ?? "Attach PDF or image"),
                ),
              ),
              if (_picked != null)
                IconButton(
                  tooltip: "Remove attachment",
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                            _picked = null;
                            _fileLabel = null;
                          }),
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _pickExpiryDateTime,
                  icon: const Icon(Icons.event_available_outlined),
                  label: Text(
                    _expiresAt == null
                        ? "Auto-remove date (optional)"
                        : "Auto-removes on ${_formatExpiry(_expiresAt!)}",
                  ),
                ),
              ),
              if (_expiresAt != null)
                IconButton(
                  tooltip: "Clear auto-remove date",
                  onPressed: _busy ? null : () => setState(() => _expiresAt = null),
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
          if (_errorText != null) ...[
            const SizedBox(height: 10),
            Text(
              _errorText!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              onPressed: _busy ? null : _submit,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_outlined),
              label: Text(_busy ? "Publishing…" : "Publish notice"),
            ),
          ),
        ],
      ),
    );
  }
}
