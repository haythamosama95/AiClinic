import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/features/patients/domain/patient_gender.dart';

/// Circular patient portrait using gender-specific avatar artwork.
class PatientGenderAvatar extends StatelessWidget {
  const PatientGenderAvatar({required this.gender, this.size = 88, super.key});

  final PatientGender? gender;
  final double size;

  static const _femaleAsset = 'assets/images/patient_avatar_female.png';
  static const _maleAsset = 'assets/images/patient_avatar_male.png';

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final asset = switch (gender) {
      PatientGender.female => _femaleAsset,
      PatientGender.male => _maleAsset,
      _ => _maleAsset,
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: colors.border),
        boxShadow: [
          BoxShadow(color: colors.foreground.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: ClipOval(
        child: Image.asset(
          asset,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _FallbackAvatar(gender: gender, size: size),
        ),
      ),
    );
  }
}

class _FallbackAvatar extends StatelessWidget {
  const _FallbackAvatar({required this.gender, required this.size});

  final PatientGender? gender;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final icon = switch (gender) {
      PatientGender.female => Icons.face_3_outlined,
      PatientGender.male => Icons.face_outlined,
      _ => Icons.person_outline,
    };

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: colors.secondary, borderRadius: BorderRadius.circular(size / 2)),
      child: Icon(icon, size: size * 0.45, color: colors.secondaryForeground),
    );
  }
}
