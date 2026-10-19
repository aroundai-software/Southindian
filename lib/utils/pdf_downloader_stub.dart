import 'dart:typed_data';

Future<void> downloadPdfOnWeb(String filename, Uint8List bytes) async {
  throw UnsupportedError('Web PDF download not available on this platform');
}

Future<void> downloadBytesOnWeb(
  String filename,
  Uint8List bytes, {
  String mimeType = 'application/octet-stream',
}) async {
  throw UnsupportedError('Web download not available on this platform');
}

