import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../models/pending_interaction.dart';

class PendingInteractionCard extends StatefulWidget {
  const PendingInteractionCard({
    super.key,
    required this.item,
    required this.enabled,
    required this.submitted,
    required this.onRespond,
  });

  final PendingInteraction item;
  final bool enabled;
  final bool submitted;
  final ValueChanged<Map<String, dynamic>> onRespond;

  @override
  State<PendingInteractionCard> createState() => _PendingInteractionCardState();
}

class _PendingInteractionCardState extends State<PendingInteractionCard> {
  final _answers = <String, String>{};
  final _custom = <String>{};
  final _form = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final waiting = widget.submitted || item.responding;
    final enabled = widget.enabled && item.canRespond && !waiting;
    final title = item.kind == 'userInput'
        ? '需要你的回答'
        : item.kind == 'approval'
        ? '需要你的审批'
        : '需要在桌面处理';
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            if (item.kind == 'approval') ...[
              Text(item.method.contains('fileChange') ? '允许修改文件' : '允许运行命令'),
              for (final field in [
                'command',
                'cwd',
                'reason',
                'grantRoot',
                'additionalPermissions',
              ])
                if (item.params[field] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: SelectableText(
                      '${_fieldLabel(field)}：${_detail(item.params[field])}',
                    ),
                  ),
              const SizedBox(height: 12),
              if (item.canRespond)
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final decision in item.decisions)
                      if (_decisionLabels.containsKey(decision))
                        OutlinedButton(
                          onPressed: enabled
                              ? () => widget.onRespond({'decision': decision})
                              : null,
                          child: Text(_decisionLabels[decision]!),
                        ),
                  ],
                ),
            ],
            if (item.kind == 'userInput')
              Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final question in item.questions)
                      _question(question, enabled),
                    if (item.canRespond)
                      FilledButton(
                        onPressed: enabled ? _submit : null,
                        child: const Text('提交回答'),
                      ),
                  ],
                ),
              ),
            if (waiting) const Text('已提交，等待确认…'),
            if (!item.canRespond) const Text('请在 Codex 桌面端处理，处理结果会自动同步。'),
            if (!widget.enabled && item.canRespond && !waiting)
              const Text('连接恢复后可继续处理。'),
          ],
        ),
      ),
    );
  }

  Widget _question(Map<String, dynamic> question, bool enabled) {
    final id = question['id'] as String? ?? '';
    final options = question['options'] is List
        ? question['options'] as List
        : const [];
    final custom = options.isEmpty || _custom.contains(id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: FormField<String>(
        validator: (_) =>
            (_answers[id]?.trim().isNotEmpty ?? false) ? null : '请回答此问题',
        builder: (field) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              question['question'] as String? ??
                  question['header'] as String? ??
                  '',
            ),
            if (options.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final raw in options)
                    if (raw is Map && raw['label'] is String)
                      Tooltip(
                        message: raw['description'] as String? ?? '',
                        child: ChoiceChip(
                          label: Text(raw['label'] as String),
                          selected: !custom && _answers[id] == raw['label'],
                          onSelected: enabled
                              ? (_) => setState(() {
                                  _custom.remove(id);
                                  _answers[id] = raw['label'] as String;
                                })
                              : null,
                        ),
                      ),
                  if (question['isOther'] == true)
                    ChoiceChip(
                      label: const Text('其他回答'),
                      selected: custom,
                      onSelected: enabled
                          ? (_) => setState(() {
                              _custom.add(id);
                              _answers.remove(id);
                            })
                          : null,
                    ),
                ],
              ),
              if (!custom && _answers[id] != null)
                for (final raw in options)
                  if (raw is Map &&
                      raw['label'] == _answers[id] &&
                      raw['description'] is String)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(raw['description'] as String),
                    ),
            ],
            if (custom)
              TextFormField(
                key: ValueKey('${widget.item.id}:$id'),
                enabled: enabled,
                initialValue: _answers[id],
                obscureText: question['isSecret'] == true,
                enableSuggestions: question['isSecret'] != true,
                autocorrect: question['isSecret'] != true,
                maxLength: 20000,
                decoration: const InputDecoration(
                  hintText: '输入回答',
                  counterText: '',
                ),
                onChanged: (value) => _answers[id] = value,
              ),
            if (field.hasError)
              Text(
                field.errorText!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    );
  }

  void _submit() {
    if (_form.currentState?.validate() != true) return;
    widget.onRespond({
      'answers': {
        for (final question in widget.item.questions)
          question['id'] as String: {
            'answers': [_answers[question['id']]!.trim()],
          },
      },
    });
    // Answers, including secret fields, live only in this widget. Do not put
    // them into the persisted conversation or task cache.
  }
}

const _decisionLabels = {
  'accept': '允许本次',
  'acceptForSession': '允许本任务',
  'decline': '拒绝',
  'cancel': '取消',
};
String _fieldLabel(String field) =>
    const {
      'command': '命令',
      'cwd': '目录',
      'reason': '原因',
      'grantRoot': '授权目录',
      'additionalPermissions': '额外权限',
    }[field] ??
    field;
String _detail(Object? value) =>
    value is String ? value : const JsonEncoder.withIndent('  ').convert(value);
