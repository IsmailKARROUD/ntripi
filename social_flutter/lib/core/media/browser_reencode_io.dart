// core/media/browser_reencode_io.dart — phones and desktop. Their picker
// already re-encodes what it hands over, so there is nothing to convert here;
// the browser side is browser_reencode_web.dart.

import 'dart:typed_data';

/// Never called off the web; answers as a browser that cannot open the file.
Future<Uint8List?> reencodeAsPng(Uint8List bytes, String mimeType) async =>
    null;
