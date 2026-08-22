import 'dart:convert' as convert;
import 'dart:typed_data';
import 'package:archive/archive.dart' as arch;
import 'package:image/image.dart' as img;
import 'package:syncfusion_flutter_pdf/pdf.dart';

Future<Uint8List> compressPdf(Uint8List input) async {
  if (input.length < 1024 * 100) return input;
  Uint8List afterLossless = await _lossless(input);
  if (afterLossless.length < input.length * 0.9) return afterLossless;
  if (input.length > 3 * 1024 * 1024) {
    try {
      final recompressed = await _recompressImages(afterLossless);
      if (recompressed != null && recompressed.length < afterLossless.length * 0.97) {
        return recompressed;
      }
    } catch (_) {}
  }
  return afterLossless;
}

Future<Uint8List> _lossless(Uint8List input) async {
  try {
    final doc = PdfDocument(inputBytes: input);
    doc.compressionLevel = PdfCompressionLevel.best;
    final out = await doc.save();
    doc.dispose();
    final compressed = Uint8List.fromList(out);
    if (compressed.length < input.length * 0.98) return compressed;
    return input;
  } catch (_) {
    return input;
  }
}

// Recomprime imagens dentro do PDF: JPEG -> JPEG 70% + downsample, Flate (raw) -> JPEG 75%
// Equivalente a gs -dPDFSETTINGS=/ebook mas mantendo texto vetorial
Future<Uint8List?> _recompressImages(Uint8List pdfBytes) async {
  String text = convert.latin1.decode(pdfBytes, allowInvalid: true);
  final images = <_ImageInfo>[];
  int idx = 0;
  while (true) {
    final streamIdx = text.indexOf('stream', idx);
    if (streamIdx == -1) break;
    final dictStart = text.lastIndexOf('<<', streamIdx);
    if (dictStart == -1 || streamIdx - dictStart > 6000) { idx = streamIdx + 6; continue; }
    final dictEnd = text.indexOf('>>', dictStart);
    if (dictEnd == -1 || dictEnd > streamIdx) { idx = streamIdx + 6; continue; }
    final dict = text.substring(dictStart, dictEnd + 2);
    if (!dict.contains('/Subtype') || !dict.contains('/Image')) { idx = streamIdx + 6; continue; }
    final isJpeg = dict.contains('DCTDecode');
    final isFlate = dict.contains('FlateDecode');
    if (!isJpeg && !isFlate) { idx = streamIdx + 6; continue; }
    // ignora imagens com predictor complexo (PNG predictor)
    if (dict.contains('/Predictor') && !dict.contains('/Predictor 1')) { idx = streamIdx + 6; continue; }
    final wMatch = RegExp(r'/Width\s+(\d+)').firstMatch(dict);
    final hMatch = RegExp(r'/Height\s+(\d+)').firstMatch(dict);
    final width = wMatch != null ? int.tryParse(wMatch.group(1)!) : null;
    final height = hMatch != null ? int.tryParse(hMatch.group(1)!) : null;
    if (width == null || height == null || width < 50 || height < 50) { idx = streamIdx + 6; continue; }
    int streamStart = streamIdx + 6;
    if (streamStart < text.length && text[streamStart] == '\r') streamStart++;
    if (streamStart < text.length && text[streamStart] == '\n') streamStart++;
    final endIdx = text.indexOf('endstream', streamStart);
    if (endIdx == -1) { idx = streamIdx + 6; continue; }
    int streamEnd = endIdx;
    if (streamEnd > 0 && text[streamEnd - 1] == '\n') streamEnd--;
    if (streamEnd > 0 && text[streamEnd - 1] == '\r') streamEnd--;
    final streamLen = streamEnd - streamStart;
    if (streamLen <= 0 || streamLen < 512) { idx = endIdx + 9; continue; }
    final hasLength = RegExp(r'/Length\s+(\d+)(\s+0\s+R)?').hasMatch(dict);
    if (!hasLength) { idx = endIdx + 9; continue; }
    images.add(_ImageInfo(
      dictStart: dictStart, dictEnd: dictEnd + 2, streamStart: streamStart, streamEnd: streamEnd,
      width: width, height: height, dict: dict, isJpeg: isJpeg,
    ));
    idx = endIdx + 9;
  }
  if (images.isEmpty) return null;
  images.sort((a, b) => b.streamStart.compareTo(a.streamStart));

  Uint8List curBytes = pdfBytes;
  String curText = text;
  int savedTotal = 0;
  int processed = 0;

  for (final info in images) {
    try {
      Uint8List imgBytes = curBytes.sublist(info.streamStart, info.streamEnd);
      img.Image? decoded;
      String? colorSpace;
      if (info.isJpeg) {
        decoded = img.decodeJpg(imgBytes);
      } else {
        // Flate: decomprime e cria imagem
        try {
          final raw = Uint8List.fromList(arch.ZLibDecoder().decodeBytes(imgBytes));
          // detecta ColorSpace
          final csMatch = RegExp(r'/ColorSpace\s*/(\w+)').firstMatch(info.dict);
          colorSpace = csMatch?.group(1);
          // fallback: procura /DeviceRGB etc sem /
          if (colorSpace == null && info.dict.contains('DeviceRGB')) colorSpace = 'DeviceRGB';
          if (colorSpace == null && info.dict.contains('DeviceGray')) colorSpace = 'DeviceGray';
          final w = info.width!, h = info.height!;
          if (colorSpace == 'DeviceRGB') {
            if (raw.length < w * h * 3) continue;
            decoded = img.Image.fromBytes(width: w, height: h, bytes: raw.buffer, numChannels: 3, order: img.ChannelOrder.rgb);
          } else if (colorSpace == 'DeviceGray') {
            if (raw.length < w * h) continue;
            // expande gray para rgb
            final rgb = Uint8List(w * h * 3);
            for (int i = 0; i < w * h; i++) {
              final g = raw[i];
              rgb[i * 3] = g; rgb[i * 3 + 1] = g; rgb[i * 3 + 2] = g;
            }
            decoded = img.Image.fromBytes(width: w, height: h, bytes: rgb.buffer, numChannels: 3, order: img.ChannelOrder.rgb);
          } else {
            continue; // CMYK etc pula
          }
        } catch (_) { continue; }
      }
      if (decoded == null) continue;
      img.Image toEncode = decoded;
      final origW = decoded.width, origH = decoded.height;
      const maxSide = 1200;
      if (origW > maxSide || origH > maxSide) {
        toEncode = img.copyResize(decoded, width: origW > origH ? maxSide : null, height: origH >= origW ? maxSide : null, interpolation: img.Interpolation.linear);
      } else if (origW > 600 || origH > 600) {
        toEncode = img.copyResize(decoded, width: (origW * 0.65).round(), height: (origH * 0.65).round(), interpolation: img.Interpolation.linear);
      }
      final recompressed = Uint8List.fromList(img.encodeJpg(toEncode, quality: 70));
      if (recompressed.length >= imgBytes.length) continue;

      String newDict = curText.substring(info.dictStart, info.dictEnd);
      if (toEncode.width != origW) newDict = newDict.replaceFirst(RegExp(r'/Width\s+\d+'), '/Width ${toEncode.width}');
      if (toEncode.height != origH) newDict = newDict.replaceFirst(RegExp(r'/Height\s+\d+'), '/Height ${toEncode.height}');
      // Flate -> DCT
      if (!info.isJpeg) {
        newDict = newDict.replaceFirst(RegExp(r'/Filter\s*\[?[^\]]*?FlateDecode[^\]]*?\]?'), '/Filter /DCTDecode');
        newDict = newDict.replaceAll(RegExp(r'/DecodeParms\s*<<[^>]*>>'), '');
        newDict = newDict.replaceAll(RegExp(r'/DecodeParms\s*\[[^\]]*\]'), '');
        // garante ColorSpace RGB
        if (newDict.contains('DeviceGray')) newDict = newDict.replaceFirst(RegExp(r'/ColorSpace\s*/\w+'), '/ColorSpace /DeviceRGB');
      }
      if (RegExp(r'/Length\s+\d+\s+0\s+R').hasMatch(newDict)) {
        newDict = newDict.replaceFirst(RegExp(r'/Length\s+\d+\s+0\s+R'), '/Length ${recompressed.length}');
      } else {
        newDict = newDict.replaceFirst(RegExp(r'/Length\s+\d+'), '/Length ${recompressed.length}');
      }
      // remove interpolação e suavização antigas
      newDict = newDict.replaceAll(RegExp(r'/Interpolate\s+true'), '');
      newDict = newDict.replaceAll(RegExp(r'\s+'), ' ');

      final beforeDict = curBytes.sublist(0, info.dictStart);
      final newDictBytes = convert.latin1.encode(newDict);
      final betweenDictAndStream = curBytes.sublist(info.dictEnd, info.streamStart);
      final afterStream = curBytes.sublist(info.streamEnd);
      final rebuilt = Uint8List(beforeDict.length + newDictBytes.length + betweenDictAndStream.length + recompressed.length + afterStream.length);
      int off = 0;
      rebuilt.setRange(off, off + beforeDict.length, beforeDict); off += beforeDict.length;
      rebuilt.setRange(off, off + newDictBytes.length, newDictBytes); off += newDictBytes.length;
      rebuilt.setRange(off, off + betweenDictAndStream.length, betweenDictAndStream); off += betweenDictAndStream.length;
      rebuilt.setRange(off, off + recompressed.length, recompressed); off += recompressed.length;
      rebuilt.setRange(off, off + afterStream.length, afterStream);
      curBytes = rebuilt;
      curText = convert.latin1.decode(curBytes, allowInvalid: true);
      savedTotal += imgBytes.length - recompressed.length;
      processed++;
      if (savedTotal > 30 * 1024 * 1024) break;
    } catch (_) { continue; }
  }
  if (processed == 0 || savedTotal < 100 * 1024) return null;
  return curBytes;
}

class _ImageInfo {
  final int dictStart, dictEnd, streamStart, streamEnd;
  final int? width, height;
  final String dict;
  final bool isJpeg;
  _ImageInfo({required this.dictStart, required this.dictEnd, required this.streamStart, required this.streamEnd, this.width, this.height, required this.dict, required this.isJpeg});
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}
