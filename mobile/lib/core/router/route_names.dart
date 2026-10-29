/// Route paths. Keep in sync with `app_router.dart` (Batch 4).
abstract final class Routes {
  // Module 1: Auth and onboarding
  static const splash = '/';
  static const onboarding = '/onboarding';
  static const auth = '/auth';
  static const workspaceSetup = '/workspace-setup';

  // Module 2: Dashboard
  static const dashboard = '/dashboard';
  static const analytics = '/analytics';

  // Module 3: CRM
  static const leads = '/leads';
  static const leadNew = '/leads/new';
  static const leadDetails = '/leads/:id';
  static const leadEdit = '/leads/:id/edit';
  static const leadConversation = '/leads/:id/conversation';
  static const pipeline = '/pipeline';

  // Module 4: AI agent
  static const playground = '/agent/playground';
  static const agentConfig = '/agent/config';
  static const modelCost = '/agent/cost';

  // Module 5: Automation
  static const workflows = '/automation/workflows';
  static const approvals = '/automation/approvals';
  static const bookings = '/automation/bookings';
  static const followups = '/automation/followups';

  // Module 6: Monitoring and administration
  static const audit = '/admin/audit';
  static const errors = '/admin/errors';
  static const team = '/admin/team';
  static const settings = '/admin/settings';

  // Path builders
  static String lead(String id) => '/leads/$id';
  static String leadEditPath(String id) => '/leads/$id/edit';
  static String leadConversationPath(String id) => '/leads/$id/conversation';
}
