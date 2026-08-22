import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'src/api/api.dart';
import 'src/features/auth/auth_gate.dart';
import 'src/features/auth/login_screen.dart';
import 'src/features/library/library_screen.dart';
import 'src/features/reader/reader_screen.dart';
import 'src/features/stats/stats_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final api = Api();
  await api.loadPersistedToken();
  runApp(
    Provider<Api>.value(
      value: api,
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
        textSelectionTheme: const TextSelectionThemeData(
          selectionColor: Color(0x663B82F6),
          selectionHandleColor: Color(0xFF3B82F6),
          cursorColor: Color(0xFF3B82F6),
        ),
      ),
      initialRoute: '/',
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case '/':
            return MaterialPageRoute(builder: (_) => const AuthGate());
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
