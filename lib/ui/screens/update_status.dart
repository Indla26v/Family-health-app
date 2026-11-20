import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/app_update.dart';
import '../widgets/update_ui.dart';

class UpdateStatusScreen extends StatelessWidget {
  const UpdateStatusScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final updates = context.watch<AppUpdateService>();
    final info = updates.available;
    final lastCheck = updates.lastSuccessfulCheck;
    final localizations = MaterialLocalizations.of(context);
    final downloadElapsed = updates.downloadElapsed;
    final verified = updates.verificationElapsed;
    final status = info != null || updates.stage != UpdateStage.idle
        ? updates.statusLabel
        : updates.upToDate
        ? 'Up to date'
        : 'No update found yet';
    return Scaffold(
      appBar: AppBar(title: const Text('Update status')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(status, style: Theme.of(context).textTheme.titleLarge),
          if (updates.usingFullApk && info != null)
            const Text('Using the full APK.'),
          if (updates.stage == UpdateStage.downloading) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: updates.progress,
              semanticsLabel: 'Update download progress',
            ),
          ],
          const SizedBox(height: 12),
          if (updates.installedVersion != null)
            _detail(
              'Installed build',
              '${updates.installedVersion}+${updates.installedBuild}',
            ),
          if (info != null) ...[
            _detail(
              'Available build',
              '${info.versionName}+${info.buildNumber}',
            ),
            _detail(
              'Downloaded',
              '${UpdateInfo.formatBytes(updates.received)} of ${info.sizeLabel}',
            ),
          ],
          if (info == null && updates.received > 0)
            _detail('Last download', UpdateInfo.formatBytes(updates.received)),
          _detail(
            'Last successful check',
            lastCheck == null
                ? 'No successful checks yet'
                : '${localizations.formatMediumDate(lastCheck)} '
                      '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(lastCheck))}',
          ),
          if (downloadElapsed != null)
            _detail(
              updates.downloadComplete
                  ? 'Queue to download complete'
                  : 'Time since queued',
              _elapsed(downloadElapsed),
            ),
          if (verified != null)
            _detail('Verification time', _elapsed(verified)),
          const SizedBox(height: 12),
          if (updates.waitingForUnmetered && info != null)
            FilledButton(
              onPressed: () => confirmMobileUpdate(context, updates),
              child: const Text('Use mobile data'),
            )
          else if (info != null && !updates.busy)
            FilledButton(
              onPressed: updates.downloadAndInstall,
              child: Text(switch (updates.stage) {
                UpdateStage.ready => 'Install',
                UpdateStage.error => 'Retry',
                _ => 'Download ${info.sizeLabel}',
              }),
            ),
          OutlinedButton(
            onPressed: updates.busy ? null : () => updates.check(force: true),
            child: const Text('Check now'),
          ),
        ],
      ),
    );
  }

  Widget _detail(String title, String value) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(title),
    subtitle: Text(value),
  );

  String _elapsed(Duration value) {
    if (value.inSeconds < 60) {
      return '${(value.inMilliseconds / 1000).toStringAsFixed(1)} s';
    }
    return '${value.inMinutes} min ${value.inSeconds.remainder(60)} s';
  }
}
