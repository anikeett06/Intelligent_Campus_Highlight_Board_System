import 'package:flutter/material.dart';

/// Vector “bulletin board” mark: rounded tile, layered “posts,” and a highlight
/// accent — reads clearly at small sizes (app bar, favourites).
class CampusBoardMark extends StatelessWidget {
  const CampusBoardMark({super.key, this.size = 36});

  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Campus Board',
      child: CustomPaint(
        size: Size(size, size),
        painter: _CampusBoardMarkPainter(
          primary: cs.primary,
          deep: Color.lerp(cs.primary, const Color(0xFF0F172A), 0.35)!,
          secondary: cs.secondary,
          line: cs.onPrimary.withValues(alpha: 0.92),
          rim: cs.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
    );
  }
}

/// App bar row: mark + wordmark (text truncates on narrow widths).
class CampusBoardAppBarTitle extends StatelessWidget {
  const CampusBoardAppBarTitle({super.key, this.markSize = 34});

  final double markSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        CampusBoardMark(size: markSize),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Campus Board',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.appBarTheme.titleTextStyle?.copyWith(
                  letterSpacing: -0.4,
                ) ??
                theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  color: theme.colorScheme.onSurface,
                ),
          ),
        ),
      ],
    );
  }
}

/// Larger hero for login / splash-style surfaces.
class CampusBoardLogoHero extends StatelessWidget {
  const CampusBoardLogoHero({super.key, this.markSize = 56});

  final double markSize;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: cs.primary.withValues(alpha: 0.22),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: ColoredBox(
              color: cs.surface,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: CampusBoardMark(size: markSize),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Campus Board',
          textAlign: TextAlign.center,
          style: tt.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: cs.onSurface,
            letterSpacing: -0.6,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Your campus, one place',
          textAlign: TextAlign.center,
          style: tt.bodyMedium?.copyWith(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _CampusBoardMarkPainter extends CustomPainter {
  _CampusBoardMarkPainter({
    required this.primary,
    required this.deep,
    required this.secondary,
    required this.line,
    required this.rim,
  });

  final Color primary;
  final Color deep;
  final Color secondary;
  final Color line;
  final Color rim;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final inset = s * 0.06;
    final r = s * 0.22;
    final board = RRect.fromRectAndRadius(
      Rect.fromLTWH(inset, inset, size.width - 2 * inset, size.height - 2 * inset),
      Radius.circular(r),
    );

    final g = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.lerp(primary, Colors.white, 0.12)!,
          deep,
        ],
      ).createShader(board.outerRect);
    canvas.drawRRect(board, g);

    final rimPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.028
      ..color = rim;
    canvas.drawRRect(board.deflate(s * 0.014), rimPaint);

    final inner = board.outerRect.deflate(s * 0.18);
    final lineStroke = s * 0.065;
    final cap = StrokeCap.round;
    final linePaint = Paint()
      ..color = line
      ..strokeWidth = lineStroke
      ..strokeCap = cap
      ..style = PaintingStyle.stroke;

    final y1 = inner.top + inner.height * 0.34;
    final y2 = inner.top + inner.height * 0.52;
    final y3 = inner.top + inner.height * 0.70;
    canvas.drawLine(
      Offset(inner.left + inner.width * 0.14, y1),
      Offset(inner.left + inner.width * 0.62, y1),
      linePaint,
    );
    canvas.drawLine(
      Offset(inner.left + inner.width * 0.10, y2),
      Offset(inner.left + inner.width * 0.78, y2),
      linePaint,
    );
    canvas.drawLine(
      Offset(inner.left + inner.width * 0.18, y3),
      Offset(inner.left + inner.width * 0.52, y3),
      linePaint,
    );

    final dotR = s * 0.11;
    final dotCenter = Offset(inner.right - dotR * 0.9, inner.top + dotR * 1.1);
    final dotPaint = Paint()..color = secondary;
    canvas.drawCircle(dotCenter, dotR, dotPaint);
    final dotRim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.02
      ..color = Color.lerp(secondary, Colors.white, 0.35)!;
    canvas.drawCircle(dotCenter, dotR, dotRim);
  }

  @override
  bool shouldRepaint(covariant _CampusBoardMarkPainter oldDelegate) {
    return oldDelegate.primary != primary ||
        oldDelegate.deep != deep ||
        oldDelegate.secondary != secondary ||
        oldDelegate.line != line ||
        oldDelegate.rim != rim;
  }
}
