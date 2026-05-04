import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:studentboard/screens/admin/event_page_layout.dart';

/// Read-only rendering of [EventPageLayout] blocks on the public event page.
class EventPageBlocksView extends StatelessWidget {
  const EventPageBlocksView({super.key, required this.layout});

  final EventPageLayout layout;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final children = <Widget>[];

    if (layout.heroOrganizedBy.trim().isNotEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Icon(Icons.apartment_outlined, size: 20, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Organized by ${layout.heroOrganizedBy.trim()}",
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      );
    }

    for (final block in layout.blocks) {
      final hasHeading = block.heading != null && block.heading!.trim().isNotEmpty;
      final hasSub = block.subheading != null && block.subheading!.trim().isNotEmpty;
      final hasSegs = block.segments.isNotEmpty;
      if (!hasHeading && !hasSub && !hasSegs) {
        continue;
      }
      children.add(
        Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (hasHeading)
                  Text(
                    block.heading!.trim(),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                  ),
                if (hasSub) ...[
                  if (hasHeading) const SizedBox(height: 6),
                  Text(
                    block.subheading!.trim(),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
                if (hasSegs) ...[
                  if (hasHeading || hasSub) const SizedBox(height: 10),
                  ...block.segments.map((s) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _SegmentView(segment: s),
                      )),
                ],
              ],
            ),
          ),
        ),
      );
    }

    if (children.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}

class _SegmentView extends StatelessWidget {
  const _SegmentView({required this.segment});

  final RichSegment segment;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (segment is SegText) {
      final st = segment as SegText;
      final t = st.text.trim();
      if (t.isEmpty) {
        return const SizedBox.shrink();
      }
      final style = switch (st.style) {
        'heading' => Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        'subheading' => Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        _ => Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.45),
      };
      return Text(t, style: style);
    }
    if (segment is SegBullets) {
      final sb = segment as SegBullets;
      if (sb.items.isEmpty) {
        return const SizedBox.shrink();
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: sb.items
            .where((e) => e.trim().isNotEmpty)
            .map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("• ", style: TextStyle(color: cs.primary, fontWeight: FontWeight.w800)),
                    Expanded(child: Text(e.trim(), style: Theme.of(context).textTheme.bodyMedium)),
                  ],
                ),
              ),
            )
            .toList(),
      );
    }
    if (segment is SegTable) {
      final tbl = segment as SegTable;
      if (tbl.rows.isEmpty && tbl.headers.isEmpty) {
        return const SizedBox.shrink();
      }
      final heads = tbl.headers.isNotEmpty
          ? tbl.headers
          : (tbl.rows.isNotEmpty
              ? List<String>.generate(tbl.rows.first.length, (i) => "Column ${i + 1}")
              : <String>[]);
      if (heads.isEmpty) {
        return const SizedBox.shrink();
      }
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStatePropertyAll(cs.surfaceContainerHighest),
          columns: heads.map((h) => DataColumn(label: Text(h))).toList(),
          rows: tbl.rows.map((r) {
            final cells = <DataCell>[];
            for (var i = 0; i < heads.length; i++) {
              cells.add(DataCell(Text(i < r.length ? r[i] : "")));
            }
            return DataRow(cells: cells);
          }).toList(),
        ),
      );
    }
    if (segment is SegLink) {
      final lk = segment as SegLink;
      final u = lk.url.trim();
      if (u.isEmpty) {
        return const SizedBox.shrink();
      }
      final label = lk.label.trim().isEmpty ? u : lk.label.trim();
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () async {
            final uri = Uri.tryParse(u);
            if (uri == null || !(uri.isScheme("http") || uri.isScheme("https"))) {
              return;
            }
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          },
          icon: const Icon(Icons.link, size: 18),
          label: Text(label, textAlign: TextAlign.start),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}
