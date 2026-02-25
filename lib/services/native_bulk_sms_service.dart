import 'package:flutter/services.dart';
import 'package:sms/models/sms_progress.dart';

class NativeBulkSmsService {
  static const MethodChannel _channel = MethodChannel('sms_native');

  Future<void> startBulkSend({
    required List<String> numbers,
    required String message,
  }) async {
    await _channel.invokeMethod<void>(
      'startBulkSend',
      <String, dynamic>{
        'numbers': numbers,
        'message': message,
      },
    );
  }

  Future<void> stopBulkSend() async {
    await _channel.invokeMethod<void>('stopBulkSend');
  }

  Future<SmsProgress> getBulkStatus() async {
    final result = await _channel.invokeMapMethod<String, dynamic>('getBulkStatus');
    final map = result ?? <String, dynamic>{};

    return SmsProgress(
      state: SmsProgress.fromNativeState(map['state'] as String?),
      total: (map['total'] as num?)?.toInt() ?? 0,
      sent: (map['sent'] as num?)?.toInt() ?? 0,
      failed: (map['failed'] as num?)?.toInt() ?? 0,
      currentIndex: (map['currentIndex'] as num?)?.toInt() ?? 0,
      currentNumber: map['currentNumber'] as String?,
      message: map['message'] as String?,
    );
  }
}
