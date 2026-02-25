import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:sms/core/app_strings.dart';
import 'package:sms/models/imported_file.dart';
import 'package:sms/models/sms_progress.dart';
import 'package:sms/services/file_parser_service.dart';
import 'package:sms/services/native_bulk_sms_service.dart';
import 'package:sms/services/sms_sender_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final FileParserService _parserService = FileParserService();
  final SmsSenderService _smsSenderService = SmsSenderService();
  final NativeBulkSmsService _nativeBulkSmsService = NativeBulkSmsService();
  final TextEditingController _messageController = TextEditingController();

  final List<ImportedFile> _files = <ImportedFile>[];
  final Set<String> _filePaths = <String>{};

  StreamSubscription<List<SharedMediaFile>>? _mediaSubscription;
  Timer? _statusTimer;
  SmsProgress _progress = const SmsProgress();
  bool _isImporting = false;
  SmsSendState _lastState = SmsSendState.idle;

  @override
  void initState() {
    super.initState();
    _listenShareIntent();
    _startStatusPolling();
  }

  @override
  void dispose() {
    _mediaSubscription?.cancel();
    _statusTimer?.cancel();
    _messageController.dispose();
    super.dispose();
  }

  void _startStatusPolling() {
    _refreshBulkStatus();
    _statusTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _refreshBulkStatus();
    });
  }

  Future<void> _refreshBulkStatus() async {
    try {
      final status = await _nativeBulkSmsService.getBulkStatus();
      if (!mounted) {
        return;
      }
      setState(() {
        _progress = status;
      });

      if (_lastState == SmsSendState.sending && status.state == SmsSendState.completed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppStrings.sendCompleted(
              sentCount: status.sent,
              failedCount: status.failed,
              totalCount: status.total,
            )),
          ),
        );
      }
      _lastState = status.state;
    } catch (_) {}
  }

  Future<void> _listenShareIntent() async {
    _mediaSubscription = ReceiveSharingIntent.instance.getMediaStream().listen(
      (List<SharedMediaFile> files) {
        _importSharedFiles(files);
      },
      onError: (_) {
        _showError(AppStrings.sharedFileReadError);
      },
    );

    try {
      final initialFiles = await ReceiveSharingIntent.instance.getInitialMedia();
      if (initialFiles.isNotEmpty) {
        await _importSharedFiles(initialFiles);
      }
      await ReceiveSharingIntent.instance.reset();
    } catch (_) {
      if (!mounted) {
        return;
      }
      _showError(AppStrings.initialShareReadError);
    }
  }

  Future<void> _pickFiles() async {
    setState(() {
      _isImporting = true;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: true,
        type: FileType.custom,
        allowedExtensions: FileParserService.supportedExtensions.toList(),
      );

      if (result == null) {
        return;
      }

      final selectedFiles = result.files;
      for (final file in selectedFiles) {
        final path = file.path;
        if (path == null || path.isEmpty) {
          continue;
        }
        final bytes = file.bytes ?? await File(path).readAsBytes();
        await _importSingleFile(
          path: path,
          name: file.name,
          bytes: bytes,
        );
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      _showError(AppStrings.pickFileError);
    } finally {
      if (mounted) {
        setState(() {
          _isImporting = false;
        });
      }
    }
  }

  Future<void> _importSharedFiles(List<SharedMediaFile> sharedFiles) async {
    if (sharedFiles.isEmpty) {
      return;
    }

    setState(() {
      _isImporting = true;
    });

    try {
      for (final shared in sharedFiles) {
        final path = shared.path;
        if (path.isEmpty) {
          continue;
        }
        final file = File(path);
        if (!await file.exists()) {
          continue;
        }

        final bytes = await file.readAsBytes();
        await _importSingleFile(path: path, name: path, bytes: bytes);
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      _showError(AppStrings.importSharedFileError);
    } finally {
      if (mounted) {
        setState(() {
          _isImporting = false;
        });
      }
    }
  }

  Future<void> _importSingleFile({
    required String path,
    required String name,
    required Uint8List bytes,
  }) async {
    final normalizedPath = path.trim();
    if (_filePaths.contains(normalizedPath)) {
      return;
    }

    final extension = _extractExtension(name, path);
    if (!FileParserService.supportedExtensions.contains(extension)) {
      return;
    }

    try {
      final parseResult = await _parserService.parse(extension: extension, bytes: bytes);
      final importedFile = ImportedFile(
        path: normalizedPath,
        name: _extractName(name, path),
        extension: extension,
        validNumbers: parseResult.validNumbers,
        invalidCount: parseResult.invalidCount,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _files.add(importedFile);
        _filePaths.add(normalizedPath);
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      final importedFile = ImportedFile(
        path: normalizedPath,
        name: _extractName(name, path),
        extension: extension,
        validNumbers: <String>{},
        invalidCount: 0,
        errorMessage: AppStrings.fileReadError,
      );

      setState(() {
        _files.add(importedFile);
        _filePaths.add(normalizedPath);
      });
    }
  }

  String _extractName(String name, String path) {
    if (name.trim().isNotEmpty) {
      final segments = name.split(RegExp(r'[\\/]'));
      return segments.isEmpty ? name : segments.last;
    }
    final segments = path.split(RegExp(r'[\\/]'));
    return segments.isEmpty ? path : segments.last;
  }

  String _extractExtension(String name, String path) {
    final fileName = _extractName(name, path).toLowerCase();
    final parts = fileName.split('.');
    if (parts.length < 2) {
      return '';
    }
    return parts.last;
  }

  Set<String> get _allUniqueNumbers {
    final numbers = <String>{};
    for (final file in _files) {
      numbers.addAll(file.validNumbers);
    }
    return numbers;
  }

  int get _invalidTotal {
    var total = 0;
    for (final file in _files) {
      total += file.invalidCount;
    }
    return total;
  }

  Future<void> _sendSms() async {
    final message = _messageController.text.trim();
    final numbers = _allUniqueNumbers.toList()..sort();

    if (message.isEmpty) {
      _showError(AppStrings.enterSmsText);
      return;
    }

    if (numbers.isEmpty) {
      _showError(AppStrings.noValidNumber);
      return;
    }

    final hasPermission = await _smsSenderService.ensurePermissions();
    if (!hasPermission) {
      if (!mounted) {
        return;
      }
      _showError(AppStrings.smsPermissionDenied);
      return;
    }

    try {
      await _nativeBulkSmsService.startBulkSend(numbers: numbers, message: message);
      await _refreshBulkStatus();
    } catch (_) {
      if (!mounted) {
        return;
      }
      _showError(AppStrings.startSendError);
    }
  }

  Future<void> _stopSms() async {
    try {
      await _nativeBulkSmsService.stopBulkSend();
      await _refreshBulkStatus();
    } catch (_) {
      if (!mounted) {
        return;
      }
      _showError(AppStrings.stopSendError);
    }
  }

  void _removeFile(ImportedFile file) {
    setState(() {
      _files.removeWhere((item) => item.path == file.path);
      _filePaths.remove(file.path);
    });
  }

  void _clearAll() {
    unawaited(_nativeBulkSmsService.stopBulkSend());
    setState(() {
      _files.clear();
      _filePaths.clear();
    });
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uniqueNumbers = _allUniqueNumbers;
    final isSending = _progress.state == SmsSendState.sending;
    final canSend = !isSending;
    final stateKey = switch (_progress.state) {
      SmsSendState.sending => 'sending',
      SmsSendState.completed => 'completed',
      SmsSendState.stopped => 'stopped',
      SmsSendState.pending => 'pending',
      SmsSendState.idle => 'idle',
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.appTitle),
        actions: [
          TextButton(
            onPressed: _files.isEmpty && _progress.state == SmsSendState.pending ? null : _clearAll,
            child: const Text(AppStrings.clear),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 420;
            final isShort = constraints.maxHeight < 760;
            final horizontalPadding = isNarrow ? 12.0 : 16.0;
            final listHeight = isShort ? 160.0 : 220.0;
            final minLines = isShort ? 3 : 4;
            final maxLines = isShort ? 4 : 5;

            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(horizontalPadding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FilledButton.icon(
                        onPressed: _isImporting ? null : _pickFiles,
                        icon: const Icon(Icons.upload_file),
                        label: const Text(AppStrings.uploadPhoneFile),
                      ),
                      const SizedBox(height: 10),
                      if (_isImporting) const LinearProgressIndicator(),
                      if (_isImporting)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(AppStrings.importingFile),
                        ),
                      const SizedBox(height: 10),
                      Text(
                        AppStrings.uploadedFiles,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: listHeight,
                        child: _files.isEmpty
                            ? const Center(
                                child: Text(AppStrings.noFilesYet),
                              )
                            : ListView.separated(
                                itemCount: _files.length,
                                separatorBuilder: (context, index) => const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final file = _files[index];
                                  final sortedNumbers = file.validNumbers.toList()..sort();
                                  return Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: Theme.of(context).colorScheme.outlineVariant,
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                file.name,
                                                style: Theme.of(context).textTheme.titleSmall,
                                              ),
                                            ),
                                            IconButton(
                                              onPressed: () => _removeFile(file),
                                              icon: const Icon(Icons.delete_outline),
                                            ),
                                          ],
                                        ),
                                        Text(
                                          file.errorMessage ??
                                              AppStrings.fileCount(
                                                validCount: file.validCount,
                                                invalidCount: file.invalidCount,
                                              ),
                                        ),
                                        const SizedBox(height: 8),
                                        if (sortedNumbers.isEmpty)
                                          const Text('-')
                                        else
                                          ConstrainedBox(
                                            constraints: const BoxConstraints(maxHeight: 120),
                                            child: ListView.builder(
                                              shrinkWrap: true,
                                              primary: false,
                                              itemCount: sortedNumbers.length,
                                              itemBuilder: (context, numberIndex) {
                                                return Padding(
                                                  padding: const EdgeInsets.symmetric(vertical: 1),
                                                  child: Text(sortedNumbers[numberIndex]),
                                                );
                                              },
                                            ),
                                          ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        AppStrings.smsText,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _messageController,
                        maxLines: maxLines,
                        minLines: minLines,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: AppStrings.smsHint,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _StatusPanel(
                        progress: _progress,
                        stateKey: stateKey,
                        totalUniqueNumbers: uniqueNumbers.length,
                        invalidTotal: _invalidTotal,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 54,
                              child: FilledButton(
                                onPressed: canSend ? _sendSms : null,
                                child: Text(
                                  _progress.state == SmsSendState.sending ? AppStrings.sending : AppStrings.send,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: SizedBox(
                              height: 54,
                              child: OutlinedButton(
                                onPressed: isSending ? _stopSms : null,
                                child: const Text(AppStrings.stop),
                              ),
                            ),
                          ),
                        ],
                      ),

                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({
    required this.progress,
    required this.stateKey,
    required this.totalUniqueNumbers,
    required this.invalidTotal,
  });

  final SmsProgress progress;
  final String stateKey;
  final int totalUniqueNumbers;
  final int invalidTotal;

  @override
  Widget build(BuildContext context) {
    final total = progress.total == 0 ? totalUniqueNumbers : progress.total;
    final percentText = progress.percent.toStringAsFixed(1);
    final remaining = progress.total == 0 ? totalUniqueNumbers : progress.remaining;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(AppStrings.statusPanel, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Text(AppStrings.labelWithCount(AppStrings.currentState, AppStrings.stateText(stateKey))),
          Text(AppStrings.labelWithCount(AppStrings.totalCount, total)),
          Text(AppStrings.labelWithCount(AppStrings.sent, progress.sent)),
          Text(AppStrings.labelWithCount(AppStrings.failed, progress.failed)),
          Text(AppStrings.labelWithCount(AppStrings.remaining, remaining)),
          Text(AppStrings.percentText(percentText)),
          const SizedBox(height: 8),
          Text(AppStrings.labelWithCount(AppStrings.totalValidNumbers, totalUniqueNumbers)),
          Text(AppStrings.labelWithCount(AppStrings.totalInvalidValues, invalidTotal)),
          if (progress.currentNumber != null)
            Text(AppStrings.labelWithCount(AppStrings.lastNumber, progress.currentNumber!)),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: total == 0 ? 0 : (progress.processed / total),
          ),
        ],
      ),
    );
  }
}
