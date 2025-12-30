import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'dart:math';
import 'analyzer.dart';

class JukeboxVisualizer extends StatefulWidget {
  final AudioFeatures features;
  final AudioPlayer player;

  const JukeboxVisualizer({super.key, required this.features, required this.player});

  @override
  State<JukeboxVisualizer> createState() => _JukeboxVisualizerState();
}

class _JukeboxVisualizerState extends State<JukeboxVisualizer> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 1))
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: ArcPainter(widget.features, widget.player),
          size: Size.infinite,
        );
      }
    );
  }
}

class ArcPainter extends CustomPainter {
  final AudioFeatures features;
  final AudioPlayer player;

  ArcPainter(this.features, this.player);

  @override
  void paint(Canvas canvas, Size size) {
    // Draw the circle of beats
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2 - 20;

    final paint = Paint()..style = PaintingStyle.stroke..strokeWidth = 2;
    final activePaint = Paint()..style = PaintingStyle.fill..color = Colors.blueAccent;

    int totalBeats = features.beats.length;
    double angleStep = 2 * pi / totalBeats;

    // We assume the player position maps to a beat.
    // Since we stream infinite audio, player.position is monotonic and increasing forever.
    // We need the "source" position from the InfiniteAudioSource.
    // But `just_audio` doesn't expose custom source state easily to UI.
    // For visualization, we might just highlight random active connections or
    // we would need a stream from our InfiniteAudioSource to tell us the "current beat".

    // For now, draw static graph
    for (var beat in features.beats) {
        double angle = beat.index * angleStep - pi / 2;
        Offset p1 = center + Offset(cos(angle), sin(angle)) * radius;

        // Draw beat marker
        paint.color = Colors.grey[800]!;
        canvas.drawCircle(p1, 2, paint);

        // Draw connections
        for (var n in beat.neighbors) {
             double angle2 = n.destIndex * angleStep - pi / 2;
             Offset p2 = center + Offset(cos(angle2), sin(angle2)) * radius;

             Path path = Path();
             path.moveTo(p1.dx, p1.dy);
             path.quadraticBezierTo(center.dx, center.dy, p2.dx, p2.dy);

             paint.color = Colors.blue.withOpacity(0.2);
             canvas.drawPath(path, paint);
        }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
