import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/router/route_names.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/lead.dart';
import '../../data/models/message.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/detail_scaffold.dart';
import '../../shared/widgets/skeleton_loader.dart';
import '../../shared/widgets/state_views.dart';
import '../../state/lead_providers.dart';
import '../../state/workspace_providers.dart';

enum _Kind { customer, team, ai, system }

class _Entry {
  const _Entry(
      {required this.kind,
      required this.name,
      required this.text,
      this.at,
      this.internal = false});

  final _Kind kind;
  final String name;
  final String text;
  final DateTime? at;
  final bool internal;
}

class ConversationHistoryScreen extends ConsumerStatefulWidget {
  const ConversationHistoryScreen({super.key, required this.leadId});

  final String leadId;

  @override
  ConsumerState<ConversationHistoryScreen> createState() =>
      _ConversationHistoryScreenState();
}

class _ConversationHistoryScreenState
    extends ConsumerState<ConversationHistoryScreen> {
  final _text = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  List<_Entry> _entries(Lead lead, List<Message> stored) {
    final entries = <_Entry>[
      _Entry(
          kind: _Kind.customer,
          name: lead.customerName,
          text: lead.message,
          at: lead.createdAt),
    ];
    final q = lead.qualification;
    if (q != null) {
      entries.add(_Entry(
        kind: _Kind.ai,
        name: q.isDemoRules ? 'Demo rules' : 'AI qualification',
        text:
            '${q.summary}\n\nScore ${q.score} (${q.priority.label} priority). Next action: ${q.recommendedNextAction.label}.',
        at: q.generatedAt,
      ));
    }
    for (final m in stored) {
      entries.add(_Entry(
        kind: switch (m.senderType) {
          SenderType.customer => _Kind.customer,
          SenderType.user => _Kind.team,
          SenderType.ai => _Kind.ai,
          SenderType.system => _Kind.system,
        },
        name: m.senderName ?? m.senderType.label,
        text: m.text,
        at: m.createdAt,
        internal: m.isInternal,
      ));
    }
    entries
        .sort((a, b) => (a.at ?? DateTime(0)).compareTo(b.at ?? DateTime(0)));
    return entries;
  }

  Future<void> _send() async {
    final value = _text.text.trim();
    if (value.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await ref
          .read(conversationRepositoryProvider)
          .addNote(widget.leadId, value);
      _text.clear();
    } catch (e) {
      if (mounted) AppSnack.error(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lead = ref.watch(leadProvider(widget.leadId));
    final messages = ref.watch(leadMessagesProvider(widget.leadId));
    final canWrite = ref.watch(canWriteProvider);
    final text = Theme.of(context).textTheme;

    return DetailScaffold(
      title: lead.valueOrNull?.customerName ?? 'Conversation',
      maxWidth: 760,
      fallbackRoute: Routes.lead(widget.leadId),
      body: AsyncValueView<Lead>(
        value: lead,
        onRetry: () => ref.invalidate(leadProvider(widget.leadId)),
        loading: const SkeletonList(count: 3),
        data: (l) {
          final entries =
              _entries(l, messages.valueOrNull ?? const <Message>[]);
          return Column(
            children: [
              if (messages.hasError)
                Container(
                  width: double.infinity,
                  color: AppColors.soft(AppColors.warning, 30),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    'Saved notes could not be loaded. Showing the inquiry only.',
                    style: text.bodySmall,
                  ),
                ),
              Expanded(
                child: ListView.separated(
                  reverse: true, // newest at the bottom, anchored like a chat
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  itemCount: entries.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppSpacing.md),
                  itemBuilder: (context, i) =>
                      _Bubble(entries[entries.length - 1 - i]),
                ),
              ),
              if (canWrite)
                _Composer(controller: _text, sending: _sending, onSend: _send)
              else
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  color: AppColors.surface,
                  child: Text(
                    'You have view-only access and cannot add notes.',
                    style: text.bodySmall
                        ?.copyWith(color: AppColors.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer(
      {required this.controller, required this.sending, required this.onSend});

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border))),
      padding: EdgeInsets.fromLTRB(
          16, 10, 8, 10 + MediaQuery.paddingOf(context).bottom * 0),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: AppTextField(
                    controller: controller,
                    hint: 'Add an internal note\u2026',
                    minLines: 1,
                    maxLines: 4,
                    inputFormatters: [LengthLimitingTextInputFormatter(2000)],
                    textInputAction: TextInputAction.newline,
                  ),
                ),
                const SizedBox(width: 4),
                IconButton.filled(
                  tooltip: 'Save note',
                  style: IconButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white),
                  onPressed: sending ? null : onSend,
                  icon: sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.send_rounded, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                'Notes are saved to this lead\u2019s history only. Nothing is sent to the customer. '
                'Customer emails go through Approvals.',
                style: text.labelSmall?.copyWith(color: AppColors.textMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble(this.entry);

  final _Entry entry;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final e = entry;
    final centered = e.kind == _Kind.ai || e.kind == _Kind.system;
    final mine = e.kind == _Kind.team;

    final color = centered
        ? const Color(0xFFEFF6FF)
        : (mine ? AppColors.primarySoft : AppColors.surface);
    final header = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (centered) ...[
          Icon(
              e.kind == _Kind.ai
                  ? Icons.auto_awesome_rounded
                  : Icons.settings_suggest_outlined,
              size: 14,
              color: AppColors.info),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(
            '${e.name} \u00B7 ${Fmt.dateTime(e.at)}',
            style: text.labelSmall?.copyWith(color: AppColors.textSecondary),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );

    final bubble = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: color,
          borderRadius: AppRadius.card,
          border: Border.all(
              color: centered ? const Color(0xFFBFDBFE) : AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            header,
            const SizedBox(height: 6),
            SelectableText(e.text, style: text.bodyMedium),
            if (e.internal) ...[
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline_rounded,
                      size: 12, color: AppColors.textMuted),
                  const SizedBox(width: 4),
                  Text('Internal note',
                      style: text.labelSmall
                          ?.copyWith(color: AppColors.textMuted)),
                ],
              ),
            ],
          ],
        ),
      ),
    );

    return Align(
      alignment: centered
          ? Alignment.center
          : (mine ? Alignment.centerRight : Alignment.centerLeft),
      child: bubble,
    );
  }
}
