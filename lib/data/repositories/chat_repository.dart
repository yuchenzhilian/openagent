// Persists chat sessions to a JSON file in app-private storage.
import 'dart:convert';

import '../models/models.dart';
import '../services/file_storage_service.dart';

class ChatRepository {
  ChatRepository(this._storage);

  final FileStorageService _storage;

  Future<List<ChatSession>> loadSessions() async {
    final file = await _storage.sessionsFile();
    if (!await file.exists()) return const [];
    try {
      final list = jsonDecode(await file.readAsString());
      if (list is! List) return const [];
      return list
          .whereType<Map<String, dynamic>>()
          .map((j) => ChatSession.fromJson(j))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveSessions(List<ChatSession> sessions) async {
    final file = await _storage.sessionsFile();
    await file.writeAsString(
      jsonEncode(sessions.map((s) => s.toJson()).toList()),
      flush: true,
    );
  }

  Future<void> deleteSession(String id, List<ChatSession> all) async {
    all.removeWhere((s) => s.id == id);
    await saveSessions(all);
  }
}
