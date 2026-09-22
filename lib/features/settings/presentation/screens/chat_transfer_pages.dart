import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/app_page_scaffold.dart';
import '../../../../providers/riverpod_providers.dart';
import '../../../../l10n/generated/app_localizations.dart';

const _formats = <(String, String)>[
  ('TXT', 'txt'),
  ('Markdown', 'md'),
  ('HTML', 'html'),
  ('JSONL', 'jsonl'),
];

class ImportPage extends ConsumerStatefulWidget {
  const ImportPage({super.key});

  @override
  ConsumerState<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends ConsumerState<ImportPage> {
  final _controller = TextEditingController();
  String _format = 'txt';
  bool _isImporting = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    final l10n = AppLocalizations.of(context)!;
    final content = _controller.text.trim();
    if (_isImporting || content.isEmpty) {
      setState(() => _error = l10n.chatImportEmpty);
      return;
    }
    final chat = ref.read(chatProvider);
    if (_format != 'jsonl' && chat.apiKey.isEmpty) {
      setState(() => _error = l10n.apiKeyNotConfiguredPrompt);
      return;
    }
    setState(() {
      _isImporting = true;
      _error = null;
    });
    try {
      final jsonl = _format == 'jsonl'
          ? content
          : (await ref.read(aiImportServiceProvider).importChat(
                    rawContent: content,
                    fileType: _format,
                  ))
              .map(jsonEncode)
              .join('\n');
      if (jsonl.isEmpty) {
        throw FormatException(
            l10n.chatImportFailed('AI returned no valid chat'));
      }
      await chat.importFromJsonl(jsonl, '');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.chatImportSuccess)),
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() => _error = l10n.chatImportFailed(
              error.toString().split('\n').first,
            ));
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AppPageScaffold(
      title: l10n.importChatTitle,
      bottomBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            key: const Key('chat-import-submit'),
            onPressed: _isImporting ? null : _import,
            icon: const Icon(Icons.file_download_outlined),
            label: Text(
              _isImporting ? l10n.chatImportParsing : l10n.chatImportAction,
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(l10n.chatImportFormat,
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (label, value) in _formats)
                ChoiceChip(
                  label: Text(label),
                  selected: _format == value,
                  onSelected: _isImporting
                      ? null
                      : (_) => setState(() => _format = value),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('chat-import-input'),
            controller: _controller,
            minLines: 8,
            maxLines: 20,
            decoration: InputDecoration(
              labelText: l10n.chatImportLabel,
              hintText: l10n.chatImportHint,
              border: const OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    );
  }
}

class ExportPage extends ConsumerStatefulWidget {
  const ExportPage({super.key});

  @override
  ConsumerState<ExportPage> createState() => _ExportPageState();
}

class _ExportPageState extends ConsumerState<ExportPage> {
  late Future<Map<String, String>> _exports;
  String _format = 'jsonl';
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _exports = _load();
  }

  Future<Map<String, String>> _load() async {
    final chat = ref.read(chatProvider);
    final jsonl = await chat.exportToJsonl();
    return {
      'jsonl': jsonl,
      'txt': chat.exportToTxt(),
      'md': chat.exportToMarkdown(),
      'html': chat.exportToHtml(),
    };
  }

  Future<void> _save(String content) async {
    final l10n = AppLocalizations.of(context)!;
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      final path = await ref.read(conversationExportUseCaseProvider).saveToFile(
            content: content,
            extension: _format,
            title: ref.read(chatProvider).currentTitle,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              path == null ? l10n.chatSaveFailed : l10n.chatSavedPath(path)),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.chatSaveFailed)),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AppPageScaffold(
      title: l10n.exportChatTitle,
      body: FutureBuilder<Map<String, String>>(
        future: _exports,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: TextButton.icon(
                onPressed: () => setState(() => _exports = _load()),
                icon: const Icon(Icons.refresh),
                label: Text(l10n.chatLoadFailedRetry),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final content = snapshot.data![_format] ?? '';
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(l10n.chatExportWarning),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (label, value) in _formats)
                    ChoiceChip(
                      label: Text(label),
                      selected: _format == value,
                      onSelected: (_) => setState(() => _format = value),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: content));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(l10n.messageCopied)),
                        );
                      }
                    },
                    icon: const Icon(Icons.copy),
                    label: Text(l10n.copyAction),
                  ),
                  FilledButton.icon(
                    key: const Key('chat-export-save'),
                    onPressed: _isSaving ? null : () => _save(content),
                    icon: const Icon(Icons.save_alt),
                    label: Text(_isSaving ? l10n.chatSaving : l10n.saveAction),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(l10n.chatCharacterCount(content.length)),
              const SizedBox(height: 8),
              SelectableText(content),
            ],
          );
        },
      ),
    );
  }
}
