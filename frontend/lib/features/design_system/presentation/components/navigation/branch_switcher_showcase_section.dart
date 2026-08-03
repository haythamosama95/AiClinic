import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_branch_switcher.dart';
import 'package:ai_clinic/core/ui/components/app_nav_models.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';

/// Branch switcher showcase (web `BranchSwitcherShowcase`).
class BranchSwitcherShowcaseSection extends ConsumerStatefulWidget {
  const BranchSwitcherShowcaseSection({super.key});

  @override
  ConsumerState<BranchSwitcherShowcaseSection> createState() => _BranchSwitcherShowcaseSectionState();
}

class _BranchSwitcherShowcaseSectionState extends ConsumerState<BranchSwitcherShowcaseSection> {
  var _branchId = 'downtown';

  @override
  Widget build(BuildContext context) {
    return ShowcaseSection(
      id: 'branch-switcher',
      title: 'Branch switcher',
      description: 'Switch between clinic branches with org context and search.',
      componentName: 'BranchSwitcher',
      child: ShowcaseDemo(
        label: 'Default',
        propsHint: 'branches + onBranchChange',
        child: AppBranchSwitcher(
          branches: kMockBranches,
          currentBranchId: _branchId,
          onBranchChange: (id) => setState(() => _branchId = id),
        ),
      ),
    );
  }
}
