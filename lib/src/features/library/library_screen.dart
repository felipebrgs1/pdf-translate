import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/api.dart';
import '../../cache/pdf_cache.dart';
import '../../cache/pdf_compress.dart';
import 'widgets/book_card.dart';
import 'widgets/library_drawer.dart';
import 'widgets/library_grid.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  List<Book> _books = [];
  bool _loading = true;
  String? _error;
  final Map<String, Future<Uint8List?>> _thumbFallback = {};

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() { _loading = true; _error = null; });
    try {
      _books = await context.read<Api>().listBooks();
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<Uint8List?> _ensureThumb(String key) {
    return _thumbFallback.putIfAbsent(key, () async {
      try {
        final pdfBytes = await context.read<Api>().getBookBytes(key);
        final thumb = await makeThumbnail(pdfBytes);
        if (thumb != null) {
          try { await context.read<Api>().uploadThumb(key, thumb); } catch (_) {}
          return thumb;
        }
      } catch (_) {}
      return null;
    });
  }

  Future<void> _pickAndUpload() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf'], withData: true);
    if (res == null || res.files.single.bytes == null) return;
    final f = res.files.single;
    try {
      Uint8List bytes = f.bytes!;
      final original = bytes.length;
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Comprimindo PDF...'), duration: Duration(seconds: 1)));
      bytes = await compressPdf(bytes);
      final saved = original - bytes.length;
      if (saved > 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Economizado ${formatBytes(saved)} (${((saved / original) * 100).toStringAsFixed(0)}%) — enviando...')));
      }
      await context.read<Api>().uploadBook(bytes, f.name);
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
      final original = await context.read<Api>().getBookBytes(book.key);
      final origLen = original.length;
      messenger.showSnackBar(SnackBar(content: Text('Comprimindo ${formatBytes(origLen)}...')));
      final compressed = await compressPdf(original);
      if (compressed.length >= origLen * 0.98) {
        messenger.showSnackBar(const SnackBar(content: Text('Já está otimizado — sem economia relevante')));
        return;
      }
      final saved = origLen - compressed.length;
      messenger.showSnackBar(SnackBar(content: Text('Economizado ${formatBytes(saved)} — reenviando...')));
      await context.read<Api>().replaceBookBytes(book.key, compressed);
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
    final isMobile = MediaQuery.of(context).size.width < 600;
    return Scaffold(
      backgroundColor: Colors.black,
      drawer: LibraryDrawer(onAddPdf: _pickAndUpload),
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Biblioteca', style: TextStyle(color: Colors.white)),
        actions: [
          IconButton(onPressed: () => Navigator.pushNamed(context, '/stats'), icon: const Icon(Icons.bar_chart, color: Colors.white70)),
          IconButton(onPressed: _pickAndUpload, icon: const Icon(Icons.add, color: Colors.white)),
          if (!isMobile)
            IconButton(onPressed: () async { await context.read<Api>().logout(); if (mounted && context.mounted) Navigator.pushReplacementNamed(context, '/login'); }, icon: const Icon(Icons.logout, color: Colors.white70)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.redAccent)))
              : _books.isEmpty
                  ? const Center(child: Text('Nenhum livro ainda', style: TextStyle(color: Colors.white54)))
                  : LibraryGrid(
                      books: _books,
                      onRefresh: _refresh,
                      cardBuilder: (b) => BookCard(
                        book: b,
                        onOpen: () => Navigator.pushNamed(context, '/reader', arguments: b).then((_) => _refresh()),
                        onCompress: () => _compressExisting(b),
                        onRemove: () => _removeBook(b),
                        ensureThumb: _ensureThumb,
                      ),
                    ),
    );
  }
}
