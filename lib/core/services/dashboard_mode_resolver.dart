import '../repositories/clinic_repository.dart';
import '../security/access_control.dart';

enum DashboardMode { administrative, staff }

class DashboardModeResolver {
  const DashboardModeResolver._();

  static DashboardMode resolve(UserSession session) {
    if (session.isPlatformOwner ||
        session.can(Permissions.clinicSettingsEdit) ||
        session.can(Permissions.clinicWorkHoursManage) ||
        session.can(Permissions.usersEdit) ||
        session.can(Permissions.usersAssignRoles) ||
        session.can(Permissions.subscriptionsManage)) {
      return DashboardMode.administrative;
    }
    return DashboardMode.staff;
  }
}
