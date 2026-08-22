import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

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
