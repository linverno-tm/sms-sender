import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

class UiErrorState {
  const UiErrorState({
    required this.message,
    required this.timestamp,
  });

  final String message;
  final DateTime timestamp;
}

class ErrorReporter {
  static final ValueNotifier<UiErrorState?> latestError = ValueNotifier<UiErrorState?>(null);
  static UiErrorState? _pendingValue;
  static bool _flushScheduled = false;

  static void report(
    Object error,
    StackTrace stackTrace, {
    String? userMessage,
    String? context,
  }) {
    final where = context == null || context.trim().isEmpty ? 'unknown' : context.trim();
    debugPrint('[APP_ERROR][$where] $error');
    debugPrintStack(stackTrace: stackTrace);

    final message = userMessage?.trim().isNotEmpty == true
        ? userMessage!.trim()
        : 'Kutilmagan xatolik yuz berdi: $error';
    _setLatestErrorSafely(UiErrorState(message: message, timestamp: DateTime.now()));
  }

  static void clear() {
    _setLatestErrorSafely(null);
  }

  static void installGlobalHandlers() {
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      report(
        details.exception,
        details.stack ?? StackTrace.current,
        context: 'FlutterError',
      );
    };

    PlatformDispatcher.instance.onError = (Object error, StackTrace stackTrace) {
      report(error, stackTrace, context: 'PlatformDispatcher');
      return true;
    };
  }

  static void _setLatestErrorSafely(UiErrorState? value) {
    _pendingValue = value;
    if (_flushScheduled) {
      return;
    }
    _flushScheduled = true;

    final binding = WidgetsBinding.instance;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle || phase == SchedulerPhase.postFrameCallbacks) {
      _flushPending();
      return;
    }

    binding.addPostFrameCallback((_) {
      _flushPending();
    });
  }

  static void _flushPending() {
    _flushScheduled = false;
    latestError.value = _pendingValue;
    _pendingValue = null;
  }
}
