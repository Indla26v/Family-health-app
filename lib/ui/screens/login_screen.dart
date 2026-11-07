import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../data/store.dart';
import '../../services/api_client.dart';
import '../../services/sync_service.dart';

/// Sign in to the family's cloud account so this phone syncs with the web app
/// ([kDefaultApiBase]). Shown on first start and from Settings.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.fromSettings = false});
  final bool fromSettings;
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false, _hide = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _email.text = TokenStore.instance.account?.email ?? '';
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final sync = context.read<SyncService>();
    final email = _email.text.trim(), pw = _password.text;
    if (email.isEmpty || pw.isEmpty) {
      setState(() => _error = 'Enter your email and password');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await sync.signIn(kDefaultApiBase, email, pw);
      if (!mounted) return;
      if (widget.fromSettings) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _error = e.status == 429 ? e.message : (e.status == 401 ? 'That email or password is not right' : e.message));
    } on OfflineException {
      setState(() => _error = 'Can’t reach the server. Check your internet.');
    } catch (e) {
      setState(() => _error = 'Sign-in failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Password reset happens on the website: it emails a 6-digit code.
  Future<void> _forgot() async {
    final ok = await launchUrl(Uri.parse('$kDefaultApiBase/forgot'), mode: LaunchMode.externalApplication);
    if (!ok && mounted) setState(() => _error = 'Couldn’t open the browser. Go to $kDefaultApiBase/forgot to reset your password.');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final other = context.read<AppStore>().sync.familyId != null;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: widget.fromSettings ? AppBar(title: const Text('Sign in')) : null,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: AutofillGroup(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (!widget.fromSettings) ...[
                    Icon(Icons.favorite_rounded, size: 56, color: c.accent),
                    const SizedBox(height: 12),
                    const Text('Family Health', textAlign: TextAlign.center, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                  ],
                  Text(
                    'Sync with your family’s web account. Works offline too.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15, color: c.textSecondary, height: 1.35),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email, AutofillHints.username],
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: _hide,
                    autofillHints: const [AutofillHints.password],
                    onSubmitted: (_) => _busy ? null : _signIn(),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(tooltip: _hide ? 'Show password' : 'Hide password', icon: Icon(_hide ? Icons.visibility_rounded : Icons.visibility_off_rounded), onPressed: () => setState(() => _hide = !_hide)),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(color: c.danger, fontWeight: FontWeight.w600)),
                  ],
                  if (other) ...[
                    const SizedBox(height: 12),
                    Text('Another family’s records will be removed from this phone (they stay online).', style: TextStyle(fontSize: 13, color: c.textSecondary)),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 52,
                    child: FilledButton(
                      onPressed: _busy ? null : _signIn,
                      child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : const Text('Sign in', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  TextButton(onPressed: _busy ? null : _forgot, child: const Text('Forgot password?')),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: _busy ? null : () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SignUpScreen())),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    child: const Text('Create an account', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(height: 8),
                  Text('Joining your family? Use the invite link from its owner instead.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: c.textSecondary)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Create an account (a new family where this person is the owner): name, email and
/// password, then the 6-digit code emailed to that address.
class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});
  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _name = TextEditingController(), _email = TextEditingController(), _password = TextEditingController(), _confirm = TextEditingController(), _code = TextEditingController();
  bool _busy = false, _hide = true, _codeSent = false;
  String? _error;

  @override
  void dispose() {
    for (final t in [_name, _email, _password, _confirm, _code]) {
      t.dispose();
    }
    super.dispose();
  }

  Future<void> _run(Future<void> Function() f) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await f();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on OfflineException {
      if (mounted) setState(() => _error = 'Can’t reach the server. Check your internet.');
    } catch (e) {
      if (mounted) setState(() => _error = 'Sign-up failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start() async {
    if (_name.text.trim().isEmpty || _email.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Enter your name, email and a password');
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() => _error = 'Passwords do not match');
      return;
    }
    final api = context.read<SyncService>().api;
    await _run(() async {
      await api.signUpStart(kDefaultApiBase, _name.text, _email.text, _password.text);
      if (mounted) setState(() => _codeSent = true);
    });
  }

  Future<void> _finish() async {
    if (_code.text.trim().length != 6) {
      setState(() => _error = 'Enter the 6-digit code from the email');
      return;
    }
    final sync = context.read<SyncService>();
    await _run(() async {
      await sync.finishSignUp(kDefaultApiBase, _email.text, _code.text);
      // Signed in: the app's first screen takes over (setting up the new family).
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    InputDecoration box(String label) => InputDecoration(labelText: label, border: const OutlineInputBorder());
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: const Text('Create an account')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: AutofillGroup(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (!_codeSent) ...[
                    Text('This starts a new family where you are the owner. We’ll email you a code to confirm the address.', style: TextStyle(fontSize: 15, color: c.textSecondary, height: 1.35)),
                    const SizedBox(height: 20),
                    TextField(controller: _name, textCapitalization: TextCapitalization.words, autofillHints: const [AutofillHints.name], textInputAction: TextInputAction.next, decoration: box('Your name')),
                    const SizedBox(height: 12),
                    TextField(controller: _email, keyboardType: TextInputType.emailAddress, autofillHints: const [AutofillHints.email], textInputAction: TextInputAction.next, decoration: box('Email')),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _password,
                      obscureText: _hide,
                      autofillHints: const [AutofillHints.newPassword],
                      textInputAction: TextInputAction.next,
                      decoration: box('Password (8+ characters)').copyWith(
                        suffixIcon: IconButton(tooltip: _hide ? 'Show password' : 'Hide password', icon: Icon(_hide ? Icons.visibility_rounded : Icons.visibility_off_rounded), onPressed: () => setState(() => _hide = !_hide)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(controller: _confirm, obscureText: _hide, autofillHints: const [AutofillHints.newPassword], onSubmitted: (_) => _busy ? null : _start(), decoration: box('Password again')),
                  ] else ...[
                    Text('We emailed a 6-digit code to ${_email.text.trim()}. It works for 10 minutes. Check spam if you don’t see it.', style: TextStyle(fontSize: 15, color: c.textSecondary, height: 1.35)),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _code,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                      autofillHints: const [AutofillHints.oneTimeCode],
                      style: const TextStyle(fontSize: 26, letterSpacing: 8, fontWeight: FontWeight.w700),
                      onSubmitted: (_) => _busy ? null : _finish(),
                      decoration: box('6-digit code'),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(color: c.danger, fontWeight: FontWeight.w600)),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 52,
                    child: FilledButton(
                      onPressed: _busy ? null : (_codeSent ? _finish : _start),
                      child: _busy
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                          : Text(_codeSent ? 'Create my account' : 'Continue', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  if (_codeSent) ...[
                    TextButton(onPressed: _busy ? null : _start, child: const Text('Send a new code')),
                    TextButton(onPressed: _busy ? null : () => setState(() => _codeSent = false), child: const Text('Change the email')),
                  ],
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
