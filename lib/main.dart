import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sms/core/app_strings.dart';
import 'package:sms/core/error_reporter.dart';
import 'package:sms/pages/home_page.dart';

void main() {
  runZonedGuarded(
    () {
      WidgetsFlutterBinding.ensureInitialized();
      ErrorReporter.installGlobalHandlers();
      ErrorWidget.builder = (FlutterErrorDetails details) {
        return Material(
          color: Colors.red.shade100,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'UI xatoligi: ${details.exceptionAsString()}',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        );
      };
      runApp(const SmsApp());
    },
    (error, stackTrace) {
      ErrorReporter.report(error, stackTrace, context: 'runZonedGuarded');
    },
  );
}

class SmsApp extends StatelessWidget {
  const SmsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: AppStrings.appTitle,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      builder: (context, child) {
        return ValueListenableBuilder<UiErrorState?>(
          valueListenable: ErrorReporter.latestError,
          builder: (context, uiError, _) {
            return Stack(
              children: [
                if (child != null) child,
                if (uiError != null)
                  Positioned(
                    left: 8,
                    right: 8,
                    top: 8,
                    child: Material(
                      elevation: 4,
                      borderRadius: BorderRadius.circular(12),
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                uiError.message,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onErrorContainer,
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: ErrorReporter.clear,
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Icon(
                                  Icons.close,
                                  color: Theme.of(context).colorScheme.onErrorContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
      home: const HomePage(), 
    );
  }
}
