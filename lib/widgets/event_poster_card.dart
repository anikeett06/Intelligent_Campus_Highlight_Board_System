import 'package:flutter/material.dart';

/// Full-bleed event image with metadata on a bottom scrim (cinema-poster style).
/// [aspectRatio] is discovered from the network image when possible; until then
/// [fallbackAspectRatio] sizes the frame.
class EventPosterCard extends StatefulWidget {
  const EventPosterCard({
    super.key,
    required this.imageUrl,
    required this.title,
    required this.description,
    required this.accentColor,
    required this.footer,
    this.topTrailing,
    this.fallbackAspectRatio = 16 / 9,
    this.borderRadius = 16,
    this.maxHeight,
    this.maxWidth,
    this.titleMaxLines = 2,
    this.descriptionMaxLines = 3,
  });

  final String imageUrl;
  final String title;
  final String description;
  final Color accentColor;
  final Widget footer;
  final Widget? topTrailing;
  final double fallbackAspectRatio;
  final double borderRadius;
  final double? maxHeight;
  final double? maxWidth;
  final int titleMaxLines;
  final int descriptionMaxLines;

  @override
  State<EventPosterCard> createState() => _EventPosterCardState();
}

class _EventPosterCardState extends State<EventPosterCard> {
  ImageStream? _imageStream;
  late ImageStreamListener _listener;
  double _aspectRatio = 0;

  @override
  void initState() {
    super.initState();
    _listener = ImageStreamListener((ImageInfo info, bool synchronousCall) {
      final w = info.image.width.toDouble();
      final h = info.image.height.toDouble();
      if (w > 0 && h > 0 && mounted) {
        setState(() => _aspectRatio = w / h);
      }
    });
    _listenImage();
  }

  void _listenImage() {
    _imageStream?.removeListener(_listener);
    final provider = NetworkImage(widget.imageUrl);
    final stream = provider.resolve(const ImageConfiguration());
    stream.addListener(_listener);
    _imageStream = stream;
  }

  @override
  void didUpdateWidget(covariant EventPosterCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      setState(() => _aspectRatio = 0);
      _listenImage();
    }
  }

  @override
  void dispose() {
    _imageStream?.removeListener(_listener);
    super.dispose();
  }

  static const _titleShadows = [
    Shadow(color: Color(0xB3000000), blurRadius: 10, offset: Offset(0, 2)),
    Shadow(color: Color(0x66000000), blurRadius: 4, offset: Offset(0, 1)),
  ];

  @override
  Widget build(BuildContext context) {
    final ratio = _aspectRatio > 0 ? _aspectRatio : widget.fallbackAspectRatio;

    return LayoutBuilder(
      builder: (context, constraints) {
        var capW = constraints.maxWidth.isFinite ? constraints.maxWidth : 400.0;
        if (widget.maxWidth != null && capW > widget.maxWidth!) {
          capW = widget.maxWidth!;
        }

        // Full-bleed width: never shrink width when maxHeight caps height (avoids side gutters).
        final displayW = capW;
        final naturalH = capW / ratio;
        final displayH = widget.maxHeight != null && naturalH > widget.maxHeight!
            ? widget.maxHeight!
            : naturalH;

        return ClipRRect(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          child: SizedBox(
            width: displayW,
            height: displayH,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  widget.imageUrl,
                  width: displayW,
                  height: displayH,
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                  errorBuilder: (context, error, stackTrace) => ColoredBox(
                    color: Theme.of(context).colorScheme.surfaceContainerHigh,
                    child: Center(
                      child: Icon(
                        Icons.broken_image_outlined,
                        size: 48,
                        color: widget.accentColor,
                      ),
                    ),
                  ),
                ),
                DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.05),
                          Colors.black.withValues(alpha: 0.12),
                          Colors.black.withValues(alpha: 0.55),
                          Colors.black.withValues(alpha: 0.78),
                        ],
                        stops: const [0.0, 0.35, 0.72, 1.0],
                      ),
                    ),
                  ),
                  if (widget.topTrailing != null)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: widget.topTrailing!,
                    ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 28, 14, 14),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            maxLines: widget.titleMaxLines,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 19,
                              height: 1.15,
                              letterSpacing: -0.4,
                              shadows: _titleShadows,
                            ),
                          ),
                          if (widget.description.trim().isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              widget.description,
                              maxLines: widget.descriptionMaxLines,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.88),
                                fontSize: 13.5,
                                height: 1.35,
                                shadows: const [
                                  Shadow(
                                    color: Color(0x99000000),
                                    blurRadius: 6,
                                    offset: Offset(0, 1),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 10),
                          widget.footer,
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        );
      },
    );
  }
}
