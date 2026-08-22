import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  const s = 1024;
  final im = img.Image(width: s, height: s);
  img.fill(im, color: img.ColorRgb8(9, 9, 11)); // #09090B
  // livro branco centralizado — replica o SVG do login
  // corpo do livro: 560x680, cantos arredondados
  const bw = 560, bh = 680;
  final bx = (s - bw) ~/ 2;
  final by = (s - bh) ~/ 2;
  // sombra sutil
  img.fillRect(im, x1: bx + 12, y1: by + 12, x2: bx + bw + 12, y2: by + bh + 12, color: img.ColorRgba8(0, 0, 0, 60), radius: 28);
  // capa branca
  img.fillRect(im, x1: bx, y1: by, x2: bx + bw, y2: by + bh, color: img.ColorRgb8(255, 255, 255), radius: 28);
  // lombada central
  img.fillRect(im, x1: s ~/ 2 - 4, y1: by + 18, x2: s ~/ 2 + 4, y2: by + bh - 18, color: img.ColorRgb8(24, 24, 27));
  // linhas horizontais internas (simulam páginas)
  for (int i = 0; i < 3; i++) {
    final y = by + 160 + i * 110;
    img.fillRect(im, x1: bx + 48, y1: y, x2: s ~/ 2 - 28, y2: y + 14, color: img.ColorRgb8(228, 228, 231), radius: 6);
    img.fillRect(im, x1: s ~/ 2 + 28, y1: y, x2: bx + bw - 48, y2: y + 14, color: img.ColorRgb8(228, 228, 231), radius: 6);
  }
  // detalhe inferior (linha mais grossa)
  img.fillRect(im, x1: bx + 48, y1: by + bh - 110, x2: bx + bw - 48, y2: by + bh - 90, color: img.ColorRgb8(113, 113, 122), radius: 6);

  final out = File('assets/icon/app_icon.png');
  out.createSync(recursive: true);
  out.writeAsBytesSync(img.encodePng(im));
  print('Icon livro gerado ${out.path} ${im.width}x${im.height}');
}
