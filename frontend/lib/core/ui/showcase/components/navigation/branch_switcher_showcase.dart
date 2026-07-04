import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/showcase/showcase_primitives.dart';
import 'package:ai_clinic/core/ui/ui.dart';

class BranchSwitcherShowcase extends StatefulWidget {
  const BranchSwitcherShowcase({super.key});

  @override
  State<BranchSwitcherShowcase> createState() => _BranchSwitcherShowcaseState();
}

class _BranchSwitcherShowcaseState extends State<BranchSwitcherShowcase> {
  String _branchId = mockBranches.first.id;

  @override
  Widget build(BuildContext context) {
    return ShowcaseSection(
      title: 'Branch switcher',
      description: 'Switch between clinic branches with org context and search.',
      child: ShowcaseDemo(
        label: 'Default',
        child: BranchSwitcher(
          branches: mockBranches,
          currentBranchId: _branchId,
          onBranchChange: (id) => setState(() => _branchId = id),
        ),
      ),
    );
  }
}
