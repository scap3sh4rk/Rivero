import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rivero/core/ingestion/platform/notification_bridge.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/rivero_app_bar.dart';
import 'package:url_launcher/url_launcher.dart';

const _site = 'https://scap3sh4rk.github.io/Rivero';
const _repo = 'https://github.com/scap3sh4rk/Rivero';

/// Fonts bundled with the app (each with its SIL Open Font License).
const _fonts = {
  'DM Sans': 'DMSans',
  'Inter': 'Inter',
  'JetBrains Mono': 'JetBrainsMono',
  'Manrope': 'Manrope',
  'Plus Jakarta Sans': 'PlusJakartaSans',
  'Urbanist': 'Urbanist',
};

/// Adds the bundled fonts' licences to the open-source licenses page. Call
/// once at start (the packages' own licences are added by Flutter).
void registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final MapEntry(key: name, value: file) in _fonts.entries) {
      final text = await rootBundle.loadString('assets/fonts/OFL-$file.txt');
      yield LicenseEntryWithLineBreaks([name], text);
    }
  });
}

/// Settings > About: version, what changed, privacy, help and licences.
class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => const AboutScreen()));

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String? _version;

  @override
  void initState() {
    super.initState();
    NotificationBridge.appVersion().then((v) {
      if (mounted) setState(() => _version = v);
    });
  }

  Future<void> _open(String url) async {
    final ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not open $url')));
    }
  }

  Widget _row(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap, {
    Key? key,
  }) => ListTile(
    key: key,
    contentPadding: const EdgeInsets.symmetric(
      horizontal: RiveroSpacing.xl,
      vertical: RiveroSpacing.xs,
    ),
    leading: Icon(icon, color: RiveroColors.textSecondary),
    title: Text(title, style: RiveroTypography.titleMedium),
    subtitle: Text(subtitle, style: RiveroTypography.bodySmall),
    onTap: onTap,
  );

  @override
  Widget build(BuildContext context) {
    final version = _version == null ? null : 'Version $_version';
    return Scaffold(
      backgroundColor: RiveroColors.background,
      appBar: const RiveroAppBar(
        title: 'About',
        showEye: false, // the hide-amounts eye is for money pages
        showProfile: false,
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: RiveroSpacing.huge),
        children: [
          const SizedBox(height: RiveroSpacing.lg),
          Center(
            child: Image.asset('assets/icon/logo.png', width: 72, height: 72),
          ),
          const SizedBox(height: RiveroSpacing.md),
          Center(child: Text('Rivero', style: RiveroTypography.titleLarge)),
          Center(
            child: Text(
              'Your Money - In Flow',
              style: RiveroTypography.bodySmall,
            ),
          ),
          if (version != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(top: RiveroSpacing.xs),
                child: Text(
                  version,
                  key: const ValueKey('about-version'),
                  style: RiveroTypography.bodySmall,
                ),
              ),
            ),
          const SizedBox(height: RiveroSpacing.xl),
          _row(
            Icons.new_releases_outlined,
            "What's new",
            'What changed in each version',
            () => _open('$_repo/releases'),
            key: const ValueKey('about-whats-new'),
          ),
          _row(
            Icons.shield_outlined,
            'Privacy & security',
            'Your data stays on this phone, encrypted',
            () => _open('$_site/privacy-security.html'),
          ),
          _row(
            Icons.menu_book_outlined,
            'User guide',
            'How each part of Rivero works',
            () => _open('$_site/user-guide.html'),
          ),
          _row(
            Icons.bug_report_outlined,
            'Report a problem or suggest an idea',
            'Opens the issue tracker',
            () => _open('$_repo/issues/new/choose'),
          ),
          _row(
            Icons.description_outlined,
            'Open-source licenses',
            'The libraries and fonts Rivero is built with',
            () => showLicensePage(
              context: context,
              applicationName: 'Rivero',
              applicationVersion: _version,
              applicationIcon: Padding(
                padding: const EdgeInsets.all(RiveroSpacing.md),
                child: Image.asset(
                  'assets/icon/logo.png',
                  width: 48,
                  height: 48,
                ),
              ),
            ),
            key: const ValueKey('about-licenses'),
          ),
        ],
      ),
    );
  }
}
