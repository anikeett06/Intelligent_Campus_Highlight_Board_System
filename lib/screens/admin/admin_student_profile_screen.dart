import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:studentboard/providers/app_state.dart';
import 'package:studentboard/utils/json_helpers.dart';
import 'package:studentboard/widgets/campus_refresh.dart';

/// Profile detail for a campus member (from registrations or admin directory).
class AdminStudentProfileScreen extends StatefulWidget {
  const AdminStudentProfileScreen({super.key, required this.userId});

  final int userId;

  @override
  State<AdminStudentProfileScreen> createState() => _AdminStudentProfileScreenState();
}

class _AdminStudentProfileScreenState extends State<AdminStudentProfileScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  final _adminNameCtrl = TextEditingController();
  String _adminRole = "student";
  bool _adminActive = true;
  bool _adminSaving = false;
  int? _clubModSavingCommunityId;
  int? _grantCommunityId;
  bool _academicPostingAllowed = false;
  bool _studentCampusLead = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _adminNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    if (app.accessToken == null) {
      return;
    }
    try {
      final d = await app.api.getUserAdminProfile(app.accessToken!, widget.userId);
      if (!mounted) {
        return;
      }
      setState(() {
        _data = d;
        _loading = false;
        _adminNameCtrl.text = d["full_name"]?.toString() ?? "";
        _adminRole = (d["role"]?.toString() ?? "student").toLowerCase() == "faculty" ? "faculty" : "student";
        _adminActive = d["is_active"] != false;
        _academicPostingAllowed = d["academic_posting_allowed"] == true;
        _studentCampusLead = d["student_admin"] == true;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _loading = false);
    }
  }

  Future<void> _saveAdminEdits(AppState app) async {
    setState(() => _adminSaving = true);
    final err = await app.adminUpdateCampusMember(
      userId: widget.userId,
      fullName: _adminNameCtrl.text.trim().isEmpty ? null : _adminNameCtrl.text.trim(),
      role: _adminRole,
      isActive: _adminActive,
      academicPostingAllowed: _adminRole == "faculty" ? _academicPostingAllowed : null,
      studentAdmin: _adminRole == "student" ? _studentCampusLead : null,
    );
    if (!mounted) return;
    setState(() => _adminSaving = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err ?? "Account updated.")));
    if (err == null) {
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text("Campus member")),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_data == null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Campus member")),
        body: const Center(child: Text("Could not load profile.")),
      );
    }
    final p = _data!;
    final img = p["profile_image_path"]?.toString();
    final regs = (p["registrations"] as List<dynamic>?) ?? [];
    final roleLabel = (p["role"]?.toString() ?? "student").toUpperCase();
    final active = p["is_active"] != false;
    final targetIsAdmin = (p["role"]?.toString() ?? "").toLowerCase() == "admin";
    final targetRole = (p["role"]?.toString() ?? "").toLowerCase();
    final canBeClubManager = targetRole == "student" || targetRole == "faculty";
    final clubRows = (p["club_memberships"] as List<dynamic>?) ?? [];
    return Scaffold(
      appBar: AppBar(title: Text(p["full_name"]?.toString() ?? "Campus member")),
      body: CampusRefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: kCampusPullToRefreshPhysics,
          padding: const EdgeInsets.all(16),
          children: [
          if (app.isAdmin || (app.isFaculty && app.academicPostingAllowed) || app.isStudentAdmin)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Material(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(
                    app.isAdmin
                        ? "You can correct this member's account below and assign per-club managers. Faculty dashboard edits follow academic rules on the dashboard or Events screens."
                        : "You are viewing this profile as staff.",
                  ),
                ),
              ),
            ),
          if (app.isAdmin && !targetIsAdmin) ...[
            Card(
              color: Colors.amber.shade50,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text("Campus account", style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _adminNameCtrl,
                      decoration: const InputDecoration(labelText: "Display name", border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _adminRole,
                      decoration: const InputDecoration(labelText: "Campus role", border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: "student", child: Text("Student")),
                        DropdownMenuItem(value: "faculty", child: Text("Faculty / staff")),
                      ],
                      onChanged: _adminSaving
                          ? null
                          : (v) {
                              if (v == null) return;
                              setState(() {
                                _adminRole = v;
                                if (v == "faculty") {
                                  _studentCampusLead = false;
                                } else {
                                  _academicPostingAllowed = false;
                                }
                              });
                            },
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text("Account active (can sign in)"),
                      value: _adminActive,
                      onChanged: _adminSaving ? null : (v) => setState(() => _adminActive = v),
                    ),
                    if (_adminRole == "faculty") ...[
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text("Academic posting enabled"),
                        subtitle: const Text(
                          "When on, this faculty member may post and edit academic dashboard items, events, polls, and academic shortcut files.",
                        ),
                        value: _academicPostingAllowed,
                        onChanged: _adminSaving ? null : (v) => setState(() => _academicPostingAllowed = v),
                      ),
                    ],
                    if (_adminRole == "student") ...[
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text("Student campus lead"),
                        subtitle: const Text(
                          "When on, this student may create clubs and non-academic activities only. Academic board stays locked.",
                        ),
                        value: _studentCampusLead,
                        onChanged: _adminSaving ? null : (v) => setState(() => _studentCampusLead = v),
                      ),
                    ],
                    FilledButton(
                      onPressed: _adminSaving ? null : () => _saveAdminEdits(app),
                      child: Text(_adminSaving ? "Saving…" : "Save account changes"),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (app.isAdmin && !targetIsAdmin && canBeClubManager) ...[
            Card(
              color: Colors.teal.shade50,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text("Club manager (per club)", style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Text(
                      "Like a group admin in chat apps: this person can post announcements, edit club details, add members, and remove this club only while the switch is on for that club. Campus administrators assign managers here.",
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black87),
                    ),
                    const SizedBox(height: 12),
                    if (clubRows.isEmpty)
                      Text("Not a member of any club yet. Use “Grant on a club” below to add them as a member and manager.", style: Theme.of(context).textTheme.bodySmall),
                    ...clubRows.map((raw) {
                      final m = raw as Map<String, dynamic>;
                      final cid = intFromJsonField(m, "community_id");
                      final name = m["community_name"]?.toString() ?? "Club #$cid";
                      final isMod = m["is_moderator"] == true;
                      if (cid == null) return const SizedBox.shrink();
                      return SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(name),
                        subtitle: const Text("Can manage this club in the app"),
                        value: isMod,
                        onChanged: _clubModSavingCommunityId != null
                            ? null
                            : (v) async {
                                final messenger = ScaffoldMessenger.of(context);
                                setState(() => _clubModSavingCommunityId = cid);
                                final err = await app.adminSetUserClubModerator(userId: widget.userId, communityId: cid, isModerator: v);
                                if (!mounted) return;
                                setState(() => _clubModSavingCommunityId = null);
                                messenger.showSnackBar(SnackBar(content: Text(err ?? (v ? "Manager enabled." : "Manager removed."))));
                                if (err == null) await _load();
                              },
                      );
                    }),
                    const Divider(height: 24),
                    Text("Grant on another club", style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    if (app.communities.isEmpty)
                      const Text("No clubs exist yet. Create a club from the dashboard first.", style: TextStyle(fontSize: 13)),
                    if (app.communities.isNotEmpty) ...[
                      DropdownButtonFormField<int>(
                        value: _grantCommunityId,
                        decoration: const InputDecoration(labelText: "Club", border: OutlineInputBorder(), isDense: true),
                        items: () {
                          final items = <DropdownMenuItem<int>>[];
                          for (final raw in app.communities) {
                            if (raw is! Map) continue;
                            final c = Map<String, dynamic>.from(raw.map((k, v) => MapEntry(k.toString(), v)));
                            final id = intFromJsonField(c, "id");
                            if (id == null) continue;
                            items.add(DropdownMenuItem<int>(
                              value: id,
                              child: Text(c["name"]?.toString() ?? "Club $id"),
                            ));
                          }
                          return items;
                        }(),
                        onChanged: _clubModSavingCommunityId != null
                            ? null
                            : (v) => setState(() => _grantCommunityId = v),
                      ),
                      const SizedBox(height: 10),
                      FilledButton.tonal(
                        onPressed: _clubModSavingCommunityId != null || _grantCommunityId == null
                            ? null
                            : () async {
                                final messenger = ScaffoldMessenger.of(context);
                                final cid = _grantCommunityId!;
                                setState(() => _clubModSavingCommunityId = cid);
                                final err = await app.adminSetUserClubModerator(userId: widget.userId, communityId: cid, isModerator: true);
                                if (!mounted) return;
                                setState(() => _clubModSavingCommunityId = null);
                                messenger.showSnackBar(SnackBar(content: Text(err ?? "Club manager granted.")));
                                if (err == null) await _load();
                              },
                        child: const Text("Grant manager on selected club"),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 48,
                backgroundImage: (img != null && img.isNotEmpty) ? NetworkImage("${app.api.serverOrigin}$img") : null,
                child: (img == null || img.isEmpty) ? const Icon(Icons.person, size: 48) : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p["full_name"]?.toString() ?? "", style: Theme.of(context).textTheme.headlineSmall),
                    Text(p["email"]?.toString() ?? ""),
                    Text("Role: $roleLabel${active ? "" : " (inactive)"}", style: Theme.of(context).textTheme.bodySmall),
                    if ((p["phone"]?.toString() ?? "").isNotEmpty) Text("Phone: ${p["phone"]}"),
                    if ((p["college_name"]?.toString() ?? "").isNotEmpty) Text("College: ${p["college_name"]}"),
                    if ((p["bio"]?.toString() ?? "").isNotEmpty) Text("Bio: ${p["bio"]}"),
                    if (p["birth_date"] != null) Text("Birth date: ${p["birth_date"]}"),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text("Registered events", style: Theme.of(context).textTheme.titleMedium),
          ...regs.map((raw) {
            final r = raw as Map<String, dynamic>;
            return Card(
              child: ListTile(
                title: Text(r["event_title"]?.toString() ?? ""),
                subtitle: Text("As: ${r["participant_name"] ?? "-"} | Roll ${r["roll_no"] ?? "-"} | Branch ${r["branch"] ?? "-"}"),
                isThreeLine: true,
              ),
            );
          }),
        ],
        ),
      ),
    );
  }
}
