// Root app: loads AppConfig and wires up a GoRouter with a ShellRoute
// providing a shared bottom navigation bar across chat / models / settings.
//
// The router is built once in initState (rebuilding it on every setState
// would reset navigation). When the active model or config changes we call
// ChatPage.reload() via a GlobalKey so it re-reads AppConfig from disk.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';

import 'data/models/models.dart';
import 'data/services/file_storage_service.dart';
import 'data/services/schedule_service.dart';
import 'features/automation/pages/permission_guide_page.dart';
import 'features/chat/pages/chat_page.dart';
import 'features/knowledge_base/pages/knowledge_base_page.dart';
import 'features/model_market/pages/model_market_page.dart';
import 'features/settings/pages/settings_page.dart';

class OpenAgentApp extends StatefulWidget {
  const OpenAgentApp({super.key});

  @override
  State<OpenAgentApp> createState() => _OpenAgentAppState();
}

class _OpenAgentAppState extends State<OpenAgentApp> {
  late final FileStorageService _storage;
  late final GoRouter _router;
  final _chatKey = GlobalKey<ChatPageState>();

  @override
  void initState() {
    super.initState();
    _storage = FileStorageService();
    _initScheduleService();
    _router = GoRouter(
      initialLocation: '/',
      routes: [
        ShellRoute(
          builder: (context, state, child) => _ScaffoldWithNav(
            location: state.uri.path,
            child: child,
          ),
          routes: [
            GoRoute(
              path: '/',
              builder: (_, __) =>
                  ChatPage(key: _chatKey, storage: _storage),
            ),
            GoRoute(
              path: '/models',
              builder: (_, __) => ModelMarketPage(
                storage: _storage,
                onActiveModelChanged: _onModelChanged,
              ),
            ),
            GoRoute(
              path: '/knowledge',
              builder: (_, __) => KnowledgeBasePage(storage: _storage),
            ),
            GoRoute(
              path: '/settings',
              builder: (_, __) => SettingsPage(
                storage: _storage,
                onChanged: _onConfigChanged,
              ),
            ),
          ],
        ),
        // Standalone page without bottom nav — returns to chat via AppBar back.
        GoRoute(
          path: '/permission_guide',
          builder: (_, __) => PermissionGuidePage(storage: _storage),
        ),
      ],
    );
  }

  Future<void> _onModelChanged(String? modelId) async {
    final config = await _storage.loadAppConfig();
    await _storage.saveAppConfig(config.copyWith(activeModelId: modelId));
    // The settings page also shows the current config; reload chat so it
    // picks up the new active model and loads it.
    _chatKey.currentState?.reload();
  }

  Future<void> _onConfigChanged(AppConfig config) async {
    await _storage.saveAppConfig(config);
    _chatKey.currentState?.reload();
  }

  Future<void> _initScheduleService() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      await ScheduleService.instance.init(storagePath: dir.path);
    } catch (_) {
      // Schedule init failure is non-fatal; the service will work when
      // storage becomes available.
    }
  }

  @override
  void dispose() {
    _router.dispose();
    ScheduleService.instance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'OpenAgent',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.light,
      ),
      routerConfig: _router,
    );
  }
}

class _ScaffoldWithNav extends StatelessWidget {
  const _ScaffoldWithNav({required this.location, required this.child});

  final String location;
  final Widget child;

  int get _index => switch (location) {
        _ when location.startsWith('/models') => 1,
        _ when location.startsWith('/knowledge') => 2,
        _ when location.startsWith('/settings') => 3,
        _ => 0,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) {
          switch (i) {
            case 1:
              context.go('/models');
            case 2:
              context.go('/knowledge');
            case 3:
              context.go('/settings');
            default:
              context.go('/');
          }
        },
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.chat_outlined),
              selectedIcon: Icon(Icons.chat),
              label: '对话'),
          NavigationDestination(
              icon: Icon(Icons.cloud_download_outlined),
              selectedIcon: Icon(Icons.cloud_download),
              label: '模型'),
          NavigationDestination(
              icon: Icon(Icons.library_books_outlined),
              selectedIcon: Icon(Icons.library_books),
              label: '知识库'),
          NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: '设置'),
        ],
      ),
    );
  }
}
