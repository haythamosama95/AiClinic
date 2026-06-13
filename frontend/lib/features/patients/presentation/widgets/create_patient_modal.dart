import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/theme/theme.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/core/utils/user_error_mapper.dart';
import 'package:ai_clinic/features/patients/application/patient_rpc_messages.dart';
import 'package:ai_clinic/features/patients/data/patient_rpc_failure.dart';
import 'package:ai_clinic/features/patients/domain/create_patient_input.dart';
import 'package:ai_clinic/features/patients/domain/patient_gender.dart';
import 'package:ai_clinic/features/patients/domain/patient_marital_status.dart';
import 'package:ai_clinic/features/patients/domain/usecases/patient_use_case_providers.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/duplicate_candidates_dialog.dart';

abstract final class _CreatePatientModalPalette {
  static const modalRadius = 24.0;
  static const maxWidth = 640.0;
}

/// Blurred overlay for registering a new patient from the patients list.
class CreatePatientModal extends ConsumerStatefulWidget {
  const CreatePatientModal({super.key});

  /// Presents the registration form over a blurred scrim.
  ///
  /// Returns the new patient id when registration succeeds.
  static Future<String?> show(BuildContext context) {
    return showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.transparent,
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return UncontrolledProviderScope(
          container: ProviderScope.containerOf(context, listen: false),
          child: const _CreatePatientModalOverlay(),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(opacity: animation, child: child);
      },
    );
  }

  @override
  ConsumerState<CreatePatientModal> createState() => _CreatePatientModalState();
}

class _CreatePatientModalOverlay extends StatelessWidget {
  const _CreatePatientModalOverlay();

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: ColoredBox(color: colors.background.withValues(alpha: 0.35)),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.lg, vertical: SpacingTokens.xl),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _CreatePatientModalPalette.maxWidth),
                  child: const CreatePatientModal(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CreatePatientModalState extends ConsumerState<CreatePatientModal> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _notesController = TextEditingController();

  DateTime? _dateOfBirth;
  PatientGender? _gender;
  PatientMaritalStatus? _maritalStatus;
  var _isSaving = false;
  String? _formError;

  static final _genderItems = {
    PatientGender.male.label: PatientGender.male,
    PatientGender.female.label: PatientGender.female,
  };
  static final _maritalStatusItems = {for (final status in PatientMaritalStatus.values) status.label: status};

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  bool get _isReady =>
      _fullNameController.text.trim().isNotEmpty && _phoneController.text.trim().isNotEmpty && _gender != null;

  CreatePatientInput _buildInput({required String activeBranchId, required bool acknowledgeDuplicate}) {
    return CreatePatientInput(
      activeBranchId: activeBranchId,
      fullName: _fullNameController.text,
      phone: _phoneController.text,
      dateOfBirth: _dateOfBirth,
      gender: _gender,
      maritalStatus: _maritalStatus,
      notes: _trimOrNull(_notesController.text),
      acknowledgeDuplicate: acknowledgeDuplicate,
    );
  }

  String? _trimOrNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final auth = ref.read(authSessionProvider);
    final activeBranchId = auth.context?.activeBranchId;
    if (activeBranchId == null || activeBranchId.isEmpty) {
      setState(() => _formError = 'Select an active branch in the shell before registering a patient.');
      return;
    }

    setState(() {
      _isSaving = true;
      _formError = null;
    });

    await _createWithDuplicateHandling(activeBranchId: activeBranchId, acknowledgeDuplicate: false);
  }

  Future<void> _createWithDuplicateHandling({
    required String activeBranchId,
    required bool acknowledgeDuplicate,
  }) async {
    try {
      final patientId = await ref.read(createPatientUseCaseProvider)(
        _buildInput(activeBranchId: activeBranchId, acknowledgeDuplicate: acknowledgeDuplicate),
      );

      if (!mounted) {
        return;
      }

      AppToast.success(context, message: 'Patient registered successfully.');
      Navigator.of(context).pop(patientId);
    } on RpcFailure catch (error) {
      if (!mounted) {
        return;
      }

      if (error.isDuplicateWarning) {
        final candidates = error.duplicateCandidates;
        setState(() => _isSaving = false);

        final proceed = await DuplicateCandidatesDialog.show(context, candidates: candidates);
        if (proceed != true || !mounted) {
          return;
        }

        setState(() => _isSaving = true);
        await _createWithDuplicateHandling(activeBranchId: activeBranchId, acknowledgeDuplicate: true);
        return;
      }

      setState(() {
        _isSaving = false;
        _formError = patientMessageForRpc(error);
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSaving = false;
        _formError = UserErrorMapper.mapToUserMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.semanticColors;
    final auth = ref.watch(authSessionProvider);
    final canCreate = AuthRouteGuard.canAccessPatientRegistration(auth);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): () {
          if (!_isSaving && _isReady && canCreate) {
            _submit();
          }
        },
      },
      child: Focus(
        autofocus: true,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(_CreatePatientModalPalette.modalRadius),
            boxShadow: ShadowTokens.shadowLg,
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Padding(
                padding: const EdgeInsets.all(SpacingTokens.xl),
                child: SingleChildScrollView(
                  child: canCreate ? _buildForm(theme, colors) : _buildPermissionDenied(theme, colors),
                ),
              ),
              Positioned(
                top: SpacingTokens.sm,
                right: SpacingTokens.sm,
                child: IconButton(
                  onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, size: 20),
                  style: IconButton.styleFrom(
                    foregroundColor: colors.mutedForeground,
                    backgroundColor: colors.background.withValues(alpha: 0.9),
                    padding: const EdgeInsets.all(SpacingTokens.sm),
                    minimumSize: const Size(36, 36),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  tooltip: 'Close',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionDenied(ThemeData theme, SemanticColors colors) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Register patient',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: SpacingTokens.lg),
        Text(
          'You do not have permission to register patients.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: colors.mutedForeground),
        ),
      ],
    );
  }

  Widget _buildForm(ThemeData theme, SemanticColors colors) {
    final now = DateTime.now();

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Register patient',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: SpacingTokens.sm),
          Text(
            'Add a new patient at the active branch.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: colors.mutedForeground),
          ),
          if (_formError != null) ...[
            const SizedBox(height: SpacingTokens.lg),
            AppAlert(variant: AppAlertVariant.destructive, title: _formError!),
          ],
          const SizedBox(height: SpacingTokens.xl),
          AppTextField(
            label: 'Full name *',
            hintText: 'Full name as recorded at the desk.',
            controller: _fullNameController,
            enabled: !_isSaving,
            validator: (value) => value == null || value.trim().isEmpty ? 'Full name is required.' : null,
          ),
          const SizedBox(height: SpacingTokens.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AppTextField(
                  label: 'Mobile number *',
                  hintText: 'Only numbers are allowed',
                  controller: _phoneController,
                  enabled: !_isSaving,
                  keyboardType: TextInputType.phone,
                  validator: (value) => value == null || value.trim().isEmpty ? 'Mobile number is required.' : null,
                ),
              ),
              const SizedBox(width: SpacingTokens.md),
              Expanded(
                child: AppDateField(
                  label: 'Date of birth *',
                  value: _dateOfBirth,
                  enabled: !_isSaving,
                  firstDate: DateTime(1900),
                  lastDate: now,
                  hintText: 'dd/mm/yyyy',
                  locale: const Locale('en', 'GB'),
                  onChanged: (value) => setState(() => _dateOfBirth = value),
                  validator: (value) => value == null ? 'Date of birth is required.' : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: SpacingTokens.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AppSelect<PatientGender>(
                  label: 'Gender *',
                  items: _genderItems,
                  value: _gender,
                  hintText: 'Select gender',
                  enabled: !_isSaving,
                  validator: (value) => value == null ? 'Gender is required.' : null,
                  onChanged: (value) => setState(() => _gender = value),
                ),
              ),
              const SizedBox(width: SpacingTokens.md),
              Expanded(
                child: AppSelect<PatientMaritalStatus>(
                  label: 'Marital status',
                  items: _maritalStatusItems,
                  value: _maritalStatus,
                  hintText: 'Not specified',
                  enabled: !_isSaving,
                  onChanged: (value) => setState(() => _maritalStatus = value),
                ),
              ),
            ],
          ),
          const SizedBox(height: SpacingTokens.md),
          AppTextField(
            label: 'Notes',
            description: 'Front-desk notes visible on the patient profile.',
            controller: _notesController,
            enabled: !_isSaving,
            maxLines: 3,
          ),
          const SizedBox(height: SpacingTokens.xl),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              AppButton(
                label: 'Cancel',
                variant: AppButtonVariant.outline,
                expand: false,
                onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: SpacingTokens.sm),
              AppButton(
                key: const Key('patient_register_submit'),
                label: 'Register patient',
                expand: false,
                isLoading: _isSaving,
                onPressed: _isSaving ? null : _submit,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
