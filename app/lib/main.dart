import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'src/api/api.dart';
import 'src/features/auth/login_screen.dart';
import 'src/features/library/library_screen.dart';
import 'src/features/reader/reader_screen.dart';
import 'src/features/stats/stats_screen.dart';

void main() {
  runApp(
    Provider<Api>(
      create: (_) => Api(),
      child: const PdfTranslateApp(),
    ),
  );
}

class PdfTranslateApp extends StatelessWidget {
  const PdfTranslateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PDF Translate',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        colorScheme: const ColorScheme.dark(primary: Colors.white),
      ),
      initialRoute: '/login',
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case '/login':
            return MaterialPageRoute(builder: (_) => const LoginScreen());
          case '/library':
            return MaterialPageRoute(builder: (_) => const LibraryScreen());
          case '/reader':
            final book = settings.arguments as dynamic;
            return MaterialPageRoute(builder: (_) => ReaderScreen(book: book));
          case '/stats':
            return MaterialPageRoute(builder: (_) => const StatsScreen());
          default:
            return MaterialPageRoute(builder: (_) => const LoginScreen());
        }
      },
    );
  }
}
