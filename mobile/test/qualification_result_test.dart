import 'package:flutter_test/flutter_test.dart';
import 'package:leadpilot_ai/data/models/qualification_result.dart';

void main() {
  group('QualificationResult.fromJson', () {
    test('parses a full backend payload', () {
      final r = QualificationResult.fromJson({
        'customerName': 'Amina Rahman',
        'summary': 'Wants a mobile app',
        'requirements': ['Mobile app', 'CRM integration'],
        'budget': {
          'text': '\$8k',
          'amountMin': 8000,
          'amountMax': 8000,
          'currency': 'USD'
        },
        'urgency': 'high',
        'deadline': 'within 6 weeks',
        'score': 82,
        'priority': 'high',
        'explanation': 'Clear scope and budget',
        'scoreFactors': [
          {'factor': 'Budget stated', 'impact': 'positive', 'note': '\$8k'},
        ],
        'missingInformation': ['Decision maker'],
        'followUpQuestions': ['Who approves the budget?'],
        'recommendedNextAction': 'book_meeting',
        'needsHumanHandoff': false,
        'suggestedFollowupMessage': 'Hi Amina',
        'safetyFlags': ['contains_link'],
        'generatedAt': '2026-11-01T10:00:00Z',
        'provider': 'gemini',
        'model': 'gemini-2.0-flash',
        'mode': 'live',
      });

      expect(r.score, 82);
      expect(r.priority, Priority.high);
      expect(r.urgency, Urgency.high);
      expect(r.recommendedNextAction, NextAction.bookMeeting);
      expect(r.requirements, ['Mobile app', 'CRM integration']);
      expect(r.budget?.display, '\$8k');
      expect(r.scoreFactors.single.impact, 'positive');
      expect(r.generatedAt, isNotNull);
      expect(r.isDemoRules, isFalse);
      expect(r.isHeuristicScore, isTrue);
    });

    test('clamps scores and parses numeric strings', () {
      expect(QualificationResult.fromJson({'score': 150}).score, 100);
      expect(QualificationResult.fromJson({'score': -5}).score, 0);
      expect(QualificationResult.fromJson({'score': '72'}).score, 72);
    });

    test('unknown enum values fall back to the safest option', () {
      final r = QualificationResult.fromJson({
        'priority': 'urgent',
        'urgency': 'whenever',
        'recommendedNextAction': 'wire_money',
      });
      expect(r.priority, Priority.low);
      expect(r.urgency, Urgency.unspecified);
      expect(r.recommendedNextAction, NextAction.humanHandoff);
    });

    test('an empty map produces safe defaults instead of crashing', () {
      final r = QualificationResult.fromJson({});
      expect(r.summary, '');
      expect(r.score, 0);
      expect(r.requirements, isEmpty);
      expect(r.budget, isNull);
      expect(r.mode, 'live');
      expect(r.isHeuristicScore, isTrue);
    });

    test('flags demo rules results', () {
      expect(
          QualificationResult.fromJson({'provider': 'demo-rules'}).isDemoRules,
          isTrue);
    });
  });

  group('BudgetInfo.display', () {
    test('prefers the original text', () {
      expect(const BudgetInfo(text: 'around 5k', amountMin: 5000).display,
          'around 5k');
    });

    test('formats amounts and ranges', () {
      expect(
          const BudgetInfo(amountMin: 5000, amountMax: 5000, currency: 'USD')
              .display,
          'USD 5000');
      expect(
          const BudgetInfo(amountMin: 1000, amountMax: 2000, currency: 'USD')
              .display,
          'USD 1000 - 2000');
    });

    test('says "Not stated" when nothing is known', () {
      expect(const BudgetInfo().display, 'Not stated');
    });
  });

  group('safety flag labels', () {
    test('known flags have friendly text and unknown flags are humanized', () {
      expect(QualificationResult.safetyFlagLabel('possible_prompt_injection'),
          'Message may try to instruct the AI');
      expect(QualificationResult.safetyFlagLabel('some_new_flag'),
          'some new flag');
    });
  });

  group('QualifyResponse.fromJson', () {
    test('keeps measured usage separate and never invents tokens', () {
      final res = QualifyResponse.fromJson({
        'result': {'summary': 's', 'score': 40, 'priority': 'medium'},
        'usage': {
          'provider': 'demo-rules',
          'model': 'keyword-rules',
          'tokensMeasured': false
        },
        'mode': 'demo',
        'persisted': false,
      });
      expect(res.mode, 'demo');
      expect(res.persisted, isFalse);
      expect(res.usage.tokensMeasured, isFalse);
      expect(res.usage.inputTokens, isNull);
      expect(res.usage.estimatedCostUsd, isNull);
      expect(res.usage.costIsEstimate, isTrue);
    });
  });
}
