import 'models.dart';

class PracticeProgress {
  PracticeProgress(this.production, this.reports);
  final Production production;
  final List<RehearsalReport> reports;
  List<RehearsalReport> get forRole => reports
      .where((r) => r.character == production.selectedCharacter)
      .toList();
  Map<String, LineAttempt> get latest {
    final lines = <String, LineAttempt>{};
    final current = {
      for (final line in production.scenes.expand((s) => s.dialogue))
        line.id: line,
    };
    for (final report in forRole) {
      for (final attempt in report.attempts) {
        if (current[attempt.line.id]?.text != attempt.line.text ||
            current[attempt.line.id]?.character !=
                production.selectedCharacter) {
          continue;
        }
        final old = lines[attempt.line.id];
        if (old == null || attempt.at.isAfter(old.at)) {
          lines[attempt.line.id] = attempt;
        }
      }
    }
    return lines;
  }

  int get total => production.scenes
      .expand((s) => s.dialogue)
      .where((e) => e.character == production.selectedCharacter)
      .length;
  int get offBook =>
      latest.values.where((a) => a.evaluation.accepted && a.hints == 0).length;
  double get coverage => total == 0 ? 0 : offBook / total;
  List<LineAttempt> get weakest =>
      latest.values
          .where(
            (a) =>
                !a.evaluation.accepted ||
                a.hints > 0 ||
                a.responseDelay.inSeconds > 6 ||
                a.evaluation.confidence < .65,
          )
          .toList()
        ..sort(
          (a, b) => a.evaluation.textualAccuracy.compareTo(
            b.evaluation.textualAccuracy,
          ),
        );
}
