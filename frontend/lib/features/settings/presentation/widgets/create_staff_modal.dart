import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/theme/theme.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/setup/domain/create_staff_account_result.dart';
import 'package:ai_clinic/features/setup/presentation/providers/provisioning_notifier.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/setup_staff_step.dart';
import 'package:ai_clinic/features/settings/presentation/providers/staff_list_notifier.dart';

abstract final class _CreateStaffModalPalette {
  static const modalRadius = 24.0;
  static const maxWidth = 920.0;
}

/// Blurred overlay with the staff create form for adding staff from settings.
class CreateStaffModal extends ConsumerStatefulWidget {
  const CreateStaffModal({super.key});

  /// Presents the create-staff form over a blurred scrim.
  static Future<bool?> show(BuildContext context) {
    return showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.transparent,
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return UncontrolledProviderScope(
          container: ProviderScope.containerOf(context, listen: false),
          child: const _CreateStaffModalOverlay(),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(opacity: animation, child: child);
      },
    );
  }

  @override
  ConsumerState<CreateStaffModal> createState() => _CreateStaffModalState();
}

class _CreateStaffModalOverlay extends StatelessWidget {
  const _CreateStaffModalOverlay();

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(false),
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
                  constraints: const BoxConstraints(maxWidth: _CreateStaffModalPalette.maxWidth),
                  child: const CreateStaffModal(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CreateStaffModalState extends ConsumerState<CreateStaffModal> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      ref.read(provisioningNotifierProvider.notifier).clearError();
    });
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _fullNameController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<bool> _createStaff({
    required StaffRole role,
    required List<String> branchIds,
    String? primaryBranchId,
    String? phone,
  }) async {
    final result = await ref
        .read(provisioningNotifierProvider.notifier)
        .createStaffAccount(
          username: _usernameController.text,
          fullName: _fullNameController.text,
          role: role,
          branchIds: branchIds,
          password: _passwordController.text,
          primaryBranchId: primaryBranchId,
          phone: phone,
        );

    if (result == null || !mounted) {
      return false;
    }

    ref.invalidate(staffListProvider);
    await _showCredentialsDialog(result);
    return true;
  }

  Future<void> _showCredentialsDialog(CreateStaffAccountResult result) async {
    final password = result.revealAssignedPassword() ?? '';
    await AppDialog.show<void>(
      context: context,
      title: 'Staff account created',
      body: SelectableText(
        'Share these credentials with the staff member:\n\n'
        'Username: ${result.username}\n'
        'Password: $password',
      ),
      actions: [
        AppButton(
          label: 'Done',
          expand: false,
          onPressed: () {
            ref.read(provisioningNotifierProvider.notifier).clearLastCreated();
            Navigator.of(context).pop();
            Navigator.of(context).pop(true);
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.semanticColors;
    final provisioning = ref.watch(provisioningNotifierProvider);
    final isBusy = provisioning.isSubmitting;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(_CreateStaffModalPalette.modalRadius),
        boxShadow: ShadowTokens.shadowLg,
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(
            padding: const EdgeInsets.all(SpacingTokens.xl),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'New staff member',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: SpacingTokens.sm),
                  Text(
                    'Create a staff account and assign branches.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(color: colors.mutedForeground),
                  ),
                  if (provisioning.errorMessage != null) ...[
                    const SizedBox(height: SpacingTokens.lg),
                    AppAlert(variant: AppAlertVariant.destructive, title: provisioning.errorMessage!),
                  ],
                  const SizedBox(height: SpacingTokens.xl),
                  SetupStaffStep(
                    formKey: _formKey,
                    usernameController: _usernameController,
                    fullNameController: _fullNameController,
                    phoneController: _phoneController,
                    passwordController: _passwordController,
                    isBusy: isBusy,
                    onCreate: _createStaff,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: SpacingTokens.sm,
            right: SpacingTokens.sm,
            child: IconButton(
              onPressed: isBusy ? null : () => Navigator.of(context).pop(false),
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
    );
  }
}
