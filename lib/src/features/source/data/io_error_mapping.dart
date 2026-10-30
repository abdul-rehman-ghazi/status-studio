import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:status_studio/src/features/source/domain/source_errors.dart';

/// Turns network and storage failures into the app's typed errors (spec
/// §8); anything else is returned unchanged to be rethrown.
Object mapIoError(Object error) {
  return switch (error) {
    // package:http turns most dart:io network failures into ClientException.
    SocketException() ||
    HttpException() ||
    TlsException() ||
    TimeoutException() ||
    http.ClientException() => OfflineException('$error'),
    FileSystemException(:final osError?)
        when osError.message.contains('No space') =>
      InsufficientStorageException('$error'),
    _ => error,
  };
}

/// Runs [action], rethrowing its failure as mapped by [mapIoError].
Future<T> guardIo<T>(Future<T> Function() action) async {
  try {
    return await action();
  } catch (error, stackTrace) {
    Error.throwWithStackTrace(mapIoError(error), stackTrace);
  }
}
