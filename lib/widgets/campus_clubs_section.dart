import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:studentboard/providers/app_state.dart';
import 'package:studentboard/services/in_app_notification_toast.dart';
import 'package:studentboard/utils/json_helpers.dart';
import 'package:studentboard/widgets/event_poster_card.dart';

String _clubBannerFallbackImage(String name) {
  final n = name.toLowerCase();
  if (n.contains("code") || n.contains("hack") || n.contains("dev")) {
    return "https://images.unsplash.com/photo-1511578314322-379afb476865?auto=format&fit=crop&w=1200&q=80";
  }
  if (n.contains("music") || n.contains("dance") || n.contains("art")) {
    return "https://images.unsplash.com/photo-1493225457124-a3eb161ffa5f?auto=format&fit=crop&w=1200&q=80";
  }
  if (n.contains("sport") || n.contains("fitness") || n.contains("athlet")) {
    return "https://images.unsplash.com/photo-1461896836934-0fe5982775da?auto=format&fit=crop&w=1200&q=80";
  }
  return "https://images.unsplash.com/photo-1528605248644-14dd04022da1?auto=format&fit=crop&w=1200&q=80";
}

String _clubBannerImageUrl(AppState app, Map<String, dynamic> e) {
  final resolved = communityPosterDisplayUrl(e, app.api.serverOrigin);
  if (resolved.isNotEmpty) {
    return resolved;
  }
  return _clubBannerFallbackImage(e["name"]?.toString() ?? "");
}

/// Follow / membership / manager role — used for "Followed" vs "Not followed" filters.
bool _userLinkedToClub(AppState app, int communityId) {
  if (app.isFollowingCommunity(communityId)) {
    return true;
  }
  if (app.moderatingCommunityIds.contains(communityId)) {
    return true;
  }
  for (final raw in app.myCommunities) {
    if (raw is! Map) {
      continue;
    }
    final m = Map<String, dynamic>.from(raw.map((k, v) => MapEntry(k.toString(), v)));
    if (intFromJsonField(m, "id") == communityId) {
      return true;
    }
  }
  return false;
}

enum ClubListScope { all, followed, notFollowed }

/// Clubs list + create/edit dialog — shared by the Clubs & community tab (and previously the dashboard).
class CampusClubsSection extends StatefulWidget {
  const CampusClubsSection({super.key, this.showTopDivider = false});

  /// When `true`, shows a divider above (e.g. under other dashboard content). On the dedicated clubs tab, use `false`.
  final bool showTopDivider;

  @override
  State<CampusClubsSection> createState() => _CampusClubsSectionState();
}

class _CampusClubsSectionState extends State<CampusClubsSection> {
  final TextEditingController _searchCtrl = TextEditingController();
  ClubListScope _scope = ClubListScope.all;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _filteredCommunities(AppState app) {
    final q = _searchCtrl.text.trim().toLowerCase();
    final out = <Map<String, dynamic>>[];
    for (final raw in app.communities.whereType<Map>()) {
      final e = Map<String, dynamic>.from(
        raw.map((k, v) => MapEntry(k.toString(), v)),
      );
      final cid = intFromJsonField(e, "id");
      if (cid == null) {
        continue;
      }
      final name = (e["name"]?.toString() ?? "").toLowerCase();
      final desc = (e["description"]?.toString() ?? "").toLowerCase();
      if (q.isNotEmpty && !name.contains(q) && !desc.contains(q)) {
        continue;
      }
      final linked = _userLinkedToClub(app, cid);
      switch (_scope) {
        case ClubListScope.all:
          break;
        case ClubListScope.followed:
          if (!linked) {
            continue;
          }
          break;
        case ClubListScope.notFollowed:
          if (linked) {
            continue;
          }
          break;
      }
      out.add(e);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final filtered = _filteredCommunities(app);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showTopDivider) ...[
          const SizedBox(height: 8),
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.65)),
          const SizedBox(height: 20),
        ],
        Text(
          "Clubs & communities",
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.35,
                color: cs.primary,
              ),
        ),
        const SizedBox(height: 6),
        Text(
          (app.canCreateClubs || app.isAdmin || app.moderatesAnyClub)
              ? "Tap a club to open it. If you manage a club, use Edit on that page to change name, description, or poster."
              : "Tap a club to open it. Follow or join from the club page to see announcements.",
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _searchCtrl,
          onChanged: (_) => setState(() {}),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: "Search clubs by name or description",
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _searchCtrl.text.isEmpty
                ? null
                : IconButton(
                    tooltip: "Clear",
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() {});
                    },
                    icon: const Icon(Icons.clear),
                  ),
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          "Show",
          style: Theme.of(context).textTheme.labelLarge?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: const Text("All"),
              selected: _scope == ClubListScope.all,
              onSelected: (_) => setState(() => _scope = ClubListScope.all),
            ),
            ChoiceChip(
              label: const Text("Followed"),
              selected: _scope == ClubListScope.followed,
              onSelected: (_) => setState(() => _scope = ClubListScope.followed),
            ),
            ChoiceChip(
              label: const Text("Not followed"),
              selected: _scope == ClubListScope.notFollowed,
              onSelected: (_) => setState(() => _scope = ClubListScope.notFollowed),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (app.communities.isEmpty)
          const Text("No communities yet.")
        else if (filtered.isEmpty)
          Text(
            _emptyFilterMessage(app),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          )
        else
          ...filtered.map((e) {
            final cid = intFromJsonField(e, "id");
            final rawName = e["name"]?.toString().trim() ?? "";
            final name = rawName.isEmpty ? "Club" : rawName;
            final desc = (e["description"]?.toString() ?? "").trim();
            final imageUrl = _clubBannerImageUrl(app, e);
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
                    onTap: cid == null ? null : () => context.push("/communities/$cid"),
                    child: LayoutBuilder(
                      builder: (context, bc) {
                        return EventPosterCard(
                          key: ValueKey<String>("club-banner-$cid-$imageUrl"),
                          imageUrl: imageUrl,
                          title: name,
                          description: desc,
                          accentColor: cs.primary,
                          borderRadius: 16,
                          maxHeight: 220,
                          maxWidth: bc.maxWidth,
                          titleMaxLines: 2,
                          descriptionMaxLines: 3,
                          footer: const SizedBox.shrink(),
                        );
                      },
                    ),
                  ),
                ),
              ),
            );
          }),
        if (app.canCreateClubs) ...[
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () => openCommunityCreateOrEditDialog(context: context, app: app),
            icon: const Icon(Icons.add),
            label: const Text("Create new club / community"),
          ),
        ],
      ],
    );
  }

  String _emptyFilterMessage(AppState app) {
    if (_searchCtrl.text.trim().isNotEmpty) {
      return "No clubs match your search.";
    }
    switch (_scope) {
      case ClubListScope.all:
        return "No clubs to show.";
      case ClubListScope.followed:
        if (app.isStudent) {
          return "You are not following any clubs yet. Open a club and tap Follow club.";
        }
        return "No clubs in your list yet. Follow (students), join, or manage a club to see it here.";
      case ClubListScope.notFollowed:
        return "Every available club is already on your list, or there are no other clubs.";
    }
  }
}

Future<void> openCommunityCreateOrEditDialog({
  required BuildContext context,
  required AppState app,
  int? communityId,
  String? initialName,
  String? initialDescription,
}) async {
  final nameCtrl = TextEditingController(text: initialName ?? "");
  final descCtrl = TextEditingController(text: initialDescription ?? "");
  final isEdit = communityId != null;
  try {
    final outcome = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isEdit ? "Edit club / community" : "Create club / community"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: "Club / community name"),
              ),
              TextField(
                controller: descCtrl,
                decoration: const InputDecoration(labelText: "Description"),
                maxLines: 4,
              ),
            ],
          ),
        ),
        actions: [
          if (isEdit)
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop("delete"),
              child: Text(
                "Delete club / community",
                style: TextStyle(color: Theme.of(dialogContext).colorScheme.error),
              ),
            ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop("cancel"),
            child: const Text("Cancel"),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop("save"),
            child: const Text("Save"),
          ),
        ],
      ),
    );
    if (outcome == null || outcome == "cancel") {
      return;
    }
    if (outcome == "delete" && communityId != null) {
      if (!context.mounted) {
        return;
      }
      final sure = await showDialog<bool>(
        context: context,
        builder: (confirmContext) => AlertDialog(
          title: const Text("Delete this club?"),
          content: const Text(
            "Members, posts, and announcements for this club will be removed permanently. This cannot be undone.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(confirmContext).pop(false),
              child: const Text("Cancel"),
            ),
            FilledButton(
              onPressed: () => Navigator.of(confirmContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(confirmContext).colorScheme.error,
                foregroundColor: Theme.of(confirmContext).colorScheme.onError,
              ),
              child: const Text("Delete"),
            ),
          ],
        ),
      );
      if (sure != true || !context.mounted) {
        return;
      }
      final delErr = await app.deleteCommunity(communityId);
      if (!context.mounted) {
        return;
      }
      showCampusOperationSnackBar(
        context,
        delErr ?? "Club removed successfully.",
        isError: delErr != null,
      );
      return;
    }
    if (outcome != "save") {
      return;
    }
    final name = nameCtrl.text.trim();
    final description = descCtrl.text.trim();
    if (name.isEmpty) {
      if (context.mounted) {
        showCampusOperationSnackBar(
          context,
          "Please enter a club or community name.",
          isError: true,
        );
      }
      return;
    }
    final String? err;
    if (communityId != null) {
      err = await app.updateCommunitySettings(
        communityId: communityId,
        name: name,
        description: description,
      );
    } else {
      err = await app.createCommunity(
        name: name,
        description: description.isEmpty ? null : description,
      );
    }
    if (!context.mounted) {
      return;
    }
    showCampusOperationSnackBar(
      context,
      err ??
          (communityId != null ? "Club updated successfully." : "Club created successfully."),
      isError: err != null,
    );
  } finally {
    nameCtrl.dispose();
    descCtrl.dispose();
  }
}
