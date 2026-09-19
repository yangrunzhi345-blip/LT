import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/app_page_scaffold.dart';
import '../../../../providers/riverpod_providers.dart';

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
    final content = _controller.text.trim();
    if (_isImporting || content.isEmpty) {
      setState(() => _error = '请先粘贴聊天内容');
      return;
    }
    final chat = ref.read(chatProvider);
    if (_format != 'jsonl' && chat.apiKey.isEmpty) {
      setState(() => _error = '请先在设置中配置 API Key');
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
        throw const FormatException('AI 未能解析出有效对话，请检查内容格式');
      }
      await chat.importFromJsonl(jsonl, '');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('导入成功')),
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() => _error = '导入失败：${error.toString().split('\n').first}');
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  @override
  Widget build(BuildContext context) => AppPageScaffold(
        title: '导入聊天',
        bottomBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: FilledButton.icon(
              key: const Key('chat-import-submit'),
              onPressed: _isImporting ? null : _import,
              icon: const Icon(Icons.file_download_outlined),
              label: Text(_isImporting ? '解析中...' : '导入'),
            ),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('格式', style: Theme.of(context).textTheme.titleSmall),
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
              decoration: const InputDecoration(
                labelText: '聊天内容',
                hintText: '在此粘贴聊天内容...',
                border: OutlineInputBorder(),
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
        SnackBar(content: Text(path == null ? '保存失败' : '已保存: $path')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败：$error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AppPageScaffold(
        title: '导出聊天',
        body: FutureBuilder<Map<String, String>>(
          future: _exports,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: TextButton.icon(
                  onPressed: () => setState(() => _exports = _load()),
                  icon: const Icon(Icons.refresh),
                  label: const Text('加载失败，重试'),
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
                const Text('导出内容可能包含对话和用户输入，请妥善保管。'),
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
                            const SnackBar(content: Text('已复制到剪贴板')),
                          );
                        }
                      },
                      icon: const Icon(Icons.copy),
                      label: const Text('复制全部'),
                    ),
                    FilledButton.icon(
                      key: const Key('chat-export-save'),
                      onPressed: _isSaving ? null : () => _save(content),
                      icon: const Icon(Icons.save_alt),
                      label: Text(_isSaving ? '保存中...' : '保存文件'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text('${content.length} 字符'),
                const SizedBox(height: 8),
                SelectableText(content),
              ],
            );
          },
        ),
      );
}
