import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/router/route_names.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/motion.dart';
import '../../state/auth_providers.dart';
import '../../state/automation_providers.dart';
import '../../state/workspace_providers.dart';
import 'demo_mode_banner.dart';

class _NavItem {
  const _NavItem(this.label, this.icon, this.route);

  final String label;
  final IconData icon;
  final String route;
}

class _NavGroup {
  const _NavGroup(this.title, this.items);

  final String title;
  final List<_NavItem> items;
}

const List<_NavGroup> _navGroups = [
  _NavGroup('Overview', [
    _NavItem('Dashboard', Icons.space_dashboard_outlined, Routes.dashboard),
    _NavItem('Analytics', Icons.insights_outlined, Routes.analytics),
  ]),
  _NavGroup('CRM', [
    _NavItem('Lead inbox', Icons.inbox_outlined, Routes.leads),
    _NavItem('Pipeline', Icons.view_kanban_outlined, Routes.pipeline),
  ]),
  _NavGroup('AI agent', [
    _NavItem('Playground', Icons.auto_awesome_outlined, Routes.playground),
    _NavItem('Agent configuration', Icons.tune_rounded, Routes.agentConfig),
    _NavItem('Model and cost', Icons.paid_outlined, Routes.modelCost),
  ]),
  _NavGroup('Automation', [
    _NavItem('Workflows', Icons.account_tree_outlined, Routes.workflows),
    _NavItem('Approvals', Icons.fact_check_outlined, Routes.approvals),
    _NavItem('Bookings', Icons.event_outlined, Routes.bookings),
    _NavItem('Follow-ups', Icons.checklist_rounded, Routes.followups),
  ]),
  _NavGroup('Administration', [
    _NavItem('Audit logs', Icons.history_rounded, Routes.audit),
    _NavItem('Error monitoring', Icons.error_outline_rounded, Routes.errors),
    _NavItem('Team', Icons.groups_outlined, Routes.team),
    _NavItem('Settings', Icons.settings_outlined, Routes.settings),
  ]),
];

bool _isSelected(String route, String location) =>
    location == route || location.startsWith('$route/');

/// Lets pages inside the shell open the drawer and know whether the sidebar is showing.
class ShellScope extends InheritedWidget {
  const ShellScope(
      {super.key,
      required this.openDrawer,
      required this.wide,
      required super.child});

  final VoidCallback openDrawer;
  final bool wide;

  static ShellScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellScope>();

  @override
  bool updateShouldNotify(ShellScope old) => wide != old.wide;
}

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  static const _bottomRoutes = [
    Routes.dashboard,
    Routes.leads,
    Routes.playground,
    Routes.approvals
  ];

  int _bottomIndex(String loc) {
    if (_isSelected(Routes.dashboard, loc) ||
        _isSelected(Routes.analytics, loc)) return 0;
    if (_isSelected(Routes.leads, loc) || _isSelected(Routes.pipeline, loc))
      return 1;
    if (loc.startsWith('/agent')) return 2;
    if (_isSelected(Routes.approvals, loc)) return 3;
    return 4;
  }

  void _go(String route) {
    if (GoRouterState.of(context).uri.path != route) context.go(route);
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final wide =
        MediaQuery.sizeOf(context).width >= AppSpacing.tabletBreakpoint;
    final pending = ref.watch(pendingApprovalsCountProvider);

    final content = AppConfig.demoMode
        ? Column(
            children: [
              const DemoModeBanner(),
              Expanded(
                  child: MediaQuery.removePadding(
                      context: context, removeTop: true, child: widget.child)),
            ],
          )
        : widget.child;

    final scoped = ShellScope(
      openDrawer: () => _scaffoldKey.currentState?.openDrawer(),
      wide: wide,
      child: content,
    );

    if (wide) {
      return Scaffold(
        key: _scaffoldKey,
        body: Row(
          children: [
            SizedBox(
              width: 264,
              child: ColoredBox(
                color: AppColors.navy,
                child: _NavPanel(location: location, onSelect: _go),
              ),
            ),
            Expanded(child: scoped),
          ],
        ),
      );
    }

    final index = _bottomIndex(location);
    return Scaffold(
      key: _scaffoldKey,
      drawer: Drawer(
        backgroundColor: AppColors.navy,
        child: _NavPanel(
          location: location,
          onSelect: (route) {
            Navigator.of(context).pop();
            _go(route);
          },
        ),
      ),
      body: scoped,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) {
          if (i == 4) {
            _scaffoldKey.currentState?.openDrawer();
          } else {
            _go(_bottomRoutes[i]);
          }
        },
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.space_dashboard_outlined),
            selectedIcon: Icon(Icons.space_dashboard_rounded),
            label: 'Home',
          ),
          const NavigationDestination(
            icon: Icon(Icons.inbox_outlined),
            selectedIcon: Icon(Icons.inbox_rounded),
            label: 'Leads',
          ),
          const NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome),
            label: 'Agent',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: pending > 0,
              label: Text('$pending'),
              child: const Icon(Icons.fact_check_outlined),
            ),
            selectedIcon: Badge(
              isLabelVisible: pending > 0,
              label: Text('$pending'),
              child: const Icon(Icons.fact_check_rounded),
            ),
            label: 'Approvals',
          ),
          const NavigationDestination(
              icon: Icon(Icons.menu_rounded), label: 'More'),
        ],
      ),
    );
  }
}

class _NavPanel extends ConsumerWidget {
  const _NavPanel({required this.location, required this.onSelect});

  final String location;
  final void Function(String route) onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final workspace = ref.watch(activeWorkspaceProvider);
    final user = ref.watch(currentUserProvider);
    final pending = ref.watch(pendingApprovalsCountProvider);

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.rocket_launch_outlined,
                      color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Text('LeadPilot AI',
                    style: text.titleMedium?.copyWith(color: Colors.white)),
              ],
            ),
          ),
          if (workspace != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Row(
                children: [
                  const Icon(Icons.business_center_outlined,
                      size: 14, color: Colors.white54),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      workspace.name,
                      style: text.bodySmall?.copyWith(color: Colors.white70),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (workspace.role != null)
                    Text(workspace.role!.label,
                        style: text.labelSmall
                            ?.copyWith(color: AppColors.primaryLight)),
                ],
              ),
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final group in _navGroups) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 14, 8, 6),
                    child: Text(
                      group.title.toUpperCase(),
                      style: text.labelSmall
                          ?.copyWith(color: Colors.white38, letterSpacing: 0.8),
                    ),
                  ),
                  for (final item in group.items)
                    _NavTile(
                      item: item,
                      selected: _isSelected(item.route, location),
                      badge: item.route == Routes.approvals ? pending : 0,
                      onTap: () => onSelect(item.route),
                    ),
                ],
              ],
            ),
          ),
          const Divider(color: Colors.white12, height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: AppColors.navyLight,
                  child: Text(
                    Fmt.initials(user?.label),
                    style: text.labelSmall?.copyWith(color: Colors.white),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    user?.label ?? 'Signed out',
                    style: text.bodySmall?.copyWith(color: Colors.white),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: 'Sign out',
                  icon: const Icon(Icons.logout_rounded,
                      color: Colors.white70, size: 20),
                  onPressed: () => ref.read(authRepositoryProvider).signOut(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile(
      {required this.item,
      required this.selected,
      required this.onTap,
      this.badge = 0});

  final _NavItem item;
  final bool selected;
  final int badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Semantics(
        selected: selected,
        button: true,
        child: AnimatedContainer(
          duration: Motion.of(context, Motion.fast),
          decoration: BoxDecoration(
            color:
                selected ? AppColors.primary.withAlpha(46) : Colors.transparent,
            borderRadius: AppRadius.control,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: AppRadius.control,
              onTap: onTap,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                child: Row(
                  children: [
                    Icon(item.icon,
                        size: 20,
                        color:
                            selected ? AppColors.primaryLight : Colors.white70),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        item.label,
                        style: text.labelLarge?.copyWith(
                          color: selected ? Colors.white : Colors.white70,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ),
                    if (badge > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text('$badge',
                            style:
                                text.labelSmall?.copyWith(color: Colors.white)),
                      ),
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

/// Standard screen frame: app bar, centered max-width body, menu button inside the shell on phones.
class PageScaffold extends StatelessWidget {
  const PageScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.floatingActionButton,
    this.bottom,
    this.maxWidth = AppSpacing.maxContentWidth,
  });

  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final PreferredSizeWidget? bottom;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.maybeOf(context);
    Widget? leading;
    if (shell != null && !shell.wide) {
      leading = IconButton(
          icon: const Icon(Icons.menu_rounded),
          tooltip: 'Menu',
          onPressed: shell.openDrawer);
    }
    return Scaffold(
      appBar: AppBar(
          title: Text(title),
          leading: leading,
          actions: actions,
          bottom: bottom),
      floatingActionButton: floatingActionButton,
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth), child: body),
      ),
    );
  }
}
