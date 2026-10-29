import '../../core/utils/json_helpers.dart';
import 'integration_settings.dart';
import 'workflow_execution.dart';

/// Usage reported for a single AI call. Tokens are null unless the provider reported them.
class UsageInfo {
  const UsageInfo({
    required this.provider,
    required this.model,
    this.inputTokens,
    this.outputTokens,
    this.totalTokens,
    this.tokensMeasured = false,
    this.latencyMs,
    this.estimatedCostUsd,
    this.costIsEstimate = true,
    this.attempts = 1,
  });

  final String provider;
  final String model;
  final int? inputTokens;
  final int? outputTokens;
  final int? totalTokens;
  final bool tokensMeasured;
  final int? latencyMs;
  final double? estimatedCostUsd;
  final bool costIsEstimate;
  final int attempts;

  factory UsageInfo.fromJson(Map<String, dynamic> j) => UsageInfo(
        provider: Json.strOr(j['provider'], 'unknown'),
        model: Json.strOr(j['model'], 'unknown'),
        inputTokens: Json.integer(j['inputTokens']),
        outputTokens: Json.integer(j['outputTokens']),
        totalTokens: Json.integer(j['totalTokens']),
        tokensMeasured: Json.flag(j['tokensMeasured']),
        latencyMs: Json.integer(j['latencyMs']),
        estimatedCostUsd: Json.number(j['estimatedCostUsd']),
        costIsEstimate: Json.flag(j['costIsEstimate'], true),
        attempts: Json.integer(j['attempts']) ?? 1,
      );
}

enum UsageKind {
  qualification('qualification', 'Qualification'),
  playground('playground', 'Playground'),
  followupDraft('followup_draft', 'Follow-up draft');

  const UsageKind(this.wire, this.label);
  final String wire;
  final String label;

  static UsageKind fromWire(String? v) {
    for (final k in values) {
      if (k.wire == v) return k;
    }
    return UsageKind.qualification;
  }
}

class UsageRecord {
  const UsageRecord({
    required this.id,
    required this.kind,
    required this.provider,
    required this.model,
    this.success = true,
    this.errorCode,
    this.leadId,
    this.inputTokens,
    this.outputTokens,
    this.tokensMeasured = false,
    this.latencyMs,
    this.estimatedCostUsd,
    this.createdAt,
  });

  final String id;
  final UsageKind kind;
  final String provider;
  final String model;
  final bool success;
  final String? errorCode;
  final String? leadId;
  final int? inputTokens;
  final int? outputTokens;
  final bool tokensMeasured;
  final int? latencyMs;
  final double? estimatedCostUsd;
  final DateTime? createdAt;

  factory UsageRecord.fromJson(Map<String, dynamic> j) => UsageRecord(
        id: Json.strOr(j['id']),
        kind: UsageKind.fromWire(Json.str(j['kind'])),
        provider: Json.strOr(j['provider'], 'unknown'),
        model: Json.strOr(j['model'], 'unknown'),
        success: Json.flag(j['success'], true),
        errorCode: Json.str(j['errorCode']),
        leadId: Json.str(j['leadId']),
        inputTokens: Json.integer(j['inputTokens']),
        outputTokens: Json.integer(j['outputTokens']),
        tokensMeasured: Json.flag(j['tokensMeasured']),
        latencyMs: Json.integer(j['latencyMs']),
        estimatedCostUsd: Json.number(j['estimatedCostUsd']),
        createdAt: Json.date(j['createdAt']),
      );
}

class ModelUsage {
  const ModelUsage({
    required this.provider,
    required this.model,
    this.requests = 0,
    this.measuredInputTokens = 0,
    this.measuredOutputTokens = 0,
    this.estimatedCostUsd,
  });

  final String provider;
  final String model;
  final int requests;
  final int measuredInputTokens;
  final int measuredOutputTokens;
  final double? estimatedCostUsd;

  factory ModelUsage.fromJson(Map<String, dynamic> j) => ModelUsage(
        provider: Json.strOr(j['provider'], 'unknown'),
        model: Json.strOr(j['model'], 'unknown'),
        requests: Json.integer(j['requests']) ?? 0,
        measuredInputTokens: Json.integer(j['measuredInputTokens']) ?? 0,
        measuredOutputTokens: Json.integer(j['measuredOutputTokens']) ?? 0,
        estimatedCostUsd: Json.number(j['estimatedCostUsd']),
      );
}

class UsageSummary {
  const UsageSummary({
    this.periodDays = 30,
    this.totalRequests = 0,
    this.successfulRequests = 0,
    this.failedRequests = 0,
    this.requestsWithoutTokenData = 0,
    this.measuredInputTokens = 0,
    this.measuredOutputTokens = 0,
    this.estimatedCostUsd,
    this.costNote = '',
    this.avgLatencyMs,
    this.byModel = const [],
    this.monthlyBudgetUsd,
    this.budgetUsedPct,
  });

  final int periodDays;
  final int totalRequests;
  final int successfulRequests;
  final int failedRequests;
  final int requestsWithoutTokenData;
  final int measuredInputTokens;
  final int measuredOutputTokens;
  final double? estimatedCostUsd;
  final String costNote;
  final double? avgLatencyMs;
  final List<ModelUsage> byModel;
  final double? monthlyBudgetUsd;
  final double? budgetUsedPct;

  int get measuredTotalTokens => measuredInputTokens + measuredOutputTokens;

  factory UsageSummary.fromJson(Map<String, dynamic> j) => UsageSummary(
        periodDays: Json.integer(j['periodDays']) ?? 30,
        totalRequests: Json.integer(j['totalRequests']) ?? 0,
        successfulRequests: Json.integer(j['successfulRequests']) ?? 0,
        failedRequests: Json.integer(j['failedRequests']) ?? 0,
        requestsWithoutTokenData:
            Json.integer(j['requestsWithoutTokenData']) ?? 0,
        measuredInputTokens: Json.integer(j['measuredInputTokens']) ?? 0,
        measuredOutputTokens: Json.integer(j['measuredOutputTokens']) ?? 0,
        estimatedCostUsd: Json.number(j['estimatedCostUsd']),
        costNote: Json.strOr(j['costNote']),
        avgLatencyMs: Json.number(j['avgLatencyMs']),
        byModel: Json.maps(j['byModel']).map(ModelUsage.fromJson).toList(),
        monthlyBudgetUsd: Json.number(j['monthlyBudgetUsd']),
        budgetUsedPct: Json.number(j['budgetUsedPct']),
      );
}

class MonitoringOverview {
  const MonitoringOverview({
    required this.executions,
    required this.usage,
    required this.integrations,
    this.errorsLast24h = 0,
  });

  final ExecutionStats executions;
  final UsageSummary usage;
  final IntegrationStatus integrations;
  final int errorsLast24h;

  factory MonitoringOverview.fromJson(Map<String, dynamic> j) =>
      MonitoringOverview(
        executions: ExecutionStats.fromJson(Json.map(j['executions'])),
        usage: UsageSummary.fromJson(Json.map(j['usage'])),
        integrations: IntegrationStatus.fromJson(Json.map(j['integrations'])),
        errorsLast24h: Json.integer(j['errorsLast24h']) ?? 0,
      );
}
