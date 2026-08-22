import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  const size = 1024;
  final image = img.Image(width: size, height: size);
  // fundo #09090B (quase preto, tema do app)
  img.fill(image, color: img.ColorRgb8(9, 9, 11));
  // borda arredondada sutil (simula ícone)
  // livro branco centralizado
  final bookW = 520, bookH = 640;
  final bx = (size - bookW) ~/ 2;
  final by = (size - bookH) ~/ 2 - 40;
  // páginas do livro (branco)
  img.fillRect(image, x1: bx, y1: by, x2: bx + bookW, y2: by + bookH, color: img.ColorRgb8(255, 255, 255), radius: 24);
  // lombada
  img.fillRect(image, x1: bx + bookW ~/ 2 - 6, y1: by, x2: bx + bookW ~/ 2 + 6, y2: by + bookH, color: img.ColorRgb8(24, 24, 27));
  // linhas simulando texto
  for (int i = 0; i < 5; i++) {
    final y = by + 120 + i * 80;
    img.fillRect(image, x1: bx + 40, y1: y, x2: bx + bookW - 40, y2: y + 18, color: img.ColorRgb8(228, 228, 231), radius: 6);
  }
  // faixa de tradução azul na base do livro
  img.fillRect(image, x1: bx, y1: by + bookH - 100, x2: bx + bookW, y2: by + bookH, color: img.ColorRgb8(59, 130, 246), radius: 16);
  // texto "A → あ" centralizado na faixa (simulado com retângulos brancos)
  // A
  img.fillRect(image, x1: bx + 90, y1: by + bookH - 70, x2: bx + 170, y2: by + bookH - 30, color: img.ColorRgb8(255,255,255), radius: 4);
  // seta
  final ax = bx + 230;
  img.fillRect(image, x1: ax, y1: by + bookH - 55, x2: ax + 60, y2: by + bookH - 45, color: img.ColorRgb8(255,255,255));
  img.fillRect(image, x1: ax + 40, y1: by + bookH - 65, x2: ax + 60, y2: by + bookH - 35, color: img.ColorRgb8(255,255,255));
  // あ
  img.fillRect(image, x1: bx + 340, y1: by + bookH - 70, x2: bx + 420, y2: by + bookH - 30, color: img.ColorRgb8(255,255,255), radius: 4);

  final out = File('assets/icon/app_icon.png');
  out.createSync(recursive: true);
  out.writeAsBytesSync(img.encodePng(image));
  print('Icon gerado em ${out.path} (${image.width}x${image.height})');
}
