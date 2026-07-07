import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_app_shell.dart';
import 'package:ai_clinic/core/ui/components/app_avatar.dart';
import 'package:ai_clinic/core/ui/components/app_branch_switcher.dart';
import 'package:ai_clinic/core/ui/components/app_breadcrumb.dart';
import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/components/app_icon_button.dart';
import 'package:ai_clinic/core/ui/components/app_nav_models.dart';
import 'package:ai_clinic/core/ui/components/app_page_header.dart';
import 'package:ai_clinic/core/ui/components/app_sidebar.dart';
import 'package:ai_clinic/core/ui/components/app_skeleton.dart';
import 'package:ai_clinic/core/ui/components/app_tabs.dart';
import 'package:ai_clinic/core/ui/theme/app_elevation.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_shell_tokens.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/design_system/presentation/components/layout/nav_model_mock.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';
import 'package:ai_clinic/features/design_system/presentation/providers/dev_preview_provider.dart';

class _AppShellCopy {
  const _AppShellCopy({
    required this.sectionDescription,
    required this.liveShellDemo,
    required this.liveShellDemoHint,
    required this.patients,
    required this.directory,
    required this.pageTitle,
    required this.pageDescription,
    required this.newPatient,
    required this.overview,
    required this.active,
    required this.archived,
  });

  final String sectionDescription;
  final String liveShellDemo;
  final String liveShellDemoHint;
  final String patients;
  final String directory;
  final String pageTitle;
  final String pageDescription;
  final String newPatient;
  final String overview;
  final String active;
  final String archived;
}

const _copyEn = _AppShellCopy(
  sectionDescription: 'Live shell with sidebar, top bar, command bar, and placeholder page content.',
  liveShellDemo: 'Live shell demo',
  liveShellDemoHint: '⌘K · collapse · toggles',
  patients: 'Patients',
  directory: 'Directory',
  pageTitle: 'Patients',
  pageDescription: 'Manage patient records, demographics, and care history.',
  newPatient: 'New patient',
  overview: 'Overview',
  active: 'Active',
  archived: 'Archived',
);

const _copyAr = _AppShellCopy(
  sectionDescription: 'هيكل تطبيق حي مع شريط جانبي وشريط علوي وشريط أوامر ومحتوى صفحة تجريبي.',
  liveShellDemo: 'عرض الهيكل الحي',
  liveShellDemoHint: '⌘K · collapse · toggles',
  patients: 'المرضى',
  directory: 'الدليل',
  pageTitle: 'المرضى',
  pageDescription: 'أدارة سجلات المرضى والبيانات الديموغرافية وتاريخ الرعاية.',
  newPatient: 'مريض جديد',
  overview: 'نظرة عامة',
  active: 'نشط',
  archived: 'مؤرشف',
);

_AppShellCopy _copyFor(String locale) => locale == 'ar' ? _copyAr : _copyEn;

/// App shell showcase (web `AppShellShowcase`).
class AppShellShowcaseSection extends ConsumerStatefulWidget {
  const AppShellShowcaseSection({super.key});

  @override
  ConsumerState<AppShellShowcaseSection> createState() => _AppShellShowcaseSectionState();
}

class _AppShellShowcaseSectionState extends ConsumerState<AppShellShowcaseSection> {
  var _activeId = 'patients';
  var _collapsed = false;
  var _branchId = mockBranches.first.id;
  var _tab = 'overview';

  @override
  Widget build(BuildContext context) {
    final copy = _copyFor(ref.watch(devPreviewProvider).locale);
    final colors = context.appColors;
    final branch = mockBranches.firstWhere((item) => item.id == _branchId, orElse: () => mockBranches.first);

    return ShowcaseSection(
      id: 'app-shell',
      title: 'App shell',
      description: copy.sectionDescription,
      componentName: 'AppShell',
      child: ShowcaseDemo(
        label: copy.liveShellDemo,
        propsHint: copy.liveShellDemoHint,
        child: SizedBox(
          height: 512,
          width: double.infinity,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.xl),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: colors.borderDefault),
                borderRadius: BorderRadius.circular(AppRadius.xl),
                boxShadow: context.appElevation.shadowsFor(2),
              ),
              child: AppAppShell(
                sidebar: AppSidebar(
                  items: clinicNavGroups,
                  footerItems: clinicNavFooter,
                  activeId: _activeId,
                  onNavigate: (id) => setState(() => _activeId = id),
                  collapsed: _collapsed,
                  onToggleCollapsed: () => setState(() => _collapsed = !_collapsed),
                  org: mockOrg,
                  branch: branch.name,
                ),
                topBar: _LiveTopBarMock(
                  breadcrumb: AppBreadcrumb(
                    items: [
                      AppBreadcrumbItem(
                        label: copy.patients,
                        onTap: () => setState(() => _activeId = 'patients'),
                      ),
                      AppBreadcrumbItem(label: copy.directory),
                    ],
                  ),
                  branches: mockBranches,
                  currentBranchId: _branchId,
                  onBranchChange: (id) => setState(() => _branchId = id),
                  user: mockUser,
                  notificationCount: mockNotificationCount,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppPageHeader(
                      title: copy.pageTitle,
                      description: copy.pageDescription,
                      actions: AppButton(
                        variant: AppButtonVariant.primary,
                        onPressed: () {},
                        child: Text(copy.newPatient),
                      ),
                      tabs: AppTabs(
                        items: [
                          AppTabItem(id: 'overview', label: copy.overview),
                          AppTabItem(id: 'active', label: copy.active),
                          AppTabItem(id: 'archived', label: copy.archived),
                        ],
                        value: _tab,
                        onChanged: (id) => setState(() => _tab = id),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.space8),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final cardWidth = constraints.maxWidth >= 640
                            ? (constraints.maxWidth - AppSpacing.space4 * 2) / 3
                            : constraints.maxWidth;
                        return Wrap(
                          spacing: AppSpacing.space4,
                          runSpacing: AppSpacing.space4,
                          children: [
                            for (var index = 0; index < 3; index++)
                              SizedBox(
                                width: cardWidth,
                                child: const AppSkeleton(variant: SkeletonVariant.rectangular, height: 96),
                              ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: AppSpacing.space4),
                    const AppSkeleton(variant: SkeletonVariant.rectangular, height: 192),
                    const SizedBox(height: AppSpacing.space4),
                    const AppSkeleton(variant: SkeletonVariant.rectangular, height: 128),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Showcase-local top bar mock (web `AppTopBar` stand-in until Navigation milestone).
class _LiveTopBarMock extends StatelessWidget {
  const _LiveTopBarMock({
    required this.breadcrumb,
    required this.branches,
    required this.currentBranchId,
    required this.onBranchChange,
    required this.user,
    required this.notificationCount,
  });

  final Widget breadcrumb;
  final List<AppBranch> branches;
  final String currentBranchId;
  final ValueChanged<String> onBranchChange;
  final AppUserMenuUser user;
  final int notificationCount;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Material(
      color: colors.surfaceDefault,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.borderSubtle)),
        ),
        child: SizedBox(
          height: AppShellTokens.topBarHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space4),
            child: Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: breadcrumb,
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  reverse: true,
                  clipBehavior: Clip.hardEdge,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (branches.isNotEmpty) ...[
                        AppBranchSwitcher(
                          branches: branches,
                          currentBranchId: currentBranchId,
                          onBranchChange: onBranchChange,
                        ),
                        const SizedBox(width: AppSpacing.space2),
                      ],
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          AppIconButton(
                            icon: const Icon(Icons.notifications_outlined, size: 24),
                            label: notificationCount > 0
                                ? 'Notifications, $notificationCount unread'
                                : 'Notifications',
                            size: AppIconButtonSize.lg,
                            onPressed: () {},
                          ),
                          if (notificationCount > 0)
                            PositionedDirectional(
                              end: 6,
                              top: 6,
                              child: Container(
                                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                                padding: const EdgeInsets.symmetric(horizontal: 2),
                                decoration: BoxDecoration(
                                  color: colors.statusDangerFg,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  notificationCount > 9 ? '9+' : '$notificationCount',
                                  style: AppTypography.bodySm(context).copyWith(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: colors.textInverse,
                                    height: 1,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(width: AppSpacing.space2),
                      AppAvatar(name: user.name, size: AvatarSize.sm),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
