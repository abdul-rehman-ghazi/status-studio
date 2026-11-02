import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/source/data/io_error_mapping.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';

void main() {
  test('maps_socket_errors_to_offline', () {
    final mapped = mapIoError(const SocketException('Failed host lookup'));

    expect(mapped, isA<OfflineException>());
  });

  test('maps_tls_errors_to_offline', () {
    final mapped = mapIoError(const HandshakeException('reset'));

    expect(mapped, isA<OfflineException>());
  });

  test('maps_no_space_errors_to_insufficient_storage', () {
    const error = FileSystemException(
      'Write failed',
      '/tmp/x',
      OSError('No space left on device', 28),
    );

    expect(mapIoError(error), isA<InsufficientStorageException>());
  });

  test('passes_other_errors_through', () {
    final error = StateError('bug');

    expect(mapIoError(error), same(error));
  });
}
