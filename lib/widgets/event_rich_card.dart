import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:studentboard/utils/json_helpers.dart';

/// Compact event preview: poster, category badge, titles, date/time/venue row,
/// short description, highlight chips, primary CTA (register or view details).
class EventRichCard extends StatelessWidget {
  const EventRichCard({
    super.key,
    required this.event,
    required this.imageUrl,
    this.onOpenDetail,
    this.onPrimaryCta,
    this.registered = false,
    this.allowRegistration = true,
    this.density = EventCardDensity.list,
    /// Status / registration-open chips (e.g. ongoing + “Registration open”).
    this.midRow,
    /// When set (e.g. draft image from disk), replaces the network poster.
    this.posterChild,
    this.showPrimaryCta = true,
    /// When true (detail density), title, tagline, date & venue sit on a bottom gradient over the poster.
    this.overlayHeroDetailsOnBanner = false,
  });

  final Map<String, dynamic> event;
  final String imageUrl;
  final VoidCallback? onOpenDetail;
  /// Register / cancel register / view details — parent handles navigation.
  final VoidCallback? onPrimaryCta;
  final bool registered;
  final bool allowRegistration;
  final EventCardDensity density;
  final Widget? midRow;
  final Widget? posterChild;
  final bool showPrimaryCta;
  final bool overlayHeroDetailsOnBanner;

  static const List<Shadow> _kBannerTitleShadows = [
    Shadow(color: Color(0xB3000000), blurRadius: 10, offset: Offset(0, 2)),
    Shadow(color: Color(0x66000000), blurRadius: 4, offset: Offset(0, 1)),
  ];

  static Widget _heroOverlayRow(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: Colors.white.withValues(alpha: 0.92)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
        ),
      ],
    );
  }

  static String _categoryLabel(Map<String, dynamic> e) {
    return (e["category"]?.toString() ?? "general").toUpperCase();
  }

  static String? _fmtTimeRange(Map<String, dynamic> e) {
    final s = DateTime.tryParse(e["start_time"]?.toString() ?? "")?.toLocal();
    final en = DateTime.tryParse(e["end_time"]?.toString() ?? "")?.toLocal();
    if (s == null) return null;
    final datePart = DateFormat.yMMMd().format(s);
    final t1 = DateFormat.jm().format(s);
    if (en == null) return "$datePart · $t1";
    final sameDay = s.year == en.year && s.month == en.month && s.day == en.day;
    final t2 = DateFormat.jm().format(en);
    if (sameDay) {
      return "$datePart · $t1 – $t2";
    }
    return "${DateFormat.yMMMd().format(s)} $t1 → ${DateFormat.yMMMd().format(en)} $t2";
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rawTitle = event["title"]?.toString().trim() ?? "";
    final title = rawTitle.isEmpty ? "Event" : rawTitle;
    final fest = event["fest_name"]?.toString().trim() ?? "";
    final desc = event["description"]?.toString().trim() ?? "";
    final loc = event["location"]?.toString().trim() ?? "";
    final team = event["team_format"]?.toString().trim() ?? "";
    final fee = event["entry_fee"]?.toString().trim() ?? "";
    final prize = event["prize_summary"]?.toString().trim() ?? "";
    // Category on the image only on detail hero; list feed stays clean (visibility toggles still apply below).
    final showCat =
        density == EventCardDensity.detail && eventBoolField(event, "show_category_badge");
    final posterH = density == EventCardDensity.detail ? 200.0 : 160.0;
    final heroOverlay = overlayHeroDetailsOnBanner && density == EventCardDensity.detail;
    final statusOnPoster = midRow != null && !heroOverlay;
    final titleSize = density == EventCardDensity.detail ? 24.0 : 20.0;
    final pad = density == EventCardDensity.detail ? 18.0 : 14.0;

    final timeLine = _fmtTimeRange(event);
    final chipStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: cs.onSecondaryContainer,
        );

    return Material(
      color: cs.surface,
      elevation: density == EventCardDensity.detail ? 2 : 5,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Builder(
            builder: (context) {
              final stack = Stack(
                clipBehavior: Clip.none,
                fit: StackFit.passthrough,
                children: [
                  SizedBox(
                    height: posterH,
                    width: double.infinity,
                    child: posterChild != null
                        ? ClipRRect(child: SizedBox.expand(child: posterChild!))
                        : Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: posterH,
                            errorBuilder: (context, error, stackTrace) => ColoredBox(
                              color: cs.surfaceContainerHigh,
                              child: Icon(Icons.event, size: 48, color: cs.outline),
                            ),
                          ),
                  ),
                  if (showCat)
                    Positioned(
                      top: 12,
                      left: 12,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.42),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.45)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.35),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          child: Text(
                            _categoryLabel(event),
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.96),
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.85,
                              height: 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (heroOverlay)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _PosterStatusGradient(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.98),
                                fontSize: titleSize,
                                fontWeight: FontWeight.w800,
                                height: 1.12,
                                shadows: _kBannerTitleShadows,
                              ),
                            ),
                            if (fest.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                fest,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.88),
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                            if (timeLine != null) ...[
                              const SizedBox(height: 8),
                              _heroOverlayRow(Icons.calendar_today_outlined, timeLine),
                            ],
                            if (loc.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              _heroOverlayRow(Icons.place_outlined, loc),
                            ],
                            if (midRow != null) ...[
                              const SizedBox(height: 10),
                              midRow!,
                            ],
                          ],
                        ),
                      ),
                    ),
                  if (statusOnPoster)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _PosterStatusGradient(
                        child: midRow!,
                      ),
                    ),
                ],
              );
              if (onOpenDetail == null) {
                return stack;
              }
              return InkWell(onTap: onOpenDetail, child: stack);
            },
          ),
          if (_shouldShowBelowSection(
            heroOverlay: heroOverlay,
            statusOnPoster: statusOnPoster,
            desc: desc,
            team: team,
            fee: fee,
            prize: prize,
          ))
            Padding(
              padding: EdgeInsets.fromLTRB(pad, 14, pad, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!heroOverlay) ...[
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: titleSize,
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                        color: cs.onSurface,
                      ),
                    ),
                    if (fest.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        fest,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                    if (timeLine != null || loc.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      if (timeLine != null)
                        _iconRow(context, Icons.calendar_today_outlined, timeLine),
                      if (timeLine != null && loc.isNotEmpty) const SizedBox(height: 6),
                      if (loc.isNotEmpty) _iconRow(context, Icons.place_outlined, loc),
                    ],
                  ],
                  if (desc.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      desc,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                            height: 1.35,
                          ),
                    ),
                  ],
                  if (midRow != null && !statusOnPoster && !heroOverlay) ...[
                    const SizedBox(height: 10),
                    midRow!,
                  ],
                  if (team.isNotEmpty || fee.isNotEmpty || prize.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (team.isNotEmpty)
                          _miniChip(context, Icons.groups_outlined, team, chipStyle),
                        if (fee.isNotEmpty) _miniChip(context, Icons.payments_outlined, fee, chipStyle),
                        if (prize.isNotEmpty) _miniChip(context, Icons.emoji_events_outlined, prize, chipStyle),
                      ],
                    ),
                  ],
                  if (showPrimaryCta) ...[
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: onPrimaryCta,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: Text(
                          allowRegistration
                              ? (registered ? "Cancel registration" : "Register now")
                              : "View details",
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  bool _shouldShowBelowSection({
    required bool heroOverlay,
    required bool statusOnPoster,
    required String desc,
    required String team,
    required String fee,
    required String prize,
  }) {
    if (!heroOverlay) {
      // Hero data is rendered below the poster — keep the section.
      return true;
    }
    if (desc.isNotEmpty) return true;
    if (team.isNotEmpty || fee.isNotEmpty || prize.isNotEmpty) return true;
    if (midRow != null && !statusOnPoster) return true;
    if (showPrimaryCta) return true;
    return false;
  }

  static Widget _iconRow(BuildContext context, IconData icon, String text) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: cs.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
          ),
        ),
      ],
    );
  }

  static Widget _miniChip(BuildContext context, IconData icon, String label, TextStyle? chipStyle) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.secondaryContainer.withValues(alpha: 0.85),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: cs.onSecondaryContainer),
            const SizedBox(width: 6),
            Text(label, style: chipStyle),
          ],
        ),
      ),
    );
  }
}

/// Dark gradient + light chip theme so status labels stay readable on any poster.
class _PosterStatusGradient extends StatelessWidget {
  const _PosterStatusGradient({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0.0, 0.45, 1.0],
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.28),
            Colors.black.withValues(alpha: 0.72),
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 22, 10, 10),
        child: IconTheme.merge(
          data: IconThemeData(color: Colors.white.withValues(alpha: 0.95), size: 17),
          child: Theme(
            data: base.copyWith(
              chipTheme: ChipThemeData(
                backgroundColor: Colors.white.withValues(alpha: 0.2),
                disabledColor: Colors.white24,
                selectedColor: Colors.white.withValues(alpha: 0.28),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                labelStyle: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.15,
                  height: 1.2,
                ),
                secondaryLabelStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.88),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                ),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.38)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
            ),
            child: DefaultTextStyle.merge(
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

enum EventCardDensity { list, detail }
