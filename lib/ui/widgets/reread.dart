import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../services/importer.dart';
import '../../services/process_upload.dart';
import '../../services/sync_service.dart';
import 'common.dart';

/// Reads a saved report again (e.g. a scan saved before photo reading worked, or
/// after the reader improved). Its values are replaced by the new reading, which
/// waits for review if anything is uncertain; sideways pages are saved upright.
/// Asks first, since hand corrections are replaced too. [onStart] runs once the
/// reading begins (to show progress). Returns null if cancelled or the original
/// file isn't available.
Future<UploadOutcome?> rereadDoc(BuildContext context, Doc d, {VoidCallback? onStart}) async {
  if (!await confirmDialog(context, 'Read this report again?', 'Its values will be replaced by a fresh reading of the original, for you to check.', yes: 'Read again', danger: false)) return null;
  if (!context.mounted) return null;
  onStart?.call();
  final s = readStore(context);
  var bytes = await ImportService.load(d.id, d.filePath);
  if (bytes == null && context.mounted) {
    final sync = context.read<SyncService?>();
    if (sync != null) (bytes, _) = await sync.fetchOriginal(d);
  }
  if (!context.mounted) return null;
  if (bytes == null) {
    toast(context, 'The original file isn’t available — scan it again', ok: false);
    return null;
  }
  final path = s.doc(d.id)?.filePath ?? d.filePath;
  final name = path ?? (d.isImage ? 'scan.jpg' : 'report.pdf');
  try {
    final o = await processUpload(s, memberId: d.memberId, fileName: name, bytes: bytes, retry: s.doc(d.id) ?? d);
    if (context.mounted) {
      toast(context, o.unreadable ? 'Still couldn’t read any tests from it' : 'Read ${o.total} test${o.total == 1 ? '' : 's'} — check them', ok: !o.unreadable);
    }
    return o;
  } catch (e) {
    debugPrint('Read again failed: $e');
    if (context.mounted) toast(context, 'Couldn’t read it again — please try once more', ok: false);
    return null;
  }
}
