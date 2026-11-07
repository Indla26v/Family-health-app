import '../data/models.dart';
import '../data/store.dart';
import '../ui/screens/upload.dart' show PickedFile;
import 'process_upload.dart';

/// Reads many old reports one after another, in the background of the UI.
/// Progress lives in `store.job`, so the screen can come and go.
class BulkImporter {
  static List<PickedFile> _queue = [];
  static String? _memberId;
  static bool get hasQueue => _queue.isNotEmpty;

  static Future<void> start(AppStore s, String memberId, List<PickedFile> files) async {
    _queue = [...files];
    _memberId = memberId;
    s.job = ImportJob(total: files.length, done: 0, needReview: 0, byYear: {0: [files.length, 0, 0]}, running: true);
    s.changed();
    await _run(s);
  }

  static Future<void> resume(AppStore s) async {
    final j = s.job;
    if (j == null || _queue.isEmpty) return;
    j.paused = false;
    j.running = true;
    s.changed();
    await _run(s);
  }

  static void pause(AppStore s) {
    s.job?.paused = true;
    s.changed();
  }

  static Future<void> _run(AppStore s) async {
    final j = s.job!;
    while (_queue.isNotEmpty && !j.paused) {
      final f = _queue.first;
      try {
        final o = await processUpload(s, memberId: _memberId!, fileName: f.name, bytes: f.bytes);
        final y = o.doc.date.year;
        j.byYear[0]![0]--;
        final e = j.byYear.putIfAbsent(y, () => [0, 0, 0]);
        e[0]++;
        e[1]++;
        if (o.doc.status == DocStatus.needsReview) {
          e[2]++;
          j.needReview++;
        }
      } catch (_) {
        j.byYear[0]![0]--;
        final e = j.byYear.putIfAbsent(DateTime.now().year, () => [0, 0, 0]);
        e[0]++;
        e[1]++;
        e[2]++;
        j.needReview++;
      }
      j.done++;
      _queue.removeAt(0);
      if (j.byYear[0]![0] <= 0) j.byYear.remove(0);
      s.changed();
    }
    j.running = false;
    s.changed();
  }
}
