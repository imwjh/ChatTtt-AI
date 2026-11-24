import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_back_button.dart';

/// 服务协议页：加载官网的 terms.html。
class ServiceTermsPage extends StatefulWidget {
  const ServiceTermsPage({super.key});

  static const String termsUrl = 'https://chatttt.imwjh.com/terms.html';

  @override
  State<ServiceTermsPage> createState() => _ServiceTermsPageState();
}

class _ServiceTermsPageState extends State<ServiceTermsPage> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            setState(() {
              _loading = true;
              _failed = false;
            });
          },
          onPageFinished: (_) {
            if (!mounted) return;
            setState(() {
              _loading = false;
              _failed = false;
            });
          },
          onWebResourceError: (error) {
            if (!mounted || error.isForMainFrame != true) return;
            setState(() {
              _loading = false;
              _failed = true;
            });
          },
        ),
      );
    _controller.loadRequest(Uri.parse(ServiceTermsPage.termsUrl));
  }

  Future<void> _retry() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    await _controller.loadRequest(Uri.parse(ServiceTermsPage.termsUrl));
  }

  Future<void> _openInBrowser() async {
    final uri = Uri.parse(ServiceTermsPage.termsUrl);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        leading: const AppBackButton(),
        title: Text(l10n.chattttTermsOfService),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: _failed
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Lucide.TriangleAlert,
                            size: 40,
                            color: cs.onSurface.withValues(alpha: 0.6),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            l10n.chattttTermsLoadFailed,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.5,
                              color: cs.onSurface.withValues(alpha: 0.7),
                            ),
                          ),
                          const SizedBox(height: 20),
                          FilledButton(
                            onPressed: _retry,
                            child: Text(l10n.chattttHelpRetry),
                          ),
                          const SizedBox(height: 4),
                          TextButton(
                            onPressed: _openInBrowser,
                            child: Text(l10n.chattttTermsOpenBrowser),
                          ),
                        ],
                      ),
                    ),
                  )
                : WebViewWidget(controller: _controller),
          ),
          if (_loading)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: const LinearProgressIndicator(minHeight: 2.5),
              ),
            ),
        ],
      ),
    );
  }
}
