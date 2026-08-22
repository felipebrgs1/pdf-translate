import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/api.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final api = context.read<Api>();
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.menu_book, color: Colors.white, size: 32),
              const SizedBox(height: 12),
              const Text('PDF Translate', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600)),
              const SizedBox(height: 24),
              TextField(controller: _email, decoration: _dec('E-mail'), style: const TextStyle(color: Colors.white)),
              const SizedBox(height: 12),
              TextField(controller: _pass, obscureText: true, decoration: _dec('Senha'), style: const TextStyle(color: Colors.white)),
              if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: Colors.redAccent))),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _loading
                      ? null
                      : () async {
                          setState(() { _loading = true; _error = null; });
                          try {
                            await api.login(_email.text.trim(), _pass.text);
                            if (!mounted) return;
                            Navigator.of(context).pushReplacementNamed('/library');
                          } catch (e) {
                            setState(() => _error = e.toString());
                          } finally {
                            if (mounted) setState(() => _loading = false);
                          }
                        },
                  child: Text(_loading ? 'Entrando…' : 'Entrar'),
                ),
              )
            ]),
          ),
        ),
      ),
    );
  }

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54),
        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey.shade800)),
        focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
      );
}
