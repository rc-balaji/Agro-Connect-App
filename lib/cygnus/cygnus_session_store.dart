import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import 'cygnus_models.dart';

class CygnusSessionStore {
  Future<void> _writes = Future<void>.value();
  Future<T> _serialize<T>(Future<T> Function() action) {
    final next = _writes.then((_) => action());
    _writes = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  static const _localSessionsKey = 'cygnus_local_sessions_v1';
  static const _localMessagesPrefix = 'cygnus_local_messages_v1_';
  static const _installIdKey = 'cygnus_install_id_v1';

  String? _ownerId;

  bool get cloudEnabled => false;
  String? get ownerId => _ownerId;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _ownerId = prefs.getString(_installIdKey);
    if (_ownerId == null || _ownerId!.isEmpty) {
      _ownerId = _randomId('install');
      await prefs.setString(_installIdKey, _ownerId!);
    }
  }

  Future<List<CygnusSessionSummary>> listSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_localSessionsKey);
    if (raw == null || raw.isEmpty) return const <CygnusSessionSummary>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <CygnusSessionSummary>[];
      final sessions = decoded
          .whereType<Map>()
          .map(
            (item) => CygnusSessionSummary.fromMap(
              item['id']?.toString() ?? '',
              Map<String, dynamic>.from(item),
            ),
          )
          .toList();
      sessions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return sessions;
    } catch (_) {
      return const <CygnusSessionSummary>[];
    }
  }

  Future<String> createSession({
    required String languageCode,
    String title = 'New chat',
  }) async {
    final id = _randomId('chat');
    final now = DateTime.now().millisecondsSinceEpoch;
    final record = <String, dynamic>{
      'title': title,
      'languageCode': languageCode,
      'createdAt': now,
      'updatedAt': now,
    };

    await _upsertLocalSession(id, record);
    return id;
  }

  Future<List<CygnusMessage>> loadMessages(String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_localMessagesPrefix$sessionId');
    if (raw == null || raw.isEmpty) return const <CygnusMessage>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <CygnusMessage>[];
      return decoded
          .whereType<Map>()
          .map((item) => CygnusMessage.fromMap(Map<String, dynamic>.from(item)))
          .toList(growable: false);
    } catch (_) {
      return const <CygnusMessage>[];
    }
  }

  Future<void> saveMessage(String sessionId, CygnusMessage message) =>
      _serialize(() => _saveMessage(sessionId, message));
  Future<void> _saveMessage(String sessionId, CygnusMessage message) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final prefs = await SharedPreferences.getInstance();
    final key = '$_localMessagesPrefix$sessionId';
    final raw = prefs.getString(key);
    var messages = <Map<String, dynamic>>[];
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          messages = decoded
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      } catch (_) {}
    }
    messages.removeWhere((e) => e['id']?.toString() == message.id);
    messages.add(message.toMap());
    if (messages.length > 120) {
      messages = messages.sublist(messages.length - 120);
    }
    await prefs.setString(key, jsonEncode(messages));

    final sessions = await _readLocalSessionMaps();
    final existing = sessions.indexWhere(
      (e) => e['id']?.toString() == sessionId,
    );
    final record = <String, dynamic>{
      'id': sessionId,
      'title': existing >= 0
          ? sessions[existing]['title'] ?? 'New chat'
          : 'New chat',
      'languageCode': existing >= 0
          ? sessions[existing]['languageCode'] ?? 'en'
          : 'en',
      'updatedAt': now,
      'createdAt': existing >= 0 ? sessions[existing]['createdAt'] ?? now : now,
    };
    if (existing >= 0) {
      sessions[existing] = record;
    } else {
      sessions.add(record);
    }
    await prefs.setString(_localSessionsKey, jsonEncode(sessions));
  }

  Future<void> updateSession({
    required String sessionId,
    String? title,
    String? languageCode,
  }) => _serialize(
    () => _updateSession(
      sessionId: sessionId,
      title: title,
      languageCode: languageCode,
    ),
  );
  Future<void> _updateSession({
    required String sessionId,
    String? title,
    String? languageCode,
  }) async {
    final patch = <String, dynamic>{
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
      if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
      if (languageCode != null) 'languageCode': languageCode,
    };

    final sessions = await _readLocalSessionMaps();
    final index = sessions.indexWhere((e) => e['id']?.toString() == sessionId);
    if (index >= 0) {
      sessions[index] = <String, dynamic>{...sessions[index], ...patch};
    } else {
      sessions.add(<String, dynamic>{'id': sessionId, ...patch});
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_localSessionsKey, jsonEncode(sessions));
  }

  Future<void> deleteSession(String sessionId) =>
      _serialize(() => _deleteSession(sessionId));
  Future<void> _deleteSession(String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    final sessions = await _readLocalSessionMaps();
    sessions.removeWhere((e) => e['id']?.toString() == sessionId);
    await prefs.setString(_localSessionsKey, jsonEncode(sessions));
    await prefs.remove('$_localMessagesPrefix$sessionId');
  }

  Future<void> _upsertLocalSession(
    String id,
    Map<String, dynamic> record,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final sessions = await _readLocalSessionMaps();
    final index = sessions.indexWhere((e) => e['id']?.toString() == id);
    final withId = <String, dynamic>{'id': id, ...record};
    if (index >= 0) {
      sessions[index] = withId;
    } else {
      sessions.add(withId);
    }
    await prefs.setString(_localSessionsKey, jsonEncode(sessions));
  }

  Future<List<Map<String, dynamic>>> _readLocalSessionMaps() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_localSessionsKey);
    if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (_) {}
    return <Map<String, dynamic>>[];
  }

  String _randomId(String prefix) {
    final random = Random.secure();
    final suffix = List<int>.generate(
      8,
      (_) => random.nextInt(16),
    ).map((e) => e.toRadixString(16)).join();
    return '${prefix}_${DateTime.now().microsecondsSinceEpoch}_$suffix';
  }
}
