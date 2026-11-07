import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../services/sync_service.dart';

/// Pull down on a tab to sync with the web app right away. The page's own
/// scroll view drives the gesture, so it is made scrollable even when short.
class SyncRefresh extends StatelessWidget {
  const SyncRefresh({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final sync = context.read<SyncService?>();
    final scroll = ScrollConfiguration.of(context).copyWith(physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()));
    if (sync == null) return ScrollConfiguration(behavior: scroll, child: child);
    return RefreshIndicator(
      color: context.c.accent,
      backgroundColor: context.c.surface,
      edgeOffset: 8,
      onRefresh: () async {
        if (!sync.signedIn) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sign in from Settings to sync with the web app')));
          return;
        }
        await sync.syncNow(full: true);
        if (!context.mounted) return;
        final st = sync.store.sync;
        final msg = sync.offline
            ? 'No internet — changes will sync later'
            : st.rejected.isNotEmpty
                ? '${st.rejected.length} change${st.rejected.length == 1 ? '' : 's'} not saved online — see Settings'
                : st.lastError ?? 'Up to date';
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2), behavior: SnackBarBehavior.floating));
      },
      child: ScrollConfiguration(behavior: scroll, child: child),
    );
  }
}
