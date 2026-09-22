import 'adventure_response.dart';
import 'adventure_runtime_state.dart';
import 'custom_status_change.dart';
import 'custom_status_evaluation.dart';

/// One status the settlement request has to account for.
///
/// `entityId` is the **stable** adventure-internal identity (never a display
/// name) so two characters that share a name can never share a settlement.
final class TurnSettlementTrackedStatus {
  final String entityId;
  final String characterName;

  /// Canonical attribute reference. `CustomStatusMerger` resolves it against
  /// `CustomAttributeItem.identityRef`, so it is the id when present.
  final String attributeId;
  final String attributeName;
  final String displayValue;
  final bool isNumeric;

  const TurnSettlementTrackedStatus({
    required this.entityId,
    required this.characterName,
    required this.attributeId,
    required this.attributeName,
    required this.displayValue,
    required this.isNumeric,
  });

  /// The prompt line that tells the model exactly which slot to judge.
  String toPromptLine() =>
      '- character_id=$entityId, attribute_id=$attributeId, '
      '角色=$characterName, 状态=$attributeName, '
      '当前=$displayValue${isNumeric ? '（数值，可用 delta）' : '（文本，只能 set）'}';
}

/// The parsed result of the second, fast **turn settlement** request.
///
/// Settlement answers one question only: *given the narrative that has just
/// been finished, what are the next options and how should tracked state
/// change?* It never writes anything by itself — the result feeds
/// `CustomStatusMerger`, `RuntimeStateValidator` and finally the single
/// `commitSceneDialogueTurn` transaction.
final class TurnSettlement {
  static const int schemaVersion = 1;

  /// The option count the UI needs before the turn is considered playable.
  static const int minimumUsableOptions = 3;

  final List<String> options;

  /// `null` means the field was **absent**. An explicit empty list means the
  /// model declined to evaluate anything, which is a different signal and is
  /// what lets `unevaluated_attribute:*` diagnostics be emitted.
  final List<CustomStatusEvaluation>? customStatusEvaluations;

  /// Legacy delta protocol. Still accepted next to the evaluations so a model
  /// that only knows the older shape is not silently ignored; the merger
  /// settles each target once, so a status present in both is never applied
  /// twice.
  final List<CustomStatusChange> customStatusChanges;

  final List<RuntimeStateChangeProposal> runtimeChanges;

  final List<String> parseDiagnostics;

  const TurnSettlement({
    this.options = const [],
    this.customStatusEvaluations,
    this.customStatusChanges = const [],
    this.runtimeChanges = const [],
    this.parseDiagnostics = const [],
  });

  bool get hasUsableOptions => options.length >= minimumUsableOptions;

  /// Parses one settlement response.
  ///
  /// Returns `null` when there is no decodable object at all, which the caller
  /// treats as a failed settlement (and therefore a fail-closed turn). Every
  /// recoverable problem is reported through [diagnostics] instead of being
  /// swallowed.
  ///
  /// The payload decoder is intentionally the same tolerant one the narrative
  /// protocol uses: a model that echoes `narrative\n---JSON---\n{...}` still
  /// yields its payload rather than an unexplained failure.
  static TurnSettlement? parse(
    String raw, {
    List<String>? diagnostics,
  }) {
    final sink = diagnostics ?? <String>[];
    final payload = _payloadOf(raw);
    if (payload == null) {
      sink.add('turn_settlement:invalid_json');
      return null;
    }

    final response = AdventureResponse.fromJson(payload);
    final runtimeDiagnostics = <String>[];
    final runtimeChanges = RuntimeStateChangeProposal.parse(
      payload['runtime_state_changes'],
      diagnostics: runtimeDiagnostics,
    );

    sink
      ..addAll(response.parseDiagnostics)
      ..addAll(runtimeDiagnostics);

    return TurnSettlement(
      options: response.options,
      customStatusEvaluations: response.customStatusEvaluations,
      customStatusChanges: response.customStatusChanges,
      runtimeChanges: runtimeChanges,
      parseDiagnostics: List.unmodifiable(sink),
    );
  }

  static Map<String, dynamic>? _payloadOf(String raw) {
    final payload = AdventureResponse.parse(raw).payload;
    if (payload != null) return payload;
    return AdventureResponse.decodeObject(raw);
  }
}
