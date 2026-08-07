import 'package:adb_ui/adb_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../build_info.dart';
import '../state/app_settings.dart';

/// App settings, shown in a tab rather than a modal.
///
/// A tab because settings here are things you compare against the app while
/// changing them — switching appearance is easier when the file list is one
/// tab away rather than behind a sheet.
class SettingsView extends StatelessWidget {
  const SettingsView({
    required this.settings,
    this.cacheSize,
    this.onClearCache,
    super.key,
  });

  final AppSettings settings;
  final int? cacheSize;
  final Future<void> Function()? onClearCache;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            children: [
              Text('Settings', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 24),

              _Section(
                title: 'Appearance',
                child: _ThemePicker(settings: settings),
              ),

              _Section(
                title: 'Preview cache',
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        cacheSize == null
                            ? 'Files opened for preview are cached here.'
                            : '${formatBytes(cacheSize!)} of previewed files '
                                  'are cached on this machine.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton(
                      onPressed: onClearCache,
                      child: const Text('Clear'),
                    ),
                  ],
                ),
              ),

              const _Section(title: 'About', child: _About()),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows exactly which build is running, and offers it as pasteable text.
///
/// The copy button is the point of this section: "it's broken on the latest
/// version" is not actionable, and asking someone to find a build number in
/// Finder's Get Info rarely works.
class _About extends StatefulWidget {
  const _About();

  @override
  State<_About> createState() => _AboutState();
}

class _AboutState extends State<_About> {
  late final Future<BuildInfo> _info = BuildInfo.load();
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FutureBuilder<BuildInfo>(
      future: _info,
      builder: (context, snapshot) {
        final info = snapshot.data;
        return Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('adb_files', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 3),
                  Text(
                    info == null ? 'Checking…' : info.detailLabel,
                    style: theme.textTheme.bodySmall,
                  ),
                  if (info?.builtAt != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Built ${_formatDate(info!.builtAt!.toLocal())}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: info == null
                  ? null
                  : () async {
                      await Clipboard.setData(
                        ClipboardData(text: info.diagnostics),
                      );
                      if (!mounted) return;
                      setState(() => _copied = true);
                    },
              icon: Icon(_copied ? Icons.check : Icons.copy_all_outlined,
                  size: 15),
              label: Text(_copied ? 'Copied' : 'Copy'),
            ),
          ],
        );
      },
    );
  }

  /// `7 Aug 2026, 14:03` — a fixed format rather than a locale-aware one, to
  /// avoid pulling in `intl` for a single line.
  static String _formatDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '${d.day} ${months[d.month - 1]} ${d.year}, $hh:$mm';
  }
}

class _ThemePicker extends StatelessWidget {
  const _ThemePicker({required this.settings});

  final AppSettings settings;

  static const _options = [
    (ThemeMode.system, 'System', Icons.brightness_auto_outlined),
    (ThemeMode.light, 'Light', Icons.light_mode_outlined),
    (ThemeMode.dark, 'Dark', Icons.dark_mode_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<ThemeMode>(
          segments: [
            for (final (mode, label, icon) in _options)
              ButtonSegment(
                value: mode,
                label: Text(label),
                icon: Icon(icon, size: 16),
              ),
          ],
          selected: {settings.themeMode},
          showSelectedIcon: false,
          onSelectionChanged: (selection) =>
              settings.setThemeMode(selection.first),
        ),
        const SizedBox(height: 8),
        Text(
          settings.themeMode == ThemeMode.system
              ? 'Follows the system appearance, including automatic '
                    'light/dark switching.'
              : 'Always ${settings.themeMode.name}, regardless of the system '
                    'setting.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              letterSpacing: 0.8,
              color: theme.hintColor,
            ),
          ),
          const SizedBox(height: 10),
          Card(
            margin: EdgeInsets.zero,
            elevation: 0,
            color: theme.colorScheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: theme.dividerColor),
            ),
            child: Padding(padding: const EdgeInsets.all(16), child: child),
          ),
        ],
      ),
    );
  }
}
