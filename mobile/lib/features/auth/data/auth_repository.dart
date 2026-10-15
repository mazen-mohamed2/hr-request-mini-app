import '../../../core/api/api_client.dart';
import '../../../core/api/json.dart';
import '../../profile/data/user_profile.dart';

class LoginResult {
  const LoginResult(this.token, this.user);
  final String token;
  final UserProfile user;
}

class AuthRepository {
  AuthRepository(this._api);
  final ApiClient _api;

  Future<LoginResult> login(String email, String password) => _api.send(
    'auth/login',
    (json) => LoginResult(
      requiredString(json, 'token'),
      UserProfile.fromJson(jsonObject(json['user'])),
    ),
    method: 'POST',
    authenticated: false,
    data: {'email': email.trim().toLowerCase(), 'password': password},
  );

  Future<UserProfile> me() =>
      _api.send('me', (json) => UserProfile.fromJson(jsonObject(json['data'])));
}
