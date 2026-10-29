import '../../core/utils/json_helpers.dart';
import 'ai_usage_record.dart';

enum Priority {
  low('low', 'Low'),
  medium('medium', 'Medium'),
  high('high', 'High');

  const Priority(this.wire, this.label);
  final String wire;
  final String label;

  static Priority fromWire(String? v) {
    for (final p in values) {
      if (p.wire == v) return p;
    }
    return Priority.low;
  }
}

enum Urgency {
  low('low', 'Low'),
  medium('medium', 'Medium'),
  high('high', 'High'),
  unspecified('unspecified', 'Not stated');

  const Urgency(this.wire, this.label);
  final String wire;
  final String label;

  static Urgency fromWire(String? v) {
    for (final u in values) {
      if (u.wire == v) return u;
    }
    return Urgency.unspecified;
  }
}

enum NextAction {
  sendFollowup('send_followup', 'Send follow-up'),
  requestInformation('request_information', 'Request information'),
  bookMeeting('book_meeting', 'Book a meeting'),
  humanHandoff('human_handoff', 'Hand off to a human'),
  nurture('nurture', 'Nurture'),
  disqualify('disqualify', 'Disqualify');

  const NextAction(this.wire, this.label);
  final String wire;
  final String label;

  static NextAction fromWire(String? v) {
    for (final a in values) {
      if (a.wire == v) return a;
    }
    return NextAction
        .humanHandoff; // unknown output defaults to the safest action
  }
}

class BudgetInfo {
  const BudgetInfo({this.text, this.amountMin, this.amountMax, this.currency});

  final String? text;
  final double? amountMin;
  final double? amountMax;
  final String? currency;

  String get display {
    if (text != null && text!.trim().isNotEmpty) return text!;
    if (amountMin != null) {
      final cur = currency ?? '';
      return amountMax != null && amountMax != amountMin
          ? '$cur ${amountMin!.toStringAsFixed(0)} - ${amountMax!.toStringAsFixed(0)}'
              .trim()
          : '$cur ${amountMin!.toStringAsFixed(0)}'.trim();
    }
    return 'Not stated';
  }

  factory BudgetInfo.fromJson(Map<String, dynamic> j) => BudgetInfo(
        text: Json.str(j['text']),
        amountMin: Json.number(j['amountMin']),
        amountMax: Json.number(j['amountMax']),
        currency: Json.str(j['currency']),
      );
}

class ScoreFactor {
  const ScoreFactor(
      {required this.factor, this.impact = 'neutral', this.note = ''});

  final String factor;
  final String impact; // positive | negative | neutral
  final String note;

  factory ScoreFactor.fromJson(Map<String, dynamic> j) => ScoreFactor(
        factor: Json.strOr(j['factor']),
        impact: Json.strOr(j['impact'], 'neutral'),
        note: Json.strOr(j['note']),
      );
}

class QualificationResult {
  const QualificationResult({
    required this.summary,
    required this.score,
    required this.priority,
    required this.explanation,
    required this.recommendedNextAction,
    this.customerName,
    this.requirements = const [],
    this.budget,
    this.urgency = Urgency.unspecified,
    this.deadline,
    this.scoreFactors = const [],
    this.missingInformation = const [],
    this.followUpQuestions = const [],
    this.needsHumanHandoff = false,
    this.handoffReason,
    this.suggestedFollowupMessage = '',
    this.isHeuristicScore = true,
    this.scoreDisclaimer = '',
    this.safetyFlags = const [],
    this.generatedAt,
    this.provider = '',
    this.model = '',
    this.mode = 'live',
  });

  final String? customerName;
  final String summary;
  final List<String> requirements;
  final BudgetInfo? budget;
  final Urgency urgency;
  final String? deadline;
  final int score;
  final Priority priority;
  final String explanation;
  final List<ScoreFactor> scoreFactors;
  final List<String> missingInformation;
  final List<String> followUpQuestions;
  final NextAction recommendedNextAction;
  final bool needsHumanHandoff;
  final String? handoffReason;
  final String suggestedFollowupMessage;
  final bool isHeuristicScore;
  final String scoreDisclaimer;
  final List<String> safetyFlags;
  final DateTime? generatedAt;
  final String provider;
  final String model;
  final String mode;

  bool get isDemoRules => provider == 'demo-rules';

  static const Map<String, String> safetyFlagLabels = {
    'possible_prompt_injection': 'Message may try to instruct the AI',
    'contains_link': 'Draft contains a link',
    'mentions_price': 'Draft mentions a price',
    'commitment_language': 'Draft contains commitment language',
  };

  static String safetyFlagLabel(String flag) =>
      safetyFlagLabels[flag] ?? flag.replaceAll('_', ' ');

  factory QualificationResult.fromJson(Map<String, dynamic> j) {
    final budget = j['budget'];
    return QualificationResult(
      customerName: Json.str(j['customerName']),
      summary: Json.strOr(j['summary']),
      requirements: Json.strings(j['requirements']),
      budget: budget is Map ? BudgetInfo.fromJson(Json.map(budget)) : null,
      urgency: Urgency.fromWire(Json.str(j['urgency'])),
      deadline: Json.str(j['deadline']),
      score: (Json.integer(j['score']) ?? 0).clamp(0, 100),
      priority: Priority.fromWire(Json.str(j['priority'])),
      explanation: Json.strOr(j['explanation']),
      scoreFactors:
          Json.maps(j['scoreFactors']).map(ScoreFactor.fromJson).toList(),
      missingInformation: Json.strings(j['missingInformation']),
      followUpQuestions: Json.strings(j['followUpQuestions']),
      recommendedNextAction:
          NextAction.fromWire(Json.str(j['recommendedNextAction'])),
      needsHumanHandoff: Json.flag(j['needsHumanHandoff']),
      handoffReason: Json.str(j['handoffReason']),
      suggestedFollowupMessage: Json.strOr(j['suggestedFollowupMessage']),
      isHeuristicScore: Json.flag(j['isHeuristicScore'], true),
      scoreDisclaimer: Json.strOr(j['scoreDisclaimer']),
      safetyFlags: Json.strings(j['safetyFlags']),
      generatedAt: Json.date(j['generatedAt']),
      provider: Json.strOr(j['provider']),
      model: Json.strOr(j['model']),
      mode: Json.strOr(j['mode'], 'live'),
    );
  }
}

class QualifyResponse {
  const QualifyResponse({
    required this.result,
    required this.usage,
    required this.mode,
    this.leadId,
    this.persisted = false,
    this.approvalId,
  });

  final QualificationResult result;
  final UsageInfo usage;
  final String mode;
  final String? leadId;
  final bool persisted;
  final String? approvalId;

  factory QualifyResponse.fromJson(Map<String, dynamic> j) => QualifyResponse(
        result: QualificationResult.fromJson(Json.map(j['result'])),
        usage: UsageInfo.fromJson(Json.map(j['usage'])),
        mode: Json.strOr(j['mode'], 'live'),
        leadId: Json.str(j['leadId']),
        persisted: Json.flag(j['persisted']),
        approvalId: Json.str(j['approvalId']),
      );
}
