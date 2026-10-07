import 'dart:convert';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cygnus_models.dart';

class CygnusSessionStore {
  static const _localSessionsKey = 'cygnus_local_sessions_v1';
  static const _localMessagesPrefix = 'cygnus_local_messages_v1_';
  static const _pendingInstructionsPrefix = 'cygnus_pending_instructions_v1_';
  static const _installIdKey = 'cygnus_install_id_v1';

  FirebaseDatabase? _database;
  String? _ownerId;
  bool _cloudEnabled = false;

  bool get cloudEnabled => _cloudEnabled;
  String? get ownerId => _ownerId;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _ownerId = prefs.getString(_installIdKey);
    if (_ownerId == null || _ownerId!.isEmpty) {
      _ownerId = _randomId('install');
      await prefs.setString(_installIdKey, _ownerId!);
    }

    try {
      final auth = FirebaseAuth.instance;
      if (auth.currentUser == null) {
        await auth.signInAnonymously();
      }
      final uid = auth.currentUser?.uid;
      if (uid != null && uid.isNotEmpty) {
        _ownerId = uid;
        _database = FirebaseDatabase.instance;
        try {
          _database!.setPersistenceEnabled(true);
          _database!.setPersistenceCacheSizeBytes(8 * 1024 * 1024);
        } catch (_) {
          // Persistence can only be configured once and before first DB use.
        }
        _cloudEnabled = true;
      }
    } catch (error) {
      _cloudEnabled = false;
      debugPrint('Cygnus cloud history fallback enabled: $error');
    }
  }

  DatabaseReference? get _root {
    final db = _database;
    final owner = _ownerId;
    if (!_cloudEnabled || db == null || owner == null) return null;
    return db.ref('cygnusUsers/$owner/sessions');
  }

  Future<List<CygnusSessionSummary>> listSessions() async {
    final root = _root;
    if (root != null) {
      try {
        final snapshot = await root
            .orderByChild('updatedAt')
            .limitToLast(40)
            .get();
        final value = snapshot.value;
        if (value is Map) {
          final sessions = <CygnusSessionSummary>[];
          value.forEach((key, dynamic raw) {
            if (raw is Map) {
              sessions.add(
                CygnusSessionSummary.fromMap(
                  key.toString(),
                  Map<String, dynamic>.from(raw),
                ),
              );
            }
          });
          sessions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
          return sessions;
        }
      } catch (error) {
        debugPrint('Cygnus Firebase session list failed: $error');
      }
    }

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

    final root = _root;
    if (root != null) {
      try {
        await root.child(id).set(record);
      } catch (error) {
        debugPrint('Cygnus Firebase session create failed: $error');
      }
    }

    await _upsertLocalSession(id, record);
    return id;
  }

  Future<List<CygnusMessage>> loadMessages(String sessionId) async {
    final root = _root;
    if (root != null) {
      try {
        final snapshot = await root
            .child(sessionId)
            .child('messages')
            .orderByChild('createdAt')
            .limitToLast(80)
            .get();
        final value = snapshot.value;
        if (value is Map) {
          final messages = <CygnusMessage>[];
          value.forEach((_, dynamic raw) {
            if (raw is Map) {
              messages.add(
                CygnusMessage.fromMap(Map<String, dynamic>.from(raw)),
              );
            }
          });
          messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
          return messages;
        }
      } catch (error) {
        debugPrint('Cygnus Firebase message load failed: $error');
      }
    }

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

  Future<void> saveMessage(String sessionId, CygnusMessage message) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final root = _root;
    if (root != null) {
      try {
        final messageRef = root
            .child(sessionId)
            .child('messages')
            .child(message.id);
        await messageRef.set(message.toMap());
        await root.child(sessionId).update(<String, dynamic>{'updatedAt': now});
      } catch (error) {
        debugPrint('Cygnus Firebase message save failed: $error');
      }
    }

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

  Future<List<CygnusQueuedInstruction>> loadInstructionQueue(
    String sessionId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_pendingInstructionsPrefix$sessionId');
    if (raw == null || raw.isEmpty) return const <CygnusQueuedInstruction>[];

    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      throw const FormatException(
        'Stored Cygnus instruction queue is not a list.',
      );
    }
    final instructions = <CygnusQueuedInstruction>[];
    for (final item in decoded) {
      if (item is! Map) {
        throw const FormatException(
          'Stored Cygnus instruction queue contains an invalid item.',
        );
      }
      instructions.add(
        CygnusQueuedInstruction.fromMap(Map<String, dynamic>.from(item)),
      );
    }
    return instructions;
  }

  Future<void> saveInstructionQueue(
    String sessionId,
    List<CygnusQueuedInstruction> instructions,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_pendingInstructionsPrefix$sessionId';
    if (instructions.isEmpty) {
      await prefs.remove(key);
      return;
    }
    final saved = await prefs.setString(
      key,
      jsonEncode(
        instructions.map((instruction) => instruction.toMap()).toList(),
      ),
    );
    if (!saved) {
      throw StateError('Could not persist the Cygnus instruction queue.');
    }
  }

  Future<void> updateSession({
    required String sessionId,
    String? title,
    String? languageCode,
  }) async {
    final patch = <String, dynamic>{
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
      if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
      if (languageCode != null) 'languageCode': languageCode,
    };

    final root = _root;
    if (root != null) {
      try {
        await root.child(sessionId).update(patch);
      } catch (error) {
        debugPrint('Cygnus Firebase session update failed: $error');
      }
    }

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

  Future<void> deleteSession(String sessionId) async {
    final root = _root;
    if (root != null) {
      try {
        await root.child(sessionId).remove();
      } catch (error) {
        debugPrint('Cygnus Firebase session delete failed: $error');
      }
    }
    final prefs = await SharedPreferences.getInstance();
    final sessions = await _readLocalSessionMaps();
    sessions.removeWhere((e) => e['id']?.toString() == sessionId);
    await prefs.setString(_localSessionsKey, jsonEncode(sessions));
    await prefs.remove('$_localMessagesPrefix$sessionId');
    await prefs.remove('$_pendingInstructionsPrefix$sessionId');
  }

  Future<void> clearSessionMessages(String sessionId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final root = _root;
    if (root != null) {
      try {
        await root.child(sessionId).child('messages').remove();
        await root.child(sessionId).update(<String, dynamic>{
          'title': 'New chat',
          'updatedAt': now,
        });
      } catch (error) {
        debugPrint('Cygnus Firebase message clear failed: $error');
      }
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_localMessagesPrefix$sessionId');
    await prefs.remove('$_pendingInstructionsPrefix$sessionId');
    final sessions = await _readLocalSessionMaps();
    final index = sessions.indexWhere((e) => e['id']?.toString() == sessionId);
    if (index >= 0) {
      sessions[index] = <String, dynamic>{
        ...sessions[index],
        'title': 'New chat',
        'updatedAt': now,
      };
      await prefs.setString(_localSessionsKey, jsonEncode(sessions));
    }
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
