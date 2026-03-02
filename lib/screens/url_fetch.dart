import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:revengi/l10n/app_localizations.dart';
import 'package:revengi/utils/background_task_manager.dart';
import 'package:revengi/utils/platform.dart';

class UrlFetchScreen extends StatefulWidget {
  const UrlFetchScreen({super.key});

  @override
  State<UrlFetchScreen> createState() => _UrlFetchScreenState();
}

class _UrlFetchScreenState extends State<UrlFetchScreen> {
  final TextEditingController _urlController = TextEditingController();
  final List<_FetchTask> _tasks = [];
  bool _backgroundMode = false;
  bool _backgroundAvailable = false;

  @override
  void initState() {
    super.initState();
    _checkBackgroundAvailability();
  }

  Future<void> _checkBackgroundAvailability() async {
    if (!isWeb() && isAndroid()) {
      final enabled = await BackgroundTaskPrefs.isEnabled();
      setState(() => _backgroundAvailable = enabled);
    }
  }

  Future<String> _getOutputDirectory() async {
    if (isAndroid()) {
      final dir = Directory('/storage/emulated/0/Download/RevEngi');
      if (!dir.existsSync()) await dir.create(recursive: true);
      return dir.path;
    }
    final dir = Directory.systemTemp.createTempSync('url_fetch_');
    return dir.path;
  }

  Future<void> _startFetch() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    if (!Uri.tryParse(url)!.hasScheme) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid URL with scheme (https://...)')),
      );
      return;
    }

    final outputPath = await _getOutputDirectory();

    if (_backgroundMode && _backgroundAvailable) {
      final workId = await BackgroundTaskManager.scheduleUrlFetch(
        url: url,
        outputPath: outputPath,
      );

      if (workId != null) {
        final task = _FetchTask(
          url: url,
          workId: workId,
          isBackground: true,
        );

        setState(() {
          _tasks.insert(0, task);
          _urlController.clear();
        });

        _watchBackgroundTask(task);
      }
    } else {
      // Foreground fetch -- schedule via WorkManager but treat as immediate
      final workId = await BackgroundTaskManager.scheduleUrlFetch(
        url: url,
        outputPath: outputPath,
      );

      if (workId != null) {
        final task = _FetchTask(
          url: url,
          workId: workId,
          isBackground: false,
        );

        setState(() {
          _tasks.insert(0, task);
          _urlController.clear();
        });

        _watchBackgroundTask(task);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to schedule download. Check if background processing is enabled in Settings.'),
          ),
        );
      }
    }
  }

  void _watchBackgroundTask(_FetchTask task) {
    task.subscription = BackgroundTaskManager.watchTaskStatus(
      task.workId,
      interval: const Duration(seconds: 1),
    ).listen((status) {
      if (!mounted) return;
      setState(() {
        task.state = status.state;
        task.progressPercent = status.progressPercent;
        task.resultPath = status.resultPath;
        task.errorMessage = status.errorMessage;
      });
    });
  }

  @override
  void dispose() {
    _urlController.dispose();
    for (final task in _tasks) {
      task.subscription?.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

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
                localizations.backgroundUrlFetching,
                style: TextStyle(
                  color: theme.textTheme.titleLarge?.color,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
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
                        Icons.cloud_download,
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
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // URL input card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: theme.dividerColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          localizations.backgroundUrlFetchingDesc,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.textTheme.bodyMedium?.color
                                ?.withValues(alpha: 0.7),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _urlController,
                          decoration: InputDecoration(
                            labelText: 'URL',
                            hintText: 'https://example.com/file.apk',
                            filled: true,
                            fillColor:
                                theme.colorScheme.surfaceContainerHighest,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            prefixIcon: const Icon(Icons.link),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                          ),
                          keyboardType: TextInputType.url,
                          onSubmitted: (_) => _startFetch(),
                        ),
                        if (_backgroundAvailable) ...[
                          const SizedBox(height: 12),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              'Background download',
                              style: theme.textTheme.bodyMedium,
                            ),
                            subtitle: Text(
                              'Continue downloading when app is closed',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.textTheme.bodySmall?.color
                                    ?.withValues(alpha: 0.6),
                              ),
                            ),
                            value: _backgroundMode,
                            onChanged: (value) =>
                                setState(() => _backgroundMode = value),
                          ),
                        ],
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 52,
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            icon: Icon(
                              _backgroundMode
                                  ? Icons.cloud_download
                                  : Icons.download,
                            ),
                            label: Text(
                              _backgroundMode
                                  ? 'Fetch in Background'
                                  : 'Fetch',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            onPressed: _urlController.text.trim().isNotEmpty
                                ? _startFetch
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: theme.colorScheme.primary,
                              foregroundColor: theme.colorScheme.onPrimary,
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  if (_tasks.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text(
                      'Downloads',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.textTheme.titleSmall?.color
                            ?.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
          ),
          // Task list
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => _TaskCard(
                  task: _tasks[index],
                  onCancel: () async {
                    await BackgroundTaskManager.cancelTask(
                        _tasks[index].workId);
                    setState(() {
                      _tasks[index].state = 'CANCELLED';
                    });
                  },
                ),
                childCount: _tasks.length,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FetchTask {
  final String url;
  final String workId;
  final bool isBackground;
  String state;
  int progressPercent;
  String? resultPath;
  String? errorMessage;
  StreamSubscription? subscription;

  _FetchTask({
    required this.url,
    required this.workId,
    required this.isBackground,
    this.state = 'ENQUEUED',
    this.progressPercent = -1,
    this.resultPath,
    this.errorMessage,
  });
}

class _TaskCard extends StatelessWidget {
  final _FetchTask task;
  final VoidCallback onCancel;

  const _TaskCard({required this.task, required this.onCancel});

  Color _stateColor(ThemeData theme) {
    switch (task.state) {
      case 'SUCCEEDED':
        return const Color(0xFF10B981);
      case 'FAILED':
        return const Color(0xFFEF4444);
      case 'CANCELLED':
        return const Color(0xFF6B7280);
      case 'RUNNING':
        return const Color(0xFF3B82F6);
      default:
        return const Color(0xFFF59E0B);
    }
  }

  IconData _stateIcon() {
    switch (task.state) {
      case 'SUCCEEDED':
        return Icons.check_circle;
      case 'FAILED':
        return Icons.error;
      case 'CANCELLED':
        return Icons.cancel;
      case 'RUNNING':
        return Icons.downloading;
      default:
        return Icons.hourglass_empty;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stateColor = _stateColor(theme);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_stateIcon(), size: 20, color: stateColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    task.url,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (task.isBackground)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'BG',
                      style: TextStyle(
                        color: const Color(0xFF6366F1),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            if (task.state == 'RUNNING' && task.progressPercent >= 0) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: task.progressPercent / 100,
                  backgroundColor: stateColor.withValues(alpha: 0.1),
                  valueColor: AlwaysStoppedAnimation(stateColor),
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${task.progressPercent}%',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: stateColor,
                ),
              ),
            ] else if (task.state == 'RUNNING') ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  backgroundColor: stateColor.withValues(alpha: 0.1),
                  valueColor: AlwaysStoppedAnimation(stateColor),
                  minHeight: 6,
                ),
              ),
            ],
            if (task.resultPath != null) ...[
              const SizedBox(height: 8),
              Text(
                'Saved: ${task.resultPath}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF10B981),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (task.errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                task.errorMessage!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFFEF4444),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (task.state == 'RUNNING' || task.state == 'ENQUEUED') ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  icon: const Icon(Icons.cancel_outlined, size: 16),
                  label: const Text('Cancel'),
                  onPressed: onCancel,
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFEF4444),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
