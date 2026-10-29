import '../../core/utils/json_helpers.dart';

class ServiceStatus {
  const ServiceStatus(
      {required this.name, required this.configured, this.detail = ''});

  final String name;
  final bool configured;
  final String detail;

  factory ServiceStatus.fromJson(Map<String, dynamic> j) => ServiceStatus(
        name: Json.strOr(j['name']),
        configured: Json.flag(j['configured']),
        detail: Json.strOr(j['detail']),
      );
}

class IntegrationStatus {
  const IntegrationStatus({
    required this.mode,
    required this.llmProvider,
    required this.llmModel,
    required this.services,
  });

  final String mode; // live | demo
  final String llmProvider;
  final String llmModel;
  final List<ServiceStatus> services;

  bool get isDemo => mode == 'demo';

  factory IntegrationStatus.fromJson(Map<String, dynamic> j) =>
      IntegrationStatus(
        mode: Json.strOr(j['mode'], 'live'),
        llmProvider: Json.strOr(j['llmProvider'], 'unknown'),
        llmModel: Json.strOr(j['llmModel'], 'unknown'),
        services: Json.maps(j['services']).map(ServiceStatus.fromJson).toList(),
      );
}

class AgentConfig {
  const AgentConfig({
    this.businessName = '',
    this.businessDescription = '',
    this.services = const [],
    this.idealCustomer = '',
    this.tone = 'professional',
    this.minimumBudgetUsd,
    this.handoffRules = const [],
    this.customInstructions = '',
    this.monthlyBudgetUsd,
    this.updatedAt,
    this.updatedBy,
  });

  static const List<String> tones = ['professional', 'friendly', 'concise'];

  final String businessName;
  final String businessDescription;
  final List<String> services;
  final String idealCustomer;
  final String tone;
  final double? minimumBudgetUsd;
  final List<String> handoffRules;
  final String customInstructions;
  final double? monthlyBudgetUsd;
  final DateTime? updatedAt;
  final String? updatedBy;

  AgentConfig copyWith({
    String? businessName,
    String? businessDescription,
    List<String>? services,
    String? idealCustomer,
    String? tone,
    double? minimumBudgetUsd,
    bool clearMinimumBudget = false,
    List<String>? handoffRules,
    String? customInstructions,
    double? monthlyBudgetUsd,
    bool clearMonthlyBudget = false,
  }) =>
      AgentConfig(
        businessName: businessName ?? this.businessName,
        businessDescription: businessDescription ?? this.businessDescription,
        services: services ?? this.services,
        idealCustomer: idealCustomer ?? this.idealCustomer,
        tone: tone ?? this.tone,
        minimumBudgetUsd: clearMinimumBudget
            ? null
            : (minimumBudgetUsd ?? this.minimumBudgetUsd),
        handoffRules: handoffRules ?? this.handoffRules,
        customInstructions: customInstructions ?? this.customInstructions,
        monthlyBudgetUsd: clearMonthlyBudget
            ? null
            : (monthlyBudgetUsd ?? this.monthlyBudgetUsd),
        updatedAt: updatedAt,
        updatedBy: updatedBy,
      );

  factory AgentConfig.fromJson(Map<String, dynamic> j) => AgentConfig(
        businessName: Json.strOr(j['businessName']),
        businessDescription: Json.strOr(j['businessDescription']),
        services: Json.strings(j['services']),
        idealCustomer: Json.strOr(j['idealCustomer']),
        tone: tones.contains(Json.str(j['tone']))
            ? Json.strOr(j['tone'])
            : 'professional',
        minimumBudgetUsd: Json.number(j['minimumBudgetUsd']),
        handoffRules: Json.strings(j['handoffRules']),
        customInstructions: Json.strOr(j['customInstructions']),
        monthlyBudgetUsd: Json.number(j['monthlyBudgetUsd']),
        updatedAt: Json.date(j['updatedAt']),
        updatedBy: Json.str(j['updatedBy']),
      );

  Map<String, dynamic> toJson() => {
        'businessName': businessName.trim(),
        'businessDescription': businessDescription.trim(),
        'services': services,
        'idealCustomer': idealCustomer.trim(),
        'tone': tone,
        'minimumBudgetUsd': minimumBudgetUsd,
        'handoffRules': handoffRules,
        'customInstructions': customInstructions.trim(),
        'monthlyBudgetUsd': monthlyBudgetUsd,
      };
}
