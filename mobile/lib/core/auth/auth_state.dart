import '../../features/profile/data/user_profile.dart';
import '../api/api_exception.dart';

enum AuthPhase { restoring, signedOut, signedIn, recovery }

class AuthState {
  const AuthState(this.phase, {this.user, this.busy = false, this.error});
  final AuthPhase phase;
  final UserProfile? user;
  final bool busy;
  final ApiException? error;
}
