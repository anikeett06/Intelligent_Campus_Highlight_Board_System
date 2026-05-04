import 'dart:convert';

int _kEventRichBlockSeq = 0;

String newEventRichBlockId() => 'b_${DateTime.now().microsecondsSinceEpoch}_${_kEventRichBlockSeq++}';

/// Structured page content for campus activities (stored in [event_page_json] on the server).
class EventPageLayout {
  EventPageLayout({
    this.heroOrganizedBy = '',
    this.overlayHeroOnBanner = false,
    List<EventRichBlock>? blocks,
  }) : blocks = blocks ?? [];

  String heroOrganizedBy;
  bool overlayHeroOnBanner;
  List<EventRichBlock> blocks;

  static EventPageLayout empty() => EventPageLayout();

  static EventPageLayout? tryParse(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    try {
      final m = jsonDecode(raw);
      if (m is! Map<String, dynamic>) {
        return null;
      }
      return EventPageLayout.fromJson(m);
    } catch (_) {
      return null;
    }
  }

  factory EventPageLayout.fromJson(Map<String, dynamic> json) {
    final hero = json['hero'];
    var organized = '';
    var overlay = false;
    if (hero is Map) {
      organized = hero['organized_by']?.toString() ?? '';
      overlay = hero['overlay_on_banner'] == true;
    }
    final rawBlocks = json['blocks'];
    final list = <EventRichBlock>[];
    if (rawBlocks is List) {
      for (final b in rawBlocks) {
        if (b is Map<String, dynamic>) {
          list.add(EventRichBlock.fromJson(b));
        } else if (b is Map) {
          list.add(EventRichBlock.fromJson(Map<String, dynamic>.from(b.map((k, v) => MapEntry(k.toString(), v)))));
        }
      }
    }
    return EventPageLayout(
      heroOrganizedBy: organized,
      overlayHeroOnBanner: overlay,
      blocks: list,
    );
  }

  Map<String, dynamic> toJson() => {
        'v': 1,
        'hero': {
          'organized_by': heroOrganizedBy,
          'overlay_on_banner': overlayHeroOnBanner,
        },
        'blocks': blocks.map((b) => b.toJson()).toList(),
      };

  String encode() => jsonEncode(toJson());

  /// Plain text for API [description] (search, notifications, legacy views).
  String flattenDescription() {
    final buf = StringBuffer();
    if (heroOrganizedBy.trim().isNotEmpty) {
      buf.writeln('Organized by: ${heroOrganizedBy.trim()}');
    }
    for (final b in blocks) {
      final t = b.flatten();
      if (t.trim().isNotEmpty) {
        buf.writeln(t.trim());
        buf.writeln();
      }
    }
    return buf.toString().trim();
  }
}

class EventRichBlock {
  EventRichBlock({
    required this.id,
    this.heading,
    this.subheading,
    List<RichSegment>? segments,
  }) : segments = segments ?? [];

  String id;
  String? heading;
  String? subheading;
  List<RichSegment> segments;

  factory EventRichBlock.fromJson(Map<String, dynamic> json) {
    final segs = <RichSegment>[];
    final raw = json['segments'];
    if (raw is List) {
      for (final s in raw) {
        final seg = RichSegment.tryParse(s);
        if (seg != null) {
          segs.add(seg);
        }
      }
    }
    return EventRichBlock(
      id: (json['id']?.toString().trim().isNotEmpty ?? false) ? json['id'].toString() : newEventRichBlockId(),
      heading: json['heading']?.toString(),
      subheading: json['subheading']?.toString(),
      segments: segs,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'heading': heading,
        'subheading': subheading,
        'segments': segments.map((s) => s.toJson()).toList(),
      };

  String flatten() {
    final buf = StringBuffer();
    if (heading != null && heading!.trim().isNotEmpty) {
      buf.writeln(heading!.trim());
    }
    if (subheading != null && subheading!.trim().isNotEmpty) {
      buf.writeln(subheading!.trim());
    }
    for (final s in segments) {
      buf.writeln(s.flatten());
    }
    return buf.toString().trim();
  }
}

abstract class RichSegment {
  const RichSegment();
  static RichSegment? tryParse(dynamic raw) {
    if (raw is! Map) {
      return null;
    }
    final m = Map<String, dynamic>.from(raw.map((k, v) => MapEntry(k.toString(), v)));
    final type = m['type']?.toString();
    return switch (type) {
      'text' => SegText.fromJson(m),
      'bullets' => SegBullets.fromJson(m),
      'table' => SegTable.fromJson(m),
      'link' => SegLink.fromJson(m),
      _ => null,
    };
  }

  Map<String, dynamic> toJson();
  String flatten();
}

class SegText extends RichSegment {
  SegText({this.style = 'body', this.text = ''});

  /// heading | subheading | body
  String style;
  String text;

  factory SegText.fromJson(Map<String, dynamic> m) {
    return SegText(
      style: m['style']?.toString() ?? 'body',
      text: m['text']?.toString() ?? '',
    );
  }

  @override
  Map<String, dynamic> toJson() => {'type': 'text', 'style': style, 'text': text};

  @override
  String flatten() {
    if (text.trim().isEmpty) {
      return '';
    }
    final prefix = switch (style) {
      'heading' => '# ',
      'subheading' => '## ',
      _ => '',
    };
    return '$prefix${text.trim()}';
  }
}

class SegBullets extends RichSegment {
  SegBullets({List<String>? items}) : items = items ?? [];

  List<String> items;

  factory SegBullets.fromJson(Map<String, dynamic> m) {
    final raw = m['items'];
    final list = <String>[];
    if (raw is List) {
      for (final x in raw) {
        list.add(x.toString());
      }
    }
    return SegBullets(items: list);
  }

  @override
  Map<String, dynamic> toJson() => {'type': 'bullets', 'items': items};

  @override
  String flatten() {
    if (items.isEmpty) {
      return '';
    }
    return items.map((e) => '• ${e.trim()}').join('\n');
  }
}

class SegTable extends RichSegment {
  SegTable({List<String>? headers, List<List<String>>? rows})
      : headers = headers ?? [],
        rows = rows ?? [];

  List<String> headers;
  List<List<String>> rows;

  factory SegTable.fromJson(Map<String, dynamic> m) {
    final h = <String>[];
    final rh = m['headers'];
    if (rh is List) {
      for (final x in rh) {
        h.add(x.toString());
      }
    }
    final r = <List<String>>[];
    final rr = m['rows'];
    if (rr is List) {
      for (final row in rr) {
        if (row is List) {
          r.add(row.map((e) => e.toString()).toList());
        }
      }
    }
    return SegTable(headers: h, rows: r);
  }

  @override
  Map<String, dynamic> toJson() => {'type': 'table', 'headers': headers, 'rows': rows};

  @override
  String flatten() {
    final buf = StringBuffer();
    if (headers.isNotEmpty) {
      buf.writeln(headers.join(' | '));
      buf.writeln(headers.map((_) => '—').join(' | '));
    }
    for (final row in rows) {
      buf.writeln(row.join(' | '));
    }
    return buf.toString().trim();
  }
}

class SegLink extends RichSegment {
  SegLink({this.label = '', this.url = ''});

  String label;
  String url;

  factory SegLink.fromJson(Map<String, dynamic> m) {
    return SegLink(
      label: m['label']?.toString() ?? '',
      url: m['url']?.toString() ?? '',
    );
  }

  @override
  Map<String, dynamic> toJson() => {'type': 'link', 'label': label, 'url': url};

  @override
  String flatten() {
    if (label.trim().isEmpty && url.trim().isEmpty) {
      return '';
    }
    if (label.trim().isEmpty) {
      return url.trim();
    }
    return '${label.trim()}: ${url.trim()}';
  }
}
