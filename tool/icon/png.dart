import 'dart:io';
import 'dart:typed_data';

/// Just enough of a PNG encoder to write an image with or without an alpha
/// channel.
///
/// The engine's own encoder always writes one, and the stores refuse it where
/// an image must be opaque: App Store Connect rejects an app icon that has an
/// alpha channel at all, and Google Play wants its feature graphic as 24-bit.
abstract final class Png {
  /// Encodes straight (not premultiplied) RGBA pixels, dropping the alpha
  /// channel unless [alpha] is set.
  static Uint8List encode(
    Uint8List rgba,
    int width,
    int height, {
    required bool alpha,
  }) {
    final int channels = alpha ? 4 : 3;
    final Uint8List scanlines = Uint8List((width * channels + 1) * height);
    int out = 0;
    for (int y = 0; y < height; y++) {
      scanlines[out++] = 0; // Filter: none.
      for (int x = 0; x < width; x++) {
        final int pixel = (y * width + x) * 4;
        scanlines[out++] = rgba[pixel];
        scanlines[out++] = rgba[pixel + 1];
        scanlines[out++] = rgba[pixel + 2];
        if (alpha) scanlines[out++] = rgba[pixel + 3];
      }
    }

    final ByteData header = ByteData(13)
      ..setUint32(0, width)
      ..setUint32(4, height)
      ..setUint8(8, 8) // Bits per channel.
      ..setUint8(9, alpha ? 6 : 2) // Colour type: RGBA, or RGB.
      ..setUint8(10, 0) // Compression: deflate.
      ..setUint8(11, 0) // Filtering: adaptive, per scanline.
      ..setUint8(12, 0); // Not interlaced.

    final BytesBuilder png = BytesBuilder(copy: false)
      ..add(const <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
    _chunk(png, 'IHDR', header.buffer.asUint8List());
    _chunk(
      png,
      'IDAT',
      Uint8List.fromList(ZLibCodec(level: 9).encode(scanlines)),
    );
    _chunk(png, 'IEND', Uint8List(0));
    return png.takeBytes();
  }

  static void _chunk(BytesBuilder png, String type, Uint8List data) {
    final Uint8List name = Uint8List.fromList(type.codeUnits);
    png
      ..add((ByteData(4)..setUint32(0, data.length)).buffer.asUint8List())
      ..add(name)
      ..add(data)
      ..add(
        (ByteData(4)..setUint32(0, _crc32(<Uint8List>[name, data])))
            .buffer
            .asUint8List(),
      );
  }

  static final Uint32List _crcTable = () {
    final Uint32List table = Uint32List(256);
    for (int n = 0; n < 256; n++) {
      int c = n;
      for (int bit = 0; bit < 8; bit++) {
        c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
      }
      table[n] = c;
    }
    return table;
  }();

  static int _crc32(List<Uint8List> parts) {
    int crc = 0xFFFFFFFF;
    for (final Uint8List part in parts) {
      for (final int byte in part) {
        crc = _crcTable[(crc ^ byte) & 0xFF] ^ (crc >> 8);
      }
    }
    return crc ^ 0xFFFFFFFF;
  }
}
