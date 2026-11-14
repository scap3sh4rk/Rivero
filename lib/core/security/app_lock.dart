import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:rivero/design_system/rivero_tokens.dart';

/// Asks the OS to verify the user (fingerprint, face, or phone PIN).
typedef Authenticator = Future<bool> Function(String reason);

final authenticatorProvider = Provider<Authenticator>((ref) {
  return (reason) async {
    final auth = LocalAuthentication();
    try {
      if (!await auth.isDeviceSupported()) return false;
      return await auth.authenticate(
        localizedReason: reason,
        persistAcrossBackgrounding: true,
      );
    } on Object {
      return false; // cancelled, locked out, or no screen lock set
    }
  };
});

/// Whether the app asks for biometrics / PIN to open.
final appLockEnabledProvider = StateProvider<bool>((ref) => false);

/// Covers [child] with a lock screen until the user is verified. Locks again
/// after the app has been in the background for [relockAfter].
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({
    required this.child,
    super.key,
    this.relockAfter = const Duration(seconds: 30),
  });

  final Widget child;
  final Duration relockAfter;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate>
    with WidgetsBindingObserver {
  bool _unlocked = false;
  bool _prompting = false;
  DateTime? _leftAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _leftAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final left = _leftAt;
      // The OS prompt itself pauses the app briefly; only real absences lock.
      if (!_prompting &&
          left != null &&
          DateTime.now().difference(left) >= widget.relockAfter) {
        setState(() => _unlocked = false);
      }
      _leftAt = null;
    }
  }

  Future<void> _unlock() async {
    if (_prompting) return;
    _prompting = true;
    final ok = await ref.read(authenticatorProvider)('Unlock Rivero');
    _prompting = false;
    if (ok && mounted) setState(() => _unlocked = true);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(appLockEnabledProvider);
    if (!enabled || _unlocked) return widget.child;
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
    return Scaffold(
      backgroundColor: RiveroColors.background,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset('assets/icon/logo.png', width: 96, height: 96),
              const SizedBox(height: RiveroSpacing.lg),
              Text('Rivero is locked', style: RiveroTypography.titleLarge),
              const SizedBox(height: RiveroSpacing.xl),
              FilledButton.icon(
                key: const ValueKey('unlock'),
                onPressed: _unlock,
                style: FilledButton.styleFrom(shape: const StadiumBorder()),
                icon: const Icon(Icons.fingerprint_rounded),
                label: const Text('Unlock'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
