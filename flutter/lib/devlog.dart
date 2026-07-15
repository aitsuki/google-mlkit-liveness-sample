import 'package:flutter/material.dart';

void devLog(String message, {Object? error, StackTrace? stackTrace}) {
  debugPrint(
    error == null ? message : '$message\nError: $error',
    wrapWidth: 1000,
  );

  if (stackTrace != null) {
    debugPrintStack(label: 'StackTrace', stackTrace: stackTrace);
  }
}
