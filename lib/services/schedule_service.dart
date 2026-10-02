import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/schedule_config.dart';
import '../models/schedule_plan.dart';

class ScheduleApiException implements Exception {
  const ScheduleApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class SchedulerHealth {
  const SchedulerHealth({
    required this.ok,
    required this.configured,
    this.detail,
  });

  final bool ok;
  final bool configured;
  final String? detail;
}

class ScheduleService {
  ScheduleService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Uri _uri(String path) => Uri.parse('${ScheduleConfig.apiBaseUrl}$path');

  Future<List<SchedulePlan>> fetchSchedules() async {
    final response = await _client
        .get(_uri('/api/schedules'), headers: const {'accept': 'application/json'})
        .timeout(ScheduleConfig.requestTimeout);
    final data = _decode(response);
    final list = data['schedules'];
    if (list is! List) return const <SchedulePlan>[];
    return list
        .whereType<Map>()
        .map((item) => SchedulePlan.fromMap(Map<String, dynamic>.from(item)))
        .toList(growable: false);
  }

  Future<SchedulePlan> createSchedule(ScheduleDraft draft) async {
    final response = await _client
        .post(
          _uri('/api/schedules'),
          headers: const {
            'accept': 'application/json',
            'content-type': 'application/json',
          },
          body: jsonEncode(draft.toMap()),
        )
        .timeout(ScheduleConfig.requestTimeout);
    final data = _decode(response);
    return SchedulePlan.fromMap(
      Map<String, dynamic>.from(data['schedule'] as Map),
    );
  }

  Future<SchedulePlan> updateSchedule(String id, Map<String, dynamic> patch) async {
    final response = await _client
        .patch(
          _uri('/api/schedules/$id'),
          headers: const {
            'accept': 'application/json',
            'content-type': 'application/json',
          },
          body: jsonEncode(patch),
        )
        .timeout(ScheduleConfig.requestTimeout);
    final data = _decode(response);
    return SchedulePlan.fromMap(
      Map<String, dynamic>.from(data['schedule'] as Map),
    );
  }

  Future<void> deleteSchedule(String id) async {
    final response = await _client
        .delete(
          _uri('/api/schedules/$id'),
          headers: const {'accept': 'application/json'},
        )
        .timeout(ScheduleConfig.requestTimeout);
    _decode(response);
  }

  Future<SchedulerHealth> fetchSchedulerHealth() async {
    try {
      final response = await _client
          .get(
            _uri('/api/scheduler/status'),
            headers: const {'accept': 'application/json'},
          )
          .timeout(ScheduleConfig.requestTimeout);
      final data = _decode(response);
      final scheduler = data['scheduler'];
      String? detail;
      if (scheduler is Map) {
        detail = scheduler['state']?.toString() ?? scheduler['error']?.toString();
      }
      return SchedulerHealth(
        ok: data['ok'] == true,
        configured: data['configured'] == true,
        detail: detail,
      );
    } catch (error) {
      return SchedulerHealth(ok: false, configured: false, detail: error.toString());
    }
  }

  Map<String, dynamic> _decode(http.Response response) {
    Map<String, dynamic> data = const <String, dynamic>{};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) data = Map<String, dynamic>.from(decoded);
    } catch (_) {}

    if (response.statusCode < 200 || response.statusCode >= 300 || data['ok'] == false) {
      final message = data['error']?.toString().trim();
      throw ScheduleApiException(
        message?.isNotEmpty == true
            ? message!
            : 'Server request failed (${response.statusCode})',
        statusCode: response.statusCode,
      );
    }

    return data;
  }

  void dispose() => _client.close();
}
