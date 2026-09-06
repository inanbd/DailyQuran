/// Failures the UI knows how to render.
///
/// Data-layer errors are converted into one of these so screens never have to
/// interpret a raw platform or database exception.
sealed class AppException implements Exception {
  const AppException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => '$runtimeType: $message';
}

/// The requested edition has no readable text on this device.
class DatasetUnavailableException extends AppException {
  const DatasetUnavailableException(this.editionId, {super.cause})
      : super('No Qur\u2019an text is installed for this edition.');

  final String editionId;
}

/// The catalog itself could not be read — the app cannot list any editions.
class CatalogUnavailableException extends AppException {
  const CatalogUnavailableException({super.cause})
      : super('The list of Qur\u2019an editions could not be loaded.');
}

/// Local storage failed.
class StorageException extends AppException {
  const StorageException(super.message, {super.cause});
}

/// The content source returned something that does not match the expected
/// schema. Kept distinct so a bad import is not reported as "no data".
class ContentFormatException extends AppException {
  const ContentFormatException(super.message, {super.cause});
}
