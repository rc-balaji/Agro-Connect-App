class ControlState {
  const ControlState({
    this.desired2 = false,
    this.desired3 = false,
    this.desired4 = false,
    this.actual1 = false,
    this.actual2 = false,
    this.actual3 = false,
    this.actual4 = false,
    this.pendingKey,
    this.lastRoundTripMs,
    this.lastCommandId,
  });

  final bool desired2;
  final bool desired3;
  final bool desired4;

  final bool actual1;
  final bool actual2;
  final bool actual3;
  final bool actual4;

  final String? pendingKey;
  final int? lastRoundTripMs;
  final String? lastCommandId;

  ControlState copyWith({
    bool? desired2,
    bool? desired3,
    bool? desired4,
    bool? actual1,
    bool? actual2,
    bool? actual3,
    bool? actual4,
    String? pendingKey,
    bool clearPending = false,
    int? lastRoundTripMs,
    String? lastCommandId,
  }) {
    return ControlState(
      desired2: desired2 ?? this.desired2,
      desired3: desired3 ?? this.desired3,
      desired4: desired4 ?? this.desired4,
      actual1: actual1 ?? this.actual1,
      actual2: actual2 ?? this.actual2,
      actual3: actual3 ?? this.actual3,
      actual4: actual4 ?? this.actual4,
      pendingKey: clearPending ? null : (pendingKey ?? this.pendingKey),
      lastRoundTripMs: lastRoundTripMs ?? this.lastRoundTripMs,
      lastCommandId: lastCommandId ?? this.lastCommandId,
    );
  }
}
