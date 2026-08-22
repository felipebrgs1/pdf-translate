import 'dart:typed_data';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Compressão client-side (opção A) — sem container, sem perda perceptível.
/// Usa Syncfusion com PdfCompressionLevel.best (Flate + streams).
/// Retorna bytes comprimidos se menor, senão original.
Future<Uint8List> compressPdf(Uint8List input) async {
  if (input.length < 1024 * 100) return input; // <100KB não vale
  try {
    final doc = PdfDocument(inputBytes: input);
    // best = máxima compressão lossless (texto/vetor + imagens mantidas)
    doc.compressionLevel = PdfCompressionLevel.best;
    final out = await doc.save();
    doc.dispose();
    final compressed = Uint8List.fromList(out);
    // só usa se realmente economizou (>2%)
    if (compressed.length < input.length * 0.98) return compressed;
    return input;
  } catch (_) {
    return input;
  }
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}
