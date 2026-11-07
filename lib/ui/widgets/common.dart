import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../data/catalog.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../../services/sync_service.dart';
import '../screens/settings.dart';
import 'motion.dart';

AppStore watchStore(BuildContext c) => c.watch<AppStore>();
AppStore readStore(BuildContext c) => c.read<AppStore>();

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
String fmtDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';
String fmtDay(DateTime d) => '${d.day} ${_months[d.month - 1]}';
String fmtWeekday(DateTime d) => _days[d.weekday - 1];
String monthName(int m) => const ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'][m - 1];
String fmtMonthYear(DateTime d) => '${_months[d.month - 1]} ${d.year}';
String fmtTime(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
}

String fmtHm(int h, int m) => fmtTime(DateTime(2000, 1, 1, h, m));

/// Height in cm → whole feet and inches (nearest inch).
(int, int) feetInches(double cm) {
  final total = (cm / 2.54).round();
  return (total ~/ 12, total % 12);
}

/// "180 cm · 5′11″"
String fmtHeight(double cm) {
  final (f, i) = feetInches(cm);
  return '${cm.round()} cm · $f′$i″';
}

String ago(DateTime d) {
  final now = DateTime.now();
  final days = dayOnly(now).difference(dayOnly(d)).inDays;
  if (days == 0) return 'Today, ${fmtTime(d)}';
  if (days == 1) return 'Yesterday';
  if (days < 31) return '$days days ago';
  return fmtDate(d);
}

/// A short floating message. [ok] adds a green tick (saved, deleted…); use
/// `ok: false` for a warning.
void toast(BuildContext context, String msg, {bool? ok}) {
  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  final c = context.c;
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(
    behavior: SnackBarBehavior.floating,
    duration: const Duration(milliseconds: 2200),
    content: Row(children: [
      if (ok != null) ...[Icon(ok ? Icons.check_circle_rounded : Icons.error_rounded, color: ok ? const Color(0xFF34D399) : const Color(0xFFFBBF24), size: 22), const SizedBox(width: 10)],
      Expanded(child: Text(msg, style: TextStyle(color: c.bg, fontSize: 15, fontWeight: FontWeight.w600))),
    ]),
  ));
}

/// White rounded card: hairline edge, soft layered shadow, and a gentle press
/// when it is tappable.
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({super.key, required this.child, this.padding = const EdgeInsets.all(12), this.onTap, this.color, this.gradient, this.borderColor, this.semanticLabel});
  final Widget child;
  final Gradient? gradient;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borderColor;
  final String? semanticLabel;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final deco = BoxDecoration(
      color: gradient == null ? (color ?? c.surface) : null,
      gradient: gradient,
      borderRadius: BorderRadius.circular(kRadiusCard),
      border: borderColor == null ? Border.all(color: c.border.withValues(alpha: gradient == null && color == null ? .7 : 0), width: .8) : Border.all(color: borderColor!, width: 1.5),
      boxShadow: [
        BoxShadow(color: c.shadow, blurRadius: 24, spreadRadius: -4, offset: const Offset(0, 10)),
        BoxShadow(color: c.shadow, blurRadius: 3, offset: const Offset(0, 1)),
      ],
    );
    final inner = Padding(padding: padding, child: child);
    if (onTap == null) return Semantics(label: semanticLabel, container: semanticLabel != null, child: Container(decoration: deco, child: inner));
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Pressable(
        child: Container(
          decoration: deco,
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(kRadiusCard),
            child: InkWell(borderRadius: BorderRadius.circular(kRadiusCard), onTap: onTap, child: inner),
          ),
        ),
      ),
    );
  }
}

class _PillStyle {
  const _PillStyle(this.icon, this.fg, this.bg);
  final IconData icon;
  final Color fg, bg;
}

/// Tint background + icon + word. Never colour alone.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, this.level, this.icon, this.tone});
  factory StatusPill.level(Level l, {Key? key, String? label}) => StatusPill(key: key, level: l, label: label ?? '');
  factory StatusPill.info(StatusInfo s, {Key? key}) => StatusPill(key: key, level: s.level, label: s.word);
  final String label;
  final Level? level;
  final IconData? icon;

  /// Used for non-lab states: 'ok' | 'warn' | 'danger' | 'info' | 'muted'.
  final String? tone;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    _PillStyle st;
    if (level != null) {
      st = switch (level!) {
        Level.normal => _PillStyle(Icons.check_circle_rounded, c.ok, c.okTint),
        Level.borderline => _PillStyle(Icons.error_rounded, c.warn, c.warnTint),
        Level.high => _PillStyle(Icons.arrow_upward_rounded, c.danger, c.dangerTint),
        Level.low => _PillStyle(Icons.arrow_downward_rounded, c.danger, c.dangerTint),
        Level.none => _PillStyle(Icons.remove_rounded, c.textSecondary, c.surfaceAlt),
      };
    } else {
      st = switch (tone) {
        'ok' => _PillStyle(Icons.check_circle_rounded, c.ok, c.okTint),
        'warn' => _PillStyle(Icons.error_rounded, c.warn, c.warnTint),
        'danger' => _PillStyle(Icons.cancel_rounded, c.danger, c.dangerTint),
        'info' => _PillStyle(Icons.info_rounded, c.info, c.infoTint),
        _ => _PillStyle(Icons.schedule_rounded, c.textSecondary, c.surfaceAlt),
      };
    }
    return Semantics(
      label: tr(label),
      excludeSemantics: true,
      child: Container(
        height: 24,
        padding: const EdgeInsets.only(left: 8, right: 10),
        decoration: BoxDecoration(color: st.bg, borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon ?? st.icon, size: 14, color: st.fg),
          const SizedBox(width: 6),
          Text(tr(label), style: TextStyle(fontSize: 13, height: 16 / 13, fontWeight: FontWeight.w600, color: c.text), maxLines: 1),
        ]),
      ),
    );
  }
}

class MemberAvatar extends StatelessWidget {
  const MemberAvatar(this.member, {super.key, this.size = 32, this.filled = true});
  final Member? member;
  final double size;
  final bool filled;
  /// A person's initial on a solid fill of their colour; "everyone" is a neutral group icon.
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final m = member;
    if (m == null) {
      return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, color: c.surfaceAlt),
        child: Icon(Icons.group_rounded, size: size * .55, color: c.textSecondary),
      );
    }
    final deep = Color.lerp(m.color, Colors.black, .28)!;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: [m.color, deep], begin: Alignment.topLeft, end: Alignment.bottomRight),
        boxShadow: [BoxShadow(color: m.color.withValues(alpha: .25), blurRadius: size * .2, offset: Offset(0, size * .06))],
      ),
      child: Text(m.initial, style: TextStyle(fontWeight: FontWeight.w700, fontSize: size * .44, height: 1, color: Colors.white)),
    );
  }
}

/// "All" chip first, then one avatar chip per member.
class MemberSwitcher extends StatelessWidget {
  const MemberSwitcher({super.key, required this.members, required this.selectedId, required this.onSelect, this.includeAll = false});
  final List<Member> members;
  final String? selectedId;
  final ValueChanged<String?> onSelect;
  final bool includeAll;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    Widget chip({required String label, required Widget avatar, required bool on, required VoidCallback tap}) {
      return Semantics(
        button: true,
        selected: on,
        label: label,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: tap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 38),
            padding: const EdgeInsets.fromLTRB(5, 5, 12, 5),
            decoration: BoxDecoration(
              color: on ? c.accentTint : c.surface,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: on ? c.accent : c.border, width: on ? 1.5 : 1),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              avatar,
              const SizedBox(width: 8),
              Text(label, style: TextStyle(fontSize: 15, fontWeight: on ? FontWeight.w700 : FontWeight.w500)),
            ]),
          ),
        ),
      );
    }

    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: kSide),
        children: [
          if (includeAll) ...[chip(label: 'All', avatar: const MemberAvatar(null), on: selectedId == null, tap: () => onSelect(null)), const SizedBox(width: 8)],
          for (final m in members) ...[
            chip(label: m.name, avatar: MemberAvatar(m), on: selectedId == m.id, tap: () => onSelect(m.id)),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

/// Who the screen shows, as a compact button in the header (left of Settings).
/// Opens a list of people, with "Everyone" first when [includeAll].
class MemberPicker extends StatelessWidget {
  const MemberPicker({super.key, required this.members, required this.selectedId, required this.onSelect, this.includeAll = false});
  final List<Member> members;
  final String? selectedId;
  final ValueChanged<String?> onSelect;
  final bool includeAll;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    if (members.length < 2) return const SizedBox.shrink();
    Member? sel;
    for (final m in members) {
      if (m.id == selectedId) sel = m;
    }
    final label = sel?.name ?? (includeAll ? 'Everyone' : members.first.name);
    PopupMenuItem<String> item(String value, Member? m, String name, bool on) => PopupMenuItem<String>(
          value: value,
          height: 44,
          child: Row(children: [
            MemberAvatar(m, size: 28),
            const SizedBox(width: 10),
            Expanded(child: Text(name, style: TextStyle(fontSize: 15, fontWeight: on ? FontWeight.w700 : FontWeight.w500))),
            if (on) Icon(Icons.check_rounded, size: 20, color: c.accent),
          ]),
        );
    return PopupMenuButton<String>(
      tooltip: 'Showing $label. Choose person',
      position: PopupMenuPosition.under,
      color: c.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      onSelected: (v) => onSelect(v.isEmpty ? null : v),
      itemBuilder: (_) => [
        if (includeAll) item('', null, 'Everyone', selectedId == null),
        for (final m in members) item(m.id, m, m.name, m.id == selectedId),
      ],
      child: Container(
        height: 40,
        padding: const EdgeInsets.fromLTRB(4, 4, 6, 4),
        decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(999), boxShadow: [BoxShadow(color: c.shadow, blurRadius: 10, offset: const Offset(0, 3))]),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          MemberAvatar(sel, size: 32),
          const SizedBox(width: 6),
          ConstrainedBox(constraints: const BoxConstraints(maxWidth: 96), child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
          Icon(Icons.expand_more_rounded, size: 20, color: c.textSecondary),
        ]),
      ),
    );
  }
}

/// Header actions: person picker (when there is a choice) + Settings.
Widget headerActions(MemberPicker? picker) => Row(mainAxisSize: MainAxisSize.min, children: [if (picker != null) ...[picker, const SizedBox(width: 8)], const SettingsButton()]);

/// Settings, top right of every main screen. A small dot shows when sync needs
/// attention (sign in again, offline with changes waiting); details are in Settings.
class SettingsButton extends StatelessWidget {
  const SettingsButton({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final store = context.watch<AppStore>();
    final sync = context.watch<SyncService?>();
    final pending = store.sync.pendingCount;
    // Not signed in (records only on this phone) also counts: the family's data lives online.
    final notSyncing = sync != null && !sync.signedIn && store.members.isNotEmpty;
    final attention = notSyncing || (sync != null && sync.signedIn && (sync.needsSignIn || (sync.offline && pending > 0) || store.sync.lastError != null));
    return Stack(clipBehavior: Clip.none, children: [
      RoundIconButton(icon: Icons.settings_rounded, label: attention ? '${tr('Settings')}, ${notSyncing ? 'not syncing' : 'sync needs attention'}' : tr('Settings'), onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()))),
      if (attention)
        Positioned(
          top: 4,
          right: 4,
          child: Container(width: 10, height: 10, decoration: BoxDecoration(color: c.warn, shape: BoxShape.circle, border: Border.all(color: c.bg, width: 2))),
        ),
    ]);
  }
}

class RoundIconButton extends StatelessWidget {
  const RoundIconButton({super.key, required this.icon, required this.label, required this.onTap, this.size = 40});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final double size;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: c.surface,
        shape: const CircleBorder(),
        elevation: 0,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: c.shadow, blurRadius: 10, offset: const Offset(0, 3))]),
            child: Icon(icon, size: 20, color: c.text),
          ),
        ),
      ),
    );
  }
}

/// App-bar style header used by every screen: optional back, title, subtitle, trailing.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({super.key, required this.title, this.subtitle, this.back = false, this.trailing, this.big = false, this.leading});
  final String title;
  final String? subtitle;
  final bool back, big;
  final Widget? trailing, leading;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: EdgeInsets.fromLTRB(kSide, big ? 12 : 8, kSide, big ? 10 : 6),
      child: Row(children: [
        if (back) ...[
          RoundIconButton(icon: Icons.arrow_back_rounded, label: 'Back', onTap: () => Navigator.of(context).maybePop()),
          const SizedBox(width: 12),
        ],
        if (leading != null) ...[leading!, const SizedBox(width: 12)],
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (big && subtitle != null) Text(subtitle!.toUpperCase(), style: TextStyle(fontSize: 12, height: 16 / 12, letterSpacing: .8, fontWeight: FontWeight.w700, color: c.accent)),
            Text(title, style: TextStyle(fontSize: big ? 30 : 19, height: big ? 36 / 30 : 24 / 19, letterSpacing: big ? -.8 : -.3, fontWeight: big ? FontWeight.w800 : FontWeight.w700), maxLines: 2, overflow: TextOverflow.ellipsis),
            if (!big && subtitle != null) Text(subtitle!, style: TextStyle(fontSize: 13, height: 18 / 13, fontWeight: FontWeight.w500, color: c.textSecondary)),
          ]),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ]),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.action, this.onAction});
  final String text;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 0, 0),
      child: Row(children: [
        Expanded(child: Text(tr(text), style: const TextStyle(fontSize: 18, height: 24 / 18, letterSpacing: -.3, fontWeight: FontWeight.w700))),
        if (action != null) TextButton(onPressed: onAction, style: TextButton.styleFrom(minimumSize: const Size(40, 36), foregroundColor: c.accent), child: Text(action!, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
      ]),
    );
  }
}

/// Large pill button. One primary per screen.
class BigButton extends StatelessWidget {
  const BigButton({super.key, required this.label, required this.onTap, this.icon, this.secondary = false, this.height = 44, this.fontSize = 15, this.danger = false, this.expand = true});
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool secondary, danger, expand;
  final double height, fontSize;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final bg = secondary ? c.surface : (danger ? c.danger : c.accent);
    final fg = secondary ? c.accent : Colors.white;
    final child = Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
      if (icon != null) ...[Icon(icon, size: fontSize + 8, color: fg), SizedBox(width: fontSize * .5)],
      Flexible(child: Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w700, color: fg), maxLines: 2)),
    ]);
    final gradient = !secondary && !danger && onTap != null;
    final btn = Material(
      color: gradient ? Colors.transparent : (onTap == null ? c.border : bg),
      borderRadius: BorderRadius.circular(999),
      child: Ink(
        decoration: gradient
            ? BoxDecoration(gradient: c.gradient, borderRadius: BorderRadius.circular(999), boxShadow: [BoxShadow(color: c.accent.withValues(alpha: .28), blurRadius: 16, offset: const Offset(0, 6))])
            : null,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Container(
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            alignment: Alignment.center,
            decoration: secondary ? BoxDecoration(borderRadius: BorderRadius.circular(999), border: Border.all(color: c.border, width: 1.5)) : null,
            child: child,
          ),
        ),
      ),
    );
    final pressed = Pressable(enabled: onTap != null, scale: .96, child: btn);
    return expand ? SizedBox(width: double.infinity, child: pressed) : pressed;
  }
}

class TextLink extends StatelessWidget {
  const TextLink(this.label, {super.key, required this.onTap, this.icon});
  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(minimumSize: const Size(48, 40), foregroundColor: c.accent, padding: const EdgeInsets.symmetric(horizontal: 12)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 6)],
        Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class IconBadge extends StatelessWidget {
  const IconBadge(this.icon, {super.key, this.size = 36, this.color, this.tint});
  final IconData icon;
  final double size;
  final Color? color, tint;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: tint ?? c.accentTint, borderRadius: BorderRadius.circular(size * .36)),
      child: Icon(icon, size: size * .52, color: color ?? c.accent),
    );
  }
}

/// Soft banner. `tone`: warn | danger | info | ok.
class BannerCard extends StatelessWidget {
  const BannerCard({super.key, required this.icon, required this.text, this.tone = 'info', this.onTap, this.trailing});
  final IconData icon;
  final String text, tone;
  final VoidCallback? onTap;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final (fg, bg) = switch (tone) {
      'warn' => (c.warn, c.warnTint),
      'danger' => (c.danger, c.dangerTint),
      'ok' => (c.ok, c.okTint),
      _ => (c.info, c.infoTint),
    };
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(children: [
            Icon(icon, size: 22, color: fg),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 15, height: 22 / 16, fontWeight: FontWeight.w600))),
            if (trailing != null) trailing! else if (onTap != null) Icon(Icons.chevron_right_rounded, color: c.textSecondary),
          ]),
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.message, this.detail, this.buttonLabel, this.onButton});
  final IconData icon;
  final String message;
  final String? detail;
  final String? buttonLabel;
  final VoidCallback? onButton;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: reduceMotion(context) ? 1 : .6, end: 1),
          duration: const Duration(milliseconds: 600),
          curve: Curves.elasticOut,
          builder: (_, v, child) => Transform.scale(scale: v, child: child),
          child: Container(
            width: 104,
            height: 104,
            decoration: BoxDecoration(gradient: c.softGradient, shape: BoxShape.circle),
            child: Icon(icon, size: 44, color: c.accent),
          ),
        ),
        const SizedBox(height: 16),
        Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, height: 24 / 17, fontWeight: FontWeight.w700)),
        if (detail != null) ...[const SizedBox(height: 8), Text(detail!, textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: c.textSecondary, height: 22 / 16))],
        if (buttonLabel != null) ...[const SizedBox(height: 24), BigButton(label: buttonLabel!, onTap: onButton, icon: Icons.upload_rounded)],
      ]),
    );
  }
}

/// Descriptive (never diagnostic) trend summary.
class InsightCard extends StatelessWidget {
  const InsightCard({super.key, required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: c.accentTint, borderRadius: BorderRadius.circular(kRadiusCard)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.insights_rounded, size: 20, color: c.accent),
          const SizedBox(width: 8),
          Text('Trend summary', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.accent)),
        ]),
        const SizedBox(height: 8),
        Text(text, style: const TextStyle(fontSize: 16, height: 26 / 18)),
        const SizedBox(height: 8),
        Text('Not medical advice. Discuss with your doctor.', style: TextStyle(fontSize: 14, height: 20 / 14, color: c.textSecondary)),
      ]),
    );
  }
}

/// Row with a label, helper text and a switch (Settings).
class SwitchRow extends StatelessWidget {
  const SwitchRow({super.key, required this.icon, required this.title, this.subtitle, required this.value, required this.onChanged});
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      toggled: value,
      label: '${tr(title)}${subtitle == null ? '' : '. $subtitle'}',
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              IconBadge(icon, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr(title), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  if (subtitle != null) Text(subtitle!, style: TextStyle(fontSize: 13, color: c.textSecondary, height: 18 / 13)),
                ]),
              ),
              Switch(value: value, onChanged: onChanged, activeTrackColor: c.accent, activeThumbColor: Colors.white),
            ]),
          ),
        ),
      ),
    );
  }
}

class Divider1 extends StatelessWidget {
  const Divider1({super.key});
  @override
  Widget build(BuildContext context) => Divider(height: 1, thickness: 1, color: context.c.border);
}

/// Pill-shaped chip row used for periods, filters, and segmented choices.
class ChoiceChips<T> extends StatelessWidget {
  const ChoiceChips({super.key, required this.options, required this.value, required this.onChanged, this.label});
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;
  final String Function(T)? label;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final (v, l) in options)
        Semantics(
          button: true,
          selected: v == value,
          label: l,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => onChanged(v),
            child: Container(
              height: 38,
              constraints: const BoxConstraints(minWidth: 56),
              padding: const EdgeInsets.symmetric(horizontal: 18),
              decoration: BoxDecoration(
                color: v == value ? c.accentTint : c.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: v == value ? c.accent : c.border),
              ),
              child: Center(widthFactor: 1, child: Text(l, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: v == value ? c.accent : c.textSecondary))),
            ),
          ),
        ),
    ]);
  }
}

/// Scaffold body wrapper: header + scrolling content, honouring safe areas.
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.header, required this.children, this.bottom, this.spacing = 12, this.padBottom = 24});
  final Widget header;
  final List<Widget> children;
  final Widget? bottom;
  final double spacing, padBottom;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(children: [
          header,
          Expanded(
            child: ListView.separated(
              padding: EdgeInsets.fromLTRB(kSide, 8, kSide, padBottom),
              itemCount: children.length,
              separatorBuilder: (_, _) => SizedBox(height: spacing),
              itemBuilder: (_, i) => FadeSlideIn(index: i, child: children[i]),
            ),
          ),
          if (bottom != null)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.border))),
              child: bottom,
            ),
        ]),
      ),
    );
  }
}

Future<bool> confirmDialog(BuildContext context, String title, String body, {String yes = 'Delete', bool danger = true}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body, style: const TextStyle(fontSize: 15)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'), style: const TextStyle(fontSize: 15))),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(yes, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: danger ? ctx.c.danger : ctx.c.accent))),
      ],
    ),
  );
  return r ?? false;
}

/// The Family Health logo (heart with a heartbeat line).
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 64});
  final double size;
  @override
  Widget build(BuildContext context) => Semantics(
        image: true,
        label: 'Family Health',
        child: Image.asset('assets/branding/logo.png', width: size, height: size, filterQuality: FilterQuality.medium),
      );
}
