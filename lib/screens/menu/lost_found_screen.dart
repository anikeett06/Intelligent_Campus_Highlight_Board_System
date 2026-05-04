import 'dart:async';
import 'dart:io' show File;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'package:studentboard/providers/app_state.dart';
import 'package:studentboard/widgets/app_shell.dart';
import 'package:studentboard/widgets/campus_refresh.dart';
import 'package:studentboard/utils/json_helpers.dart';

class LostFoundScreen extends StatefulWidget {
  const LostFoundScreen({super.key});

  @override
  State<LostFoundScreen> createState() => _LostFoundScreenState();
}

class _LostFoundScreenState extends State<LostFoundScreen> {
  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _location = TextEditingController();
  final _picker = ImagePicker();
  XFile? _selectedImage;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return AppShell(
      title: "Lost & Found",
      body: CampusRefreshIndicator(
        onRefresh: app.loadAll,
        child: ListView(
          physics: kCampusPullToRefreshPhysics,
          padding: const EdgeInsets.all(12),
          children: [
          if (app.isFaculty || app.isAdmin)
            Card(
              color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.55),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.verified_user_outlined, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        app.isFaculty
                            ? "Faculty: you can mark any listing as resolved when an item is returned to its owner."
                            : "Admin: mark items resolved or remove listings as needed.",
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onPrimaryContainer,
                              fontSize: 13,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (app.isFaculty || app.isAdmin) const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  const Text("Post item", style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  TextField(controller: _title, decoration: const InputDecoration(labelText: "Title")),
                  TextField(controller: _desc, decoration: const InputDecoration(labelText: "Description")),
                  TextField(controller: _location, decoration: const InputDecoration(labelText: "Location")),
                  const SizedBox(height: 8),
                  if (_selectedImage != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: kIsWeb
                          ? FutureBuilder<Uint8List>(
                              future: _selectedImage!.readAsBytes(),
                              builder: (context, snapshot) {
                                if (!snapshot.hasData) {
                                  return const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()));
                                }
                                return Image.memory(snapshot.data!, height: 140, width: double.infinity, fit: BoxFit.cover);
                              },
                            )
                          : Image.file(File(_selectedImage!.path), height: 140, width: double.infinity, fit: BoxFit.cover),
                    ),
                  TextButton.icon(
                    onPressed: () async {
                      final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 75);
                      if (!mounted) {
                        return;
                      }
                      setState(() => _selectedImage = picked);
                    },
                    icon: const Icon(Icons.photo_camera_back_outlined),
                    label: Text(_selectedImage == null ? "Upload item photo" : "Change photo"),
                  ),
                  const SizedBox(height: 10),
                  FilledButton(
                    onPressed: () async {
                      await app.createLostItem(_title.text.trim(), _desc.text.trim(), _location.text.trim(), _selectedImage);
                      if (!mounted) {
                        return;
                      }
                      setState(() {
                        _title.clear();
                        _desc.clear();
                        _location.clear();
                        _selectedImage = null;
                      });
                    },
                    child: const Text("Submit"),
                  ),
                ],
              ),
            ),
          ),
          ...app.lostFound.map(
            (raw) {
              final item = Map<String, dynamic>.from(raw as Map);
              return Card(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (item["image_path"] != null && item["image_path"].toString().isNotEmpty)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          "${app.api.serverOrigin}${item["image_path"]}",
                          height: 140,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Container(
                            height: 140,
                            color: Colors.grey.shade200,
                            alignment: Alignment.center,
                            child: const Icon(Icons.broken_image_outlined),
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Text(item["title"]?.toString() ?? "", style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(item["description"]?.toString() ?? ""),
                    const SizedBox(height: 4),
                    Text("Location: ${item["location"] ?? "-"}"),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(item["is_found"] == true ? "Found" : "Open"),
                    ),
                    if (_canChangeFoundStatus(app, item)) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (item["is_found"] != true)
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  final id = intFromJsonField(item, "id");
                                  if (id == null) return;
                                  final err = await app.setLostFoundItemFound(id, true);
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(err ?? "Marked as found / resolved.")),
                                  );
                                },
                                icon: const Icon(Icons.check_circle_outline),
                                label: Text(app.isFaculty || app.isAdmin ? "Mark resolved" : "Mark as found"),
                              ),
                            ),
                          if (item["is_found"] == true)
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  final id = intFromJsonField(item, "id");
                                  if (id == null) return;
                                  final err = await app.setLostFoundItemFound(id, false);
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(err ?? "Listing reopened.")),
                                  );
                                },
                                icon: const Icon(Icons.restore),
                                label: const Text("Reopen listing"),
                              ),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _openFoundCommentDialog(context, item),
                            icon: const Icon(Icons.message_outlined),
                            label: const Text("Found this item? Comment"),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => _showComments(context, item),
                            child: const Text("View found comments"),
                          ),
                        ),
                        if (_canCancelItem(app, item))
                          Expanded(
                            child: TextButton(
                              onPressed: () => _cancelItem(context, item),
                              child: const Text("Cancel request"),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            );
            },
          ),
        ],
        ),
      ),
    );
  }

  bool _canCancelItem(AppState app, Map<String, dynamic> item) {
    final myId = intFromJsonField(app.profile ?? {}, "id");
    final authorId = intFromJsonField(item, "author_id");
    return app.isAdmin || (myId != null && authorId != null && myId == authorId);
  }

  bool _canChangeFoundStatus(AppState app, Map<String, dynamic> item) {
    final myId = intFromJsonField(app.profile ?? {}, "id");
    final authorId = intFromJsonField(item, "author_id");
    return app.isAdmin || app.isFaculty || (myId != null && authorId != null && myId == authorId);
  }

  Future<void> _cancelItem(BuildContext context, Map<String, dynamic> item) async {
    final app = context.read<AppState>();
    final itemId = intFromJsonField(item, "id");
    if (itemId == null) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final err = await app.cancelLostFoundRequest(itemId);
    if (!context.mounted) {
      return;
    }
    messenger.showSnackBar(SnackBar(content: Text(err ?? "Item request cancelled.")));
  }

  Future<void> _openFoundCommentDialog(BuildContext context, Map<String, dynamic> item) async {
    final app = context.read<AppState>();
    final itemId = intFromJsonField(item, "id");
    if (itemId == null) {
      return;
    }
    final finderCtrl = TextEditingController(text: app.profile?["full_name"]?.toString() ?? "");
    final contactCtrl = TextEditingController();
    final messageCtrl = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Found this item?"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: finderCtrl, decoration: const InputDecoration(labelText: "Your name")),
              TextField(controller: contactCtrl, decoration: const InputDecoration(labelText: "Contact (phone/email)")),
              TextField(
                controller: messageCtrl,
                decoration: const InputDecoration(labelText: "Message to owner"),
                maxLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text("Cancel")),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text("Submit")),
        ],
      ),
    );
    if (result != true) {
      return;
    }
    if (finderCtrl.text.trim().isEmpty || messageCtrl.text.trim().isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Name and message are required.")));
      }
      return;
    }
    final err = await app.addFoundComment(
      itemId: itemId,
      finderName: finderCtrl.text.trim(),
      message: messageCtrl.text.trim(),
      contact: contactCtrl.text.trim().isEmpty ? null : contactCtrl.text.trim(),
    );
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err ?? "Comment sent to item owner.")));
  }

  Future<void> _showComments(BuildContext context, Map<String, dynamic> item) async {
    final app = context.read<AppState>();
    final itemId = intFromJsonField(item, "id");
    if (itemId == null) {
      return;
    }
    final err = await app.loadLostFoundComments(itemId);
    if (!context.mounted) {
      return;
    }
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    final comments = app.lostFoundComments[itemId] ?? [];
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Found comments (${comments.length})", style: Theme.of(sheetContext).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (comments.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text("No comments yet.")),
              if (comments.isNotEmpty)
                SizedBox(
                  height: 300,
                  child: ListView.builder(
                    itemCount: comments.length,
                    itemBuilder: (context, index) {
                      final c = comments[index] as Map<String, dynamic>;
                      return Card(
                        child: ListTile(
                          title: Text(c["finder_name"]?.toString() ?? "Finder"),
                          subtitle: Text("${c["message"] ?? ""}\nContact: ${c["contact"] ?? "-"}"),
                          isThreeLine: true,
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
