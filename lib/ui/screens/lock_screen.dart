import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:provider/provider.dart';

import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../data/store.dart';
import '../widgets/common.dart';

/// Reusable 4-digit PIN pad (lock screen, and set-PIN flow in Settings).
class PinPad extends StatelessWidget {
  const PinPad({super.key, required this.value, required this.onChanged, this.onFingerprint});
  final String value;
  final ValueChanged<String> onChanged;
  final VoidCallback? onFingerprint;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    Widget key(String label, {String? semantic, VoidCallback? onTap, Widget? child, bool plain = false}) {
      return Semantics(
        button: true,
        label: semantic ?? label,
        excludeSemantics: true,
        child: Material(
          color: plain ? Colors.transparent : c.surfaceAlt,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap == null
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    onTap();
                  },
            child: Container(height: 64, alignment: Alignment.center, child: child ?? Text(label, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w600))),
          ),
        ),
      );
    }

    void add(String d) {
      if (value.length < 4) onChanged(value + d);
    }

    return Column(mainAxisSize: MainAxisSize.min, children: [
      Semantics(
        label: 'PIN entered: ${value.length} of 4',
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 0; i < 4; i++)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 10),
              width: 18,
              height: 18,
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: c.accent, width: 2), color: i < value.length ? c.accent : Colors.transparent),
            ),
        ]),
      ),
      const SizedBox(height: 28),
      GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.7,
        children: [
          for (var i = 1; i <= 9; i++) key('$i', onTap: () => add('$i')),
          onFingerprint == null ? const SizedBox() : key('fp', semantic: 'Use fingerprint', plain: true, onTap: onFingerprint, child: Icon(Icons.fingerprint_rounded, size: 30, color: c.accent)),
          key('0', onTap: () => add('0')),
          key('del', semantic: 'Delete', plain: true, onTap: () => onChanged(value.isEmpty ? '' : value.substring(0, value.length - 1)), child: Icon(Icons.backspace_outlined, size: 26, color: c.text)),
        ],
      ),
    ]);
  }
}

class LockScreen extends StatefulWidget {
  const LockScreen({super.key});
  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _auth = LocalAuthentication();
  bool _bio = false, _pinMode = false, _wrong = false;
  String _pin = '';

  @override
  void initState() {
    super.initState();
    _checkBio();
  }

  Future<void> _checkBio() async {
    if (kIsWeb) {
      setState(() => _pinMode = true);
      return;
    }
    try {
      final ok = await _auth.isDeviceSupported() && await _auth.canCheckBiometrics;
      if (!mounted) return;
      setState(() {
        _bio = ok;
        _pinMode = !ok;
      });
      if (ok) _prompt();
    } catch (_) {
      if (mounted) setState(() => _pinMode = true);
    }
  }

  Future<void> _prompt() async {
    try {
      final ok = await _auth.authenticate(localizedReason: 'Unlock Family Health', biometricOnly: true);
      if (ok && mounted) _unlock();
    } catch (_) {
      if (mounted) setState(() => _pinMode = true);
    }
  }

  void _unlock() {
    final s = context.read<AppStore>();
    s.unlocked = true;
    s.changed();
  }

  void _onPin(String v) {
    setState(() {
      _pin = v;
      _wrong = false;
    });
    if (v.length == 4) {
      final s = context.read<AppStore>();
      if (s.checkPin(v)) {
        _unlock();
      } else {
        HapticFeedback.heavyImpact();
        setState(() {
          _pin = '';
          _wrong = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: MediaQuery.of(context).size.height - 100),
            child: Column(children: [
              const SizedBox(height: 56),
              const AppLogo(size: 72),
              const SizedBox(height: 20),
              const Text('Family Health', style: TextStyle(fontSize: 24, height: 34 / 28, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.lock_rounded, size: 16, color: c.textSecondary),
                const SizedBox(width: 6),
                Text('Private · stored on this phone', style: TextStyle(fontSize: 15, color: c.textSecondary)),
              ]),
              if (!_pinMode) ...[
                const SizedBox(height: 96),
                Semantics(
                  button: true,
                  label: 'Unlock with fingerprint',
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _prompt,
                    child: Container(
                      width: 112,
                      height: 112,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: c.surface, border: Border.all(color: c.accent, width: 2)),
                      child: Icon(Icons.fingerprint_rounded, size: 56, color: c.accent),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(tr('Touch the sensor to unlock'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                const SizedBox(height: 120),
                BigButton(label: tr('Use PIN instead'), secondary: true, onTap: () => setState(() => _pinMode = true)),
              ] else ...[
                const SizedBox(height: 36),
                Text(tr('Enter your 4-digit PIN'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                SizedBox(height: 24, child: _wrong ? Text('That PIN is not right. Try again.', style: TextStyle(fontSize: 15, color: c.danger, fontWeight: FontWeight.w600)) : null),
                const SizedBox(height: 8),
                PinPad(value: _pin, onChanged: _onPin, onFingerprint: _bio ? () => _prompt() : null),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}
