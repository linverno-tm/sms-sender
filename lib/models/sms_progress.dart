enum SmsSendState {
  idle,
  pending,
  sending,
  completed,
  stopped,
}

class SmsProgress {
  const SmsProgress({
    this.state = SmsSendState.idle,
    this.total = 0,
    this.sent = 0,
    this.failed = 0,
    this.currentIndex = 0,
    this.currentNumber,
    this.message,
  });

  final SmsSendState state;
  final int total;
  final int sent;
  final int failed;
  final int currentIndex;
  final String? currentNumber;
  final String? message;

  int get processed => sent + failed;
  int get remaining => (total - processed).clamp(0, total);

  double get percent {
    if (total == 0) {
      return 0;
    }
    return (processed / total) * 100;
  }

  SmsProgress copyWith({
    SmsSendState? state,
    int? total,
    int? sent,
    int? failed,
    int? currentIndex,
    String? currentNumber,
    String? message,
    bool clearCurrentNumber = false,
  }) {
    return SmsProgress(
      state: state ?? this.state,
      total: total ?? this.total,
      sent: sent ?? this.sent,
      failed: failed ?? this.failed,
      currentIndex: currentIndex ?? this.currentIndex,
      currentNumber: clearCurrentNumber ? null : (currentNumber ?? this.currentNumber),
      message: message ?? this.message,
    );
  }

  static SmsSendState fromNativeState(String? value) {
    switch ((value ?? '').toLowerCase()) {
      case 'pending':
        return SmsSendState.pending;
      case 'sending':
        return SmsSendState.sending;
      case 'completed':
        return SmsSendState.completed;
      case 'stopped':
        return SmsSendState.stopped;
      default:
        return SmsSendState.idle;
    }
  }
}
