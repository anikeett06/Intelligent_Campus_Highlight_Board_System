import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:studentboard/providers/app_state.dart';
import 'package:studentboard/utils/json_helpers.dart';
import 'package:studentboard/widgets/campus_refresh.dart';

/// Admin-only list of campus accounts (students and faculty).
class AdminCampusUsersScreen extends StatefulWidget {
  const AdminCampusUsersScreen({super.key});

  @override
  State<AdminCampusUsersScreen> createState() => _AdminCampusUsersScreenState();
}

class _AdminCampusUsersScreenState extends State<AdminCampusUsersScreen> {
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
    if (!app.isAdmin || app.accessToken == null) {
      setState(() {
        _loading = false;
        _err = "Administrators only.";
      });
      return;
    }
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final raw = await app.api.getUsersList(app.accessToken!);
      if (!mounted) return;
      setState(() {
        _rows = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _err = "Could not load directory.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (!app.isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text("Campus directory")),
        body: const Center(child: Text("Only campus administrators can open this list.")),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text("Campus directory"),
        actions: [
          IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh_outlined), tooltip: "Refresh"),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _err != null
              ? Center(child: Text(_err!))
              : CampusRefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    physics: kCampusPullToRefreshPhysics,
                    padding: const EdgeInsets.all(12),
                    itemCount: _rows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, i) {
                      final u = _rows[i];
                      final id = intFromJsonField(u, "id");
                      final name = u["full_name"]?.toString() ?? "-";
                      final email = u["email"]?.toString() ?? "";
                      final role = (u["role"]?.toString() ?? "student").toUpperCase();
                      final active = u["is_active"] != false;
                      return Card(
                        child: ListTile(
                          title: Text(name),
                          subtitle: Text("$email · $role${active ? "" : " · INACTIVE"}"),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: id == null ? null : () => context.push("/admin/users/$id"),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
