import 'package:flutter/material.dart';
import '../domain/models.dart';
import '../services/export_service.dart';
import 'theme.dart';

class ResultsView extends StatelessWidget {
  const ResultsView({
    super.key,
    required this.report,
    this.runAgain,
    this.drill,
    this.cueDrill,
    this.acceptVariation,
    this.recordings,
  });
  final RehearsalReport report;
  final VoidCallback? runAgain, drill, cueDrill, recordings;
  final Future<void> Function(LineAttempt)? acceptVariation;
  @override
  Widget build(BuildContext context) => PageBody(
    children: [
      const SectionLabel('Take a breath'),
      Text(
        report.completed ? 'Scene complete.' : 'Your rehearsal so far.',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const SizedBox(height: 24),
      Text(
        '${(report.accuracy * 100).round()}%',
        style: Theme.of(context).textTheme.displaySmall?.copyWith(fontSize: 64),
      ),
      const Text('Textual accuracy · wording, never acting quality'),
      const SizedBox(height: 24),
      Wrap(
        spacing: 24,
        runSpacing: 12,
        children: [
          Text('${report.attempts.length} attempts'),
          Text('${report.perfect} word perfect'),
          Text('${report.accepted - report.perfect} accepted variations'),
          Text('${report.hintCount} hints'),
          Text('${report.attempts.length - report.accepted} to review'),
        ],
      ),
      if (runAgain != null) ...[
        const SizedBox(height: 28),
        FilledButton.icon(
          onPressed: runAgain,
          icon: const Icon(Icons.replay_rounded),
          label: const Text('RUN IT AGAIN'),
        ),
      ],
      if (drill != null) ...[
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: report.weak.isEmpty ? null : drill,
          child: const Text('Drill weak lines'),
        ),
      ],
      if (cueDrill != null)
        TextButton(onPressed: cueDrill, child: const Text('Cue drill')),
      if (recordings != null)
        TextButton(
          onPressed: recordings,
          child: const Text('Recordings / export audio'),
        ),
      Wrap(
        spacing: 12,
        children: [
          TextButton(
            onPressed: () async {
              try {
                await ExportService.report(report);
              } catch (e) {
                if (context.mounted) showError(context, e);
              }
            },
            child: const Text('Export results CSV'),
          ),
          TextButton(
            onPressed: () async {
              try {
                await ExportService.report(report, json: true);
              } catch (e) {
                if (context.mounted) showError(context, e);
              }
            },
            child: const Text('Export results JSON'),
          ),
        ],
      ),
      if (report.attempts.isNotEmpty) ...[
        const SectionLabel('Timing'),
        Text(
          'Average response delay: ${(report.attempts.fold<int>(0, (n, a) => n + a.responseDelay.inMilliseconds) / report.attempts.length / 1000).toStringAsFixed(1)} seconds.',
        ),
      ],
      const SectionLabel('Review deviations'),
      if (report.weak.isEmpty)
        const Text('No weak lines this run. Stay with the scene.'),
      for (final attempt in report.attempts.where(
        (a) =>
            a.evaluation.classification != LineClassification.wordPerfect ||
            a.hints > 0,
      ))
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  attempt.line.text,
                  style: const TextStyle(
                    fontFamily: 'Literata',
                    fontSize: 20,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'You said: ${attempt.transcript.isEmpty ? 'No line heard' : attempt.transcript}',
                ),
                const SizedBox(height: 8),
                Text(attempt.evaluation.reason),
                if (attempt.evaluation.missingWords.isNotEmpty)
                  Text(
                    'Missing: ${attempt.evaluation.missingWords.join(', ')}',
                  ),
                if (attempt.evaluation.insertedWords.isNotEmpty)
                  Text('Added: ${attempt.evaluation.insertedWords.join(', ')}'),
                if (attempt.hints > 0) Text('${attempt.hints} hint requests'),
                if (acceptVariation != null &&
                    !attempt.evaluation.accepted &&
                    !attempt.evaluation.meaningChanged &&
                    attempt.evaluation.protectedWordViolations.isEmpty &&
                    attempt.transcript.isNotEmpty)
                  TextButton(
                    onPressed: () => acceptVariation!(attempt),
                    child: const Text('Accept as a rehearsal variation'),
                  ),
              ],
            ),
          ),
        ),
    ],
  );
}
