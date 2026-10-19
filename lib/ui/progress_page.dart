import 'package:flutter/material.dart';
import '../data/app_controller.dart';
import '../domain/models.dart';
import '../domain/progress.dart';
import 'theme.dart';

class ProgressPage extends StatelessWidget {
  const ProgressPage({
    super.key,
    required this.controller,
    required this.production,
  });
  final AppController controller;
  final Production production;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Your progress')),
    body: FutureBuilder<List<RehearsalReport>>(
      future: controller.database.history(production),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Center(
            child: snapshot.hasError
                ? Text('Could not load progress: ${snapshot.error}')
                : const CircularProgressIndicator(),
          );
        }
        final progress = PracticeProgress(production, snapshot.data!);
        final trend = progress.forRole.take(12).toList().reversed.toList();
        return PageBody(
          children: [
            Text(
              production.selectedCharacter ?? 'Choose a role',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 16),
            Text(
              '${(progress.coverage * 100).round()}% off book',
              style: Theme.of(context).textTheme.displaySmall,
            ),
            Text(
              '${progress.offBook} of ${progress.total} lines accepted without hints in their latest attempts. Unpractised lines count toward the total.',
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(value: progress.coverage),
            const SectionLabel('Recent runs'),
            if (trend.isEmpty)
              const Text('Finish a rehearsal to begin tracking progress.'),
            if (trend.isNotEmpty) ...[
              Semantics(
                label:
                    'Text accuracy of ${trend.length} runs, oldest to newest: ${trend.map((r) => '${(r.accuracy * 100).round()} percent').join(', ')}',
                child: ExcludeSemantics(
                  child: SizedBox(
                    height: 150,
                    child: CustomPaint(
                      painter: _TrendPainter(
                        trend.map((r) => r.accuracy).toList(),
                        Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              ),
              const Text(
                'Text accuracy over time · different scenes and accuracy modes may not be directly comparable.',
              ),
              for (final report in trend.reversed)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${(report.accuracy * 100).round()}% · ${report.mode.label}',
                  ),
                  subtitle: Text(
                    '${report.startedAt.toLocal().toString().split('.').first}\n${report.attempts.length} attempts · ${report.hintCount} hints · ${_latency(report).toStringAsFixed(1)}s average response',
                  ),
                ),
            ],
            const SectionLabel('Lines needing attention'),
            for (final a in progress.weakest.take(20))
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        a.line.text,
                        style: const TextStyle(
                          fontFamily: 'Literata',
                          fontSize: 20,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${(a.evaluation.textualAccuracy * 100).round()}% wording · ${a.hints} hints · ${(a.responseDelay.inMilliseconds / 1000).toStringAsFixed(1)}s response',
                      ),
                    ],
                  ),
                ),
              ),
            if (progress.weakest.isEmpty)
              const Text('No weak lines in the latest attempts.'),
          ],
        );
      },
    ),
  );
  double _latency(RehearsalReport r) => r.attempts.isEmpty
      ? 0
      : r.attempts.fold<double>(
              0,
              (n, a) => n + a.responseDelay.inMilliseconds,
            ) /
            r.attempts.length /
            1000;
}

class _TrendPainter extends CustomPainter {
  _TrendPainter(this.values, this.color);
  final List<double> values;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = values.length == 1
          ? size.width / 2
          : 8 + (size.width - 16) * i / (values.length - 1);
      final y = 8 + (size.height - 16) * (1 - values[i]);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
      canvas.drawCircle(Offset(x, y), 4, Paint()..color = color);
    }
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.values != values || old.color != color;
}
