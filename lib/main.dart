import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'history.dart';
import 'app_style.dart';
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
  const HuaxiaApp({super.key, this.data, this.territoryRepository});
  final HistoryData? data;
  final TerritoryRepository? territoryRepository;
  @override
  Widget build(BuildContext context) => CupertinoApp(
    title: '华夏脉络 · 中国历史',
    debugShowCheckedModeBanner: false,
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
    localizationsDelegates: const [
      GlobalCupertinoLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ],
    theme: const CupertinoThemeData(
      brightness: Brightness.light,
      primaryColor: AppColors.accent,
      primaryContrastingColor: AppColors.surface,
      barBackgroundColor: AppColors.canvas,
      scaffoldBackgroundColor: AppColors.canvas,
      textTheme: CupertinoTextThemeData(
        textStyle: TextStyle(
          inherit: false,
          fontFamily: 'NotoSansSC',
          fontSize: 15,
          color: AppColors.ink,
        ),
        navTitleTextStyle: TextStyle(
          inherit: false,
          fontFamily: 'NotoSansSC',
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
        ),
        navLargeTitleTextStyle: TextStyle(
          inherit: false,
          fontFamily: 'NotoSansSC',
          fontSize: 30,
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
        ),
        actionTextStyle: TextStyle(
          inherit: false,
          fontFamily: 'NotoSansSC',
          fontSize: 17,
          color: AppColors.accent,
        ),
        actionSmallTextStyle: TextStyle(
          inherit: false,
          fontFamily: 'NotoSansSC',
          fontSize: 15,
          color: AppColors.accent,
        ),
        navActionTextStyle: TextStyle(
          inherit: false,
          fontFamily: 'NotoSansSC',
          fontSize: 17,
          color: AppColors.accent,
          decoration: TextDecoration.none,
        ),
        pickerTextStyle: TextStyle(
          inherit: false,
          fontFamily: 'NotoSansSC',
          fontSize: 21,
          color: AppColors.ink,
        ),
        dateTimePickerTextStyle: TextStyle(
          inherit: false,
          fontFamily: 'NotoSansSC',
          fontSize: 21,
          color: AppColors.ink,
        ),
        tabLabelTextStyle: TextStyle(
          inherit: false,
          fontFamily: 'NotoSansSC',
          fontSize: 10,
          color: AppColors.subtle,
        ),
      ),
    ),
    home: HistoryShell(data: data, territoryRepository: territoryRepository),
  );
}

class HistoryShell extends StatefulWidget {
  const HistoryShell({super.key, this.data, this.territoryRepository});
  final HistoryData? data;
  final TerritoryRepository? territoryRepository;
  @override
  State<HistoryShell> createState() => _HistoryShellState();
}

class _HistoryShellState extends State<HistoryShell> {
  late Future<HistoryData> _data;
  late CupertinoTabController _tabs;
  @override
  void initState() {
    super.initState();
    _data = widget.data != null
        ? Future.value(widget.data)
        : HistoryData.load();
    final uri = Uri.base;
    _tabs = CupertinoTabController(
      initialIndex:
          uri.queryParameters['view'] == 'territory' ||
              uri.fragment.contains('territory')
          ? 1
          : 0,
    );
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<HistoryData>(
    future: _data,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return CupertinoPageScaffold(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(CupertinoIcons.exclamationmark_circle, size: 36),
                const SizedBox(height: 16),
                const Text('历史资料暂未载入'),
                CupertinoButton(
                  onPressed: () => setState(() => _data = HistoryData.load()),
                  child: const Text('重新载入'),
                ),
              ],
            ),
          ),
        );
      }
      if (!snapshot.hasData) {
        return const CupertinoPageScaffold(
          child: Center(child: CupertinoActivityIndicator()),
        );
      }
      final data = snapshot.data!;
      return CupertinoTabScaffold(
        controller: _tabs,
        tabBar: AppNavigationDock(
          textScaler: MediaQuery.textScalerOf(context),
          height:
              84 +
              (MediaQuery.textScalerOf(context).scale(13) - 13).clamp(0, 80),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(CupertinoIcons.clock),
              activeIcon: Icon(CupertinoIcons.clock_fill),
              label: '历史脉络',
            ),
            BottomNavigationBarItem(
              icon: Icon(CupertinoIcons.map),
              activeIcon: Icon(CupertinoIcons.map_fill),
              label: '疆域地图',
            ),
          ],
        ),
        tabBuilder: (context, index) => CupertinoTabView(
          builder: (context) => CupertinoPageScaffold(
            navigationBar: CupertinoNavigationBar(
              middle: const Text(
                '华夏脉络',
                style: TextStyle(letterSpacing: 2, fontWeight: FontWeight.w700),
              ),
              backgroundColor: AppColors.canvas,
              border: const Border(
                bottom: BorderSide(color: AppColors.line, width: .5),
              ),
              trailing: CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: const Size(44, 44),
                onPressed: () => showAboutHistory(context, data),
                child: const Icon(
                  CupertinoIcons.info_circle,
                  size: 20,
                  semanticLabel: '阅读说明',
                ),
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: index == 0
                  ? TimelinePage(data: data)
                  : TerritoryPage(
                      dynasties: data.dynasties,
                      repository: widget.territoryRepository,
                    ),
            ),
          ),
        ),
      );
    },
  );
}

void showAboutHistory(BuildContext context, HistoryData data) {
  Navigator.of(context).push(
    CupertinoPageRoute<void>(
      builder: (context) => CupertinoPageScaffold(
        navigationBar: const CupertinoNavigationBar(
          middle: Text('阅读说明'),
          previousPageTitle: '华夏脉络',
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
            children: [
              const AppSectionHeading('有尺度，也保留余地。'),
              AppGroupedSection(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ...data.meta.entries
                          .where(
                            (e) => [
                              'coverage',
                              'dating',
                              'regions',
                            ].contains(e.key),
                          )
                          .map(
                            (e) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Text(
                                '${e.value}',
                                style: const TextStyle(
                                  height: 1.7,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                      const Text(
                        '轨道不代表地理方位、疆域大小或正统地位。同一高度对应同一年；紧凑模式各段比例不同，精确模式关闭压缩。',
                        style: TextStyle(height: 1.7, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 22),
              ...data.traditions.map(
                (t) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: AppGroupedSection(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${t['name']}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${t['dateLabel']}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.secondary,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            '${t['note']}',
                            style: const TextStyle(fontSize: 14, height: 1.7),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              AppSectionHeading('参考资料 · ${data.sources.length} 项'),
              AppGroupedSection(
                child: Column(
                  children: data.sources
                      .map((s) => SourceTile(source: s))
                      .toList(),
                ),
              ),
              const SizedBox(height: 24),
              const AppSectionHeading('开放资料与许可'),
              AppGroupedSection(
                child: Column(
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(18),
                      child: Text(
                        '疆域：Cliopatria v0.2.1，CC BY 4.0。底图：Natural Earth，公共领域。资料存在缺漏与年代错位，详见地图逐年说明。字体：Noto Sans CJK，SIL OFL。',
                        style: TextStyle(fontSize: 14, height: 1.7),
                      ),
                    ),
                    CupertinoListTile(
                      title: const Text('查看开源许可'),
                      trailing: const CupertinoListTileChevron(),
                      onTap: () => Navigator.of(context).push(
                        CupertinoPageRoute<void>(
                          builder: (context) => const _LicensesPage(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _LicensesPage extends StatelessWidget {
  const _LicensesPage();
  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    navigationBar: const CupertinoNavigationBar(
      middle: Text('开源许可'),
      previousPageTitle: '阅读说明',
    ),
    child: SafeArea(
      child: FutureBuilder<List<LicenseEntry>>(
        future: LicenseRegistry.licenses.toList(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CupertinoActivityIndicator());
          }
          return ListView.builder(
            itemCount: snapshot.data!.length,
            itemBuilder: (context, index) {
              final entry = snapshot.data![index];
              return Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.packages.join(' · '),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 10),
                    AppSelectableText(
                      entry.paragraphs.map((p) => p.text).join('\n\n'),
                      style: const TextStyle(fontSize: 12, height: 1.6),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    ),
  );
}
