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
  final _urlController = TextEditingController();
  final _fileNameController = TextEditingController();
  final _headersController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isProcessing = false;
  bool _useBackground = true;
  String? _activeWorkId;
  BackgroundTaskStatus? _currentStatus;
  VoidCallback? _cancelPoll;
  final List<_FetchHistoryEntry> _history = [];

  @override
  void initState() {
    super.initState();
    _checkBackgroundEnabled();
  }

  Future<void> _checkBackgroundEnabled() async {
    final enabled = await BackgroundTaskPreferences.isEnabled();
    if (mounted) {
      setState(() {
        _useBackground = enabled;
      });
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _fileNameController.dispose();
    _headersController.dispose();
    _cancelPoll?.call();
    super.dispose();
  }

  Future<void> _startFetch() async {
    if (!_formKey.currentState!.validate()) return;

    final url = _urlController.text.trim();
    final fileName =
        _fileNameController.text.trim().isEmpty
            ? null
            : _fileNameController.text.trim();
    final headers =
        _headersController.text.trim().isEmpty
            ? null
            : _headersController.text.trim();
    final outputPath = await getDownloadsDirectory();

    // Ensure output directory exists
    final dir = Directory(outputPath);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    setState(() {
      _isProcessing = true;
      _currentStatus = null;
    });

    if (_useBackground && BackgroundTaskManager.isSupported) {
      // Request notification permission first
      await BackgroundTaskManager.requestNotificationPermission();

      final workId = await BackgroundTaskManager.scheduleUrlFetch(
        url: url,
        outputPath: outputPath,
        fileName: fileName,
        headers: headers,
      );

      if (workId != null) {
        setState(() {
          _activeWorkId = workId;
        });

        _history.insert(
          0,
          _FetchHistoryEntry(
            url: url,
            workId: workId,
            timestamp: DateTime.now(),
            state: 'ENQUEUED',
          ),
        );

        _cancelPoll = BackgroundTaskManager.pollTaskStatus(workId, (status) {
          if (mounted) {
            setState(() {
              _currentStatus = status;
              if (_history.isNotEmpty && _history[0].workId == workId) {
                _history[0].state = status.state;
                _history[0].resultPath = status.resultPath;
              }
              if (status.isCompleted) {
                _isProcessing = false;
                _activeWorkId = null;
              }
            });
          }
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Download scheduled in background'),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
      } else {
        setState(() {
          _isProcessing = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Failed to schedule background download. Is background processing enabled?',
              ),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Theme.of(context).colorScheme.error,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
      }
    } else {
      // Foreground download (simple progress)
      _performForegroundFetch(url, outputPath, fileName, headers);
    }
  }

  Future<void> _performForegroundFetch(
    String url,
    String outputPath,
    String? fileName,
    String? headers,
  ) async {
    try {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set('User-Agent', 'RevEngi-App/1.0');

      if (headers != null) {
        for (final header in headers.split(';')) {
          final parts = header.split(':');
          if (parts.length == 2) {
            request.headers.set(parts[0].trim(), parts[1].trim());
          }
        }
      }

      final response = await request.close();
      final resolvedName =
          fileName ?? url.split('/').last.split('?').first;
      final outputFile = File('$outputPath/$resolvedName');

      final totalBytes = response.contentLength;
      var downloadedBytes = 0;
      final sink = outputFile.openWrite();

      await for (final chunk in response) {
        sink.add(chunk);
        downloadedBytes += chunk.length;

        if (mounted) {
          final percent =
              totalBytes > 0
                  ? ((downloadedBytes * 100) / totalBytes).toInt()
                  : -1;
          setState(() {
            _currentStatus = BackgroundTaskStatus(
              workId: 'foreground',
              state: 'RUNNING',
              progressPercent: percent,
              progressBytes: downloadedBytes,
              progressTotal: totalBytes,
            );
          });
        }
      }

      await sink.flush();
      await sink.close();
      client.close();

      _history.insert(
        0,
        _FetchHistoryEntry(
          url: url,
          workId: 'foreground',
          timestamp: DateTime.now(),
          state: 'SUCCEEDED',
          resultPath: outputFile.path,
        ),
      );

      if (mounted) {
        setState(() {
          _isProcessing = false;
          _currentStatus = BackgroundTaskStatus(
            workId: 'foreground',
            state: 'SUCCEEDED',
            resultPath: outputFile.path,
            downloadedBytes: downloadedBytes,
          );
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Downloaded to: ${outputFile.path}'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _currentStatus = BackgroundTaskStatus(
            workId: 'foreground',
            state: 'FAILED',
            errorMessage: e.toString(),
          );
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download failed: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Theme.of(context).colorScheme.error,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }

  void _cancelCurrentTask() {
    if (_activeWorkId != null) {
      BackgroundTaskManager.cancelTask(_activeWorkId!);
      _cancelPoll?.call();
      setState(() {
        _isProcessing = false;
        _activeWorkId = null;
        _currentStatus = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: const Text('URL Fetch'), centerTitle: true),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // -- URL Input Form --
                _buildFormSection(theme),
                const SizedBox(height: 16),

                // -- Progress Section --
                if (_currentStatus != null) ...[
                  _buildProgressSection(theme),
                  const SizedBox(height: 16),
                ],

                // -- Action Buttons --
                _buildActionButtons(theme, l10n),
                const SizedBox(height: 24),

                // -- Fetch History --
                if (_history.isNotEmpty) ...[
                  Text(
                    'Recent Downloads',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ..._history.map((entry) => _buildHistoryTile(theme, entry)),
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormSection(ThemeData theme) {
    return Form(
      key: _formKey,
      child: Card(
        elevation: 0,
        color: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: theme.dividerColor),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.download_rounded,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Download Configuration',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Fetch APK or resource files from URLs',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.textTheme.bodySmall?.color?.withValues(
                              alpha: 0.6,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // URL field
              TextFormField(
                controller: _urlController,
                decoration: InputDecoration(
                  labelText: 'URL',
                  hintText: 'https://example.com/file.apk',
                  prefixIcon: const Icon(Icons.link),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                keyboardType: TextInputType.url,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a URL';
                  }
                  final uri = Uri.tryParse(value.trim());
                  if (uri == null || !uri.hasScheme) {
                    return 'Please enter a valid URL';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // File name field (optional)
              TextFormField(
                controller: _fileNameController,
                decoration: InputDecoration(
                  labelText: 'File Name (optional)',
                  hintText: 'custom_name.apk',
                  prefixIcon: const Icon(Icons.insert_drive_file_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Custom headers (optional, advanced)
              TextFormField(
                controller: _headersController,
                decoration: InputDecoration(
                  labelText: 'Headers (optional)',
                  hintText: 'Authorization: Bearer token',
                  prefixIcon: const Icon(Icons.code),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  helperText: 'Semicolon-separated key:value pairs',
                ),
                maxLines: 1,
              ),
              const SizedBox(height: 16),

              // Background toggle
              if (BackgroundTaskManager.isSupported)
                SwitchListTile(
                  title: const Text('Background Download'),
                  subtitle: const Text(
                    'Continue downloading when app is minimized',
                  ),
                  value: _useBackground,
                  onChanged:
                      _isProcessing
                          ? null
                          : (value) => setState(() => _useBackground = value),
                  secondary: Icon(
                    Icons.cloud_download_outlined,
                    color: theme.colorScheme.primary,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProgressSection(ThemeData theme) {
    final status = _currentStatus!;
    final percent = status.progressPercent;
    final isIndeterminate = percent < 0;

    Color stateColor;
    IconData stateIcon;
    String stateLabel;

    if (status.isRunning) {
      stateColor = theme.colorScheme.primary;
      stateIcon = Icons.downloading;
      stateLabel =
          isIndeterminate
              ? 'Downloading...'
              : 'Downloading... $percent%';
    } else if (status.isSucceeded) {
      stateColor = Colors.green;
      stateIcon = Icons.check_circle;
      stateLabel = 'Download Complete';
    } else if (status.isFailed) {
      stateColor = theme.colorScheme.error;
      stateIcon = Icons.error;
      stateLabel = status.errorMessage ?? 'Download Failed';
    } else if (status.isCancelled) {
      stateColor = Colors.orange;
      stateIcon = Icons.cancel;
      stateLabel = 'Download Cancelled';
    } else if (status.isEnqueued) {
      stateColor = Colors.blue;
      stateIcon = Icons.schedule;
      stateLabel = 'Scheduled - Waiting for constraints';
    } else {
      stateColor = theme.colorScheme.onSurface;
      stateIcon = Icons.info;
      stateLabel = status.state;
    }

    return Card(
      elevation: 0,
      color: stateColor.withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: stateColor.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(stateIcon, color: stateColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    stateLabel,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: stateColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            if (status.isRunning) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child:
                    isIndeterminate
                        ? const LinearProgressIndicator()
                        : LinearProgressIndicator(value: percent / 100.0),
              ),
              if (status.progressBytes > 0) ...[
                const SizedBox(height: 8),
                Text(
                  _formatBytes(status.progressBytes) +
                      (status.progressTotal > 0
                          ? ' / ${_formatBytes(status.progressTotal)}'
                          : ''),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.textTheme.bodySmall?.color?.withValues(
                      alpha: 0.6,
                    ),
                  ),
                ),
              ],
            ],
            if (status.isSucceeded && status.resultPath != null) ...[
              const SizedBox(height: 8),
              Text(
                'Saved to: ${status.resultPath}',
                style: theme.textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(ThemeData theme, AppLocalizations l10n) {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: _isProcessing ? null : _startFetch,
            icon: const Icon(Icons.download),
            label: Text(_isProcessing ? 'Downloading...' : 'Fetch'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
        if (_isProcessing && _activeWorkId != null) ...[
          const SizedBox(width: 12),
          FilledButton.tonalIcon(
            onPressed: _cancelCurrentTask,
            icon: const Icon(Icons.cancel_outlined),
            label: Text(l10n.cancel),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildHistoryTile(ThemeData theme, _FetchHistoryEntry entry) {
    Color stateColor;
    IconData stateIcon;

    switch (entry.state) {
      case 'SUCCEEDED':
        stateColor = Colors.green;
        stateIcon = Icons.check_circle_outline;
        break;
      case 'FAILED':
        stateColor = theme.colorScheme.error;
        stateIcon = Icons.error_outline;
        break;
      case 'RUNNING':
        stateColor = theme.colorScheme.primary;
        stateIcon = Icons.downloading;
        break;
      case 'CANCELLED':
        stateColor = Colors.orange;
        stateIcon = Icons.cancel_outlined;
        break;
      default:
        stateColor = theme.colorScheme.onSurface.withValues(alpha: 0.5);
        stateIcon = Icons.schedule;
    }

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.dividerColor),
      ),
      child: ListTile(
        leading: Icon(stateIcon, color: stateColor),
        title: Text(
          entry.url,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          '${_formatTime(entry.timestamp)} - ${entry.state}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: stateColor.withValues(alpha: 0.8),
          ),
        ),
        trailing:
            entry.resultPath != null
                ? Icon(
                  Icons.folder_open,
                  color: theme.colorScheme.primary,
                  size: 20,
                )
                : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _FetchHistoryEntry {
  final String url;
  final String workId;
  final DateTime timestamp;
  String state;
  String? resultPath;

  _FetchHistoryEntry({
    required this.url,
    required this.workId,
    required this.timestamp,
    required this.state,
    this.resultPath,
  });
}
