import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'history.dart';
import 'timeline.dart';
import 'territory.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Noto Sans CJK SC',
    ], await rootBundle.loadString('assets/fonts/NOTO-LICENSE.txt'));
    yield LicenseEntryWithLineBreaks([
      'Cliopatria v0.2.1',
    ], await rootBundle.loadString('assets/map-data/LICENSE-CLIOPATRIA.md'));
  });
  runApp(const HuaxiaApp());
}

class HuaxiaApp extends StatelessWidget {
  const HuaxiaApp({super.key, this.data});
  final HistoryData? data;
  @override
  Widget build(BuildContext context) {
    const ink = Color(0xff284c42);
    final scheme = ColorScheme.fromSeed(
      seedColor: ink,
      surface: const Color(0xfffaf8f1),
    );
    return MaterialApp(
      title: '华夏脉络 · 中国历史',
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        fontFamily: 'NotoSansSC',
        scaffoldBackgroundColor: const Color(0xfffaf8f1),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xfffaf8f1),
          surfaceTintColor: Colors.transparent,
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: const Color(0xfffffdf7),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Color(0xffe4e4d9)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white.withValues(alpha: .7),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xffdddcd2)),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
        ),
      ),
      home: HistoryShell(data: data),
    );
  }
}

class HistoryShell extends StatefulWidget {
  const HistoryShell({super.key, this.data});
  final HistoryData? data;
  @override
  State<HistoryShell> createState() => _HistoryShellState();
}

class _HistoryShellState extends State<HistoryShell> {
  late Future<HistoryData> _data;
  int _page = 0;
  @override
  void initState() {
    super.initState();
    _data = widget.data != null
        ? Future.value(widget.data)
        : HistoryData.load();
    final uri = Uri.base;
    if (uri.queryParameters['view'] == 'territory' ||
        uri.fragment.contains('territory')) {
      _page = 1;
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<HistoryData>(
    future: _data,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off_outlined, size: 42),
                  const SizedBox(height: 16),
                  const Text('历史资料暂未载入，请重试。'),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => setState(() => _data = HistoryData.load()),
                    child: const Text('重新载入'),
                  ),
                ],
              ),
            ),
          ),
        );
      }
      if (!snapshot.hasData) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      final data = snapshot.data!;
      final wide = MediaQuery.sizeOf(context).width >= 1000;
      final pages = [
        TimelinePage(data: data),
        TerritoryPage(dynasties: data.dynasties),
      ];
      return Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xffa4543b),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Text(
                  '华',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 22,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                '华夏脉络',
                style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 2),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: '阅读说明与来源',
              onPressed: () => showAboutHistory(context, data),
              icon: const Icon(Icons.info_outline),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Row(
            children: [
              if (wide)
                NavigationRail(
                  selectedIndex: _page,
                  onDestinationSelected: (value) =>
                      setState(() => _page = value),
                  labelType: NavigationRailLabelType.all,
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.account_tree_outlined),
                      selectedIcon: Icon(Icons.account_tree),
                      label: Text('历史脉络'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.map_outlined),
                      selectedIcon: Icon(Icons.map),
                      label: Text('疆域随时间'),
                    ),
                  ],
                ),
              if (wide) const VerticalDivider(width: 1),
              Expanded(
                child: IndexedStack(
                  index: _page,
                  children: [
                    pages[0],
                    TickerMode(enabled: _page == 1, child: pages[1]),
                  ],
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: wide
            ? null
            : NavigationBar(
                selectedIndex: _page,
                onDestinationSelected: (value) => setState(() => _page = value),
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.account_tree_outlined),
                    selectedIcon: Icon(Icons.account_tree),
                    label: '历史脉络',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.map_outlined),
                    selectedIcon: Icon(Icons.map),
                    label: '疆域随时间',
                  ),
                ],
              ),
      );
    },
  );
}

void showAboutHistory(BuildContext context, HistoryData data) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: .8,
      minChildSize: .4,
      maxChildSize: .95,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
        children: [
          Text('怎样阅读华夏脉络', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          ...data.meta.entries
              .where((e) => ['coverage', 'dating', 'regions'].contains(e.key))
              .map(
                (e) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text('${e.value}'),
                ),
              ),
          const Text('图中的轨道不代表地理方位、疆域大小或正统地位。同一高度对应同一年；紧凑模式各段比例不同，精确模式关闭压缩。'),
          const SizedBox(height: 18),
          ...data.traditions.map(
            (t) => Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${t['name']}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text('${t['dateLabel']}'),
                    const SizedBox(height: 8),
                    Text('${t['note']}'),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '参考资料 · ${data.sources.length} 项',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          ...data.sources.map((s) => SourceTile(source: s)),
          const SizedBox(height: 12),
          const Text(
            '疆域：Cliopatria v0.2.1 / CC BY 4.0。底图：Natural Earth，公共领域。原始资料包含缺漏与年代错位，详见地图中的逐年说明。字体：Noto Sans CJK，SIL Open Font License。',
          ),
          TextButton(
            onPressed: () => showLicensePage(
              context: context,
              applicationName: '华夏脉络',
              applicationVersion: '1.0.0',
            ),
            child: const Text('查看开源许可'),
          ),
        ],
      ),
    ),
  );
}
