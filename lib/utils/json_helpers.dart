
// JSON helpers shared across screens.

int? intFromJsonField(Map<String, dynamic> e, String key) {
  final v = e[key];
  if (v is int) {
    return v;
  }
  if (v is num) {
    return v.toInt();
  }
  if (v is String) {
    return int.tryParse(v);
  }
  return null;
}

int? eventIdFromJson(Map<String, dynamic> e) => intFromJsonField(e, "id");

/// Parses API booleans stored as bool, int, or string (e.g. multipart forms).
bool eventBoolField(Map<String, dynamic> e, String key, {bool defaultValue = true}) {
  final v = e[key];
  if (v == null) return defaultValue;
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final s = v.toLowerCase();
    if (s == "false" || s == "0") return false;
    if (s == "true" || s == "1") return true;
  }
  return defaultValue;
}

int registrationCountFromJson(Map<String, dynamic> e) {
  final v = e["registration_count"];
  if (v is int) {
    return v;
  }
  if (v is num) {
    return v.toInt();
  }
  if (v is String) {
    return int.tryParse(v) ?? 0;
  }
  return 0;
}

/// In progress by schedule or explicit [priority] `ongoing` (UTC).
bool eventIsOngoing(Map<String, dynamic> item) {
  final priority = item["priority"]?.toString().toLowerCase() ?? "";
  if (priority == "ongoing") {
    return true;
  }
  final now = DateTime.now().toUtc();
  final start = DateTime.tryParse(item["start_time"]?.toString() ?? "")?.toUtc();
  final end = DateTime.tryParse(item["end_time"]?.toString() ?? "")?.toUtc();
  return start != null &&
      end != null &&
      (start.isBefore(now) || start.isAtSameMomentAs(now)) &&
      end.isAfter(now);
}

/// Not started yet by schedule or explicit [priority] `upcoming` (UTC).
bool eventIsUpcoming(Map<String, dynamic> item) {
  final priority = item["priority"]?.toString().toLowerCase() ?? "";
  if (priority == "upcoming") {
    return true;
  }
  final now = DateTime.now().toUtc();
  final start = DateTime.tryParse(item["start_time"]?.toString() ?? "")?.toUtc();
  return start != null && start.isAfter(now);
}

/// Poster chip text: [ONGOING] or [UPCOMING] only.
String eventOngoingOrUpcomingLabel(Map<String, dynamic> item) {
  if (eventIsOngoing(item)) {
    return "ONGOING";
  }
  if (eventIsUpcoming(item)) {
    return "UPCOMING";
  }
  final now = DateTime.now().toUtc();
  final start = DateTime.tryParse(item["start_time"]?.toString() ?? "")?.toUtc();
  if (start != null && start.isAfter(now)) {
    return "UPCOMING";
  }
  return "ONGOING";
}

/// When false, the activity stays in the Events list but is hidden from dashboard buckets/carousel.
bool eventShowInDashboard(Map<String, dynamic> item) {
  if (!item.containsKey("show_in_dashboard")) return true;
  return eventBoolField(item, "show_in_dashboard", defaultValue: true);
}

/// When true, this activity appears in the dashboard "Trending highlights" carousel.
bool eventTrendingHighlight(Map<String, dynamic> item) {
  if (!item.containsKey("trending_highlight")) return false;
  return eventBoolField(item, "trending_highlight", defaultValue: false);
}

/// Short headline on the dashboard poster; falls back to the main event title.
String eventDashboardTeaserTitle(Map<String, dynamic> item) {
  final t = item["dashboard_title"]?.toString().trim() ?? "";
  if (t.isNotEmpty) return t;
  return item["title"]?.toString() ?? "";
}

/// Image path for dashboard carousel / cards: optional carousel-only upload, else main poster.
String? eventHeroImageStoragePath(Map<String, dynamic> item) {
  final dash = item["dashboard_carousel_poster_path"]?.toString().trim() ?? "";
  if (dash.isNotEmpty) {
    return dash;
  }
  final poster = item["poster_path"]?.toString().trim() ?? "";
  return poster.isEmpty ? null : poster;
}

/// Short line under the dashboard headline; falls back to the main description.
String eventDashboardTeaserDescription(Map<String, dynamic> item) {
  final t = item["dashboard_description"]?.toString().trim() ?? "";
  if (t.isNotEmpty) return t;
  return item["description"]?.toString() ?? "";
}

/// Prefer API [poster_url] (absolute); else join [poster_path] to [serverOrigin].
/// Empty string means no poster (caller may use a fallback image).
String communityPosterDisplayUrl(Map<String, dynamic> item, String serverOrigin) {
  final abs = item["poster_url"]?.toString().trim();
  if (abs != null && abs.isNotEmpty) {
    return abs;
  }
  final path = item["poster_path"]?.toString().trim();
  if (path == null || path.isEmpty) {
    return "";
  }
  if (path.startsWith("http://") || path.startsWith("https://")) {
    return path;
  }
  final o = serverOrigin.trim();
  if (o.isEmpty) {
    return "";
  }
  return "$o${path.startsWith("/") ? path : "/$path"}";
}
