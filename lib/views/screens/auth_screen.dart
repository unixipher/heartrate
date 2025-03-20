import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../controllers/auth_controller.dart';
import '../../utils/constants.dart';
import '../../views/widgets/auth_button.dart';

class AuthScreen extends StatefulWidget {
  final AuthController authController;
  final Function() onAuthSuccess;

  const AuthScreen({
    Key? key,
    required this.authController,
    required this.onAuthSuccess,
  }) : super(key: key);

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool showWebView = false;
  late WebViewController webViewController;
  String error = '';

  @override
  void initState() {
    super.initState();
    initWebViewController();
  }

  void initWebViewController() {
    webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (NavigationRequest request) {
            final uri = Uri.parse(request.url);
            if (request.url.startsWith('heartwatch://') || 
                request.url.startsWith('sample://')) {
              widget.authController.openAppLink(uri);
              return NavigationDecision.prevent;
            }
            if (request.url.startsWith('https://authcheck.co/auth')) {
              return NavigationDecision.navigate;
            }
            return NavigationDecision.navigate;
          },
          onPageStarted: (String url) => print('Page started: $url'),
          onPageFinished: (String url) => print('Page finished: $url'),
          onWebResourceError: (WebResourceError error) {
            setState(() => this.error = 'WebView error: ${error.description}');
          },
        ),
      )
      ..loadRequest(Uri.parse(kAppleAuthUrl));
  }

  void openAuthWebView() {
    setState(() {
      showWebView = true;
      webViewController.loadRequest(Uri.parse(kAppleAuthUrl));
    });
  }

  @override
  Widget build(BuildContext context) {
    return showWebView ? _buildWebView() : _buildAuthScreen();
  }

  Widget _buildWebView() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Apple Sign In'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => setState(() => showWebView = false),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => webViewController.reload(),
          ),
        ],
      ),
      body: WebViewWidget(controller: webViewController),
    );
  }

  Widget _buildAuthScreen() {
    return Container(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.favorite, color: Colors.red, size: 80),
          const SizedBox(height: 16),
          Text(
            'Heart Rate Monitor',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.red.shade800,
            ),
          ),
          const SizedBox(height: 50),
          AuthButton(onPressed: openAuthWebView),
          if (widget.authController.token.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12.0),
              child: Text(
                'Token: ${widget.authController.token}',
                style: const TextStyle(color: Colors.grey),
              ),
            ),
          if (error.isNotEmpty) _buildErrorDisplay(),
        ],
      ),
    );
  }

  Widget _buildErrorDisplay() {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(error, style: TextStyle(color: Colors.red.shade800)),
    );
  }
}