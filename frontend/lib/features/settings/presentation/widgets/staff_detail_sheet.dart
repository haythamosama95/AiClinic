import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/theme/theme.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/staff_username.dart';
import 'package:ai_clinic/features/settings/application/settings_rpc_messages.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';
import 'package:ai_clinic/features/settings/domain/staff_member_detail.dart';
import 'package:ai_clinic/features/settings/domain/update_staff_member_input.dart';
import 'package:ai_clinic/features/settings/domain/usecases/settings_use_case_providers.dart';
import 'package:ai_clinic/features/settings/presentation/providers/staff_list_notifier.dart';
import 'package:ai_clinic/features/setup/domain/branch_summary.dart';
import 'package:ai_clinic/features/setup/domain/provisioning_rules.dart';
import 'package:ai_clinic/features/setup/presentation/providers/provisioning_notifier.dart';
import 'package:ai_clinic/features/setup/presentation/providers/staff_assignable_branches_provider.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/staff_form_fields.dart';

const _sheetWidth = 520.0;

/// Right-side sheet for viewing and editing a staff member.
class StaffDetailSheet extends ConsumerStatefulWidget {
  const StaffDetailSheet({required this.member, super.key});

  final StaffListItem member;

  static Future<void> show(BuildContext context, StaffListItem member) {
    return AppSheets.showModal<void>(
      context: context,
      side: AppSheetSide.right,
      width: _sheetWidth,
      builder: (context) => StaffDetailSheet(member: member),
    );
  }

  @override
  ConsumerState<StaffDetailSheet> createState() => _StaffDetailSheetState();
}

class _StaffDetailSheetState extends ConsumerState<StaffDetailSheet> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  StaffMemberDetail? _detail;
  var _isLoading = true;
  var _isEditing = false;
  var _isSaving = false;
  var _usernameRevealed = false;
  String? _originalUsername;
  String? _errorMessage;
  StaffRole? _selectedRole;
  String? _primaryBranchId;
  late final FMultiValueNotifier<String> _branchSelection;

  @override
  void initState() {
    super.initState();
    _branchSelection = FMultiValueNotifier<String>();
    _usernameController.text = widget.member.username ?? '';
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDetail());
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _branchSelection.dispose();
    super.dispose();
  }

  Future<void> _loadDetail() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final detail = await ref.read(fetchStaffMemberUseCaseProvider)(widget.member.id);
      if (!mounted) {
        return;
      }

      if (detail == null) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'That staff member was not found. Refresh the list and try again.';
        });
        return;
      }

      _applyDetail(detail);
      setState(() {
        _detail = detail;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _errorMessage = 'Unable to load staff details. Check connectivity and try again.';
      });
    }
  }

  String? get _resolvedUsername => _detail?.username ?? widget.member.username;

  void _applyDetail(StaffMemberDetail detail) {
    _fullNameController.text = detail.fullName;
    _phoneController.text = detail.phone ?? '';
    _usernameController.text = detail.username ?? widget.member.username ?? '';
    _selectedRole = detail.role;
    _primaryBranchId = detail.primaryBranchId;
    _branchSelection.value = detail.branchIds.toSet();
  }

  bool get _canViewCredentials {
    final caller = ref.read(authSessionProvider).context?.staffProfile;
    return caller != null && ProvisioningRules.canResetStaffPassword(caller);
  }

  void _closeSheet() {
    FocusManager.instance.primaryFocus?.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
    });
  }

  void _startEditing() {
    setState(() {
      _isEditing = true;
      _errorMessage = null;
      _usernameRevealed = false;
      _originalUsername = _resolvedUsername;
      _usernameController.text = _resolvedUsername ?? '';
      _passwordController.clear();
    });
  }

  void _cancelEditing() {
    final detail = _detail;
    if (detail != null) {
      _applyDetail(detail);
    }
    setState(() {
      _isEditing = false;
      _errorMessage = null;
      _usernameController.text = _resolvedUsername ?? '';
      _passwordController.clear();
    });
  }

  String _branchAssignmentLabel() {
    final branches = widget.member.branches;
    if (branches.isEmpty) {
      return 'No branches assigned';
    }
    return branches.map((branch) => branch.isPrimary ? '${branch.name} (primary)' : branch.name).join(', ');
  }

  Future<void> _save() async {
    final detail = _detail;
    if (detail == null) {
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final role = _selectedRole;
    final branchIds = _branchSelection.value.toList();
    if (role == null) {
      return;
    }
    if (branchIds.isEmpty) {
      setState(() => _errorMessage = 'Select at least one branch assignment.');
      return;
    }

    final newUsername = _usernameController.text.trim();
    final newPassword = _passwordController.text.trim();
    final usernameChanged =
        _canViewCredentials &&
        _originalUsername != null &&
        normalizeStaffUsername(newUsername) != normalizeStaffUsername(_originalUsername!);
    final passwordChanged = _canViewCredentials && newPassword.isNotEmpty;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      await ref.read(updateStaffMemberUseCaseProvider)(
        UpdateStaffMemberInput(
          staffMemberId: detail.id,
          fullName: _fullNameController.text,
          role: role,
          branchIds: branchIds,
          phone: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
          primaryBranchId: _primaryBranchId,
        ),
      );

      if (usernameChanged) {
        final usernameResult = await ref
            .read(provisioningNotifierProvider.notifier)
            .updateStaffUsername(staffMemberId: detail.id, newUsername: newUsername);
        if (usernameResult == null) {
          if (!mounted) {
            return;
          }
          setState(() {
            _isSaving = false;
            _errorMessage = ref.read(provisioningNotifierProvider).errorMessage ?? 'Unable to update the username.';
          });
          return;
        }
      }

      var passwordWasReset = false;
      if (passwordChanged) {
        final passwordResult = await ref
            .read(provisioningNotifierProvider.notifier)
            .resetStaffPassword(staffMemberId: detail.id, newPassword: newPassword);
        if (passwordResult == null) {
          if (!mounted) {
            return;
          }
          setState(() {
            _isSaving = false;
            _errorMessage = ref.read(provisioningNotifierProvider).errorMessage ?? 'Unable to reset the password.';
          });
          return;
        }
        passwordResult.clearAssignedPassword();
        passwordWasReset = true;
      }

      ref.invalidate(staffListProvider);

      if (!mounted) {
        return;
      }

      await _loadDetail();
      if (!mounted) {
        return;
      }

      setState(() {
        _isEditing = false;
        _isSaving = false;
        _passwordController.clear();
      });
      AppToast.success(
        context,
        message: passwordWasReset ? 'Staff member and password updated.' : 'Staff member updated.',
      );
    } on RpcFailure catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSaving = false;
        _errorMessage = staffMessageForRpc(error);
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSaving = false;
        _errorMessage = 'Unable to save staff changes. Check connectivity and try again.';
      });
    }
  }

  void _onBranchChecked(String branchId, bool checked) {
    if (checked) {
      _branchSelection.update(branchId, add: true);
    } else {
      _branchSelection.update(branchId, add: false);
    }
    final selected = _branchSelection.value;
    final nextPrimary = _primaryBranchId != null && selected.contains(_primaryBranchId!)
        ? _primaryBranchId
        : (selected.isEmpty ? null : selected.first);
    setState(() => _primaryBranchId = nextPrimary);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final theme = Theme.of(context);
    final caller = ref.watch(authSessionProvider).context?.staffProfile;
    final selectableRoles = caller == null ? const <StaffRole>[] : ProvisioningRules.selectableRoles(caller);
    final branchesAsync = ref.watch(staffAssignableBranchesProvider);

    return Material(
      color: colors.popover,
      child: SizedBox(
        width: _sheetWidth,
        height: MediaQuery.sizeOf(context).height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SheetHeader(member: widget.member, isEditing: _isEditing, onClose: _closeSheet, onEdit: _startEditing),
            Expanded(
              child: _isLoading
                  ? const Center(child: AppCircularProgress())
                  : _errorMessage != null && _detail == null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(SpacingTokens.lg),
                        child: Text(_errorMessage!, textAlign: TextAlign.center),
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(SpacingTokens.lg, 0, SpacingTokens.lg, SpacingTokens.lg),
                      child: _isEditing
                          ? branchesAsync.when(
                              loading: () => const Center(child: AppCircularProgress()),
                              error: (_, _) => const Text('Unable to load branches for assignment.'),
                              data: (branches) => _buildEditForm(branches, selectableRoles),
                            )
                          : _buildViewBody(theme, colors),
                    ),
            ),
            if (_isEditing && _detail != null)
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: colors.border)),
                  color: colors.popover,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(SpacingTokens.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_errorMessage != null) ...[
                        AppAlert(variant: AppAlertVariant.destructive, title: _errorMessage!),
                        const SizedBox(height: SpacingTokens.md),
                      ],
                      Row(
                        children: [
                          Expanded(
                            child: AppButton(
                              label: 'Cancel',
                              variant: AppButtonVariant.outline,
                              expand: true,
                              onPressed: _isSaving ? null : _cancelEditing,
                            ),
                          ),
                          const SizedBox(width: SpacingTokens.md),
                          Expanded(
                            child: AppButton(
                              label: 'Update',
                              expand: true,
                              isLoading: _isSaving,
                              onPressed: _isSaving ? null : _save,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildViewBody(ThemeData theme, SemanticColors colors) {
    final detail = _detail!;
    final username = _resolvedUsername;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DetailInfoRow(label: 'Full name', value: detail.fullName),
        const SizedBox(height: SpacingTokens.lg),
        _DetailInfoRow(label: 'Phone', value: detail.phone ?? 'No phone number'),
        const SizedBox(height: SpacingTokens.lg),
        _DetailInfoRow(label: 'Role', value: StaffFormFields.roleLabel(detail.role)),
        const SizedBox(height: SpacingTokens.lg),
        _DetailInfoRow(label: 'Branches', value: _branchAssignmentLabel()),
        const SizedBox(height: SpacingTokens.lg),
        _DetailInfoRow(label: 'Status', value: detail.isActive ? 'Active' : 'Inactive'),
        const SizedBox(height: SpacingTokens.xl),
        Text('Login credentials', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: SpacingTokens.md),
        _BlurredCredentialField(
          label: 'Username',
          value: username ?? 'Unavailable',
          canReveal: _canViewCredentials && username != null,
          isRevealed: _usernameRevealed,
          unavailableMessage: _canViewCredentials && username == null
              ? 'No login username is assigned. Set one in edit mode.'
              : (_canViewCredentials ? null : 'Only administrators can view credentials.'),
          onReveal: () => setState(() => _usernameRevealed = true),
        ),
        const SizedBox(height: SpacingTokens.lg),
        _BlurredCredentialField(
          label: 'Password',
          value: '••••••••',
          canReveal: false,
          isRevealed: false,
          unavailableMessage: _canViewCredentials
              ? 'Passwords cannot be viewed. Set a new password in edit mode.'
              : 'Only administrators can manage credentials.',
          onReveal: () {},
        ),
      ],
    );
  }

  Widget _buildEditForm(List<BranchSummary> branches, List<StaffRole> selectableRoles) {
    final branchIds = branches.map((branch) => branch.id).toList();
    final branchById = {for (final branch in branches) branch.id: branch};

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_errorMessage != null) ...[
            AppAlert(variant: AppAlertVariant.destructive, title: _errorMessage!),
            const SizedBox(height: SpacingTokens.lg),
          ],
          StaffFormFields(
            mode: StaffFormFieldsMode.edit,
            usernameController: _usernameController,
            fullNameController: _fullNameController,
            phoneController: _phoneController,
            passwordController: _passwordController,
            showCredentials: _canViewCredentials,
            existing: StaffFormExistingData(
              fullName: _detail?.fullName,
              phone: _detail?.phone,
              role: _detail?.role,
              branchAssignmentLabel: _branchAssignmentLabel(),
            ),
            enabled: !_isSaving,
            selectableRoles: selectableRoles,
            selectedRole: _selectedRole,
            onRoleChanged: (role) => setState(() => _selectedRole = role),
            branchIds: branchIds,
            branchById: branchById,
            selectedBranchIds: _branchSelection.value,
            primaryBranchId: _primaryBranchId,
            onBranchChecked: _onBranchChecked,
            onPrimaryBranchChanged: (id) => setState(() => _primaryBranchId = id),
          ),
        ],
      ),
    );
  }
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.member, required this.isEditing, required this.onClose, required this.onEdit});

  final StaffListItem member;
  final bool isEditing;
  final VoidCallback onClose;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.semanticColors;

    return Padding(
      padding: const EdgeInsets.fromLTRB(SpacingTokens.lg, SpacingTokens.lg, SpacingTokens.md, SpacingTokens.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: colors.muted,
            foregroundColor: colors.foreground,
            child: Text(_initials(member.fullName), style: theme.textTheme.titleSmall),
          ),
          const SizedBox(width: SpacingTokens.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(member.fullName, style: theme.textTheme.titleLarge?.copyWith(color: colors.foreground)),
                const SizedBox(height: SpacingTokens.xs),
                Text(
                  StaffFormFields.roleLabel(member.role),
                  style: theme.textTheme.bodySmall?.copyWith(color: colors.mutedForeground),
                ),
              ],
            ),
          ),
          if (!isEditing)
            IconButton(
              tooltip: 'Edit',
              onPressed: onEdit,
              icon: Icon(Icons.edit_outlined, color: colors.mutedForeground),
            ),
          IconButton(
            tooltip: 'Close',
            onPressed: onClose,
            icon: Icon(Icons.close, color: colors.mutedForeground),
          ),
        ],
      ),
    );
  }

  static String _initials(String fullName) {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) {
      return '?';
    }
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'.toUpperCase();
  }
}

class _DetailInfoRow extends StatelessWidget {
  const _DetailInfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.semanticColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelMedium?.copyWith(color: colors.mutedForeground)),
        const SizedBox(height: SpacingTokens.xs),
        Text(value, style: theme.textTheme.bodyLarge?.copyWith(color: colors.foreground)),
      ],
    );
  }
}

class _BlurredCredentialField extends StatelessWidget {
  const _BlurredCredentialField({
    required this.label,
    required this.value,
    required this.canReveal,
    required this.isRevealed,
    required this.onReveal,
    this.unavailableMessage,
  });

  final String label;
  final String value;
  final bool canReveal;
  final bool isRevealed;
  final VoidCallback onReveal;
  final String? unavailableMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.semanticColors;
    final showBlurred = !isRevealed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelMedium?.copyWith(color: colors.mutedForeground)),
        const SizedBox(height: SpacingTokens.sm),
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.muted.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(context.shapeTokens.md),
            border: Border.all(color: colors.border),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.md, vertical: SpacingTokens.sm),
            child: Row(
              children: [
                Expanded(
                  child: ClipRect(
                    child: Stack(
                      alignment: Alignment.centerLeft,
                      children: [
                        SelectableText(
                          value,
                          style: theme.textTheme.bodyLarge?.copyWith(fontFamily: 'monospace', letterSpacing: 0.5),
                        ),
                        if (showBlurred)
                          Positioned.fill(
                            child: ClipRect(
                              child: BackdropFilter(
                                filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                                child: ColoredBox(color: colors.muted.withValues(alpha: 0.45)),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (canReveal && showBlurred)
                  IconButton(
                    tooltip: 'Reveal $label',
                    onPressed: onReveal,
                    icon: const Icon(Icons.visibility_outlined, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
              ],
            ),
          ),
        ),
        if (!canReveal && unavailableMessage != null) ...[
          const SizedBox(height: SpacingTokens.xs),
          Text(unavailableMessage!, style: theme.textTheme.bodySmall?.copyWith(color: colors.mutedForeground)),
        ],
      ],
    );
  }
}
