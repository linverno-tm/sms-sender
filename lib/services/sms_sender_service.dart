import 'dart:async';

import 'package:another_telephony/telephony.dart';
import 'package:sms/models/sms_progress.dart';

class SmsSenderService {
  SmsSenderService({Telephony? telephony})
      : _telephony = telephony ?? Telephony.instance;

  final Telephony _telephony;
  bool _isCancelled = false;

  Future<bool> ensurePermissions() async {
    try {
      final bool? granted = await _telephony.requestPhoneAndSmsPermissions;
      return granted ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> sendInQueue({
    required List<String> numbers,
    required String message,
    required void Function(SmsProgress progress) onProgress,
  }) async {
    _isCancelled = false;
    var sent = 0;
    var failed = 0;

    onProgress(
      SmsProgress(
        state: SmsSendState.sending,
        total: numbers.length,
        sent: 0,
        failed: 0,
      ),
    );

    for (var i = 0; i < numbers.length; i++) {
      if (_isCancelled) {
        break;
      }

      final number = numbers[i];
      final wasSent = await _sendSingle(number: number, message: message);

      if (wasSent) {
        sent++;
      } else {
        failed++;
      }

      onProgress(
        SmsProgress(
          state: SmsSendState.sending,
          total: numbers.length,
          sent: sent,
          failed: failed,
          currentNumber: number,
        ),
      );

      if (i < numbers.length - 1) {
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    }

    onProgress(
      SmsProgress(
        state: SmsSendState.completed,
        total: numbers.length,
        sent: sent,
        failed: failed,
      ),
    );
  }

  void cancel() {
    _isCancelled = true;
  }

  Future<bool> _sendSingle({
    required String number,
    required String message,
  }) async {
    final completer = Completer<bool>();

    try {
      await _telephony.sendSms(
        to: number,
        message: message,
        isMultipart: true,
        statusListener: (SendStatus status) {
          if (status == SendStatus.SENT || status == SendStatus.DELIVERED) {
            if (!completer.isCompleted) {
              completer.complete(true);
            }
          }
        },
      );

      return await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () => false,
      );
    } catch (_) {
      return false;
    }
  }
}
