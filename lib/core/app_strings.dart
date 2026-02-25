class AppStrings {
  static const appTitle = 'Оммавий СМС';
  static const uploadPhoneFile = 'Телефон рақамлар файлини юклаш';
  static const clear = 'Тозалаш';
  static const importingFile = 'Файл юкланмоқда...';
  static const uploadedFiles = 'Юкланган файллар';
  static const noFilesYet = 'Ҳали файл юкланмаган';
  static const smsText = 'СМС матни';
  static const smsHint = 'Хабар матнини киритинг...';
  static const send = 'Юбориш';
  static const stop = 'Тўхтатиш';
  static const sending = 'Юборилмоқда...';
  static const statusPanel = 'Ҳолат панели';
  static const currentState = 'Жорий ҳолат';
  static const totalCount = 'Умумий сони';
  static const totalValidNumbers = 'Умумий тўғри рақамлар';
  static const totalInvalidValues = 'Умумий нотўғри қийматлар';
  static const pending = 'Кутилмоқда';
  static const inProgress = 'Юборилмоқда';
  static const sent = 'Юборилди';
  static const failed = 'Хато';
  static const remaining = 'Қолди';
  static const progress = 'Фоиз';
  static const lastNumber = 'Охирги рақам';
  static const valid = 'Тўғри';
  static const invalid = 'Нотўғри';

  static const stateIdle = 'Кутилмоқда';
  static const statePending = 'Кутилмоқда';
  static const stateSending = 'Юборилмоқда';
  static const stateCompleted = 'Якунланди';
  static const stateStopped = 'Тўхтатилди';

  static const sharedFileReadError = 'Улашилган файлни ўқишда хатолик юз берди';
  static const initialShareReadError = 'Бошланғич улашилган файлни ўқиб бўлмади';
  static const pickFileError = 'Файл танлашда хатолик юз берди';
  static const importSharedFileError = 'Улашилган файлни юклаб бўлмади';
  static const fileReadError = 'Файл ўқилмади';
  static const enterSmsText = 'СМС матнини киритинг';
  static const noValidNumber = 'Юбориш учун тўғри рақам топилмади';
  static const smsPermissionDenied = 'СМС юбориш рухсати берилмади';
  static const startSendError = 'Юборишни бошлашда хатолик юз берди';
  static const stopSendError = 'Юборишни тўхтатишда хатолик юз берди';

  static String sendCompleted({
    required int sentCount,
    required int failedCount,
    required int totalCount,
  }) {
    return 'Якунланди: $sentCount та юборилди, $failedCount та хато, жами $totalCount та';
  }

  static String fileCount({
    required int validCount,
    required int invalidCount,
  }) {
    return '$valid: $validCount, $invalid: $invalidCount';
  }

  static String labelWithCount(String label, Object count) {
    return '$label: $count';
  }

  static String percentText(String percent) {
    return '$progress: $percent%';
  }

  static String stateText(String stateKey) {
    switch (stateKey) {
      case 'sending':
        return stateSending;
      case 'completed':
        return stateCompleted;
      case 'stopped':
        return stateStopped;
      case 'pending':
        return statePending;
      default:
        return stateIdle;
    }
  }
}
