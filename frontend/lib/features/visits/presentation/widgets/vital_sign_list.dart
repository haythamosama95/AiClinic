import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/application/visit_rpc_messages.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/domain/catalog_item.dart';
import 'package:ai_clinic/features/visits/domain/catalog_name_normalizer.dart';
import 'package:ai_clinic/features/visits/domain/visit_vital_sign.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/health_profile_card_tokens.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/save_to_catalog_dialog.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_page_tokens.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_text_field.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_shared_widgets.dart';

const _customVitalSignKey = '__custom__';

/// Opens the add-vital-sign dialog used by [VitalSignList] and [VitalSignsTrackingCard].
Future<void> showVitalSignAddDialog({
  required BuildContext context,
  required String visitId,
  required List<CatalogItem> predefinedVitalSigns,
  required VoidCallback onRefresh,
  String? initialPredefinedId,
}) {
  return AppDialog.show<void>(
    context: context,
    title: 'Add vital sign',
    barrierDismissible: false,
    bodyBuilder: (dialogContext) => _VitalSignAddDialogBody(
      visitId: visitId,
      predefinedVitalSigns: predefinedVitalSigns,
      initialPredefinedId: initialPredefinedId,
      hostContext: context,
      onCancel: () => Navigator.of(dialogContext).pop(),
      onRefresh: onRefresh,
      onSaved: () {
        Navigator.of(dialogContext).pop();
        onRefresh();
      },
    ),
  );
}

/// Editable vital sign list for visit documentation (013 US2).
class VitalSignList extends ConsumerStatefulWidget {
  const VitalSignList({
    required this.visitId,
    required this.vitalSigns,
    required this.predefinedVitalSigns,
    required this.canEdit,
    required this.onChanged,
    required this.sectionTitle,
    required this.sectionKind,
    this.showSectionCard = true,
    this.embeddedInTrackingCard = false,
    this.expandBody = false,
    super.key,
  });

  final String visitId;
  final List<VisitVitalSign> vitalSigns;
  final List<CatalogItem> predefinedVitalSigns;
  final bool canEdit;
  final VoidCallback onChanged;
  final String sectionTitle;
  final VisitPanelKind sectionKind;
  final bool showSectionCard;
  final bool embeddedInTrackingCard;
  final bool expandBody;

  @override
  ConsumerState<VitalSignList> createState() => _VitalSignListState();
}

class _VitalSignListState extends ConsumerState<VitalSignList> {
  String? _editingVitalSignId;
  bool _isSubmitting = false;
  String? _errorMessage;

  Future<void> _openAddDialog({String? initialPredefinedId}) async {
    if (_isSubmitting) return;

    await showVitalSignAddDialog(
      context: context,
      visitId: widget.visitId,
      predefinedVitalSigns: widget.predefinedVitalSigns,
      onRefresh: widget.onChanged,
      initialPredefinedId: initialPredefinedId,
    );
  }

  List<Widget>? _shelfActions() {
    if (!widget.canEdit || widget.embeddedInTrackingCard) return null;

    return [
      AppNotchedCardAction(
        providesOwnBackground: true,
        action: AppButton(
          key: const Key('vital_sign_add_button'),
          label: 'Add vital sign',
          size: AppFieldSize.sm,
          icon: const Icon(Icons.add, size: 18),
          onPressed: _isSubmitting ? null : () => _openAddDialog(),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final body = _buildBody();

    if (!widget.showSectionCard || widget.embeddedInTrackingCard) {
      return body;
    }

    return VisitSectionCard(
      kind: widget.sectionKind,
      title: widget.sectionTitle,
      headerActions: _shelfActions(),
      child: body,
    );
  }

  Widget _buildBody() {
    final signs = widget.vitalSigns;

    if (signs.isEmpty && widget.canEdit && widget.embeddedInTrackingCard) {
      final cardTheme = context.healthProfileCardTheme;
      final theme = context.visitTheme;
      final emptyHint = VisitEmptyHint(
        key: const Key('vital_sign_empty'),
        message: 'Blood pressure, heart rate, temperature, and other measurements for this visit.',
        icon: widget.sectionKind.icon,
        maxMessageWidth: HealthProfileCardTokens.emptyMessageMaxWidth,
        actionLabel: 'Add vital sign',
        onAction: _isSubmitting ? null : () => _openAddDialog(),
        actionKey: const Key('vital_sign_add_button'),
      );

      return TiltedBackgroundIconStack(
        icon: widget.sectionKind.icon,
        iconSize: HealthProfileCardTokens.sectionWatermarkIconSize,
        iconColor: cardTheme.sectionWatermark(theme.pulse),
        fillChild: widget.expandBody,
        alignment: Alignment.center,
        child: widget.expandBody ? Center(child: emptyHint) : emptyHint,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!widget.showSectionCard && !widget.embeddedInTrackingCard && widget.canEdit && signs.isNotEmpty) ...[
          Align(
            alignment: Alignment.centerRight,
            child: AppButton(
              key: const Key('vital_sign_add_button'),
              label: 'Add vital sign',
              size: AppFieldSize.sm,
              variant: AppButtonVariant.ghost,
              icon: Icon(Icons.add, size: 18, color: context.visitTheme.pulse),
              onPressed: _isSubmitting ? null : () => _openAddDialog(),
            ),
          ),
          const SizedBox(height: SpacingTokens.sm),
        ],
        if (_errorMessage != null) ...[
          const SizedBox(height: SpacingTokens.sm),
          Text(
            _errorMessage!,
            key: const Key('vital_sign_error'),
            style: context.visitTheme.caption(color: context.visitTheme.danger),
          ),
        ],
        if (signs.isEmpty && !widget.embeddedInTrackingCard)
          const VisitEmptyHint(
            key: Key('vital_sign_empty'),
            message: 'No vital signs recorded yet.',
            icon: Icons.monitor_heart_outlined,
          ),
        if (signs.isNotEmpty && _editingVitalSignId == null)
          Wrap(
            spacing: SpacingTokens.sm,
            runSpacing: SpacingTokens.sm,
            children: [
              for (final sign in signs)
                VitalSignCardView(
                  sign: sign,
                  canEdit: widget.canEdit,
                  onEdit: () => setState(() => _editingVitalSignId = sign.id),
                  onArchive: () => _archiveSign(sign),
                ),
            ],
          ),
        ...signs
            .where((sign) => _editingVitalSignId == sign.id)
            .map(
              (sign) => Padding(
                padding: const EdgeInsets.only(top: SpacingTokens.sm),
                child: _editingVitalSignId == sign.id
                    ? VitalSignFormView(
                        key: Key('vital_sign_edit_form_${sign.id}'),
                        predefinedVitalSigns: widget.predefinedVitalSigns,
                        initialSign: sign,
                        isSubmitting: _isSubmitting,
                        onSubmit: (data) => _updateSign(sign, data),
                        onCancel: () => setState(() => _editingVitalSignId = null),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
      ],
    );
  }

  Future<void> _updateSign(VisitVitalSign existing, VitalSignFormData data) async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final normalizedName = CatalogNameNormalizer.normalize(data.name);
      if (normalizedName.isEmpty || data.value.trim().isEmpty) {
        throw RpcFailure(
          RpcResult(success: false, errorCode: 'INVALID_INPUT', errorMessage: 'Name and value are required.'),
        );
      }

      final trimmedValue = data.value.trim();
      final trimmedUnit = _nullableTrim(data.unit);
      final hasChanges =
          normalizedName != existing.name ||
          trimmedValue != existing.value ||
          trimmedUnit != existing.unit ||
          data.predefinedVitalSignId != existing.predefinedVitalSignId;

      if (hasChanges) {
        await ref
            .read(visitRepositoryProvider)
            .updateVisitVitalSign(
              vitalSignId: existing.id,
              name: normalizedName,
              value: trimmedValue,
              unit: trimmedUnit,
              predefinedVitalSignId: data.predefinedVitalSignId,
            );
      }

      if (!mounted) return;

      final becameCustom = data.predefinedVitalSignId == null && existing.predefinedVitalSignId != null;
      final wasCustom = existing.predefinedVitalSignId == null;
      final nameChanged = normalizedName != existing.name;

      setState(() {
        _editingVitalSignId = null;
        _isSubmitting = false;
      });
      widget.onChanged();

      if (mounted && (becameCustom || (wasCustom && nameChanged))) {
        await _maybeSaveCustomToCatalog(normalizedName: normalizedName, defaultUnit: trimmedUnit);
      }
    } on RpcFailure catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = visitMessageForRpc(e);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  Future<void> _archiveSign(VisitVitalSign sign) async {
    final remove = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove vital sign?'),
        content: Text('Remove "${sign.name}" from this visit?'),
        actions: [
          AppButton(label: 'Cancel', variant: AppButtonVariant.secondary, onPressed: () => Navigator.pop(ctx, false)),
          AppButton(label: 'Remove', variant: AppButtonVariant.destructive, onPressed: () => Navigator.pop(ctx, true)),
        ],
      ),
    );
    if (remove != true || !mounted) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await ref.read(visitRepositoryProvider).archiveVisitVitalSign(vitalSignId: sign.id);
      if (mounted) {
        setState(() => _isSubmitting = false);
        widget.onChanged();
      }
    } on RpcFailure catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = visitMessageForRpc(e);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  Future<void> _maybeSaveCustomToCatalog({required String normalizedName, String? defaultUnit}) async {
    if (!mounted) return;
    await _maybeSaveCustomVitalToCatalog(
      ref: ref,
      context: context,
      normalizedName: normalizedName,
      defaultUnit: defaultUnit,
      onCatalogSaved: widget.onChanged,
    );
  }

  String? _nullableTrim(String? value) => _nullableTrimVitalField(value);
}

/// Add-vital-sign form hosted inside [AppDialog].
class _VitalSignAddDialogBody extends ConsumerStatefulWidget {
  const _VitalSignAddDialogBody({
    required this.visitId,
    required this.predefinedVitalSigns,
    required this.hostContext,
    required this.onCancel,
    required this.onRefresh,
    required this.onSaved,
    this.initialPredefinedId,
  });

  final String visitId;
  final List<CatalogItem> predefinedVitalSigns;
  final BuildContext hostContext;
  final String? initialPredefinedId;
  final VoidCallback onCancel;
  final VoidCallback onRefresh;
  final VoidCallback onSaved;

  @override
  ConsumerState<_VitalSignAddDialogBody> createState() => _VitalSignAddDialogBodyState();
}

class _VitalSignAddDialogBodyState extends ConsumerState<_VitalSignAddDialogBody> {
  bool _isSubmitting = false;

  Future<void> _submit(VitalSignFormData data) async {
    setState(() => _isSubmitting = true);

    try {
      final normalizedName = CatalogNameNormalizer.normalize(data.name);
      if (normalizedName.isEmpty || data.value.trim().isEmpty) {
        throw RpcFailure(
          RpcResult(success: false, errorCode: 'INVALID_INPUT', errorMessage: 'Name and value are required.'),
        );
      }

      final isCustom = data.predefinedVitalSignId == null;
      await ref
          .read(visitRepositoryProvider)
          .createVisitVitalSign(
            visitId: widget.visitId,
            name: normalizedName,
            value: data.value.trim(),
            unit: _nullableTrimVitalField(data.unit),
            predefinedVitalSignId: data.predefinedVitalSignId,
          );

      if (!mounted) return;

      if (isCustom) {
        await _maybeSaveCustomVitalToCatalog(
          ref: ref,
          context: widget.hostContext,
          normalizedName: normalizedName,
          defaultUnit: _nullableTrimVitalField(data.unit),
          onCatalogSaved: widget.onRefresh,
        );
      }

      widget.onSaved();
    } on RpcFailure catch (e) {
      if (mounted) AppToast.error(context, message: visitMessageForRpc(e));
    } catch (e) {
      if (mounted) AppToast.error(context, message: e.toString());
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return VitalSignFormView(
      key: const Key('vital_sign_add_form'),
      predefinedVitalSigns: widget.predefinedVitalSigns,
      initialPredefinedId: widget.initialPredefinedId,
      isSubmitting: _isSubmitting,
      inDialog: true,
      onSubmit: _submit,
      onCancel: widget.onCancel,
    );
  }
}

Future<void> _maybeSaveCustomVitalToCatalog({
  required WidgetRef ref,
  required BuildContext context,
  required String normalizedName,
  required VoidCallback onCatalogSaved,
  String? defaultUnit,
}) async {
  final save = await SaveToCatalogDialog.show(context, normalizedName: normalizedName, itemTypeLabel: 'vital sign');
  if (save != true || !context.mounted) return;

  try {
    await ref.read(visitRepositoryProvider).createPredefinedVitalSign(name: normalizedName, defaultUnit: defaultUnit);
    if (!context.mounted) return;
    AppToast.success(context, message: 'Saved "$normalizedName" to your vital sign catalog.');
    onCatalogSaved();
  } on RpcFailure catch (e) {
    if (!context.mounted) return;
    AppToast.error(context, message: visitMessageForRpc(e));
  } catch (e) {
    if (!context.mounted) return;
    AppToast.error(context, message: e.toString());
  }
}

String? _nullableTrimVitalField(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// Read-only vital sign metric tile.
class VitalSignCardView extends StatelessWidget {
  const VitalSignCardView({required this.sign, this.canEdit = false, this.onEdit, this.onArchive, super.key});

  final VisitVitalSign sign;
  final bool canEdit;
  final VoidCallback? onEdit;
  final VoidCallback? onArchive;

  @override
  Widget build(BuildContext context) {
    final theme = context.visitTheme;
    final hasUnit = sign.unit != null && sign.unit!.isNotEmpty;

    return ConstrainedBox(
      key: Key('vital_sign_card_${sign.id}'),
      constraints: const BoxConstraints(minWidth: VisitPageTokens.metricTileMinWidth),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.tile,
          borderRadius: BorderRadius.circular(theme.tileRadius),
          border: Border.all(color: theme.hairline),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(SpacingTokens.md, SpacingTokens.md, SpacingTokens.sm, SpacingTokens.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(sign.name.toUpperCase(), style: theme.eyebrow(size: 10).copyWith(letterSpacing: 1.1)),
                  ),
                  if (canEdit)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppIconButton(
                          key: Key('vital_sign_edit_${sign.id}'),
                          icon: const Icon(Icons.edit_outlined, size: 16),
                          tooltip: 'Edit',
                          onPressed: onEdit,
                        ),
                        AppIconButton(
                          key: Key('vital_sign_archive_${sign.id}'),
                          icon: const Icon(Icons.close_rounded, size: 16),
                          tooltip: 'Remove',
                          onPressed: onArchive,
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: SpacingTokens.sm),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(sign.value, style: theme.readout(color: theme.ink, size: 24)),
                  if (hasUnit) ...[
                    const SizedBox(width: 4),
                    Text(sign.unit!, style: theme.readout(color: theme.mutedInk, size: 12)),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Form data for creating or updating a vital sign line.
class VitalSignFormData {
  const VitalSignFormData({required this.name, required this.value, this.unit, this.predefinedVitalSignId});

  final String name;
  final String value;
  final String? unit;
  final String? predefinedVitalSignId;
}

/// Add/edit form for a vital sign line.
class VitalSignFormView extends StatefulWidget {
  const VitalSignFormView({
    required this.predefinedVitalSigns,
    required this.onSubmit,
    required this.onCancel,
    this.initialSign,
    this.initialPredefinedId,
    this.isSubmitting = false,
    this.inDialog = false,
    super.key,
  });

  final List<CatalogItem> predefinedVitalSigns;
  final VisitVitalSign? initialSign;
  final String? initialPredefinedId;
  final bool isSubmitting;
  final bool inDialog;
  final Future<void> Function(VitalSignFormData data) onSubmit;
  final VoidCallback onCancel;

  @override
  State<VitalSignFormView> createState() => _VitalSignFormViewState();
}

class _VitalSignFormViewState extends State<VitalSignFormView> {
  late String _selectedKey;
  late final TextEditingController _customName;
  late final TextEditingController _value;
  late final TextEditingController _unit;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialSign;
    if (initial?.predefinedVitalSignId != null) {
      _selectedKey = initial!.predefinedVitalSignId!;
    } else if (initial != null) {
      _selectedKey = _customVitalSignKey;
    } else if (widget.initialPredefinedId != null &&
        widget.predefinedVitalSigns.any((item) => item.id == widget.initialPredefinedId)) {
      _selectedKey = widget.initialPredefinedId!;
    } else {
      _selectedKey = widget.predefinedVitalSigns.isNotEmpty
          ? widget.predefinedVitalSigns.first.id
          : _customVitalSignKey;
    }

    _customName = TextEditingController(text: initial?.predefinedVitalSignId == null ? (initial?.name ?? '') : '');
    _value = TextEditingController(text: initial?.value ?? '');
    _unit = TextEditingController(text: initial?.unit ?? _defaultUnitForSelection(_selectedKey));
  }

  @override
  void dispose() {
    _customName.dispose();
    _value.dispose();
    _unit.dispose();
    super.dispose();
  }

  String? _defaultUnitForSelection(String key) {
    if (key == _customVitalSignKey) return null;
    return widget.predefinedVitalSigns.where((item) => item.id == key).map((item) => item.defaultUnit).firstOrNull;
  }

  CatalogItem? _selectedPredefined() {
    if (_selectedKey == _customVitalSignKey) return null;
    for (final item in widget.predefinedVitalSigns) {
      if (item.id == _selectedKey) return item;
    }
    return null;
  }

  bool get _isCustom => _selectedKey == _customVitalSignKey;

  Map<String, String> get _selectItems {
    final items = <String, String>{
      for (final item in widget.predefinedVitalSigns) item.name: item.id,
      'Custom…': _customVitalSignKey,
    };
    return items;
  }

  Future<void> _submit() async {
    final predefined = _selectedPredefined();
    final name = _isCustom ? _customName.text : (predefined?.name ?? '');
    final data = VitalSignFormData(
      name: name,
      value: _value.text,
      unit: _unit.text,
      predefinedVitalSignId: predefined?.id,
    );
    await widget.onSubmit(data);
  }

  @override
  Widget build(BuildContext context) {
    final form = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.predefinedVitalSigns.isNotEmpty)
          AppSelect<String>(
            key: const Key('vital_sign_predefined_select'),
            label: 'Vital sign',
            items: _selectItems,
            value: _selectItems.containsValue(_selectedKey) ? _selectedKey : _customVitalSignKey,
            enabled: !widget.isSubmitting,
            onChanged: (key) {
              if (key == null) return;
              setState(() {
                _selectedKey = key;
                if (!_isCustom) {
                  _customName.clear();
                  final defaultUnit = _defaultUnitForSelection(key);
                  if (defaultUnit != null) {
                    _unit.text = defaultUnit;
                  }
                }
              });
            },
          )
        else
          VisitTextInput(
            key: const Key('vital_sign_custom_name'),
            label: 'Vital sign name',
            controller: _customName,
            enabled: !widget.isSubmitting,
          ),
        if (_isCustom && widget.predefinedVitalSigns.isNotEmpty) ...[
          const SizedBox(height: SpacingTokens.sm),
          VisitTextInput(
            key: const Key('vital_sign_custom_name'),
            label: 'Custom name',
            controller: _customName,
            enabled: !widget.isSubmitting,
          ),
        ],
        const SizedBox(height: SpacingTokens.sm),
        VisitTextInput(
          key: const Key('vital_sign_value'),
          label: 'Value',
          controller: _value,
          enabled: !widget.isSubmitting,
        ),
        const SizedBox(height: SpacingTokens.sm),
        VisitTextInput(
          key: const Key('vital_sign_unit'),
          label: 'Unit (optional)',
          controller: _unit,
          enabled: !widget.isSubmitting,
        ),
        const SizedBox(height: SpacingTokens.md),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            AppButton(
              label: 'Cancel',
              variant: AppButtonVariant.secondary,
              expand: false,
              onPressed: widget.isSubmitting ? null : widget.onCancel,
            ),
            const SizedBox(width: SpacingTokens.sm),
            AppButton(
              key: const Key('vital_sign_form_submit'),
              label: widget.isSubmitting ? 'Saving…' : (widget.initialSign == null ? 'Add' : 'Save'),
              isLoading: widget.isSubmitting,
              expand: false,
              onPressed: widget.isSubmitting ? null : _submit,
            ),
          ],
        ),
      ],
    );

    if (widget.inDialog) {
      return form;
    }

    final theme = context.visitTheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.tile,
        borderRadius: BorderRadius.circular(theme.tileRadius),
        border: Border.all(color: theme.pulse.withValues(alpha: 0.35)),
      ),
      child: Padding(padding: const EdgeInsets.all(SpacingTokens.md), child: form),
    );
  }
}
