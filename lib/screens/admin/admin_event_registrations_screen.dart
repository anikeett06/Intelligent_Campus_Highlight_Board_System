import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:studentboard/providers/app_state.dart';
import 'package:studentboard/utils/json_helpers.dart';
import 'package:studentboard/widgets/campus_refresh.dart';

class AdminEventRegistrationsScreen extends StatefulWidget {
  const AdminEventRegistrationsScreen({super.key, required this.eventId});

  final int eventId;

  @override
  State<AdminEventRegistrationsScreen> createState() => _AdminEventRegistrationsScreenState();
}

class _AdminEventRegistrationsScreenState extends State<AdminEventRegistrationsScreen> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _err;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    if (app.accessToken == null || !app.canManageEvents) {
      return;
    }
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final raw = await app.api.getEventRegistrationsAdmin(app.accessToken!, widget.eventId);
      if (!mounted) {
        return;
      }
      setState(() {
        _rows = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _err = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: Text("Registrations · Event ${widget.eventId}")),
      body: CampusRefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  physics: kCampusPullToRefreshPhysics,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                ),
              )
            : ListView(
                physics: kCampusPullToRefreshPhysics,
                padding: const EdgeInsets.all(12),
                children: [
                  if (_err != null) Text(_err!),
                  Text("Students registered: ${_rows.length}", style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    "Tap a student to open their full profile (admin & faculty).",
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54),
                  ),
                  const SizedBox(height: 8),
                  ..._rows.map((r) {
                    final uid = intFromJsonField(r, "user_id");
                    final img = r["profile_image_path"]?.toString();
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundImage: (img != null && img.isNotEmpty) ? NetworkImage("${app.api.serverOrigin}$img") : null,
                          child: (img == null || img.isEmpty) ? const Icon(Icons.person) : null,
                        ),
                        title: Text(r["full_name"]?.toString() ?? ""),
                        subtitle: Text(
                          "Account: ${r["account_email"] ?? "-"}\nRoll: ${r["roll_no"] ?? "-"} · Registered as: ${r["participant_name"] ?? "-"}",
                        ),
                        isThreeLine: true,
                        trailing: const Icon(Icons.chevron_right),
                        onTap: uid == null ? null : () => context.push("/admin/users/$uid"),
                      ),
                    );
                  }),
                ],
              ),
      ),
    );
  }
}
