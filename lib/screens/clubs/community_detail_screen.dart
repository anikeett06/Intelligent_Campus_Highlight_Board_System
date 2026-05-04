import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:studentboard/providers/app_state.dart';
import 'package:studentboard/services/in_app_notification_toast.dart';
import 'package:studentboard/utils/api_user_message.dart';
import 'package:studentboard/widgets/app_shell.dart';
import 'package:studentboard/widgets/campus_refresh.dart';
import 'package:studentboard/utils/json_helpers.dart';

String communityNameForId(AppState app, int communityId) {
  for (final raw in app.communities) {
    final m = raw as Map<String, dynamic>;
    if (intFromJsonField(m, "id") == communityId) {
      return m["name"]?.toString() ?? "Community";
    }
  }
  for (final raw in app.myCommunities) {
    final m = raw as Map<String, dynamic>;
    if (intFromJsonField(m, "id") == communityId) {
      return m["name"]?.toString() ?? "Community";
    }
  }
  return "Community #$communityId";
}

Map<String, dynamic>? communityMapForId(AppState app, int communityId) {
  for (final raw in app.communities) {
    final m = raw as Map<String, dynamic>;
    if (intFromJsonField(m, "id") == communityId) {
      return m;
    }
  }
  for (final raw in app.myCommunities) {
    final m = raw as Map<String, dynamic>;
    if (intFromJsonField(m, "id") == communityId) {
      return m;
    }
  }
  return null;
}

class CommunityDetailScreen extends StatefulWidget {
  const CommunityDetailScreen({super.key, required this.communityId});

  final int communityId;

  @override
  State<CommunityDetailScreen> createState() => _CommunityDetailScreenState();
}

class _CommunityDetailScreenState extends State<CommunityDetailScreen> {
  List<Map<String, dynamic>> _announcements = [];
  bool _loading = true;
  String? _loadErr;
  bool _guestNeedJoin = false;
  bool _adminBusy = false;

  final _editName = TextEditingController();
  final _editDesc = TextEditingController();
  final _memberIdCtrl = TextEditingController();
  final _picker = ImagePicker();
  XFile? _communityPoster;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initFromApp());
  }

  bool _userIsMember(AppState app) {
    for (final raw in app.myCommunities) {
      final m = raw as Map<String, dynamic>;
      if (intFromJsonField(m, "id") == widget.communityId) {
        return true;
      }
    }
    return false;
  }

  bool _userCanViewClub(AppState app) {
    return app.canManageClubContent(widget.communityId) || _userIsMember(app) || app.isFollowingCommunity(widget.communityId);
  }

  void _initFromApp() {
    final app = context.read<AppState>();
    final cm = communityMapForId(app, widget.communityId);
    if (cm != null) {
      _editName.text = cm["name"]?.toString() ?? "";
      _editDesc.text = cm["description"]?.toString() ?? "";
    }
    _loadAnnouncements();
  }

  Future<void> _loadAnnouncements() async {
    final app = context.read<AppState>();
    if (app.accessToken == null) {
      return;
    }
    if (!_userCanViewClub(app)) {
      if (!mounted) {
        return;
      }
      setState(() {
        _guestNeedJoin = true;
        _loading = false;
        _announcements = [];
        _loadErr = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _loadErr = null;
      _guestNeedJoin = false;
    });
    try {
      final raw = await app.api.getClubAnnouncements(app.accessToken!, widget.communityId);
      if (!mounted) {
        return;
      }
      setState(() {
        _announcements = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _loadErr = mapDioToUserMessage(e);
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _loadErr = userMessageFromUnknown(e);
      });
    }
  }

  String _formatPosted(String? raw) {
    if (raw == null || raw.isEmpty) {
      return "";
    }
    final dt = DateTime.tryParse(raw)?.toLocal();
    if (dt == null) {
      return "";
    }
    return DateFormat.yMMMd().add_jm().format(dt);
  }

  Future<void> _openAnnouncementEditor(BuildContext context, AppState app, Map<String, dynamic>? existing) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _ClubAnnouncementEditorSheet(
          communityId: widget.communityId,
          existing: existing,
          app: app,
        ),
      ),
    );
    if (saved == true && mounted) {
      await _loadAnnouncements();
    }
  }

  Future<void> _confirmDelete(BuildContext context, AppState app, Map<String, dynamic> row) async {
    final id = intFromJsonField(row, "id");
    if (id == null) {
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete announcement?"),
        content: const Text("This cannot be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Delete")),
        ],
      ),
    );
    if (ok != true || !mounted) {
      return;
    }
    setState(() => _adminBusy = true);
    final err = await app.deleteClubAnnouncement(id, clubId: widget.communityId);
    if (!context.mounted) {
      return;
    }
    setState(() => _adminBusy = false);
    if (err != null) {
      showCampusOperationSnackBar(context, err, isError: true);
    } else {
      await _loadAnnouncements();
    }
  }

  Future<void> _showEditClubDialog(BuildContext context, AppState app) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Edit club"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: _editName, decoration: const InputDecoration(labelText: "Name")),
              const SizedBox(height: 10),
              TextField(controller: _editDesc, decoration: const InputDecoration(labelText: "Description"), maxLines: 3),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(_communityPoster == null ? "Optional new poster" : _communityPoster!.name),
                trailing: TextButton(
                  onPressed: () async {
                    final img = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
                    if (ctx.mounted) {
                      setState(() => _communityPoster = img);
                    }
                  },
                  child: const Text("Choose"),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _adminBusy
                ? null
                : () async {
                    final sure = await showDialog<bool>(
                      context: ctx,
                      builder: (cctx) => AlertDialog(
                        title: const Text("Delete this club?"),
                        content: const Text(
                          "Members, posts, and announcements will be removed permanently. This cannot be undone.",
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(cctx, false), child: const Text("Cancel")),
                          FilledButton(
                            onPressed: () => Navigator.pop(cctx, true),
                            style: FilledButton.styleFrom(
                              backgroundColor: Theme.of(cctx).colorScheme.error,
                              foregroundColor: Theme.of(cctx).colorScheme.onError,
                            ),
                            child: const Text("Delete"),
                          ),
                        ],
                      ),
                    );
                    if (sure != true || !ctx.mounted) {
                      return;
                    }
                    setState(() => _adminBusy = true);
                    final delErr = await app.deleteCommunity(widget.communityId);
                    if (!ctx.mounted) {
                      return;
                    }
                    setState(() => _adminBusy = false);
                    showCampusOperationSnackBar(
                      ctx,
                      delErr ?? "Club removed successfully.",
                      isError: delErr != null,
                    );
                    if (delErr == null) {
                      Navigator.pop(ctx);
                      if (!mounted) {
                        return;
                      }
                      context.go("/communities");
                    }
                  },
            child: Text(
              "Delete club / community",
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          FilledButton(
            onPressed: _adminBusy
                ? null
                : () async {
                    setState(() => _adminBusy = true);
                    final err = await app.updateCommunitySettings(
                      communityId: widget.communityId,
                      name: _editName.text.trim().isEmpty ? null : _editName.text.trim(),
                      description: _editDesc.text.trim(),
                      poster: _communityPoster,
                    );
                    if (!ctx.mounted) {
                      return;
                    }
                    setState(() => _adminBusy = false);
                    showCampusOperationSnackBar(
                      ctx,
                      err ?? "Club details saved successfully.",
                      isError: err != null,
                    );
                    if (err == null) {
                      setState(() => _communityPoster = null);
                      await app.loadAll();
                      if (!ctx.mounted) {
                        return;
                      }
                      Navigator.pop(ctx);
                      if (mounted) {
                        setState(() {});
                      }
                    }
                  },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddMemberDialog(BuildContext context, AppState app) async {
    _memberIdCtrl.clear();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Add member"),
        content: TextField(
          controller: _memberIdCtrl,
          decoration: const InputDecoration(labelText: "User ID (integer)"),
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          FilledButton(
            onPressed: _adminBusy
                ? null
                : () async {
                    final uid = int.tryParse(_memberIdCtrl.text.trim());
                    if (uid == null) {
                      showCampusOperationSnackBar(ctx, "Enter a valid user ID.", isError: true);
                      return;
                    }
                    setState(() => _adminBusy = true);
                    final err = await app.addCommunityMemberByUserId(communityId: widget.communityId, userId: uid);
                    if (!ctx.mounted) {
                      return;
                    }
                    setState(() => _adminBusy = false);
                    showCampusOperationSnackBar(
                      ctx,
                      err ?? "Member added successfully.",
                      isError: err != null,
                    );
                    if (err == null) {
                      Navigator.pop(ctx);
                      await app.loadAll();
                    }
                  },
            child: const Text("Add"),
          ),
        ],
      ),
    );
  }

  Widget _announcementCard(BuildContext context, AppState app, Map<String, dynamic> row) {
    final urgent = (row["priority"]?.toString().toLowerCase() ?? "") == "urgent";
    final img = row["image_url"]?.toString();
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    row["title"]?.toString() ?? "",
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
                  ),
                ),
                Chip(
                  label: Text(urgent ? "Urgent" : "Normal", style: const TextStyle(fontSize: 12)),
                  backgroundColor: urgent
                      ? Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.65)
                      : Theme.of(context).colorScheme.surfaceContainerHigh,
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
                if (app.canManageClubContent(widget.communityId))
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == "edit") {
                        _openAnnouncementEditor(context, app, row);
                      } else if (v == "delete") {
                        _confirmDelete(context, app, row);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: "edit", child: Text("Edit")),
                      PopupMenuItem(value: "delete", child: Text("Delete")),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(row["description"]?.toString() ?? "", style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 10),
            Text(
              [
                _formatPosted(row["created_at"]?.toString()),
                if ((row["creator_name"]?.toString() ?? "").isNotEmpty) " · ${row["creator_name"]}",
              ].join(),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54),
            ),
            if (img != null && img.isNotEmpty) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  "${app.api.serverOrigin}$img",
                  height: 180,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _editName.dispose();
    _editDesc.dispose();
    _memberIdCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (widget.communityId <= 0) {
      return const AppShell(title: "Club", body: Center(child: Text("Invalid club.")));
    }
    final title = communityNameForId(app, widget.communityId);
    final cm = communityMapForId(app, widget.communityId);
    final poster = cm != null ? communityPosterDisplayUrl(cm, app.api.serverOrigin) : "";
    final desc = cm?["description"]?.toString() ?? "";

    final showFab = app.canManageClubContent(widget.communityId) && !_guestNeedJoin && !_loading;

    return AppShell(
      title: title,
      floatingActionButton: showFab
          ? FloatingActionButton.extended(
              onPressed: _adminBusy ? null : () => _openAnnouncementEditor(context, app, null),
              icon: const Icon(Icons.campaign_outlined),
              label: const Text("Announcement"),
            )
          : null,
      appBarActions: app.canManageClubContent(widget.communityId)
          ? [
              IconButton(
                tooltip: "Edit club name, description, poster",
                icon: const Icon(Icons.edit_outlined),
                onPressed: _adminBusy ? null : () => _showEditClubDialog(context, app),
              ),
              IconButton(
                tooltip: "Add member by user ID",
                icon: const Icon(Icons.person_add_outlined),
                onPressed: _adminBusy ? null : () => _showAddMemberDialog(context, app),
              ),
            ]
          : null,
      body: CampusRefreshIndicator(
        onRefresh: () async {
          await app.loadAll();
          await _loadAnnouncements();
        },
        child: ListView(
          physics: kCampusPullToRefreshPhysics,
          padding: const EdgeInsets.all(12),
          children: [
            if (poster.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  poster,
                  height: 180,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    height: 120,
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    alignment: Alignment.center,
                    child: Icon(Icons.groups, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
              )
            else
              Container(
                height: 140,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(Icons.groups, size: 56, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            const SizedBox(height: 14),
            Text(title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            if (desc.isNotEmpty)
              Text(desc, style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                Chip(label: const Text("Club"), visualDensity: VisualDensity.compact, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
              ],
            ),
            if (app.isStudent && app.isFollowingCommunity(widget.communityId) && !_guestNeedJoin) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _adminBusy
                      ? null
                      : () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text("Unfollow this club?"),
                              content: const Text(
                                "You will stop receiving club updates here and in notifications until you follow again.",
                              ),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
                                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Unfollow")),
                              ],
                            ),
                          );
                          if (ok != true || !mounted) return;
                          setState(() => _adminBusy = true);
                          final err = await app.unfollowCommunity(widget.communityId);
                          if (!context.mounted) return;
                          setState(() => _adminBusy = false);
                          showCampusOperationSnackBar(
                            context,
                            err ?? "You are no longer following this club.",
                            isError: err != null,
                          );
                          if (err == null) {
                            await app.loadAll();
                            await _loadAnnouncements();
                          }
                        },
                  child: Text(
                    "Unfollow club",
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            Text("About the club", style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              desc.isEmpty ? "No description has been added for this club yet." : desc,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 18),
            Text("Activities & purpose", style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              "Members take part in activities and updates shared in announcements below.",
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black87),
            ),
            const SizedBox(height: 22),
            Text("Announcements", style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            if (_guestNeedJoin && !app.canManageClubContent(widget.communityId))
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        app.isStudent
                            ? "Follow this club to see announcements and updates here and in your notifications."
                            : "Join this club to see announcements and club updates.",
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _adminBusy
                            ? null
                            : () async {
                                setState(() => _adminBusy = true);
                                final err = app.isStudent
                                    ? await app.followCommunity(widget.communityId)
                                    : await app.joinCommunity(widget.communityId);
                                if (!context.mounted) return;
                                setState(() => _adminBusy = false);
                                showCampusOperationSnackBar(
                                  context,
                                  err ??
                                      (app.isStudent
                                          ? "You are now following this club."
                                          : "You joined this club."),
                                  isError: err != null,
                                );
                                if (err == null) {
                                  await app.loadAll();
                                  await _loadAnnouncements();
                                }
                              },
                        child: Text(app.isStudent ? "Follow club" : "Join club"),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              if (_loadErr != null)
                Card(
                  color: Colors.red.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(_loadErr!, style: TextStyle(color: Colors.red.shade900)),
                  ),
                ),
              if (_loading) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
              if (!_loading && _announcements.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text("No announcements yet. Check back later for updates from club leads."),
                  ),
                ),
              if (!_loading) ..._announcements.map((a) => _announcementCard(context, app, a)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Owns [TextEditingController]s for the modal so they are disposed after the route is torn down
/// (avoids framework `_dependents.isEmpty` assertion when disposing too early).
class _ClubAnnouncementEditorSheet extends StatefulWidget {
  const _ClubAnnouncementEditorSheet({
    required this.communityId,
    required this.existing,
    required this.app,
  });

  final int communityId;
  final Map<String, dynamic>? existing;
  final AppState app;

  @override
  State<_ClubAnnouncementEditorSheet> createState() => _ClubAnnouncementEditorSheetState();
}

class _ClubAnnouncementEditorSheetState extends State<_ClubAnnouncementEditorSheet> {
  late final TextEditingController _title;
  late final TextEditingController _desc;
  late String _priority;
  XFile? _picked;
  bool _submitting = false;
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    final ex = widget.existing;
    _title = TextEditingController(text: ex?["title"]?.toString() ?? "");
    _desc = TextEditingController(text: ex?["description"]?.toString() ?? "");
    final p = (ex?["priority"]?.toString() ?? "normal").toLowerCase();
    _priority = p == "urgent" ? "urgent" : "normal";
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_title.text.trim().isEmpty || _desc.text.trim().isEmpty) {
      showCampusOperationSnackBar(context, "Please enter a title and description.", isError: true);
      return;
    }
    setState(() => _submitting = true);
    final nav = Navigator.of(context);
    String? err;
    if (widget.existing == null) {
      err = await widget.app.createClubAnnouncement(
        clubId: widget.communityId,
        title: _title.text.trim(),
        description: _desc.text.trim(),
        priority: _priority,
        image: _picked,
      );
    } else {
      final id = intFromJsonField(widget.existing!, "id");
      if (id == null) {
        err = "Invalid announcement";
      } else {
        err = await widget.app.updateClubAnnouncement(
          announcementId: id,
          clubId: widget.communityId,
          title: _title.text.trim(),
          description: _desc.text.trim(),
          priority: _priority,
          image: _picked,
        );
      }
    }
    if (!mounted) {
      return;
    }
    setState(() => _submitting = false);
    if (err != null) {
      showCampusOperationSnackBar(context, err, isError: true);
      return;
    }
    showCampusOperationSnackBar(
      context,
      widget.existing == null ? "Announcement published successfully." : "Announcement updated successfully.",
    );
    nav.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.existing == null;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            isNew ? "Create announcement" : "Edit announcement",
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          TextField(controller: _title, decoration: const InputDecoration(labelText: "Title")),
          const SizedBox(height: 12),
          TextField(
            controller: _desc,
            decoration: const InputDecoration(labelText: "Description"),
            minLines: 3,
            maxLines: 8,
          ),
          const SizedBox(height: 12),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text("Priority", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 4),
          DropdownButton<String>(
            value: _priority,
            isExpanded: true,
            items: const [
              DropdownMenuItem(value: "normal", child: Text("Normal")),
              DropdownMenuItem(value: "urgent", child: Text("Urgent")),
            ],
            onChanged: _submitting
                ? null
                : (v) {
                    if (v != null) {
                      setState(() => _priority = v);
                    }
                  },
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _submitting
                  ? null
                  : () async {
                      final img = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
                      if (img != null && mounted) {
                        setState(() => _picked = img);
                      }
                    },
              icon: const Icon(Icons.image_outlined),
              label: Text(_picked == null ? "Optional image" : _picked!.name),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            child: Text(isNew ? "Publish" : "Save changes"),
          ),
        ],
      ),
    );
  }
}
