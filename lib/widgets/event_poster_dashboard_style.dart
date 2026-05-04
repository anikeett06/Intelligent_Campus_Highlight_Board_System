import 'package:flutter/material.dart';

/// Shared visuals for [EventPosterCard] footers on the dashboard and Events tab.

class EventPosterDashboardColors {
  EventPosterDashboardColors._();

  static const Color ongoingFg = Color(0xFF0F766E);
  static const Color ongoingBg = Color(0xFFCCFBF1);
  static const Color upcomingFg = Color(0xFF4338CA);
  static const Color upcomingBg = Color(0xFFE0E7FF);
  static const Color academicFg = Color(0xFF1D4ED8);
  static const Color urgentFg = Color(0xFFB91C1C);
  static const Color slateTint = Color(0xFFCBD5E1);
  static const Color regTint = Color(0xFFBAE6FD);
}

String effectiveDashboardSegment(Map<String, dynamic> item) {
  final s = item["dashboard_segment"]?.toString();
  if (s == "academic") return "academic";
  if (s == "non_academic") return "non_academic";
  return isDashboardAcademicItem(item) ? "academic" : "non_academic";
}

bool isDashboardAcademicItem(Map<String, dynamic> item) {
  final category = item["category"]?.toString().toLowerCase() ?? "";
  final text =
      "${item["title"] ?? ""} ${item["description"] ?? ""}".toLowerCase();
  return category == "academic" ||
      text.contains("exam") ||
      text.contains("time table") ||
      text.contains("timetable") ||
      text.contains("syllabus") ||
      text.contains("semester") ||
      text.contains("notice");
}

bool isDashboardEventOngoing(Map<String, dynamic> item) {
  final priority = item["priority"]?.toString().toLowerCase() ?? "";
  if (priority == "ongoing") {
    return true;
  }
  final now = DateTime.now().toUtc();
  final start =
      DateTime.tryParse(item["start_time"]?.toString() ?? "")?.toUtc();
  final end = DateTime.tryParse(item["end_time"]?.toString() ?? "")?.toUtc();
  return start != null &&
      end != null &&
      (start.isBefore(now) || start.isAtSameMomentAs(now)) &&
      end.isAfter(now);
}

bool isDashboardEventUpcoming(Map<String, dynamic> item) {
  final priority = item["priority"]?.toString().toLowerCase() ?? "";
  if (priority == "upcoming") {
    return true;
  }
  final now = DateTime.now().toUtc();
  final start =
      DateTime.tryParse(item["start_time"]?.toString() ?? "")?.toUtc();
  return start != null && start.isAfter(now);
}

Color dashboardEventCardAccent(Map<String, dynamic> item) {
  final p = item["priority"]?.toString().toLowerCase() ?? "";
  if (p.contains("urgent")) {
    return EventPosterDashboardColors.urgentFg;
  }
  if (effectiveDashboardSegment(item) == "academic") {
    return EventPosterDashboardColors.academicFg;
  }
  if (p == "ongoing" || isDashboardEventOngoing(item)) {
    return EventPosterDashboardColors.ongoingFg;
  }
  if (p == "upcoming" || isDashboardEventUpcoming(item)) {
    return EventPosterDashboardColors.upcomingFg;
  }
  return const Color(0xFF64748B);
}

Widget eventPosterGlassPill(String text, {Color tint = Colors.white}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.38),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: tint.withValues(alpha: 0.4)),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: Color.lerp(tint, Colors.white, 0.88)!,
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.35,
      ),
    ),
  );
}

Widget eventPosterCategoryPill(Map<String, dynamic> item) {
  final display = (item["category"]?.toString() ?? "general").toUpperCase();
  final academic = effectiveDashboardSegment(item) == "academic";
  final tint =
      academic ? EventPosterDashboardColors.academicFg : EventPosterDashboardColors.slateTint;
  return eventPosterGlassPill(display, tint: tint);
}

Widget eventPosterPriorityPill(Map<String, dynamic> item) {
  final raw = (item["priority"]?.toString() ?? "normal").toLowerCase();
  late final Color tint;
  if (raw.contains("urgent")) {
    tint = EventPosterDashboardColors.urgentFg;
  } else if (raw == "ongoing") {
    tint = EventPosterDashboardColors.ongoingFg;
  } else if (raw == "upcoming") {
    tint = EventPosterDashboardColors.upcomingFg;
  } else {
    tint = EventPosterDashboardColors.slateTint;
  }
  final label = (item["priority"]?.toString() ?? "normal").toUpperCase();
  return eventPosterGlassPill(label, tint: tint);
}

Widget eventPosterRegistrationPill(int regCount) {
  final t = regCount == 0 ? "No registrations yet" : "$regCount registered";
  return eventPosterGlassPill(t, tint: EventPosterDashboardColors.regTint);
}

/// Returns an ONGOING/UPCOMING pill based on the event's start/end times.
/// Returns null when the event is finished or has no schedule yet.
Widget? eventPosterStatusPill(Map<String, dynamic> item) {
  if (isDashboardEventOngoing(item)) {
    return eventPosterGlassPill(
      "ONGOING",
      tint: EventPosterDashboardColors.ongoingFg,
    );
  }
  if (isDashboardEventUpcoming(item)) {
    return eventPosterGlassPill(
      "UPCOMING",
      tint: EventPosterDashboardColors.upcomingFg,
    );
  }
  return null;
}

Widget eventPosterDashboardPillsWrap(
  Map<String, dynamic> item, {
  required bool allowRegistration,
  required int registrationCount,
}) {
  final statusPill = eventPosterStatusPill(item);
  return Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      eventPosterCategoryPill(item),
      eventPosterPriorityPill(item),
      if (statusPill != null) statusPill,
      if (allowRegistration) eventPosterRegistrationPill(registrationCount),
    ],
  );
}
