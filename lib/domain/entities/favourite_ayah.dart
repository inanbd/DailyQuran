import 'package:meta/meta.dart';

import 'ayah.dart';

/// An ayah the reader has saved, with the moment they saved it.
///
/// Favourites are stored by verse key, not by edition, so an ayah saved while
/// reading one translation is still saved after switching to another — and is
/// shown in whichever translation the reader is on now.
@immutable
class FavouriteAyah {
  const FavouriteAyah({required this.ayah, required this.savedAt});

  final Ayah ayah;
  final DateTime savedAt;

  String get verseKey => ayah.verseKey;

  @override
  bool operator ==(Object other) =>
      other is FavouriteAyah &&
      other.ayah.id == ayah.id &&
      other.savedAt == savedAt;

  @override
  int get hashCode => Object.hash(ayah.id, savedAt);
}
