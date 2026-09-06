import '../entities/ayah.dart';
import '../entities/quran_edition.dart';
import '../entities/surah.dart';

/// The swappable content layer.
///
/// This is the single seam between the app and wherever Qur'an text comes
/// from. The bundled implementation reads JSON assets; a network-backed or
/// publisher-provided implementation can replace it without any UI change.
///
/// Implementations must reproduce source text verbatim.
abstract interface class QuranContentSource {
  /// Every edition this source knows about, whether or not its text is
  /// available yet.
  Future<List<QuranEdition>> loadCatalog();

  /// True when [editionId]'s text can be produced by this source.
  Future<bool> hasContentFor(String editionId);

  /// The full ordered text of an edition, ready to be persisted locally.
  ///
  /// Called once per edition when it is first opened. Ordinals must be
  /// contiguous and 1-based, in the edition's own reading order.
  Future<List<Ayah>> loadAyat(String editionId);

  /// Surah metadata for an edition.
  ///
  /// This is reference data, not Qur'an text, so a complete edition normally
  /// inherits the shared index that ships with the app; an edition may carry
  /// its own when its surahs are not the Qur'an's.
  Future<List<Surah>> loadSurahs(String editionId);
}
