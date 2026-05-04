import 'dart:async';
import 'dart:convert';
import 'dart:io' show File;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'package:studentboard/providers/app_state.dart';
import 'package:studentboard/screens/admin/event_page_layout.dart';
import 'package:studentboard/services/in_app_notification_toast.dart';
import 'package:studentboard/utils/json_helpers.dart';
import 'package:studentboard/widgets/campus_refresh.dart';
import 'package:studentboard/widgets/event_rich_card.dart';

Uint8List _defaultBannerPngBytes() => base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
    );

class AdminEventEditorScreen extends StatefulWidget {
  const AdminEventEditorScreen({super.key, this.eventId});

  final int? eventId;

  @override
  State<AdminEventEditorScreen> createState() => _AdminEventEditorScreenState();
}

class _AdminEventEditorScreenState extends State<AdminEventEditorScreen> {
  static const List<String> _kEditorSectionOrder = [
    "poster",
    "headline",
    "schedule",
    "story",
    "highlights",
    "links",
    "audience",
    "advanced",
  ];

  final _titleCtrl = TextEditingController();
  final _festNameCtrl = TextEditingController();
  final _organizedByCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _teamFormatCtrl = TextEditingController();
  final _entryFeeCtrl = TextEditingController();
  final _prizeSummaryCtrl = TextEditingController();
  final _picker = ImagePicker();

  DateTime _start = DateTime.now().add(const Duration(hours: 1));
  DateTime _end = DateTime.now().add(const Duration(hours: 2));
  String _category = "general";
  String _priority = "normal";
  bool _allowRegistration = true;
  bool _showDescription = true;
  bool _showLocation = true;
  bool _showRegistrationSection = true;
  bool _showPollsSection = true;
  bool _showAnnouncementsSection = true;
  bool _showCategoryBadge = true;
  bool _showInDashboard = true;
  bool _trendingHighlight = false;
  bool _overlayOnBanner = false;
  bool _useSeparateCarousel = false;
  String _backgroundKind = "none";
  String _backgroundColorHex = "#FFFFFF";
  XFile? _backgroundImage;
  String? _existingBackgroundPath;
  final _customLinkLabelCtrl = TextEditingController();
  final _customLinkUrlCtrl = TextEditingController();
  final _dashboardTitleCtrl = TextEditingController();
  final _dashboardDescriptionCtrl = TextEditingController();
  final _autoRemoveHoursCtrl = TextEditingController(text: "0");
  XFile? _poster;
  XFile? _carouselPoster;
  String? _existingCarouselPath;
  PlatformFile? _examTimetable;
  String? _existingPosterPath;
  String? _existingExamTimetablePath;
  bool _busy = false;
  EventPageLayout _layout = EventPageLayout.empty();

  bool get _isEdit => widget.eventId != null && widget.eventId! > 0;

  String _fmt(DateTime dt) {
    final d = dt.toLocal();
    final y = d.year.toString().padLeft(4, "0");
    final m = d.month.toString().padLeft(2, "0");
    final day = d.day.toString().padLeft(2, "0");
    final hh = d.hour.toString().padLeft(2, "0");
    final mm = d.minute.toString().padLeft(2, "0");
    return "$y-$m-$day $hh:$mm";
  }

  Map<String, dynamic>? _eventRowForId(AppState app, int id) {
    for (final raw in app.events) {
      final m = raw as Map<String, dynamic>;
      if (eventIdFromJson(m) == id) {
        return m;
      }
    }
    return null;
  }

  List<Widget> _deleteToolbarActions(BuildContext context, AppState app) {
    final id = widget.eventId;
    if (id == null) {
      return const [];
    }
    final row = _eventRowForId(app, id);
    if (row == null || !app.canDeleteDashboardActivity(row)) {
      return const [];
    }
    return [
      IconButton(
        tooltip: "Delete activity",
        icon: const Icon(Icons.delete_outline),
        onPressed: _busy ? null : () => unawaited(_confirmDeleteFromEditor(context, app, id)),
      ),
    ];
  }

  Future<void> _confirmDeleteFromEditor(BuildContext context, AppState app, int eventId) async {
    final row = _eventRowForId(app, eventId);
    final titleHint = row?["title"]?.toString() ?? "This activity";
    final title = _titleCtrl.text.trim().isEmpty ? titleHint : _titleCtrl.text.trim();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete this activity?"),
        content: Text(
          '"$title" will be removed from the campus dashboard for everyone. All registrations '
          "will be cleared. This cannot be undone.",
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
    if (ok != true || !mounted) {
      return;
    }
    setState(() => _busy = true);
    final err = await app.deleteAdminEvent(eventId);
    if (!mounted || !context.mounted) {
      return;
    }
    setState(() => _busy = false);
    if (err != null) {
      showCampusOperationSnackBar(context, err, isError: true);
      return;
    }
    showCampusOperationSnackBar(context, "Activity deleted.");
    context.pop();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _loadExisting();
    });
  }

  Future<void> _loadExisting() async {
    if (!_isEdit || !mounted) {
      return;
    }
    final app = context.read<AppState>();
    if (!app.canManageEvents) {
      return;
    }
    Map<String, dynamic>? item;
    for (final row in app.events) {
      final m = row as Map<String, dynamic>;
      if (eventIdFromJson(m) == widget.eventId) {
        item = m;
        break;
      }
    }
    if (item == null) {
      return;
    }
    final loaded = item;
    if (!app.canEditDashboardActivity(loaded)) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "You can only edit dashboard activities you created. Campus administrators may edit any.",
            ),
          ),
        );
        context.pop();
      });
      return;
    }
    final parsed = EventPageLayout.tryParse(loaded["event_page_json"]?.toString());
    setState(() {
      _titleCtrl.text = loaded["title"]?.toString() ?? "";
      _festNameCtrl.text = loaded["fest_name"]?.toString() ?? "";
      _locationCtrl.text = loaded["location"]?.toString() ?? "";
      _category = loaded["category"]?.toString() ?? "general";
      _priority = loaded["priority"]?.toString() ?? "normal";
      _allowRegistration = loaded["allow_registration"] != false;
      _showDescription = eventBoolField(loaded, "show_description");
      _showLocation = eventBoolField(loaded, "show_location");
      _showRegistrationSection = eventBoolField(loaded, "show_registration_section");
      _showPollsSection = eventBoolField(loaded, "show_polls_section");
      _showAnnouncementsSection = eventBoolField(loaded, "show_announcements_section");
      _customLinkLabelCtrl.text = loaded["custom_link_label"]?.toString() ?? "";
      _customLinkUrlCtrl.text = loaded["custom_link_url"]?.toString() ?? "";
      _teamFormatCtrl.text = loaded["team_format"]?.toString() ?? "";
      _entryFeeCtrl.text = loaded["entry_fee"]?.toString() ?? "";
      _prizeSummaryCtrl.text = loaded["prize_summary"]?.toString() ?? "";
      _showCategoryBadge = eventBoolField(loaded, "show_category_badge");
      _showInDashboard = eventShowInDashboard(loaded);
      _trendingHighlight = eventTrendingHighlight(loaded);
      _dashboardTitleCtrl.text = loaded["dashboard_title"]?.toString() ?? "";
      _dashboardDescriptionCtrl.text = loaded["dashboard_description"]?.toString() ?? "";
      _autoRemoveHoursCtrl.text = loaded["auto_remove_after_hours"]?.toString() ?? "0";
      _existingPosterPath = loaded["poster_path"]?.toString();
      _existingExamTimetablePath = loaded["exam_timetable_path"]?.toString();
      _existingCarouselPath = loaded["dashboard_carousel_poster_path"]?.toString();
      _useSeparateCarousel =
          _existingCarouselPath != null && _existingCarouselPath!.trim().isNotEmpty;
      final rawBgKind = loaded["event_page_background_kind"]?.toString().trim().toLowerCase() ?? "none";
      _backgroundKind = (rawBgKind == "color" || rawBgKind == "image") ? rawBgKind : "none";
      final rawBgColor = loaded["event_page_background_color"]?.toString().trim() ?? "";
      _backgroundColorHex = rawBgColor.isEmpty ? "#FFFFFF" : rawBgColor;
      _existingBackgroundPath = loaded["event_page_background_path"]?.toString();
      final s = DateTime.tryParse(loaded["start_time"]?.toString() ?? "");
      final e = DateTime.tryParse(loaded["end_time"]?.toString() ?? "");
      if (s != null) _start = s.toLocal();
      if (e != null) _end = e.toLocal();
      if (parsed != null) {
        _layout = parsed;
        _organizedByCtrl.text = _layout.heroOrganizedBy;
        _overlayOnBanner = _layout.overlayHeroOnBanner;
      } else {
        _layout = EventPageLayout.empty();
        _organizedByCtrl.clear();
        _overlayOnBanner = false;
      }
      if (app.isFaculty && !app.isAdmin && app.academicPostingAllowed) {
        if (_category == "club") {
          _category = "general";
        }
      }
      if (app.isStudent && app.isStudentAdmin && !app.isAdmin) {
        if (_category == "academic" || _category == "exam") {
          _category = "general";
        }
      }
    });
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _festNameCtrl.dispose();
    _organizedByCtrl.dispose();
    _locationCtrl.dispose();
    _teamFormatCtrl.dispose();
    _entryFeeCtrl.dispose();
    _prizeSummaryCtrl.dispose();
    _customLinkLabelCtrl.dispose();
    _customLinkUrlCtrl.dispose();
    _dashboardTitleCtrl.dispose();
    _dashboardDescriptionCtrl.dispose();
    _autoRemoveHoursCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime({required bool isStart}) async {
    final base = isStart ? _start : _end;
    final date = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) {
      return;
    }
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(base));
    if (time == null || !mounted) {
      return;
    }
    final dt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() {
      if (isStart) {
        _start = dt;
        if (_end.isBefore(_start)) {
          _end = _start.add(const Duration(hours: 1));
        }
      } else {
        _end = dt;
      }
    });
  }

  Future<void> _openAddSegmentSheet(EventRichBlock block) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.title),
              title: const Text("Heading"),
              onTap: () => Navigator.pop(ctx, "heading"),
            ),
            ListTile(
              leading: const Icon(Icons.short_text),
              title: const Text("Sub-heading"),
              onTap: () => Navigator.pop(ctx, "subheading"),
            ),
            ListTile(
              leading: const Icon(Icons.notes_outlined),
              title: const Text("Body text"),
              onTap: () => Navigator.pop(ctx, "body"),
            ),
            ListTile(
              leading: const Icon(Icons.format_list_bulleted),
              title: const Text("Bullet list"),
              onTap: () => Navigator.pop(ctx, "bullets"),
            ),
            ListTile(
              leading: const Icon(Icons.grid_on_outlined),
              title: const Text("Table"),
              onTap: () => Navigator.pop(ctx, "table"),
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text("Link"),
              onTap: () => Navigator.pop(ctx, "link"),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) {
      return;
    }
    setState(() {
      switch (choice) {
        case "heading":
          block.segments.add(SegText(style: "heading", text: ""));
        case "subheading":
          block.segments.add(SegText(style: "subheading", text: ""));
        case "body":
          block.segments.add(SegText(style: "body", text: ""));
        case "bullets":
          block.segments.add(SegBullets(items: [""]));
        case "table":
          block.segments.add(SegTable(headers: ["Column A", "Column B"], rows: [["", ""]]));
        case "link":
          block.segments.add(SegLink());
        default:
          break;
      }
    });
  }

  void _moveBlock(int index, int delta) {
    final j = index + delta;
    if (j < 0 || j >= _layout.blocks.length) {
      return;
    }
    setState(() {
      final b = _layout.blocks.removeAt(index);
      _layout.blocks.insert(j, b);
    });
  }

  void _deleteBlockAt(int index) {
    setState(() => _layout.blocks.removeAt(index));
  }

  String _segmentLabel(RichSegment seg) {
    if (seg is SegText) {
      return "Text (${seg.style})";
    }
    if (seg is SegBullets) {
      return "Bullet list (${seg.items.where((e) => e.trim().isNotEmpty).length} items)";
    }
    if (seg is SegTable) {
      return "Table (${seg.rows.length} rows)";
    }
    if (seg is SegLink) {
      return "Link: ${seg.label.isNotEmpty ? seg.label : seg.url}";
    }
    return "Segment";
  }

  String _segmentPreview(RichSegment seg) {
    final t = seg.flatten();
    if (t.length > 120) {
      return "${t.substring(0, 117)}…";
    }
    return t.isEmpty ? "(empty)" : t;
  }

  Future<void> _editSegmentDialog(EventRichBlock block, int segIndex) async {
    final seg = block.segments[segIndex];
    if (seg is SegText) {
      final c = TextEditingController(text: seg.text);
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text("Edit ${seg.style}"),
          content: TextField(
            controller: c,
            maxLines: seg.style == "body" ? 8 : 3,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Save")),
          ],
        ),
      );
      if (ok == true && mounted) {
        setState(() => seg.text = c.text);
      }
      c.dispose();
      return;
    }
    if (seg is SegBullets) {
      final c = TextEditingController(text: seg.items.join("\n"));
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Edit bullet list"),
          content: TextField(
            controller: c,
            maxLines: 10,
            decoration: const InputDecoration(hintText: "One item per line", border: OutlineInputBorder()),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Save")),
          ],
        ),
      );
      if (ok == true && mounted) {
        setState(() {
          seg.items
            ..clear()
            ..addAll(c.text.split("\n").map((e) => e.trim()).where((e) => e.isNotEmpty));
        });
      }
      c.dispose();
      return;
    }
    if (seg is SegTable) {
      final h = TextEditingController(text: seg.headers.join(", "));
      final r = TextEditingController(text: seg.rows.map((row) => row.join(" | ")).join("\n"));
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Edit table"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: h,
                  decoration: const InputDecoration(labelText: "Headers (comma-separated)", border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: r,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    labelText: "Rows (one per line, cells with | )",
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Save")),
          ],
        ),
      );
      if (ok == true && mounted) {
        setState(() {
          seg.headers
            ..clear()
            ..addAll(h.text.split(",").map((e) => e.trim()).where((e) => e.isNotEmpty));
          seg.rows.clear();
          for (final line in r.text.split("\n")) {
            if (line.trim().isEmpty) {
              continue;
            }
            seg.rows.add(line.split("|").map((e) => e.trim()).toList());
          }
        });
      }
      h.dispose();
      r.dispose();
      return;
    }
    if (seg is SegLink) {
      final la = TextEditingController(text: seg.label);
      final ur = TextEditingController(text: seg.url);
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Edit link"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: la, decoration: const InputDecoration(labelText: "Label", border: OutlineInputBorder())),
              const SizedBox(height: 10),
              TextField(controller: ur, decoration: const InputDecoration(labelText: "URL", border: OutlineInputBorder())),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Save")),
          ],
        ),
      );
      if (ok == true && mounted) {
        setState(() {
          seg.label = la.text;
          seg.url = ur.text;
        });
      }
      la.dispose();
      ur.dispose();
    }
  }

  Widget _segmentRow(int blockIndex, int segIndex, RichSegment seg) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(_segmentLabel(seg), style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(_segmentPreview(seg), maxLines: 3, overflow: TextOverflow.ellipsis),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: _busy ? null : () => _editSegmentDialog(_layout.blocks[blockIndex], segIndex),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              onPressed: _busy ? null : () => setState(() => _layout.blocks[blockIndex].segments.removeAt(segIndex)),
            ),
          ],
        ),
      ),
    );
  }

  static const List<String> _kPresetBackgroundColors = [
    "#FFFFFF",
    "#F8FAFC",
    "#FEF3C7",
    "#FCE7F3",
    "#E0F2FE",
    "#DCFCE7",
    "#EDE9FE",
    "#1F2937",
    "#0F172A",
  ];

  Color _hexToColor(String hex, {Color fallback = const Color(0xFFFFFFFF)}) {
    var s = hex.trim();
    if (s.startsWith("#")) {
      s = s.substring(1);
    }
    if (s.length == 3) {
      s = s.split("").map((c) => "$c$c").join();
    }
    if (s.length != 6) {
      return fallback;
    }
    final v = int.tryParse(s, radix: 16);
    if (v == null) {
      return fallback;
    }
    return Color(0xFF000000 | v);
  }

  Future<void> _openColorPickerDialog() async {
    final ctrl = TextEditingController(text: _backgroundColorHex);
    String temp = _backgroundColorHex;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text("Pick a background color"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final hex in _kPresetBackgroundColors)
                      InkWell(
                        onTap: () {
                          setLocal(() => temp = hex);
                          ctrl.text = hex;
                        },
                        borderRadius: BorderRadius.circular(28),
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: _hexToColor(hex),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: temp.toLowerCase() == hex.toLowerCase()
                                  ? Theme.of(ctx).colorScheme.primary
                                  : Theme.of(ctx).colorScheme.outlineVariant,
                              width: temp.toLowerCase() == hex.toLowerCase() ? 3 : 1,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: ctrl,
                  decoration: const InputDecoration(
                    labelText: "Hex (e.g. #112233)",
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => setLocal(() => temp = v),
                ),
                const SizedBox(height: 12),
                Container(
                  height: 56,
                  decoration: BoxDecoration(
                    color: _hexToColor(temp),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Theme.of(ctx).colorScheme.outlineVariant),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    "Preview",
                    style: TextStyle(
                      color: ThemeData.estimateBrightnessForColor(_hexToColor(temp)) == Brightness.dark
                          ? Colors.white
                          : Colors.black,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Apply")),
          ],
        ),
      ),
    );
    if (ok == true && mounted) {
      var hex = ctrl.text.trim();
      if (!hex.startsWith("#")) {
        hex = "#$hex";
      }
      if (hex.length == 4) {
        hex = "#${hex.substring(1).split("").map((c) => "$c$c").join()}";
      }
      if (hex.length == 7) {
        setState(() => _backgroundColorHex = hex.toUpperCase());
      }
    }
    ctrl.dispose();
  }

  Widget _buildBackgroundCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final app = context.read<AppState>();
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Event page background",
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              "Optional. Pick a solid color or upload an image to use behind the event page content.",
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            RadioListTile<String>(
              contentPadding: EdgeInsets.zero,
              value: "none",
              groupValue: _backgroundKind,
              onChanged: _busy ? null : (v) => setState(() => _backgroundKind = v ?? "none"),
              title: const Text("Default (theme background)"),
            ),
            RadioListTile<String>(
              contentPadding: EdgeInsets.zero,
              value: "color",
              groupValue: _backgroundKind,
              onChanged: _busy ? null : (v) => setState(() => _backgroundKind = v ?? "color"),
              title: const Text("Solid color"),
              secondary: GestureDetector(
                onTap: _busy
                    ? null
                    : () {
                        setState(() => _backgroundKind = "color");
                        _openColorPickerDialog();
                      },
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: _hexToColor(_backgroundColorHex),
                    shape: BoxShape.circle,
                    border: Border.all(color: cs.outlineVariant),
                  ),
                ),
              ),
            ),
            if (_backgroundKind == "color")
              Padding(
                padding: const EdgeInsets.only(left: 12, bottom: 6),
                child: Row(
                  children: [
                    Text(
                      _backgroundColorHex.toUpperCase(),
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: _busy ? null : _openColorPickerDialog,
                      icon: const Icon(Icons.palette_outlined),
                      label: const Text("Change"),
                    ),
                  ],
                ),
              ),
            RadioListTile<String>(
              contentPadding: EdgeInsets.zero,
              value: "image",
              groupValue: _backgroundKind,
              onChanged: _busy ? null : (v) => setState(() => _backgroundKind = v ?? "image"),
              title: const Text("Custom image"),
            ),
            if (_backgroundKind == "image") ...[
              if (_backgroundImage != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: kIsWeb
                      ? FutureBuilder<Uint8List>(
                          future: _backgroundImage!.readAsBytes(),
                          builder: (context, snap) {
                            if (!snap.hasData) {
                              return const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()));
                            }
                            return Image.memory(snap.data!, height: 140, width: double.infinity, fit: BoxFit.cover);
                          },
                        )
                      : Image.file(File(_backgroundImage!.path), height: 140, width: double.infinity, fit: BoxFit.cover),
                )
              else if (_existingBackgroundPath != null &&
                  _existingBackgroundPath!.trim().isNotEmpty &&
                  app.api.serverOrigin.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    "${app.api.serverOrigin}${_existingBackgroundPath!}",
                    height: 140,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _busy
                      ? null
                      : () async {
                          final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
                          if (!mounted || picked == null) {
                            return;
                          }
                          setState(() => _backgroundImage = picked);
                        },
                  icon: const Icon(Icons.image_outlined),
                  label: Text(
                    _backgroundImage != null || (_existingBackgroundPath?.isNotEmpty ?? false)
                        ? "Change background image"
                        : "Choose background image",
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _richBlockCard(int index, EventRichBlock b) {
    return Card(
      key: ValueKey(b.id),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                  child: Text("${index + 2}", style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "Content block",
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  tooltip: "Move up",
                  icon: const Icon(Icons.arrow_upward),
                  onPressed: index == 0 || _busy ? null : () => _moveBlock(index, -1),
                ),
                IconButton(
                  tooltip: "Move down",
                  icon: const Icon(Icons.arrow_downward),
                  onPressed: index >= _layout.blocks.length - 1 || _busy ? null : () => _moveBlock(index, 1),
                ),
                IconButton(
                  tooltip: "Remove block",
                  icon: Icon(Icons.close, color: Theme.of(context).colorScheme.error),
                  onPressed: _busy ? null : () => _deleteBlockAt(index),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextFormField(
              key: ValueKey("bh-${b.id}"),
              initialValue: b.heading ?? "",
              onChanged: (v) => b.heading = v.trim().isEmpty ? null : v,
              decoration: const InputDecoration(
                labelText: "Block heading (optional)",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              key: ValueKey("bs-${b.id}"),
              initialValue: b.subheading ?? "",
              onChanged: (v) => b.subheading = v.trim().isEmpty ? null : v,
              decoration: const InputDecoration(
                labelText: "Sub-heading (optional)",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                icon: const Icon(Icons.add_circle_outline),
                label: const Text("Add to this block"),
                onPressed: _busy ? null : () => _openAddSegmentSheet(b),
              ),
            ),
            const SizedBox(height: 8),
            for (var s = 0; s < b.segments.length; s++) _segmentRow(index, s, b.segments[s]),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    final location = _locationCtrl.text.trim();
    final customLabel = _customLinkLabelCtrl.text.trim();
    final customUrl = _customLinkUrlCtrl.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please enter the event name.")));
      return;
    }
    XFile? posterSend = _poster;
    if (posterSend == null && !_isEdit) {
      posterSend = XFile.fromData(
        _defaultBannerPngBytes(),
        name: "default-banner.png",
        mimeType: "image/png",
      );
    }
    if (!_isEdit && posterSend == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Add a banner image.")));
      return;
    }
    if (_isEdit &&
        posterSend == null &&
        (_existingPosterPath == null || _existingPosterPath!.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Add a banner image.")));
      return;
    }
    if (customLabel.isEmpty != customUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Custom button needs both a label and a URL, or leave both empty.")),
      );
      return;
    }
    if (customUrl.isNotEmpty) {
      final uri = Uri.tryParse(customUrl);
      if (uri == null || !uri.hasScheme || !(uri.isScheme("http") || uri.isScheme("https"))) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Custom link URL must start with http:// or https://")),
        );
        return;
      }
    }
    if (_end.isBefore(_start)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("End time must be after start time.")));
      return;
    }
    final autoRemoveHours = int.tryParse(_autoRemoveHoursCtrl.text.trim()) ?? 0;
    if (autoRemoveHours < 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Auto remove hours must be 0 or more.")));
      return;
    }

    _layout.heroOrganizedBy = _organizedByCtrl.text;
    _layout.overlayHeroOnBanner = _overlayOnBanner;
    final flatDesc = _layout.flattenDescription();

    setState(() => _busy = true);
    final app = context.read<AppState>();
    final String segment;
    final String category;
    if (app.isFaculty && !app.isAdmin && app.academicPostingAllowed) {
      segment = "academic";
      category = _category == "club" ? "general" : _category;
    } else if (app.isStudent && app.isStudentAdmin && !app.isAdmin) {
      segment = "non_academic";
      category = (_category == "academic" || _category == "exam") ? "general" : _category;
    } else if (app.isAdmin) {
      segment = (_category == "academic" || _category == "exam") ? "academic" : "non_academic";
      category = _category;
    } else {
      segment = "non_academic";
      category = _category;
    }
    final err = await app.saveAdminEvent(
      eventId: _isEdit ? widget.eventId : null,
      title: title,
      description: flatDesc,
      category: category,
      priority: _priority,
      location: location,
      startTime: _start,
      endTime: _end,
      autoRemoveAfterHours: autoRemoveHours,
      allowRegistration: _allowRegistration,
      dashboardSegment: segment,
      showDescription: _showDescription,
      showLocation: _showLocation,
      showRegistrationSection: _showRegistrationSection,
      showPollsSection: _showPollsSection,
      showAnnouncementsSection: _showAnnouncementsSection,
      customLinkLabel: customLabel.isEmpty ? null : customLabel,
      customLinkUrl: customUrl.isEmpty ? null : customUrl,
      festName: _festNameCtrl.text.trim().isEmpty ? null : _festNameCtrl.text.trim(),
      teamFormat: _teamFormatCtrl.text.trim().isEmpty ? null : _teamFormatCtrl.text.trim(),
      entryFee: _entryFeeCtrl.text.trim().isEmpty ? null : _entryFeeCtrl.text.trim(),
      prizeSummary: _prizeSummaryCtrl.text.trim().isEmpty ? null : _prizeSummaryCtrl.text.trim(),
      showCategoryBadge: _showCategoryBadge,
      editorSectionOrderJson: jsonEncode(_kEditorSectionOrder),
      showInDashboard: _showInDashboard,
      trendingHighlight: _trendingHighlight && _showInDashboard,
      dashboardTitle: _dashboardTitleCtrl.text.trim().isEmpty ? null : _dashboardTitleCtrl.text.trim(),
      dashboardDescription:
          _dashboardDescriptionCtrl.text.trim().isEmpty ? null : _dashboardDescriptionCtrl.text.trim(),
      eventPageJson: _layout.encode(),
      useSeparateCarouselImage: _useSeparateCarousel,
      eventPageBackgroundKind: _backgroundKind,
      eventPageBackgroundColor: _backgroundKind == "color" ? _backgroundColorHex : null,
      poster: posterSend,
      carouselPoster: _useSeparateCarousel ? _carouselPoster : null,
      eventPageBackground: _backgroundKind == "image" ? _backgroundImage : null,
      examTimetable: _examTimetable,
    );
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
    final ok = err == null;
    showCampusOperationSnackBar(
      context,
      err ?? (_isEdit ? "Activity updated successfully." : "Activity published successfully."),
      isError: !ok,
    );
    if (ok) {
      context.pop();
    }
  }

  Map<String, dynamic> _previewEventMap() {
    return {
      "title": _titleCtrl.text.trim().isEmpty ? "Event title" : _titleCtrl.text.trim(),
      "fest_name": _festNameCtrl.text.trim(),
      "description": _layout.flattenDescription(),
      "location": _locationCtrl.text.trim(),
      "category": _category,
      "start_time": _start.toUtc().toIso8601String(),
      "end_time": _end.toUtc().toIso8601String(),
      "team_format": _teamFormatCtrl.text.trim(),
      "entry_fee": _entryFeeCtrl.text.trim(),
      "prize_summary": _prizeSummaryCtrl.text.trim(),
      "allow_registration": _allowRegistration,
      "show_category_badge": _showCategoryBadge,
    };
  }

  String _previewPosterUrl(AppState app) {
    if (_existingPosterPath != null &&
        _existingPosterPath!.isNotEmpty &&
        app.api.serverOrigin.isNotEmpty) {
      return "${app.api.serverOrigin}${_existingPosterPath!}";
    }
    return "https://images.unsplash.com/photo-1511578314322-379afb476865?auto=format&fit=crop&w=1200&q=80";
  }

  Widget? _previewPosterChild() {
    if (_poster == null) {
      return null;
    }
    if (kIsWeb) {
      return FutureBuilder<Uint8List>(
        future: _poster!.readAsBytes(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return Image.memory(snap.data!, fit: BoxFit.cover);
        },
      );
    }
    return Image.file(File(_poster!.path), fit: BoxFit.cover);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (!app.canManageEvents) {
      return Scaffold(
        appBar: AppBar(title: const Text("Permission required")),
        body: const Center(
          child: Text(
            "Only campus administrators, faculty with academic posting enabled, or appointed student campus leads may create or edit activities here.",
          ),
        ),
      );
    }
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        title: Text(_isEdit ? "Edit activity" : "Create activity"),
        actions: [
          if (_isEdit && widget.eventId != null) ..._deleteToolbarActions(context, app),
        ],
      ),
      body: CampusRefreshIndicator(
        onRefresh: app.loadAll,
        child: ListView(
          physics: kCampusPullToRefreshPhysics,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Text(
              "Build your event in blocks",
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              "Start with the hero banner, then add optional content blocks. Nothing beyond the hero is required.",
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: cs.primary,
                          foregroundColor: cs.onPrimary,
                          child: const Text("1", style: TextStyle(fontWeight: FontWeight.w900)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            "Hero — top banner",
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        Chip(label: const Text("Required"), side: BorderSide(color: cs.outline)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "Event name, dates, and a banner image are required. Everything else in this card is optional.",
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _titleCtrl,
                      decoration: const InputDecoration(
                        labelText: "Event name *",
                        hintText: "e.g. TechNova 2026 – Coding & Innovation Fest",
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _festNameCtrl,
                      decoration: const InputDecoration(
                        labelText: "Tagline (optional)",
                        hintText: "e.g. Code. Create. Compete.",
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text("Start *"),
                      subtitle: Text(_fmt(_start)),
                      trailing: const Icon(Icons.calendar_today_outlined),
                      onTap: _busy ? null : () => _pickDateTime(isStart: true),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text("End *"),
                      subtitle: Text(_fmt(_end)),
                      trailing: const Icon(Icons.calendar_today_outlined),
                      onTap: _busy ? null : () => _pickDateTime(isStart: false),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _locationCtrl,
                      decoration: const InputDecoration(
                        labelText: "Venue (optional)",
                        hintText: "Main Auditorium, XYZ Engineering College",
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _organizedByCtrl,
                      decoration: const InputDecoration(
                        labelText: "Organized by (optional)",
                        hintText: "Computer Science Department",
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text("Banner image *", style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    if (_poster != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: kIsWeb
                            ? FutureBuilder<Uint8List>(
                                future: _poster!.readAsBytes(),
                                builder: (context, snap) {
                                  if (!snap.hasData) {
                                    return const SizedBox(height: 140, child: Center(child: CircularProgressIndicator()));
                                  }
                                  return Image.memory(snap.data!, height: 160, width: double.infinity, fit: BoxFit.cover);
                                },
                              )
                            : Image.file(File(_poster!.path), height: 160, width: double.infinity, fit: BoxFit.cover),
                      )
                    else if (_existingPosterPath != null &&
                        _existingPosterPath!.isNotEmpty &&
                        app.api.serverOrigin.isNotEmpty)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          "${app.api.serverOrigin}${_existingPosterPath!}",
                          height: 160,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        TextButton.icon(
                          onPressed: _busy
                              ? null
                              : () async {
                                  final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
                                  if (!mounted || picked == null) {
                                    return;
                                  }
                                  setState(() => _poster = picked);
                                },
                          icon: const Icon(Icons.photo_library_outlined),
                          label: Text(_isEdit ? "Change banner" : "Choose banner"),
                        ),
                        TextButton.icon(
                          onPressed: _busy
                              ? null
                              : () {
                                  setState(() {
                                    _poster = XFile.fromData(
                                      _defaultBannerPngBytes(),
                                      name: "default-banner.png",
                                      mimeType: "image/png",
                                    );
                                  });
                                },
                          icon: const Icon(Icons.image_outlined),
                          label: const Text("Use default banner"),
                        ),
                      ],
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text("Show title & dates on the banner"),
                      subtitle: const Text("Otherwise they appear in a separate section under the image."),
                      value: _overlayOnBanner,
                      onChanged: _busy ? null : (v) => setState(() => _overlayOnBanner = v),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Dashboard carousel",
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "Optional: use a different image in the home carousel than the main event banner.",
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text("Show on dashboard"),
                      value: _showInDashboard,
                      onChanged: _busy
                          ? null
                          : (v) => setState(() {
                                _showInDashboard = v;
                                if (!v) {
                                  _trendingHighlight = false;
                                  _useSeparateCarousel = false;
                                }
                              }),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text("Trending highlight"),
                      subtitle: const Text("If on, this activity appears in the dashboard Trending highlights carousel."),
                      value: _trendingHighlight,
                      onChanged: _busy || !_showInDashboard ? null : (v) => setState(() => _trendingHighlight = v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text("Use a separate carousel image"),
                      subtitle: const Text("If off, the same banner as above is used when the event appears on the dashboard."),
                      value: _useSeparateCarousel,
                      onChanged: _busy || !_showInDashboard ? null : (v) => setState(() => _useSeparateCarousel = v),
                    ),
                    if (_useSeparateCarousel && _showInDashboard) ...[
                      if (_carouselPoster != null ||
                          (_existingCarouselPath != null &&
                              _existingCarouselPath!.isNotEmpty &&
                              app.api.serverOrigin.isNotEmpty))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            _carouselPoster != null ? "New carousel image selected" : "Current carousel image on file",
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ),
                      TextButton.icon(
                        onPressed: _busy
                            ? null
                            : () async {
                                final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
                                if (!mounted || picked == null) {
                                  return;
                                }
                                setState(() => _carouselPoster = picked);
                              },
                        icon: const Icon(Icons.collections_outlined),
                        label: const Text("Pick carousel image"),
                      ),
                    ],
                    const SizedBox(height: 8),
                    TextField(
                      controller: _dashboardTitleCtrl,
                      enabled: !_busy && _showInDashboard,
                      decoration: const InputDecoration(
                        labelText: "Short dashboard title (optional)",
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _dashboardDescriptionCtrl,
                      enabled: !_busy && _showInDashboard,
                      decoration: const InputDecoration(
                        labelText: "Short line under the title on the dashboard (optional)",
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            _buildBackgroundCard(context),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    "More content blocks",
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.add),
                  label: const Text("Add block"),
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                            _layout.blocks.add(EventRichBlock(id: newEventRichBlockId()));
                          }),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < _layout.blocks.length; i++) _richBlockCard(i, _layout.blocks[i]),
            const SizedBox(height: 8),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: ExpansionTile(
                title: Text("Announcements & polls", style: TextStyle(fontWeight: FontWeight.w700, color: cs.onSurface)),
                subtitle: const Text("Optional — control what appears on the public event page"),
                children: [
                  SwitchListTile(
                    value: _showAnnouncementsSection,
                    onChanged: _busy ? null : (v) => setState(() => _showAnnouncementsSection = v),
                    title: const Text("Announcements block"),
                    subtitle: const Text("Related campus notices that mention this event."),
                  ),
                  SwitchListTile(
                    value: _showPollsSection,
                    onChanged: _busy ? null : (v) => setState(() => _showPollsSection = v),
                    title: const Text("Polls / voting block"),
                    subtitle: const Text("After saving, add polls from the event page with “New poll”."),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: ExpansionTile(
                title: Text("Activity details & visibility", style: TextStyle(fontWeight: FontWeight.w700, color: cs.onSurface)),
                children: [
                  TextField(
                    controller: _teamFormatCtrl,
                    decoration: const InputDecoration(labelText: "Team format (optional)", border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _entryFeeCtrl,
                    decoration: const InputDecoration(labelText: "Entry fee (optional)", border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _prizeSummaryCtrl,
                    decoration: const InputDecoration(labelText: "Prizes (optional)", border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    value: _showCategoryBadge,
                    onChanged: _busy ? null : (v) => setState(() => _showCategoryBadge = v),
                    title: const Text("Show category badge on poster"),
                  ),
                  DropdownButtonFormField<String>(
                    key: ValueKey("category_$_category"),
                    initialValue: _category,
                    items: [
                      const DropdownMenuItem(value: "general", child: Text("General")),
                      if (!(app.isStudent && app.isStudentAdmin && !app.isAdmin)) ...[
                        const DropdownMenuItem(value: "academic", child: Text("Academic")),
                        const DropdownMenuItem(value: "exam", child: Text("Exam")),
                      ],
                      if (!app.isFaculty || app.isAdmin || (app.isStudent && app.isStudentAdmin && !app.isAdmin))
                        const DropdownMenuItem(value: "club", child: Text("Club / Community")),
                    ],
                    onChanged: _busy ? null : (v) => setState(() => _category = v ?? "general"),
                    decoration: const InputDecoration(labelText: "Category", border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    key: ValueKey("priority_$_priority"),
                    initialValue: _priority,
                    items: const [
                      DropdownMenuItem(value: "normal", child: Text("Normal")),
                      DropdownMenuItem(value: "urgent", child: Text("Urgent")),
                      DropdownMenuItem(value: "ongoing", child: Text("Ongoing")),
                      DropdownMenuItem(value: "upcoming", child: Text("Upcoming")),
                      DropdownMenuItem(value: "academic", child: Text("Academic")),
                    ],
                    onChanged: _busy ? null : (v) => setState(() => _priority = v ?? "normal"),
                    decoration: const InputDecoration(labelText: "Priority", border: OutlineInputBorder()),
                  ),
                  SwitchListTile(
                    value: _allowRegistration,
                    onChanged: _busy ? null : (v) => setState(() => _allowRegistration = v),
                    title: const Text("Allow registration"),
                  ),
                  TextField(
                    controller: _autoRemoveHoursCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: "Auto remove after end (hours)",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _customLinkLabelCtrl,
                    decoration: const InputDecoration(labelText: "Custom button label (optional)", border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _customLinkUrlCtrl,
                    decoration: const InputDecoration(labelText: "Custom button URL (optional)", border: OutlineInputBorder()),
                  ),
                  SwitchListTile(
                    value: _showDescription,
                    onChanged: _busy ? null : (v) => setState(() => _showDescription = v),
                    title: const Text("Show generated description text"),
                  ),
                  SwitchListTile(
                    value: _showLocation,
                    onChanged: _busy ? null : (v) => setState(() => _showLocation = v),
                    title: const Text("Show venue on event page"),
                  ),
                  SwitchListTile(
                    value: _showRegistrationSection,
                    onChanged: _busy ? null : (v) => setState(() => _showRegistrationSection = v),
                    title: const Text("Show registration block"),
                  ),
                  if (_category == "exam") ...[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.table_chart_outlined),
                      title: Text(
                        _examTimetable?.name ??
                            ((_existingExamTimetablePath != null && _existingExamTimetablePath!.isNotEmpty)
                                ? _existingExamTimetablePath!.split("/").last
                                : "No timetable file selected"),
                      ),
                      subtitle: const Text("Exam timetable (PDF / spreadsheet)"),
                      trailing: TextButton(
                        onPressed: _busy
                            ? null
                            : () async {
                                final picked = await FilePicker.pickFiles(
                                  withData: kIsWeb,
                                  type: FileType.custom,
                                  allowedExtensions: const ["pdf", "xls", "xlsx", "csv", "ods"],
                                );
                                if (!mounted || picked == null || picked.files.isEmpty) {
                                  return;
                                }
                                setState(() => _examTimetable = picked.files.single);
                              },
                        child: const Text("Choose"),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 0,
              color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Live preview", style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    EventRichCard(
                      event: _previewEventMap(),
                      imageUrl: _previewPosterUrl(app),
                      posterChild: _previewPosterChild(),
                      registered: false,
                      allowRegistration: _allowRegistration,
                      onOpenDetail: null,
                      onPrimaryCta: null,
                      showPrimaryCta: false,
                      overlayHeroDetailsOnBanner: _overlayOnBanner,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _save,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: Text(_isEdit ? "Save changes" : "Publish activity"),
            ),
          ],
        ),
      ),
    );
  }
}
