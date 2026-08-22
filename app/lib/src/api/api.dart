import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

const defaultBaseUrl = 'https://pdf-translate.felipebrgs.workers.dev';

// Usa o mesmo Worker da web — sem duplicar backend.
class Api {
  final String baseUrl;
  final http.Client _client;
  Api({String? baseUrl, http.Client? client})
      : baseUrl = baseUrl ?? defaultBaseUrl,
        _client = client ?? http.Client();

  // Sessão via cookie httpOnly — no mobile mandamos Authorization: Bearer <jwt> se o Worker for adaptado;
  // por enquanto o Worker usa cookie; no Flutter web o cookie funciona igual. Para mobile nativo,
  // o login retorna o Set-Cookie e o http.Client mantém se usar comCredentials no web; no nativo
  // precisaria ajustar o Worker para aceitar Authorization. Mantemos simples: tentamos cookie + fallback.
  String? _bearer;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_bearer != null) 'Authorization': 'Bearer $_bearer',
      };

  Future<Map<String, dynamic>> me() async {
    final r = await _client.get(Uri.parse('$baseUrl/api/me'), headers: _headers);
    return _json(r);
  }

  Future<void> login(String email, String password) async {
    final r = await _client.post(
      Uri.parse('$baseUrl/api/login'),
      headers: _headers,
      body: jsonEncode({'email': email, 'password': password}),
    );
    final data = _json(r);
    // tenta extrair token se o Worker passar em JSON (ajuste opcional no Worker)
    _bearer = data['token'] as String?;
  }

  Future<void> logout() async {
    await _client.post(Uri.parse('$baseUrl/api/logout'), headers: _headers);
    _bearer = null;
  }

  Future<List<Book>> listBooks() async {
    final r = await _client.get(Uri.parse('$baseUrl/api/books'), headers: _headers);
    final data = _json(r);
    // Worker retorna lista direto
    final list = data is List ? data : (data['books'] as List? ?? []);
    return list.map((e) => Book.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Book> uploadBook(Uint8List bytes, String name) async {
    final r = await _client.post(
      Uri.parse('$baseUrl/api/books'),
      headers: {
        ..._headers,
        'Content-Type': 'application/pdf',
        'x-file-name': Uri.encodeComponent(name.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '')),
      },
      body: bytes,
    );
    return Book.fromJson(_json(r) as Map<String, dynamic>);
  }

  Future<void> deleteBook(String key) async {
    final r = await _client.delete(Uri.parse('$baseUrl/api/books/$key'), headers: _headers);
    _json(r);
  }

  Future<BookProgress?> getProgress(String key) async {
    final r = await _client.get(Uri.parse('$baseUrl/api/progress/$key'), headers: _headers);
    if (r.statusCode == 404) return null;
    return BookProgress.fromJson(_json(r) as Map<String, dynamic>);
  }

  Future<BookProgress> saveProgress(String key, int page, int totalPages) async {
    final r = await _client.put(
      Uri.parse('$baseUrl/api/progress/$key'),
      headers: _headers,
      body: jsonEncode({'page': page, 'totalPages': totalPages}),
    );
    return BookProgress.fromJson(_json(r) as Map<String, dynamic>);
  }

  Future<Uint8List> getBookBytes(String key) async {
    final r = await _client.get(Uri.parse('$baseUrl/api/books/$key'), headers: _headers);
    if (r.statusCode != 200) throw Exception('download failed ${r.statusCode}');
    return r.bodyBytes;
  }

  Future<Map<String, DayStats>> getStats() async {
    final r = await _client.get(Uri.parse('$baseUrl/api/stats'), headers: _headers);
    final data = _json(r) as Map<String, dynamic>;
    final days = (data['days'] as Map<String, dynamic>? ?? {});
    return days.map((k, v) => MapEntry(k, DayStats.fromJson(v as Map<String, dynamic>)));
  }

  Future<void> addStats({required String date, int pages = 0, int minutes = 0, int highlights = 0}) async {
    final r = await _client.post(
      Uri.parse('$baseUrl/api/stats'),
      headers: _headers,
      body: jsonEncode({'date': date, 'pages': pages, 'minutes': minutes, 'highlights': highlights}),
    );
    _json(r);
  }

  Future<String> translate(String q, String target) async {
    final uri = Uri.parse('$baseUrl/api/translate').replace(queryParameters: {'q': q, 'target': target});
    final r = await _client.get(uri, headers: _headers);
    final data = _json(r) as Map<String, dynamic>;
    return data['translated'] as String? ?? '';
  }

  dynamic _json(http.Response r) {
    final body = r.body.isEmpty ? '{}' : r.body;
    final decoded = jsonDecode(body);
    if (r.statusCode >= 400) {
      throw Exception((decoded is Map ? decoded['error'] : null) ?? 'request failed ${r.statusCode}');
    }
    return decoded;
  }
}

class Book {
  final String key, name;
  final int size;
  final String uploaded;
  final BookProgress? progress;
  Book({required this.key, required this.name, required this.size, required this.uploaded, this.progress});
  factory Book.fromJson(Map<String, dynamic> j) => Book(
        key: j['key'] as String,
        name: j['name'] as String? ?? j['key'] as String,
        size: (j['size'] as num?)?.toInt() ?? 0,
        uploaded: j['uploaded'] as String? ?? '',
        progress: j['progress'] == null ? null : BookProgress.fromJson(j['progress'] as Map<String, dynamic>),
      );
}

class BookProgress {
  final int page, totalPages;
  final double percent;
  final String updatedAt;
  BookProgress({required this.page, required this.totalPages, required this.percent, required this.updatedAt});
  factory BookProgress.fromJson(Map<String, dynamic> j) => BookProgress(
        page: (j['page'] as num).toInt(),
        totalPages: (j['totalPages'] as num).toInt(),
        percent: (j['percent'] as num).toDouble(),
        updatedAt: j['updatedAt'] as String? ?? '',
      );
}

class DayStats {
  final int pages, minutes, highlights;
  DayStats({required this.pages, required this.minutes, required this.highlights});
  factory DayStats.fromJson(Map<String, dynamic> j) => DayStats(
        pages: (j['pages'] as num?)?.toInt() ?? 0,
        minutes: (j['minutes'] as num?)?.toInt() ?? 0,
        highlights: (j['highlights'] as num?)?.toInt() ?? 0,
      );
}
