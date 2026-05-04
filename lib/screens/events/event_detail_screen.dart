import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:studentboard/providers/app_state.dart';
import 'package:studentboard/services/in_app_notification_toast.dart';
import 'package:studentboard/utils/json_helpers.dart';
import 'package:studentboard/screens/admin/event_page_layout.dart';
import 'package:studentboard/widgets/campus_refresh.dart';
import 'package:studentboard/widgets/event_page_blocks_view.dart';
import 'package:studentboard/widgets/event_rich_card.dart';
import 'package:url_launcher/url_launcher.dart';

class EventDetailScreen extends StatefulWidget {
  const EventDetailScreen({super.key, required this.eventId});

  final int eventId;

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshLive());
    _refreshTimer = Timer.periodic(const Duration(seconds: 20), (_) => _refreshLive(silent: true));
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshLive({bool silent = false}) async {
    final app = context.read<AppState>();
    if (app.accessToken == null) return;
    try {
      app.events = await app.api.getEvents(app.accessToken!);
      app.notifications = await app.api.getNotifications(app.accessToken!);
      app.polls = await app.api.getPolls(app.accessToken!);
      app.applyDataChange();
      if (mounted) {
        setState(() {});
      }
    } catch (_) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Could not refresh event feed.")));
      }
    }
  }

  Future<void> _openEventEditor(BuildContext context) async {
    await context.push("/admin/events/${widget.eventId}/edit");
    if (!mounted) return;
    await _refreshLive(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    Map<String, dynamic>? event;
    for (final raw in app.events) {
      final m = raw as Map<String, dynamic>;
      if (eventIdFromJson(m) == widget.eventId) {
        event = m;
        break;
      }
    }
    if (event == null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Event")),
        body: const Center(child: Text("Event not found.")),
      );
    }
    final ev = event;

    final title = ev["title"]?.toString() ?? "Event";
    final desc = ev["description"]?.toString() ?? "";
    final banner = ev["poster_path"]?.toString();
    final allowReg = ev["allow_registration"] != false;
    final registered = app.isRegisteredForEvent(widget.eventId);
    final regCount = registrationCountFromJson(ev);
    final imageUrl =
        (banner != null && banner.isNotEmpty && app.api.serverOrigin.isNotEmpty)
            ? "${app.api.serverOrigin}$banner"
            : "https://images.unsplash.com/photo-1511578314322-379afb476865?auto=format&fit=crop&w=1200&q=80";

    final lowerTitle = title.toLowerCase();
    /// Polls whose question/description mentions this event (no global fallback — avoids unrelated polls).
    final feedPolls = app.polls
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where(
          (p) =>
              (p["question"]?.toString().toLowerCase().contains(lowerTitle) ?? false) ||
              (p["description"]?.toString().toLowerCase().contains(lowerTitle) ?? false),
        )
        .toList();
    final canManagePollsHere = app.canStaffManageThisEvent(ev);
    final showPollBlock =
        canManagePollsHere || (eventBoolField(ev, "show_polls_section") && feedPolls.isNotEmpty);
    final staffView = app.canStaffManageThisEvent(ev);
    final showDesc = staffView || eventBoolField(ev, "show_description");
    final showLoc = staffView || eventBoolField(ev, "show_location");
    final showRegBlock = staffView || eventBoolField(ev, "show_registration_section");
    final customLabel = ev["custom_link_label"]?.toString().trim() ?? "";
    final customUrl = ev["custom_link_url"]?.toString().trim() ?? "";

    final pageLayout = EventPageLayout.tryParse(ev["event_page_json"]?.toString());
    final overlayHero = pageLayout?.overlayHeroOnBanner == true;
    final hasRichBlocks = pageLayout != null &&
        (pageLayout.blocks.isNotEmpty || pageLayout.heroOrganizedBy.trim().isNotEmpty);

    final hero = Map<String, dynamic>.from(ev);
    if (hasRichBlocks) {
      // Block view replaces the legacy description preview to avoid duplication.
      hero["description"] = "";
    }
    if (!staffView) {
      if (!showDesc) hero["description"] = "";
      if (!showLoc) hero["location"] = "";
    }

    final bgKind = (ev["event_page_background_kind"]?.toString().trim().toLowerCase()) ?? "none";
    final bgColorHex = ev["event_page_background_color"]?.toString().trim() ?? "";
    final bgImagePath = ev["event_page_background_path"]?.toString().trim() ?? "";
    Color? scaffoldBgColor;
    String? scaffoldBgImageUrl;
    if (bgKind == "color" && bgColorHex.isNotEmpty) {
      scaffoldBgColor = _parseHexColor(bgColorHex);
    } else if (bgKind == "image" && bgImagePath.isNotEmpty && app.api.serverOrigin.isNotEmpty) {
      scaffoldBgImageUrl = "${app.api.serverOrigin}$bgImagePath";
    }
    return Scaffold(
      backgroundColor: scaffoldBgColor,
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (app.canDeleteDashboardActivity(ev))
            IconButton(
              tooltip: "Delete activity",
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _confirmDeleteEvent(context, app, widget.eventId, title),
            ),
          if (app.canStaffManageThisEvent(ev))
            IconButton(
              tooltip: "Edit activity",
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _openEventEditor(context),
            ),
        ],
      ),
      body: _wrapWithBackground(
        scaffoldBgImageUrl,
        CampusRefreshIndicator(
        onRefresh: () async {
          await context.read<AppState>().loadAll();
          if (mounted) setState(() {});
        },
        child: ListView(
          physics: kCampusPullToRefreshPhysics,
          padding: const EdgeInsets.all(12),
          children: [
            EventRichCard(
              event: hero,
              imageUrl: imageUrl,
              density: EventCardDensity.detail,
              registered: registered,
              allowRegistration: allowReg,
              onOpenDetail: null,
              onPrimaryCta: null,
              showPrimaryCta: false,
              overlayHeroDetailsOnBanner: overlayHero,
              midRow: overlayHero
                  ? null
                  : Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Chip(
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          backgroundColor: Colors.black.withValues(alpha: 0.55),
                          side: BorderSide(color: Colors.white.withValues(alpha: 0.45)),
                          shape: const StadiumBorder(),
                          label: Text(eventOngoingOrUpcomingLabel(ev)),
                          labelStyle: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                            color: Colors.white,
                            letterSpacing: 0.4,
                          ),
                        ),
                        if (allowReg)
                          Chip(
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            backgroundColor: Colors.black.withValues(alpha: 0.55),
                            side: BorderSide(color: Colors.white.withValues(alpha: 0.45)),
                            shape: const StadiumBorder(),
                            avatar: const Icon(Icons.how_to_reg_outlined, size: 18, color: Colors.white),
                            label: const Text("Registration open"),
                            labelStyle: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                              color: Colors.white,
                            ),
                          ),
                      ],
                    ),
            ),
            if (hasRichBlocks)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: EventPageBlocksView(layout: pageLayout),
              ),
            if (staffView)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text("Edit activity details"),
                    onPressed: () => _openEventEditor(context),
                  ),
                ),
              ),
            if (staffView && desc.isNotEmpty && !showDesc)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Description (hidden from members)",
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Text(desc, style: Theme.of(context).textTheme.bodyMedium),
                    ],
                  ),
                ),
              ),
            if (showDesc && desc.length > 200 && !hasRichBlocks)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Full description", style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      Text(desc),
                    ],
                  ),
                ),
              ),
            if (customLabel.isNotEmpty && customUrl.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: FilledButton.icon(
                  onPressed: () async {
                    final uri = Uri.tryParse(customUrl);
                    if (uri == null || !(uri.isScheme("http") || uri.isScheme("https"))) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("This link is not valid.")),
                      );
                      return;
                    }
                    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
                    if (!ok && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Could not open the link.")),
                      );
                    }
                  },
                  icon: const Icon(Icons.open_in_new),
                  label: Text(customLabel),
                ),
              ),
            if (allowReg && showRegBlock && (staffView || regCount > 0))
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Registrations", style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Text(
                        regCount == 0
                            ? "No registrations yet."
                            : "$regCount ${regCount == 1 ? "person has" : "people have"} registered.",
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      if (app.canStaffManageThisEvent(ev)) ...[
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: () => context.push("/admin/events/${widget.eventId}/registrations"),
                          icon: const Icon(Icons.groups_outlined),
                          label: const Text("View registrants & student profiles"),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            if (showPollBlock && (canManagePollsHere || feedPolls.isNotEmpty))
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              "Polling / voting",
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          if (canManagePollsHere)
                            TextButton.icon(
                              onPressed: () => _openPollEditorDialog(context, app, null, eventTitle: title),
                              icon: const Icon(Icons.add_circle_outline, size: 20),
                              label: const Text("New poll"),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (feedPolls.isEmpty && canManagePollsHere)
                        Text(
                          "No polls linked yet. Use “New poll” and include the event title in the question so it shows up here.",
                          style: Theme.of(context).textTheme.bodySmall,
                        )
                      else
                        ...feedPolls.map((poll) {
                        final pollId = intFromJsonField(poll, "id");
                        final options = (poll["options"] as List<dynamic>? ?? [])
                            .map((e) => Map<String, dynamic>.from(e as Map))
                            .toList();
                        int optionVotes(Map<String, dynamic> o) =>
                            intFromJsonField(o, "votes_count") ?? intFromJsonField(o, "votesCount") ?? 0;
                        final totalVotesCast = options.fold<int>(0, (sum, o) => sum + optionVotes(o));
                        final myVote = intFromJsonField(poll, "my_vote_option_id");
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        poll["question"]?.toString() ?? "",
                                        style: const TextStyle(fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                    if (canManagePollsHere && pollId != null) ...[
                                      IconButton(
                                        tooltip: "Edit poll",
                                        onPressed: () => _openPollEditorDialog(context, app, poll),
                                        icon: const Icon(Icons.edit_outlined, size: 22),
                                      ),
                                      IconButton(
                                        tooltip: "Delete poll",
                                        onPressed: () => _confirmDeletePoll(context, app, pollId),
                                        icon: Icon(Icons.delete_outline, size: 22, color: Colors.red.shade700),
                                      ),
                                    ],
                                  ],
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Text(
                                    totalVotesCast == 0
                                        ? "No votes yet."
                                        : "$totalVotesCast ${totalVotesCast == 1 ? "vote" : "votes"} cast (one vote per person).",
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                                        ),
                                  ),
                                ),
                                ...options.map((o) {
                                  final optionId = intFromJsonField(o, "id");
                                  final votes = optionVotes(o);
                                  final selected = myVote != null && optionId != null && myVote == optionId;
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: OutlinedButton(
                                      onPressed: (pollId != null && optionId != null)
                                          ? () async {
                                              final err = await app.submitPollVote(pollId: pollId, optionId: optionId);
                                              if (!context.mounted) return;
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(content: Text(err ?? "Vote recorded.")),
                                              );
                                            }
                                          : null,
                                      style: OutlinedButton.styleFrom(
                                        backgroundColor: selected
                                            ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4)
                                            : null,
                                        side: selected
                                            ? BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.6)
                                            : null,
                                      ),
                                      child: Row(
                                        children: [
                                          if (selected)
                                            Padding(
                                              padding: const EdgeInsets.only(right: 6),
                                              child: Icon(Icons.check_circle,
                                                  size: 18, color: Theme.of(context).colorScheme.primary),
                                            ),
                                          Expanded(
                                            child: Align(
                                              alignment: Alignment.centerLeft,
                                              child: Text(
                                                o["label"]?.toString() ?? "",
                                                style: TextStyle(
                                                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                          ),
                                          Text(
                                            votes == 1 ? "1 vote" : "$votes votes",
                                            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                  color: Theme.of(context).colorScheme.primary,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            if (!app.canManageEvents && allowReg && showRegBlock)
              FilledButton(
                onPressed: () {
                  context.push("/events/${widget.eventId}/register");
                },
                child: Text(registered ? "View / update registration" : "Register"),
              ),
          ],
        ),
      ),
      ),
    );
  }

  Color _parseHexColor(String hex) {
    var s = hex.trim();
    if (s.startsWith("#")) {
      s = s.substring(1);
    }
    if (s.length == 3) {
      s = s.split("").map((c) => "$c$c").join();
    }
    if (s.length != 6) {
      return const Color(0xFFFFFFFF);
    }
    final v = int.tryParse(s, radix: 16);
    if (v == null) {
      return const Color(0xFFFFFFFF);
    }
    return Color(0xFF000000 | v);
  }

  Widget _wrapWithBackground(String? imageUrl, Widget child) {
    if (imageUrl == null) {
      return child;
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.network(imageUrl, fit: BoxFit.cover, errorBuilder: (_, e, s) => const SizedBox.shrink()),
        Container(color: Colors.black.withValues(alpha: 0.25)),
        child,
      ],
    );
  }

  Future<void> _openPollEditorDialog(
    BuildContext context,
    AppState app,
    Map<String, dynamic>? poll, {
    String? eventTitle,
  }) async {
    final isEdit = poll != null;
    final qCtrl = TextEditingController(text: poll?["question"]?.toString() ?? (eventTitle != null ? "Poll: $eventTitle" : ""));
    final dCtrl = TextEditingController(text: poll?["description"]?.toString() ?? "");
    final optionCtrls = <TextEditingController>[];
    if (poll != null) {
      final opts = poll["options"] as List<dynamic>? ?? [];
      for (final o in opts) {
        optionCtrls.add(TextEditingController(text: (o as Map<String, dynamic>)["label"]?.toString() ?? ""));
      }
    }
    while (optionCtrls.length < 2) {
      optionCtrls.add(TextEditingController());
    }
    bool isActive = poll?["is_active"] != false;

    final submit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(isEdit ? "Edit poll" : "Create poll"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: qCtrl, decoration: const InputDecoration(labelText: "Question")),
                const SizedBox(height: 8),
                TextField(
                  controller: dCtrl,
                  decoration: const InputDecoration(labelText: "Description (optional)"),
                  maxLines: 2,
                ),
                const SizedBox(height: 8),
                ...optionCtrls.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final ctrl = entry.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: ctrl,
                            decoration: InputDecoration(labelText: "Option ${idx + 1}"),
                          ),
                        ),
                        if (optionCtrls.length > 2)
                          IconButton(
                            onPressed: () => setDialogState(() => optionCtrls.removeAt(idx)),
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                      ],
                    ),
                  );
                }),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setDialogState(() => optionCtrls.add(TextEditingController())),
                    icon: const Icon(Icons.add),
                    label: const Text("Add option"),
                  ),
                ),
                SwitchListTile(
                  value: isActive,
                  onChanged: (v) => setDialogState(() => isActive = v),
                  title: const Text("Active"),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text("Cancel")),
            FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text("Save")),
          ],
        ),
      ),
    );
    if (submit != true) {
      for (final c in optionCtrls) {
        c.dispose();
      }
      qCtrl.dispose();
      dCtrl.dispose();
      return;
    }
    final err = await app.savePoll(
      pollId: intFromJsonField(poll ?? {}, "id"),
      question: qCtrl.text,
      description: dCtrl.text.trim().isEmpty ? null : dCtrl.text.trim(),
      isActive: isActive,
      options: optionCtrls.map((e) => e.text).toList(),
    );
    for (final c in optionCtrls) {
      c.dispose();
    }
    qCtrl.dispose();
    dCtrl.dispose();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err ?? "Poll saved.")));
    await _refreshLive(silent: true);
  }

  Future<void> _confirmDeleteEvent(
    BuildContext context,
    AppState app,
    int eventId,
    String eventTitle,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete this activity?"),
        content: Text(
          '"$eventTitle" will be removed from the campus dashboard for everyone. All registrations '
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
    if (err != null) {
      showCampusOperationSnackBar(context, err, isError: true);
      return;
    }
    showCampusOperationSnackBar(context, "Activity deleted.");
    context.pop();
  }

  Future<void> _confirmDeletePoll(BuildContext context, AppState app, int pollId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete poll?"),
        content: const Text("Votes will be cleared. This cannot be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text("Cancel")),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text("Delete")),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final err = await app.removePoll(pollId);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err ?? "Poll deleted.")));
    await _refreshLive(silent: true);
  }
}
