import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/admin/audit_logs_screen.dart';
import '../../features/admin/error_monitoring_screen.dart';
import '../../features/admin/settings_screen.dart';
import '../../features/admin/team_management_screen.dart';
import '../../features/agent/agent_config_screen.dart';
import '../../features/agent/agent_playground_screen.dart';
import '../../features/agent/model_cost_screen.dart';
import '../../features/auth/auth_screen.dart';
import '../../features/auth/onboarding_screen.dart';
import '../../features/auth/splash_screen.dart';
import '../../features/auth/workspace_setup_screen.dart';
import '../../features/automation/approval_center_screen.dart';
import '../../features/automation/booking_calendar_screen.dart';
import '../../features/automation/followup_manager_screen.dart';
import '../../features/automation/workflow_center_screen.dart';
import '../../features/dashboard/analytics_screen.dart';
import '../../features/dashboard/home_dashboard_screen.dart';
import '../../features/leads/conversation_history_screen.dart';
import '../../features/leads/lead_details_screen.dart';
import '../../features/leads/lead_form_screen.dart';
import '../../features/leads/lead_inbox_screen.dart';
import '../../features/leads/lead_pipeline_screen.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../state/auth_providers.dart';
import '../../state/workspace_providers.dart';
import 'page_transitions.dart';
import 'route_names.dart';

final GlobalKey<NavigatorState> rootNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'root');
final GlobalKey<NavigatorState> _shellNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'shell');

String? _redirect(Ref ref, GoRouterState state) {
  final loc = state.uri.path;
  if (loc == Routes.splash)
    return null; // the splash screen decides when to leave

  String toSplash() =>
      Uri(path: Routes.splash, queryParameters: {'from': state.uri.toString()})
          .toString();

  final auth = ref.read(authStateProvider);
  if (auth.isLoading && !auth.hasValue) return toSplash();
  final user = auth.valueOrNull;

  if (user == null) {
    if (loc == Routes.onboarding || loc == Routes.auth) return null;
    return ref.read(onboardingSeenProvider) ? Routes.auth : Routes.onboarding;
  }

  final workspaces = ref.read(myWorkspacesProvider);
  // Only bounce to the splash screen while the list has never loaded. A background reload
  // (for example after saving workspace settings) keeps the previous list and does not interrupt the user.
  if ((workspaces.isLoading && !workspaces.hasValue) || workspaces.hasError)
    return toSplash();
  final list = workspaces.valueOrNull ?? const [];
  if (list.isEmpty)
    return loc == Routes.workspaceSetup ? null : Routes.workspaceSetup;
  if (loc == Routes.onboarding || loc == Routes.auth) return Routes.dashboard;
  return null;
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(authStateProvider, (_, __) => refresh.value++);
  ref.listen(myWorkspacesProvider, (_, __) => refresh.value++);
  ref.onDispose(refresh.dispose);

  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: (context, state) => _redirect(ref, state),
    routes: [
      GoRoute(
        path: Routes.splash,
        pageBuilder: (c, s) => AppPages.fade(s, const SplashScreen()),
      ),
      GoRoute(
        path: Routes.onboarding,
        pageBuilder: (c, s) => AppPages.fade(s, const OnboardingScreen()),
      ),
      GoRoute(
        path: Routes.auth,
        pageBuilder: (c, s) => AppPages.fade(s, const AuthScreen()),
      ),
      GoRoute(
        path: Routes.workspaceSetup,
        pageBuilder: (c, s) => AppPages.fade(s, const WorkspaceSetupScreen()),
      ),
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          // Module 2: Dashboard
          GoRoute(
            path: Routes.dashboard,
            pageBuilder: (c, s) =>
                AppPages.shellTab(s, const HomeDashboardScreen()),
          ),
          GoRoute(
            path: Routes.analytics,
            pageBuilder: (c, s) =>
                AppPages.shellTab(s, const AnalyticsScreen()),
          ),

          // Module 3: CRM
          GoRoute(
            path: Routes.leads,
            pageBuilder: (c, s) =>
                AppPages.shellTab(s, const LeadInboxScreen()),
          ),
          GoRoute(
            path: Routes.leadNew,
            pageBuilder: (c, s) => AppPages.rise(s, const LeadFormScreen()),
          ),
          GoRoute(
            path: Routes.leadDetails,
            pageBuilder: (c, s) => AppPages.slide(
                s, LeadDetailsScreen(leadId: s.pathParameters['id'] ?? '')),
          ),
          GoRoute(
            path: Routes.leadEdit,
            pageBuilder: (c, s) => AppPages.rise(
              s,
              LeadFormScreen(leadId: s.pathParameters['id']),
            ),
          ),
          GoRoute(
            path: Routes.leadConversation,
            pageBuilder: (c, s) => AppPages.slide(
                s,
                ConversationHistoryScreen(
                    leadId: s.pathParameters['id'] ?? '')),
          ),
          GoRoute(
            path: Routes.pipeline,
            pageBuilder: (c, s) =>
                AppPages.shellTab(s, const LeadPipelineScreen()),
          ),

          // Module 4: AI agent
          GoRoute(
            path: Routes.playground,
            pageBuilder: (c, s) =>
                AppPages.shellTab(s, const AgentPlaygroundScreen()),
          ),
          GoRoute(
            path: Routes.agentConfig,
            pageBuilder: (c, s) =>
                AppPages.shellTab(s, const AgentConfigScreen()),
          ),
          GoRoute(
            path: Routes.modelCost,
            pageBuilder: (c, s) =>
                AppPages.shellTab(s, const ModelCostScreen()),
          ),

          // Module 5: Automation
          GoRoute(
            path: Routes.workflows,
            pageBuilder: (c, s) =>
                AppPages.shellTab(s, const WorkflowCenterScreen()),
          ),
          GoRoute(
            path: Routes.approvals,
            pageBuilder: (c, s) =>
                AppPages.shellTab(s, const ApprovalCenterScreen()),
          ),
          GoRoute(
            path: Routes.bookings,
            pageBuilder: (c, s) =>
                AppPages.shellTab(s, const BookingCalendarScreen()),
          ),
          GoRoute(
            path: Routes.followups,
            pageBuilder: (c, s) =>
                AppPages.shellTab(s, const FollowupManagerScreen()),
          ),

          // Module 6: Monitoring and administration
          GoRoute(
            path: Routes.audit,
            pageBuilder: (c, s) =>
                AppPages.shellTab(s, const AuditLogsScreen()),
          ),
          GoRoute(
            path: Routes.errors,
            pageBuilder: (c, s) =>
                AppPages.shellTab(s, const ErrorMonitoringScreen()),
          ),
          GoRoute(
            path: Routes.team,
            pageBuilder: (c, s) =>
                AppPages.shellTab(s, const TeamManagementScreen()),
          ),
          GoRoute(
            path: Routes.settings,
            pageBuilder: (c, s) => AppPages.shellTab(s, const SettingsScreen()),
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
