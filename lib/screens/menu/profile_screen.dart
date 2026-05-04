import 'dart:async';
import 'dart:io' show File;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'package:studentboard/app/app_colors.dart' show AppColors;
import 'package:studentboard/providers/app_state.dart';
import 'package:studentboard/widgets/app_shell.dart';
import 'package:studentboard/widgets/campus_refresh.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _name = TextEditingController();
  final _bio = TextEditingController();
  final _phone = TextEditingController();
  final _college = TextEditingController();
  final _picker = ImagePicker();
  XFile? _newAvatar;
  DateTime? _birthDate;
  bool _saving = false;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final app = context.read<AppState>();
      final p = app.profile;
      if (p != null && mounted) {
        setState(() => _syncFromProfile(p));
      }
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _bio.dispose();
    _phone.dispose();
    _college.dispose();
    super.dispose();
  }

  void _syncFromProfile(Map<String, dynamic> p) {
    _name.text = p["full_name"]?.toString() ?? "";
    _bio.text = p["bio"]?.toString() ?? "";
    _phone.text = p["phone"]?.toString() ?? "";
    _college.text = p["college_name"]?.toString() ?? "";
    final raw = p["birth_date"]?.toString();
    if (raw != null && raw.length >= 10) {
      _birthDate = DateTime.tryParse(raw.substring(0, 10));
    } else {
      _birthDate = null;
    }
  }

  Future<void> _saveProfile(AppState app) async {
    setState(() => _saving = true);
    final birthIso = _birthDate == null
        ? ""
        : "${_birthDate!.year}-${_birthDate!.month.toString().padLeft(2, "0")}-${_birthDate!.day.toString().padLeft(2, "0")}";
    final err = await app.saveMyProfile(
      fullName: _name.text.trim().isEmpty ? null : _name.text.trim(),
      bio: _bio.text,
      birthDateIso: birthIso.isEmpty ? null : birthIso,
      phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      collegeName: _college.text.trim().isEmpty ? null : _college.text.trim(),
      profileImage: _newAvatar,
    );
    if (!mounted) {
      return;
    }
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err ?? "Profile saved.")));
    if (err == null) {
      setState(() {
        _editing = false;
        _newAvatar = null;
        if (app.profile != null) {
          _syncFromProfile(app.profile!);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final profile = app.profile ?? {};
    final imgPath = profile["profile_image_path"]?.toString();
    final origin = app.api.serverOrigin;
    final userId = profile["id"]?.toString() ?? "-";
    var role = (profile["role"]?.toString() ?? "student").toUpperCase();
    if (profile["student_admin"] == true && (profile["role"]?.toString() ?? "") == "student") {
      role = "$role · CAMPUS LEAD";
    }
    final email = profile["email"]?.toString() ?? "";
    final name = _name.text.trim().isEmpty ? (profile["full_name"]?.toString() ?? "-") : _name.text.trim();
    final college = _college.text.trim();
    final headline = college.isEmpty ? role : "$role at $college";

    return AppShell(
      title: "Profile",
      appBarActions: [
        TextButton.icon(
          onPressed: _saving
              ? null
              : () async {
                  if (_editing) {
                    await _saveProfile(app);
                  } else {
                    setState(() => _editing = true);
                  }
                },
          icon: Icon(_editing ? Icons.save_outlined : Icons.edit_outlined),
          label: Text(_editing ? (_saving ? "Saving..." : "Save") : "Edit"),
        ),
        const SizedBox(width: 8),
      ],
      body: CampusRefreshIndicator(
        onRefresh: app.loadAll,
        child: ListView(
          physics: kCampusPullToRefreshPhysics,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
          children: [
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      height: 128,
                      width: double.infinity,
                      decoration: const BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppColors.profileHeaderStart, AppColors.profileHeaderEnd],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                    ),
                    Positioned(
                      left: 18,
                      bottom: -44,
                      child: Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          CircleAvatar(
                            radius: 44,
                            backgroundColor: Colors.white,
                            child: CircleAvatar(
                              radius: 40,
                              backgroundImage: _newAvatar != null && !kIsWeb
                                  ? FileImage(File(_newAvatar!.path))
                                  : (imgPath != null && imgPath.isNotEmpty && _newAvatar == null ? NetworkImage("$origin$imgPath") : null),
                              child: _newAvatar != null && kIsWeb
                                  ? ClipOval(
                                      child: FutureBuilder<Uint8List>(
                                        future: _newAvatar!.readAsBytes(),
                                        builder: (context, snap) {
                                          if (!snap.hasData) {
                                            return const SizedBox(width: 56, height: 56, child: CircularProgressIndicator(strokeWidth: 2));
                                          }
                                          return Image.memory(snap.data!, width: 80, height: 80, fit: BoxFit.cover);
                                        },
                                      ),
                                    )
                                  : (_newAvatar == null && (imgPath == null || imgPath.isEmpty))
                                      ? const Icon(Icons.person, size: 42)
                                      : null,
                            ),
                          ),
                          IconButton(
                            onPressed: !_editing
                                ? null
                                : () async {
                                    final img = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
                                    if (mounted) {
                                      setState(() => _newAvatar = img);
                                    }
                                  },
                            icon: const Icon(Icons.camera_alt, size: 18, color: Colors.white),
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.black54,
                              minimumSize: const Size(28, 28),
                              padding: const EdgeInsets.all(4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 50),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(headline, style: Theme.of(context).textTheme.bodyMedium),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              "ID: $userId",
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Chip(label: Text(role), visualDensity: VisualDensity.compact),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(email, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (app.isAdmin) ...[
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.groups_2_outlined),
                title: const Text("Campus directory"),
                subtitle: const Text("Students and faculty: open a profile to change role or suspend access"),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push("/admin/campus-users"),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Profile details", style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _name,
                    readOnly: !_editing,
                    decoration: const InputDecoration(labelText: "Full name"),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _bio,
                    readOnly: !_editing,
                    decoration: const InputDecoration(labelText: "Bio"),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 4),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text("Birth date (optional)"),
                    subtitle: Text(_birthDate == null ? "Not set" : "${_birthDate!.year}-${_birthDate!.month.toString().padLeft(2, "0")}-${_birthDate!.day.toString().padLeft(2, "0")}"),
                    trailing: TextButton(
                      onPressed: !_editing
                          ? null
                          : () async {
                              final now = DateTime.now();
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _birthDate ?? DateTime(now.year - 18),
                                firstDate: DateTime(1900),
                                lastDate: now,
                              );
                              if (picked != null && mounted) {
                                setState(() => _birthDate = picked);
                              }
                            },
                      child: const Text("Choose"),
                    ),
                  ),
                  TextField(
                    controller: _phone,
                    readOnly: !_editing,
                    decoration: const InputDecoration(labelText: "Phone (optional)"),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _college,
                    readOnly: !_editing,
                    decoration: const InputDecoration(labelText: "College name (optional)"),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: () async {
                      await app.logout();
                      if (context.mounted) {
                        context.go("/");
                      }
                    },
                    child: const Text("Logout"),
                  ),
                ],
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }
}
