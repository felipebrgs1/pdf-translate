import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/api.dart';
import '../../cache/pdf_cache.dart';
import '../../cache/pdf_compress.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  List<Book> _books = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() { _loading = true; _error = null; });
    try {
      final api = context.read<Api>();
      _books = await api.listBooks();
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickAndUpload() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf'], withData: true);
    if (res == null || res.files.single.bytes == null) return;
    final f = res.files.single;
    try {
      Uint8List bytes = f.bytes!;
      final original = bytes.length;
      // compressão client-side antes de enviar pro R2
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Comprimindo PDF...'), duration: Duration(seconds: 1)));
      final compressed = await compressPdf(bytes);
      bytes = compressed;
      final saved = original - bytes.length;
      if (saved > 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Economizado ${formatBytes(saved)} (${((saved / original) * 100).toStringAsFixed(0)}%) — enviando...')));
      }
      final api = context.read<Api>();
      await api.uploadBook(bytes, f.name);
      await _refresh();
      if (saved > 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Enviado ${formatBytes(bytes.length)} (original ${formatBytes(original)})')));
      }
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _compressExisting(Book book) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('Baixando PDF...')));
    try {
      final api = context.read<Api>();
      final original = await api.getBookBytes(book.key);
      final origLen = original.length;
      messenger.showSnackBar(SnackBar(content: Text('Comprimindo ${formatBytes(origLen)}...')));
      final compressed = await compressPdf(original);
      if (compressed.length >= origLen * 0.98) {
        messenger.showSnackBar(const SnackBar(content: Text('Já está otimizado — sem economia relevante')));
        return;
      }
      final saved = origLen - compressed.length;
      messenger.showSnackBar(SnackBar(content: Text('Economizado ${formatBytes(saved)} — reenviando...')));
      await api.replaceBookBytes(book.key, compressed);
      try { final f = await cachedPdfFile(book.key); if (await f.exists()) await f.delete(); } catch (_) {}
      await _refresh();
      if (mounted) messenger.showSnackBar(SnackBar(content: Text('Comprimido: ${formatBytes(origLen)} → ${formatBytes(compressed.length)} (-${((saved / origLen) * 100).toStringAsFixed(0)}%)')));
    } catch (e) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text('Falha: $e')));
    }
  }

  Future<void> _removeBook(Book book) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF18181B),
        title: const Text('Remover livro?', style: TextStyle(color: Colors.white)),
        content: Text('"${book.name}" será removido.', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remover')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await context.read<Api>().deleteBook(book.key);
      try { final f = await cachedPdfFile(book.key); if (await f.exists()) await f.delete(); } catch (_) {}
      await _refresh();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Biblioteca', style: TextStyle(color: Colors.white)),
        actions: [
          IconButton(onPressed: () => Navigator.pushNamed(context, '/stats'), icon: const Icon(Icons.bar_chart, color: Colors.white70)),
          IconButton(onPressed: _pickAndUpload, icon: const Icon(Icons.add, color: Colors.white)),
          IconButton(
              onPressed: () async { await context.read<Api>().logout(); if (mounted) Navigator.pushReplacementNamed(context, '/login'); },
              icon: const Icon(Icons.logout, color: Colors.white70)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.redAccent)))
              : _books.isEmpty
                  ? const Center(child: Text('Nenhum livro ainda', style: TextStyle(color: Colors.white54)))
                  : GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 0.65, crossAxisSpacing: 12, mainAxisSpacing: 12),
                      itemCount: _books.length,
                      itemBuilder: (_, i) {
                        final b = _books[i];
                        return GestureDetector(
                          onSecondaryTapDown: (d) async {
                            final v = await showMenu<String>(
                              context: context,
                              position: RelativeRect.fromLTRB(d.globalPosition.dx, d.globalPosition.dy, d.globalPosition.dx, d.globalPosition.dy),
                              items: const [
                                PopupMenuItem(value: 'compress', child: Row(children: [Icon(Icons.compress, size: 18), SizedBox(width: 8), Text('Comprimir')])),
                                PopupMenuItem(value: 'remove', child: Row(children: [Icon(Icons.delete, size: 18, color: Colors.redAccent), SizedBox(width: 8), Text('Remover')])),
                              ],
                            );
                            if (v == 'compress') _compressExisting(b);
                            if (v == 'remove') _removeBook(b);
                          },
                          child: InkWell(
                          onTap: () => Navigator.pushNamed(context, '/reader', arguments: b).then((_) => _refresh()),
                          child: Container(
                            clipBehavior: Clip.antiAlias,
                            decoration: BoxDecoration(border: Border.all(color: Colors.white12), borderRadius: BorderRadius.circular(12)),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                              // capa autenticada + selo offline
                              Expanded(
                                child: Stack(children: [
                                  Positioned.fill(
                                    child: FutureBuilder<Uint8List?>(
                                      future: context.read<Api>().getThumbBytes(b.key),
                                      builder: (_, snap) {
                                        if (snap.connectionState == ConnectionState.waiting) {
                                          return Container(color: const Color(0xFF18181B), child: const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))));
                                        }
                                        final bytes = snap.data;
                                        if (bytes != null && bytes.isNotEmpty) {
                                          return Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true,
                                              errorBuilder: (_, __, ___) => Container(color: const Color(0xFF18181B), child: const Icon(Icons.broken_image, color: Colors.white24)));
                                        }
                                        return Container(
                                          color: const Color(0xFF18181B),
                                          child: const Center(child: Icon(Icons.picture_as_pdf, color: Colors.white24, size: 40)),
                                        );
                                      },
                                    ),
                                  ),
                                  // icone offline (aparece apos abrir o livro uma vez)
                                  Positioned(
                                    right: 6,
                                    top: 6,
                                    child: FutureBuilder<bool>(
                                      future: isPdfCached(b.key),
                                      builder: (_, snap) {
                                        final cached = snap.data == true;
                                        if (!cached) return const SizedBox.shrink();
                                        return Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(6)),
                                          child: const Icon(Icons.offline_pin, size: 14, color: Color(0xFF4ADE80)),
                                        );
                                      },
                                    ),
                                  ),
                                  Positioned(
                                    left: 6,
                                    top: 6,
                                    child: PopupMenuButton<String>(
                                      padding: EdgeInsets.zero,
                                      icon: Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(6)), child: const Icon(Icons.more_vert, size: 14, color: Colors.white70)),
                                      onSelected: (v) {
                                        if (v == 'compress') _compressExisting(b);
                                        if (v == 'remove') _removeBook(b);
                                      },
                                      itemBuilder: (_) => const [
                                        PopupMenuItem(value: 'compress', child: Row(children: [Icon(Icons.compress, size: 18), SizedBox(width: 8), Text('Comprimir')])),
                                        PopupMenuItem(value: 'remove', child: Row(children: [Icon(Icons.delete, size: 18, color: Colors.redAccent), SizedBox(width: 8), Text('Remover')])),
                                      ],
                                    ),
                                  ),
                                ]),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(10),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(b.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 13)),
                                  const SizedBox(height: 6),
                                  if (b.progress != null) ...[
                                    Text('Página ${b.progress!.page} de ${b.progress!.totalPages} · ${b.progress!.percent % 1 == 0 ? b.progress!.percent.toStringAsFixed(0) : b.progress!.percent.toStringAsFixed(1)}%', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                                    const SizedBox(height: 4),
                                    LinearProgressIndicator(value: (b.progress!.percent / 100).clamp(0, 1), minHeight: 3),
                                    const SizedBox(height: 4),
                                    Text('${(b.size / 1024).toStringAsFixed(0)} KB', style: const TextStyle(color: Colors.white38, fontSize: 10)),
                                  ] else
                                    Text('${(b.size / 1024).toStringAsFixed(0)} KB', style: const TextStyle(color: Colors.white38, fontSize: 11)),
                                ]),
                              ),
                            ]),
                          ),
                        ),
                        );
                      },
                    ),
    );
  }
}
