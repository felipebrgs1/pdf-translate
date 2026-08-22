import 'package:flutter/material.dart';
import '../../../api/api.dart';

class LibraryGrid extends StatelessWidget {
  final List<Book> books;
  final Widget Function(Book) cardBuilder;
  final Future<void> Function() onRefresh;

  const LibraryGrid({super.key, required this.books, required this.cardBuilder, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (_, c) {
      final cols = c.maxWidth < 600 ? 2 : (c.maxWidth < 900 ? 3 : 5);
      return GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols, childAspectRatio: 0.65, crossAxisSpacing: 12, mainAxisSpacing: 12),
        itemCount: books.length,
        itemBuilder: (_, i) => cardBuilder(books[i]),
      );
    });
  }
}
