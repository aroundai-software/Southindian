import 'dart:html' as html;
import 'dart:typed_data';

Future<void> downloadPdfOnWeb(String filename, Uint8List bytes) async {
  await downloadBytesOnWeb(
    filename,
    bytes,
    mimeType: 'application/pdf',
  );
}

Future<void> downloadBytesOnWeb(
  String filename,
  Uint8List bytes, {
  String mimeType = 'application/octet-stream',
}) async {
  final blob = html.Blob([bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
}
