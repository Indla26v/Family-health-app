import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../services/app_update.dart';
import 'common.dart';

/// Floating Today card for the active download and handoff to Android.
class UpdateProgressCard extends StatelessWidget {
  const UpdateProgressCard({super.key, required this.u});
  final AppUpdateService u;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final downloading = u.stage == UpdateStage.downloading;
    return SurfaceCard(
      borderColor: c.accent.withValues(alpha: .35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconBadge(
                downloading
                    ? Icons.download_rounded
                    : Icons.system_update_rounded,
                size: 36,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  downloading
                      ? 'Downloading update…'
                      : 'Opening Android installer…',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (downloading) Text('${(u.progress * 100).round()}%'),
            ],
          ),
          if (downloading) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: u.progress > 0 ? u.progress : null,
                minHeight: 5,
                color: c.accent,
                backgroundColor: c.border,
                semanticsLabel: 'Update download progress',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Availability and retry actions on Today.
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key, required this.u});
  final AppUpdateService u;
  @override
  Widget build(BuildContext context) {
    final info = u.available;
    if (info == null) return const SizedBox.shrink();
    if (u.stage == UpdateStage.error) {
      return BannerCard(
        icon: Icons.error_rounded,
        tone: 'danger',
        text: 'Couldn’t install the update — tap to retry',
        onTap: u.downloadAndInstall,
      );
    }
    return BannerCard(
      icon: Icons.system_update_rounded,
      tone: 'info',
      text: 'Update available • v${info.versionName}+${info.buildNumber}',
      onTap: () => showUpdateSheet(context, u, info),
      trailing: IconButton(
        tooltip: 'Dismiss',
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        icon: const Icon(Icons.close_rounded, size: 18),
        onPressed: u.dismiss,
      ),
    );
  }
}

/// Details sheet: what's new, and the "Update now" / "Later" choice.
void showUpdateSheet(
  BuildContext context,
  AppUpdateService u,
  UpdateInfo info,
) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        16 + MediaQuery.of(ctx).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: SurfaceCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const IconBadge(Icons.system_update_rounded, size: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Update to v${info.versionName}+${info.buildNumber}',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (u.installedVersion != null)
                          Text(
                            'Installed v${u.installedVersion}+${u.installedBuild}',
                            style: TextStyle(
                              fontSize: 13,
                              color: ctx.c.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              if (info.notes.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  info.notes,
                  style: const TextStyle(fontSize: 15, height: 22 / 15),
                ),
              ],
              const SizedBox(height: 18),
              BigButton(
                label: 'Download ${info.sizeLabel}',
                icon: Icons.download_rounded,
                onTap: () {
                  Navigator.pop(ctx);
                  u.downloadAndInstall();
                },
              ),
              const SizedBox(height: 8),
              BigButton(
                label: 'Later',
                secondary: true,
                onTap: () => Navigator.pop(ctx),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
