part of 'runtime_state_hub_page.dart';

class RuntimeStateEditPage extends ConsumerStatefulWidget {
  final RuntimeEntityState entity;

  const RuntimeStateEditPage({super.key, required this.entity});

  @override
  ConsumerState<RuntimeStateEditPage> createState() =>
      _RuntimeStateEditPageState();
}

class _RuntimeStateEditPageState extends ConsumerState<RuntimeStateEditPage> {
  final _formKey = GlobalKey<FormState>();
  late final List<RuntimeStatePathDefinition> _definitions =
      RuntimeStateSchemaRegistry.definitions
          .where((definition) =>
              definition.entities.contains(widget.entity.entityType) &&
              RuntimeStateSchemaRegistry.canonicalPath(
                      widget.entity.entityType, definition.id) ==
                  definition.id)
          .toList(growable: false);
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, Object?> _values = {};
  final Set<String> _resetRequested = {};
  final Set<String> _touched = {};
  int? _baseRevision;
  bool _loading = true;
  bool _saving = false;
  String? _conflictMessage;

  bool get _hasChanges => _definitions.any((definition) {
        final path = definition.id;
        if (_resetRequested.contains(path)) return true;
        if (!_touched.contains(path)) return false;
        final original = widget.entity.overlay[path];
        if (original == null && !_touched.contains(path)) return false;
        final value = _draftValue(definition);
        return value != original;
      });

  @override
  void initState() {
    super.initState();
    for (final definition in _definitions) {
      final value = widget.entity.overlay[definition.id];
      _values[definition.id] = value;
      if (definition.valueKind == RuntimeStateValueKind.text ||
          definition.valueKind == RuntimeStateValueKind.integer ||
          definition.valueKind == RuntimeStateValueKind.number) {
        _controllers[definition.id] =
            TextEditingController(text: value?.toString() ?? '');
      }
    }
    _loadRevision();
  }

  Future<void> _loadRevision() async {
    final chat = ref.read(chatProvider);
    final adventureId = chat.currentAdventureId;
    if (adventureId == null) return;
    final repo = ref.read(adventureRepoProvider);
    final current = await repo.getCurrentRuntimeState(
      adventureId: adventureId,
      branchId: chat.currentBranchId,
      entityType: widget.entity.entityType,
      entityId: widget.entity.entityId,
    );
    final head = await repo.getRuntimeHead(adventureId, chat.currentBranchId);
    if (!mounted) return;
    setState(() {
      _baseRevision = head.revision;
      _conflictMessage = null;
      _loading = false;
      final entity = current.entities.values.firstOrNull;
      if (entity == null) return;
      for (final definition in _definitions) {
        final value = entity.overlay[definition.id];
        _values[definition.id] = value;
        _resetRequested.remove(definition.id);
        _touched.remove(definition.id);
        _controllers[definition.id]?.text = value?.toString() ?? '';
      }
    });
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    if (!_formKey.currentState!.validate()) return;
    final chat = ref.read(chatProvider);
    final adventureId = chat.currentAdventureId;
    if (adventureId == null) return;
    setState(() => _saving = true);
    try {
      final repo = ref.read(adventureRepoProvider);
      final changes = <RuntimeStateChangeProposal>[];
      for (final definition in _definitions) {
        final path = definition.id;
        final original = widget.entity.overlay[path];
        final operation = _resetRequested.contains(path)
            ? RuntimeChangeOperation.remove
            : RuntimeChangeOperation.set;
        final value = operation == RuntimeChangeOperation.remove
            ? null
            : _draftValue(definition);
        if (!_resetRequested.contains(path) && !_touched.contains(path)) {
          continue;
        }
        if (operation == RuntimeChangeOperation.remove || value != original) {
          changes.add(RuntimeStateChangeProposal(
            entityType: widget.entity.entityType,
            entityId: widget.entity.entityId,
            changeKind: RuntimeChangeKind.primary,
            operation: operation,
            path: path,
            value: value,
            reason: 'User edit',
          ));
        }
      }
      if (changes.isNotEmpty) {
        final expectedRevision = _baseRevision;
        if (expectedRevision == null) return;
        await repo.commitRuntimeMutation(RuntimeStateMutation(
          requestId: 'user-edit-${DateTime.now().microsecondsSinceEpoch}',
          adventureId: adventureId,
          branchId: chat.currentBranchId,
          draft: RuntimeStateCommitDraft(
            expectedRevision: expectedRevision,
            changes: changes,
            summary: 'User edited ${widget.entity.entityId}',
            source: RuntimeEventSource.userEdit,
            causeType: 'user_edit',
          ),
        ));
      }
      if (mounted) Navigator.of(context).pop(true);
    } on RuntimeHeadConflict {
      if (mounted) {
        setState(() => _conflictMessage = _messageText(l10n, 'conflict'));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Object? _draftValue(RuntimeStatePathDefinition definition) {
    if (_controllers[definition.id] case final controller?) {
      final text = controller.text.trim();
      return switch (definition.valueKind) {
        RuntimeStateValueKind.integer => int.tryParse(text),
        RuntimeStateValueKind.number => num.tryParse(text),
        _ => text,
      };
    }
    return _values[definition.id];
  }

  String _label(AppLocalizations l10n, String path) => switch (path) {
        'hp' => _labelText(l10n, 'hp'),
        'mp' => _labelText(l10n, 'mp'),
        'energy' => _labelText(l10n, 'energy'),
        'experience' => _labelText(l10n, 'experience'),
        'level' => _labelText(l10n, 'level'),
        'base_atk' => _labelText(l10n, 'base_atk'),
        'base_def' => _labelText(l10n, 'base_def'),
        'base_speed' => _labelText(l10n, 'base_speed'),
        'affinity' => _labelText(l10n, 'affinity'),
        'life_status' => _labelText(l10n, 'life_status'),
        'lifecycle_status' => _labelText(l10n, 'lifecycle_status'),
        'global_flag' => _labelText(l10n, 'global_flag'),
        'faction_id' => _labelText(l10n, 'faction_id'),
        'former_faction_id' => _labelText(l10n, 'former_faction_id'),
        'controller_id' => _labelText(l10n, 'controller_id'),
        'relationship' ||
        'relation_type' ||
        'relationship_type' ||
        'type' =>
          _labelText(l10n, 'relationship'),
        'strength' => l10n.runtimeStateFieldRelationshipStrength,
        'notes' => l10n.runtimeStateFieldRelationshipNotes,
        'goal' => _labelText(l10n, 'goal'),
        'status' => _labelText(l10n, 'status'),
        'control' => _labelText(l10n, 'control'),
        'environment' => _labelText(l10n, 'environment'),
        'condition' => _labelText(l10n, 'condition'),
        'influence' => _labelText(l10n, 'influence'),
        'time' => _labelText(l10n, 'time'),
        _ => l10n.runtimeStateFieldUnknown,
      };

  String? _validate(RuntimeStatePathDefinition definition, String? raw,
      AppLocalizations l10n) {
    if (_resetRequested.contains(definition.id)) return null;
    final value = _draftValue(definition);
    if (value == null) {
      return definition.valueKind == RuntimeStateValueKind.integer
          ? _messageText(l10n, 'integer')
          : definition.valueKind == RuntimeStateValueKind.number
              ? _messageText(l10n, 'number')
              : _messageText(l10n, 'required');
    }
    if (definition.valueKind == RuntimeStateValueKind.text &&
        (raw?.length ?? 0) > 1000) {
      return _messageText(l10n, 'large');
    }
    if (value is num && !value.isFinite) {
      return _messageText(l10n, 'number');
    }
    if (value is num &&
        definition.minimum != null &&
        value < definition.minimum!) {
      return _messageText(l10n, 'small');
    }
    if (value is num &&
        definition.maximum != null &&
        value > definition.maximum!) {
      return _messageText(l10n, 'large');
    }
    if (!definition.accepts(widget.entity.entityType, value)) {
      return _messageText(l10n, 'required');
    }
    return null;
  }

  Widget _field(RuntimeStatePathDefinition definition, AppLocalizations l10n) {
    final path = definition.id;
    final label = _label(l10n, path);
    final overridden = widget.entity.overlay.containsKey(path);
    final reset = _resetRequested.contains(path);
    final resetButton = overridden
        ? TextButton(
            onPressed: () => setState(() {
              if (reset) {
                _resetRequested.remove(path);
                _controllers[path]?.text =
                    widget.entity.overlay[path]?.toString() ?? '';
                _values[path] = widget.entity.overlay[path];
              } else {
                _resetRequested.add(path);
              }
            }),
            child: Text(reset
                ? _messageText(l10n, 'keep')
                : _messageText(l10n, 'reset')),
          )
        : null;
    String? validator(String? value) => _validate(definition, value, l10n);
    switch (definition.valueKind) {
      case RuntimeStateValueKind.boolean:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(label),
            value: (_values[path] as bool?) ?? false,
            onChanged: reset
                ? null
                : (value) => setState(() {
                      _touched.add(path);
                      _values[path] = value;
                    }),
          ),
          if (resetButton != null) resetButton,
        ]);
      case RuntimeStateValueKind.enumValue:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AppSelect<String>(
            value: _values[path] as String?,
            label: label,
            items: definition.enumValues
                .map((value) =>
                    AppSelectItem(value: value, label: _enumLabel(l10n, value)))
                .toList(),
            onChanged: reset
                ? null
                : (value) => setState(() {
                      _touched.add(path);
                      _values[path] = value;
                    }),
          ),
          if (resetButton != null) resetButton,
        ]);
      case RuntimeStateValueKind.integer:
      case RuntimeStateValueKind.number:
      case RuntimeStateValueKind.text:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AppTextField(
            key: ValueKey('runtime-edit-$path'),
            controller: _controllers[path],
            label: label,
            enabled: !reset,
            maxLines:
                definition.valueKind == RuntimeStateValueKind.text ? 3 : 1,
            keyboardType: definition.valueKind == RuntimeStateValueKind.text
                ? TextInputType.multiline
                : const TextInputType.numberWithOptions(
                    decimal: true, signed: true),
            validator: validator,
            onChanged: (_) => setState(() => _touched.add(path)),
          ),
          if (resetButton != null) resetButton,
        ]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    if (_loading) return const Center(child: CircularProgressIndicator());
    return AppPageScaffold(
      title: l10n.editAction,
      maxWidth: 760,
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
                RuntimeStatePresentation.entityLabel(
                    widget.entity.entityType, null, l10n),
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            if (_conflictMessage != null) ...[
              Text(_conflictMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
              TextButton(
                  onPressed: _loadRevision, child: Text(l10n.reloadAction)),
            ],
            for (final definition in _definitions)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _field(definition, l10n),
              ),
            FilledButton.icon(
              onPressed: _saving || !_hasChanges || _conflictMessage != null
                  ? null
                  : _save,
              icon: const AppSvgIcon('save'),
              label: Text(l10n.saveAction),
            ),
          ],
        ),
      ),
    );
  }

  String _labelText(AppLocalizations l10n, String path) {
    return switch (path) {
      'hp' => l10n.runtimeStateFieldHp,
      'mp' => l10n.runtimeStateFieldMp,
      'energy' => l10n.runtimeStateFieldEnergy,
      'experience' => l10n.runtimeStateFieldExperience,
      'level' => l10n.runtimeStateFieldLevel,
      'base_atk' => l10n.runtimeStateFieldBaseAtk,
      'base_def' => l10n.runtimeStateFieldBaseDef,
      'base_speed' => l10n.runtimeStateFieldBaseSpeed,
      'affinity' => l10n.runtimeStateFieldAffinity,
      'life_status' => l10n.runtimeStateFieldLifeStatus,
      'lifecycle_status' => l10n.runtimeStateFieldLifecycleStatus,
      'global_flag' => l10n.runtimeStateFieldGlobalFlag,
      'faction_id' => l10n.runtimeStateFieldFactionId,
      'former_faction_id' => l10n.runtimeStateFieldFormerFactionId,
      'controller_id' => l10n.runtimeStateFieldControllerId,
      'relationship' ||
      'relation_type' ||
      'relationship_type' ||
      'type' =>
        l10n.runtimeStateFieldRelationship,
      'strength' => l10n.runtimeStateFieldRelationshipStrength,
      'notes' => l10n.runtimeStateFieldRelationshipNotes,
      'goal' => l10n.runtimeStateFieldGoal,
      'status' => l10n.runtimeStateFieldStatus,
      'control' => l10n.runtimeStateFieldControl,
      'environment' => l10n.runtimeStateFieldEnvironment,
      'condition' => l10n.runtimeStateFieldCondition,
      'influence' => l10n.runtimeStateFieldInfluence,
      'time' => l10n.runtimeStateFieldTime,
      _ => l10n.runtimeStateFieldUnknown,
    };
  }

  String _messageText(AppLocalizations l10n, String type) {
    return switch (type) {
      'reset' => l10n.runtimeStateResetToBaseline,
      'keep' => l10n.runtimeStateKeepOverride,
      'conflict' => l10n.runtimeStateEditConflict,
      'integer' => l10n.runtimeStateIntegerRequired,
      'number' => l10n.runtimeStateNumberRequired,
      'small' => l10n.runtimeStateValueTooSmall,
      'large' => l10n.runtimeStateValueTooLarge,
      _ => l10n.runtimeStateValueRequired,
    };
  }

  String _enumLabel(AppLocalizations l10n, String value) {
    return switch (value) {
      'alive' => l10n.runtimeStateAlive,
      'dead' => l10n.runtimeStateDead,
      'active' => l10n.runtimeStateActive,
      'inactive' => l10n.runtimeStateInactive,
      'destroyed' => l10n.runtimeStateDestroyed,
      _ => value,
    };
  }
}
