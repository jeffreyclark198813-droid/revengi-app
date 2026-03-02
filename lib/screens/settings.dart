import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:revengi/l10n/app_localizations.dart';
import 'package:revengi/utils/theme_provider.dart';
import 'package:revengi/utils/language_provider.dart';
import 'package:revengi/utils/platform.dart';
import 'package:revengi/utils/background_task_manager.dart';

class SettingsScreen extends StatefulWidget {
  final String currentVersion;

  const SettingsScreen({super.key, required this.currentVersion});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _checkUpdate = false;
  bool _logEnabled = false;
  bool _backgroundEnabled = false;
  bool _wifiOnly = false;
  bool _requireCharging = false;
  String _ollamaBaseUrl = 'http://localhost:11434/api';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _checkUpdate = prefs.getBool('checkUpdate') ?? false;
      _logEnabled = prefs.getBool('logEnabled') ?? false;
      _backgroundEnabled =
          prefs.getBool(BackgroundTaskPrefs.enabledKey) ?? false;
      _wifiOnly = prefs.getBool(BackgroundTaskPrefs.wifiOnlyKey) ?? false;
      _requireCharging =
          prefs.getBool(BackgroundTaskPrefs.requireChargingKey) ?? false;
      _ollamaBaseUrl =
          prefs.getString('ollamaBaseUrl') ?? 'http://localhost:11434/api';
      _isLoading = false;
    });
  }

  String _getLanguageName(String languageCode) {
    switch (languageCode) {
      case 'en':
        return 'English';
      case 'es':
        return 'Espa\u00f1ol';
      case 'ar':
        return '\u0627\u0644\u0639\u0631\u0628\u064a\u0629';
      case 'af':
        return 'Afrikaans';
      case 'ca':
        return 'Catal\u00e0';
      case 'cs':
        return '\u010ce\u0161tina';
      case 'da':
        return 'Dansk';
      case 'de':
        return 'Deutsch';
      case 'el':
        return '\u0395\u03bb\u03bb\u03b7\u03bd\u03b9\u03ba\u03ac';
      case 'fi':
        return 'Suomi';
      case 'fr':
        return 'Fran\u00e7ais';
      case 'he':
        return '\u05e2\u05d1\u05e8\u05d9\u05ea';
      case 'hi':
        return '\u0939\u093f\u0928\u094d\u0926\u0940';
      case 'hu':
        return 'Magyar';
      case 'it':
        return 'Italiano';
      case 'ja':
        return '\u65e5\u672c\u8a9e';
      case 'ko':
        return '\ud55c\uad6d\uc5b4';
      case 'nl':
        return 'Nederlands';
      case 'no':
        return 'Norsk';
      case 'pl':
        return 'Polski';
      case 'pt':
        return 'Portugu\u00eas';
      case 'ro':
        return 'Rom\u00e2n\u0103';
      case 'ru':
        return '\u0420\u0443\u0441\u0441\u043a\u0438\u0439';
      case 'sr':
        return '\u0421\u0440\u043f\u0441\u043a\u0438';
      case 'sv':
        return 'Svenska';
      case 'tr':
        return 'T\u00fcrk\u00e7e';
      case 'uk':
        return '\u0423\u043a\u0440\u0430\u0457\u043d\u0441\u044c\u043a\u0430';
      case 'vi':
        return 'Ti\u1ebfng Vi\u1ec7t';
      case 'zh':
        return '\u4e2d\u6587';
      default:
        return languageCode.toUpperCase();
    }
  }

  String _getThemeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return 'System';
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
    }
  }

  IconData _getThemeIcon(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return Icons.brightness_auto;
      case ThemeMode.light:
        return Icons.light_mode;
      case ThemeMode.dark:
        return Icons.dark_mode;
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final themeMode = context.watch<ThemeProvider>().themeMode;
    final languageCode =
        context.watch<LanguageProvider>().locale.languageCode;

    if (_isLoading) {
      return Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            expandedHeight: 180,
            pinned: true,
            stretch: true,
            backgroundColor: theme.scaffoldBackgroundColor,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                localizations.settings,
                style: TextStyle(
                  color: theme.textTheme.titleLarge?.color,
                  fontWeight: FontWeight.bold,
                ),
              ),
              centerTitle: true,
              titlePadding: const EdgeInsets.only(bottom: 16),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          theme.colorScheme.primary.withValues(alpha: 0.15),
                          theme.scaffoldBackgroundColor,
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                  Positioned(
                    right: -20,
                    top: -20,
                    child: Opacity(
                      opacity: 0.1,
                      child: Icon(
                        Icons.settings,
                        size: 200,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 80),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- APPEARANCE ---
                  _SectionHeader(
                    title: localizations.appearance,
                    icon: Icons.palette_outlined,
                  ),
                  const SizedBox(height: 8),
                  _SettingsCard(
                    children: [
                      ListTile(
                        leading: Icon(
                          _getThemeIcon(themeMode),
                          color: theme.colorScheme.primary,
                        ),
                        title: Text(localizations.theme),
                        subtitle: Text(_getThemeLabel(themeMode)),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () =>
                            context.read<ThemeProvider>().toggleTheme(),
                      ),
                      Divider(height: 1, color: theme.dividerColor),
                      ListTile(
                        leading: Icon(
                          Icons.language,
                          color: theme.colorScheme.primary,
                        ),
                        title: Text(localizations.language(
                            languageCode.toUpperCase())),
                        subtitle: Text(_getLanguageName(languageCode)),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _showLanguagePicker(context),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // --- API CONFIGURATION ---
                  _SectionHeader(
                    title: localizations.apiConfiguration,
                    icon: Icons.api_outlined,
                  ),
                  const SizedBox(height: 8),
                  _SettingsCard(
                    children: [
                      ListTile(
                        leading: Icon(
                          Icons.link,
                          color: const Color(0xFF10B981),
                        ),
                        title: Text(localizations.ollama_api_url),
                        subtitle: Text(
                          _ollamaBaseUrl,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _showOllamaUrlDialog(context),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // --- BACKGROUND TASKS (Android only) ---
                  if (!isWeb() && isAndroid()) ...[
                    _SectionHeader(
                      title: localizations.backgroundTasks,
                      icon: Icons.schedule_outlined,
                    ),
                    const SizedBox(height: 8),
                    _SettingsCard(
                      children: [
                        SwitchListTile.adaptive(
                          secondary: Icon(
                            Icons.sync,
                            color: const Color(0xFF6366F1),
                          ),
                          title: Text(localizations.enableBackgroundProcessing),
                          subtitle: Text(
                            localizations.backgroundTasksDesc,
                          ),
                          value: _backgroundEnabled,
                          onChanged: (value) async {
                            await BackgroundTaskPrefs.setEnabled(value);
                            setState(() => _backgroundEnabled = value);
                          },
                        ),
                        if (_backgroundEnabled) ...[
                          Divider(height: 1, color: theme.dividerColor),
                          SwitchListTile.adaptive(
                            secondary: Icon(
                              Icons.wifi,
                              color: const Color(0xFF3B82F6),
                            ),
                            title: Text(localizations.wifiOnly),
                            subtitle: Text(
                              'Restrict background downloads to Wi-Fi',
                            ),
                            value: _wifiOnly,
                            onChanged: (value) async {
                              await BackgroundTaskPrefs.setWifiOnly(value);
                              setState(() => _wifiOnly = value);
                            },
                          ),
                          Divider(height: 1, color: theme.dividerColor),
                          SwitchListTile.adaptive(
                            secondary: Icon(
                              Icons.battery_charging_full,
                              color: const Color(0xFFF59E0B),
                            ),
                            title: Text(localizations.requireCharging),
                            subtitle: Text(
                              'Only run background tasks while charging',
                            ),
                            value: _requireCharging,
                            onChanged: (value) async {
                              await BackgroundTaskPrefs.setRequiresCharging(
                                  value);
                              setState(() => _requireCharging = value);
                            },
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 24),
                  ],

                  // --- UPDATES & MAINTENANCE ---
                  if (!isWeb()) ...[
                    _SectionHeader(
                      title: localizations.updatesAndMaintenance,
                      icon: Icons.system_update_outlined,
                    ),
                    const SizedBox(height: 8),
                    _SettingsCard(
                      children: [
                        SwitchListTile.adaptive(
                          secondary: Icon(
                            Icons.update,
                            color: const Color(0xFF14B8A6),
                          ),
                          title: Text(localizations.checkForUpdate),
                          subtitle: Text(
                            'Automatically check for new versions',
                          ),
                          value: _checkUpdate,
                          onChanged: (value) async {
                            final prefs =
                                await SharedPreferences.getInstance();
                            await prefs.setBool('checkUpdate', value);
                            setState(() => _checkUpdate = value);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                  ],

                  // --- DIAGNOSTICS ---
                  _SectionHeader(
                    title: localizations.diagnostics,
                    icon: Icons.bug_report_outlined,
                  ),
                  const SizedBox(height: 8),
                  _SettingsCard(
                    children: [
                      SwitchListTile.adaptive(
                        secondary: Icon(
                          Icons.bug_report,
                          color: const Color(0xFFEC4899),
                        ),
                        title: Text(
                          _logEnabled
                              ? localizations.disableLogs
                              : localizations.enableLogs,
                        ),
                        subtitle: Text(localizations.restartRequired),
                        value: _logEnabled,
                        onChanged: (value) async {
                          final prefs =
                              await SharedPreferences.getInstance();
                          await prefs.setBool('logEnabled', value);
                          setState(() => _logEnabled = value);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content:
                                  Text(localizations.restartRequired),
                            ),
                          );
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // --- ABOUT ---
                  _SectionHeader(
                    title: localizations.about,
                    icon: Icons.info_outlined,
                  ),
                  const SizedBox(height: 8),
                  _SettingsCard(
                    children: [
                      ListTile(
                        leading: Icon(
                          Icons.info_outline,
                          color: theme.colorScheme.primary,
                        ),
                        title: Text(localizations.version),
                        subtitle: Text(widget.currentVersion),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showLanguagePicker(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(localizations.selectLanguage),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: AppLocalizations.supportedLocales.map((locale) {
              return ListTile(
                title: Text(_getLanguageName(locale.languageCode)),
                trailing: context
                            .read<LanguageProvider>()
                            .locale
                            .languageCode ==
                        locale.languageCode
                    ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
                    : null,
                onTap: () {
                  context.read<LanguageProvider>().setLocale(locale);
                  Navigator.pop(context);
                },
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  void _showOllamaUrlDialog(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final localizations = AppLocalizations.of(context)!;
    if (!context.mounted) return;

    final controller = TextEditingController(text: _ollamaBaseUrl);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(localizations.ollama_api_url),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Enter API URL',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) async {
            await prefs.setString('ollamaBaseUrl', value);
            setState(() => _ollamaBaseUrl = value);
            if (context.mounted) Navigator.pop(context);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(localizations.cancel),
          ),
          TextButton(
            onPressed: () {
              prefs.remove('ollamaBaseUrl');
              setState(() =>
                  _ollamaBaseUrl = 'http://localhost:11434/api');
              Navigator.pop(context);
            },
            child: Text(localizations.reset),
          ),
          TextButton(
            onPressed: () async {
              await prefs.setString(
                  'ollamaBaseUrl', controller.text);
              setState(() => _ollamaBaseUrl = controller.text);
              if (context.mounted) Navigator.pop(context);
            },
            child: Text(localizations.save),
          ),
        ],
      ),
    );
  }
}

/// Section header with icon and title.
class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Card wrapper for settings groups.
class _SettingsCard extends StatelessWidget {
  final List<Widget> children;

  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: children,
      ),
    );
  }
}
