import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

Future<Directory> _cacheDir() async {
  final base = await getApplicationDocumentsDirectory();
  final dir = Directory(p.join(base.path, 'pdf_cache'));
  if (!await dir.exists()) await dir.create(recursive: true);
  return dir;
}

Future<File> cachedPdfFile(String key) async {
  final dir = await _cacheDir();
  return File(p.join(dir.path, '$key.pdf'));
}

Future<bool> isPdfCached(String key) async {
  try {
    final f = await cachedPdfFile(key);
    return await f.exists() && await f.length() > 0;
  } catch (_) {
    return false;
  }
}

Future<void> savePdfToCache(String key, Uint8List bytes) async {
  try {
    final f = await cachedPdfFile(key);
    await f.writeAsBytes(bytes, flush: true);
  } catch (_) {}
}

Future<Uint8List?> makeThumbnail(Uint8List pdfBytes) async {
  try {
    final doc = await PdfDocument.openData(pdfBytes);
    if (doc.pages.isEmpty) { doc.dispose(); return null; }
    final page = doc.pages[0];
    final pdfImage = await page.render(fullWidth: 300, fullHeight: 400, backgroundColor: 0xffffffff);
    if (pdfImage == null) { doc.dispose(); return null; }
    final uiImage = await pdfImage.createImage();
    pdfImage.dispose();
    final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.png);
    uiImage.dispose();
    doc.dispose();
    if (byteData == null) return null;
    final pngBytes = byteData.buffer.asUint8List();
    final decoded = img.decodePng(pngBytes);
    if (decoded == null) return pngBytes;
    return Uint8List.fromList(img.encodeJpg(decoded, quality: 80));
  } catch (_) {
    return null;
  }
}
