import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../data/card_order.dart';
import '../../data/catalog.dart';
import '../../services/sync_service.dart';
import '../widgets/common.dart';

/// Puts the Health cards in the order this user wants: drag a row by its handle,
/// or use ↑ / ↓. Saved on the account (the website uses the same order) and on
/// this phone; cards not moved stay A–Z after the others.
class ArrangeCardsScreen extends StatefulWidget {
  const ArrangeCardsScreen({super.key, required this.memberId});
  final String memberId;
  @override
  State<ArrangeCardsScreen> createState() => _ArrangeCardsScreenState();
}

typedef _Card = ({String key, String label});

class _ArrangeCardsScreenState extends State<ArrangeCardsScreen> {
  List<List<_Card>>? lists;
  List<String> titles = [];
  bool saving = false;

  void _load() {
    final s = readStore(context);
    final m = s.member(widget.memberId);
    final order = s.prefs.healthOrder;
    final conds = byUserOrder((m?.conditions ?? const <String>[]).map(conditionById), (c) => 'cond:${c.id}', (c) => c.en, order);
    final tests = byUserOrder(
      s.healthTestKeysOf(widget.memberId).map(testByKey).whereType<TestDef>(),
      (t) => 'test:${t.key}',
      (t) => t.name,
      order,
    );
    titles = [if (conds.isNotEmpty) 'Condition cards', if (tests.isNotEmpty) 'Test cards'];
    lists = [
      if (conds.isNotEmpty) [for (final c in conds) (key: 'cond:${c.id}', label: tr(c.en))],
      if (tests.isNotEmpty) [for (final t in tests) (key: 'test:${t.key}', label: t.name)],
    ];
  }

  void _move(int g, int from, int to) {
    final l = lists![g];
    if (to < 0 || to >= l.length || from == to) return;
    setState(() => l.insert(to, l.removeAt(from)));
    HapticFeedback.selectionClick();
    SemanticsService.sendAnnouncement(View.of(context), '${l[to].label} is now number ${to + 1}', TextDirection.ltr);
  }

  Future<void> _save() async {
    final s = readStore(context);
    final shown = [for (final l in lists!) for (final c in l) c.key];
    // Cards of other family members keep their place after the ones arranged here.
    final order = [...shown, ...s.prefs.healthOrder.where((k) => !shown.contains(k))].take(200).toList();
    setState(() => saving = true);
    final sync = context.read<SyncService?>();
    if (sync != null) {
      await sync.saveHealthOrder(order);
    } else {
      s.setPref((p) => p.healthOrder = order);
    }
    if (!mounted) return;
    toast(context, 'Card order saved', ok: true);
    Navigator.of(context).maybePop();
  }

  void _reset() {
    final sync = context.read<SyncService?>();
    if (sync != null) {
      sync.saveHealthOrder([]);
    } else {
      readStore(context).setPref((p) => p.healthOrder = []);
    }
    toast(context, 'Cards back in A–Z order', ok: true);
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    if (lists == null) _load();
    final s = watchStore(context);
    final m = s.member(widget.memberId);
    final empty = lists!.isEmpty;
    return PageBody(
      header: ScreenHeader(title: 'Arrange cards', subtitle: 'Your order · showing ${m?.name ?? ''}’s cards', back: true),
      bottom: empty ? null : BigButton(label: saving ? 'Saving…' : 'Save order', icon: Icons.check_rounded, onTap: saving ? () {} : _save),
      children: [
        Text('Drag a card by its handle, or use the arrows. The order is saved on your account and used for everyone in the family; cards you don’t move stay A–Z after them.',
            style: TextStyle(fontSize: 14, color: c.textSecondary)),
        if (empty) Text('No cards yet for ${m?.name ?? 'this person'}.', style: TextStyle(fontSize: 15, color: c.textSecondary)),
        for (var g = 0; g < lists!.length; g++) ...[
          SectionTitle(titles[g]),
          SurfaceCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              onReorderItem: (from, to) => _move(g, from, to),
              proxyDecorator: (child, _, _) => Material(elevation: 6, color: c.surface, borderRadius: BorderRadius.circular(12), child: child),
              children: [
                for (var i = 0; i < lists![g].length; i++)
                  Padding(
                    key: ValueKey(lists![g][i].key),
                    padding: const EdgeInsets.only(left: 4, right: 4),
                    child: Row(children: [
                      ReorderableDragStartListener(
                        index: i,
                        child: Padding(padding: const EdgeInsets.all(10), child: Icon(Icons.drag_indicator_rounded, color: c.textSecondary)),
                      ),
                      SizedBox(width: 22, child: Text('${i + 1}', textAlign: TextAlign.right, style: TextStyle(fontSize: 13, color: c.textSecondary, fontFeatures: const [FontFeature.tabularFigures()]))),
                      const SizedBox(width: 10),
                      Expanded(child: Text(lists![g][i].label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
                      IconButton(tooltip: 'Move ${lists![g][i].label} up', onPressed: i == 0 ? null : () => _move(g, i, i - 1), icon: const Icon(Icons.arrow_upward_rounded)),
                      IconButton(tooltip: 'Move ${lists![g][i].label} down', onPressed: i == lists![g].length - 1 ? null : () => _move(g, i, i + 1), icon: const Icon(Icons.arrow_downward_rounded)),
                    ]),
                  ),
              ],
            ),
          ),
        ],
        if (s.prefs.healthOrder.isNotEmpty) Center(child: TextLink('Reset to A–Z order', icon: Icons.sort_by_alpha_rounded, onTap: _reset)),
      ],
    );
  }
}
