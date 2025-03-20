import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_links/app_links.dart';
import 'dart:async';
import '../controllers/socket_controller.dart';

class AuthController {
  String _token = '';
  StreamSubscription<Uri>? _linkSubscription;
  bool isAuthenticated = false;
  String error = '';
  Function(bool) onAuthStateChanged;
  Function(String) onErrorChanged;
  late SocketController socketController;

  AuthController({required this.onAuthStateChanged, required this.onErrorChanged}) {
    _loadToken();
    initDeepLinks();
  }

  Future<void> _loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token != null) {
      _token = token;
      isAuthenticated = true;
      onAuthStateChanged(true);
      socketController = SocketController(
        token: token,
        onError: (error) => onErrorChanged(error),
      );
    }
  }

  Future<void> initDeepLinks() async {
    _linkSubscription = AppLinks().uriLinkStream.listen(openAppLink);
    final initialLink = await AppLinks().getInitialLink();
    if (initialLink != null) openAppLink(initialLink);
  }

  void openAppLink(Uri uri) async {
    String extractedToken = uri.fragment.isEmpty 
        ? uri.queryParameters['token'] ?? ''
        : uri.fragment;

    if (extractedToken.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('token', extractedToken);
      
      _token = extractedToken;
      isAuthenticated = true;
      onAuthStateChanged(true);
      
      socketController = SocketController(
        token: extractedToken,
        onError: (error) => onErrorChanged(error),
      );
    }
  }

  String get token => _token;

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    
    if (isAuthenticated) {
      socketController.disconnect();
    }

    _token = '';
    isAuthenticated = false;
    onAuthStateChanged(false);
  }

  void dispose() {
    _linkSubscription?.cancel();
    if (isAuthenticated) {
      socketController.disconnect();
    }
  }
}