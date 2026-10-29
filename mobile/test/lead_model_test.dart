import 'package:flutter_test/flutter_test.dart';
import 'package:leadpilot_ai/data/models/lead.dart';
import 'package:leadpilot_ai/data/models/membership.dart';

void main() {
  group('Lead.fromJson', () {
    test('parses a qualified lead', () {
      final lead = Lead.fromJson({
        'id': 'l1',
        'workspaceId': 'w1',
        'customerName': 'Amina Rahman',
        'customerEmail': 'amina@example.com',
        'source': 'referral',
        'message': 'Need an app',
        'tags': ['vip', 'demo'],
        'status': 'meeting_booked',
        'score': 71,
        'priority': 'high',
        'qualification': {
          'summary': 's',
          'score': 71,
          'priority': 'high',
          'explanation': 'e',
          'recommendedNextAction': 'book_meeting',
        },
        'createdAt': '2026-11-01T10:00:00Z',
      });

      expect(lead.status, LeadStatus.meetingBooked);
      expect(lead.source, LeadSource.referral);
      expect(lead.isQualified, isTrue);
      expect(lead.hasEmail, isTrue);
      expect(lead.tags, ['vip', 'demo']);
      expect(lead.createdAt, isNotNull);
    });

    test('tolerates an empty map', () {
      final lead = Lead.fromJson({});
      expect(lead.customerName, 'Unknown customer');
      expect(lead.status, LeadStatus.newLead);
      expect(lead.source, LeadSource.other);
      expect(lead.isQualified, isFalse);
      expect(lead.priority, isNull);
    });
  });

  group('pipeline rules (must match backend ALLOWED_TRANSITIONS)', () {
    Set<String> next(LeadStatus s) => s.allowedNext.map((e) => e.wire).toSet();

    test('allowed moves', () {
      expect(next(LeadStatus.newLead),
          {'qualified', 'contacted', 'meeting_booked', 'lost'});
      expect(next(LeadStatus.qualified),
          {'new', 'contacted', 'meeting_booked', 'converted', 'lost'});
      expect(next(LeadStatus.contacted),
          {'qualified', 'meeting_booked', 'converted', 'lost'});
      expect(
          next(LeadStatus.meetingBooked), {'contacted', 'converted', 'lost'});
      expect(next(LeadStatus.lost), {'new'});
    });

    test('converted is final', () {
      expect(LeadStatus.converted.allowedNext, isEmpty);
      expect(LeadStatus.converted.isClosed, isTrue);
      expect(LeadStatus.lost.isClosed, isTrue);
      expect(LeadStatus.qualified.isClosed, isFalse);
    });

    test('unknown wire values', () {
      expect(LeadStatus.tryFromWire('nonsense'), isNull);
      expect(LeadStatus.fromWire('nonsense'), LeadStatus.newLead);
    });
  });

  group('LeadSource', () {
    test('unknown sources become "other" and system sources are not selectable',
        () {
      expect(LeadSource.fromWire('carrier_pigeon'), LeadSource.other);
      expect(LeadSource.selectable, isNot(contains(LeadSource.webhook)));
      expect(LeadSource.selectable, isNot(contains(LeadSource.playground)));
    });
  });

  group('LeadInput', () {
    const input = LeadInput(
      customerName: '  Amina  ',
      message: '  Need an app  ',
      customerEmail: '   ',
      customerPhone: ' +880 1700 000000 ',
      company: '',
      source: LeadSource.referral,
      tags: ['vip'],
      notes: ' note ',
    );

    test('create payload trims text and turns blanks into null', () {
      final json = input.toCreateJson();
      expect(json['customerName'], 'Amina');
      expect(json['message'], 'Need an app');
      expect(json['customerEmail'], isNull);
      expect(json['customerPhone'], '+880 1700 000000');
      expect(json['company'], isNull);
      expect(json['source'], 'referral');
      expect(json['qualify'], isTrue);
    });

    test('update payload never includes the immutable message or qualify flag',
        () {
      final json = input.toUpdateJson();
      expect(json.containsKey('message'), isFalse);
      expect(json.containsKey('qualify'), isFalse);
      expect(json['customerName'], 'Amina');
    });
  });

  group('Role', () {
    test('unknown roles are least privileged', () {
      final role = Role.fromWire('superuser');
      expect(role, Role.viewer);
      expect(role.canWrite, isFalse);
      expect(role.canManage, isFalse);
    });

    test('capabilities by role', () {
      expect(Role.owner.canManage, isTrue);
      expect(Role.admin.canManage, isTrue);
      expect(Role.agent.canWrite, isTrue);
      expect(Role.agent.canManage, isFalse);
    });
  });
}
