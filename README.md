# 华夏脉络 · Flutter

独立的 Flutter 多端项目：Web、iOS、Android 共用一套 Dart 界面与资料。

界面保留 Cupertino 交互体系，并采用统一的瓷白、石墨、深玉与柔和青柠色视觉系统：悬浮胶囊导航、薄边圆角面板、中文探索索引、轻量轨道图形，以及原生搜索、滑动分段控件、Action Sheet、年份输入与导航转场。不是 Material 换色。

胶囊导航继续使用 CupertinoTabScaffold / CupertinoTabView，保留分页面导航栈与状态；支持键盘焦点、选择状态语义、安全区、减少动画及大号文字。文字色与背景保持 WCAG AA 对比度，历史分类色与警告色仍各自保留语义。

- 新仓库：https://github.com/KingXcode/china-dynasty-flutter
- 新 Web 地址：https://kingxcode.github.io/china-dynasty-flutter/
- 原 HTML 项目和原网站保持独立，不被此工程替换或部署。

## 功能

- 102 条王朝与并行政权记录，13 个时代/区域入口，52 项参考来源。
- 原生 Flutter 时间轴：手机采用一屏宽紧凑轨道；桌面使用固定宽度并行轨道与旁侧详情，支持双轴滚动。保留同年对齐、严格等比例刻度、缩放、年代表、搜索、来源与同期政权。
- 近现代年表：中华民国1912–1949，中华人民共和国1949年至今。
- 原生 CustomPainter 疆域地图：秦至清、原始 GeoJSON、拖动/双指缩放、年份切换、来源变化播放、重叠多边形与可访问列表、年表对照和已知数据问题。
- 地图拖动年份时优先同步读取已缓存的来源区间；快速跨世纪拖动合并读取，松手立即加载最终目标。新资料未到时保留上一幅地图并同时标出原年份和目标年份，不把旧疆域当作新年份；失败和过期请求不会覆盖当前结果。缓存有界，闲置后预读相邻世纪，地图标签布局复用。
- 所有历史资料和地图随应用打包，不依赖第三方地图瓦片或 JS。中文显示字体经过子集处理并打包。外部参考来源需联网打开。
- iOS / Android 标准工程、系统返回键、中文无障碍语义、可调整文字大小；Web 自托管 CanvasKit。

这不是 WebView 包装。地图是**来源区间筛选器**，不是逐年复原的精确疆域；缺漏和超出年表的记录会明确提示，绝不插值或虚构边界。

## 开发

验证使用 Flutter 3.47.5 / Dart 3.13.4。请先安装官方 Flutter SDK。

```sh
flutter pub get
flutter run -d chrome
# 已连接 Android 或 iOS 模拟器/真机时：
flutter run
```

```sh
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
python3 scripts/verify_assets.py
flutter build web --release --base-href /china-dynasty-flutter/ --no-web-resources-cdn
python3 scripts/test_version_web_build.py
python3 scripts/version_web_build.py build/web
```

本地预览发布构建时保留子路径，例如把 `build/web` 放入服务根的 `china-dynasty-flutter/`，再访问该子路径。若部署至域名根目录，改为 `--base-href /`。

## GitHub Pages

`.github/workflows/deploy.yml` 会在新仓库 `main` 更新时检查、测试、构建和发布；PR 仅检查，不部署。仓库 Settings → Pages → Source 选择 GitHub Actions。

发布构建会为 JavaScript、字体、历史和地图资源生成一致的内容版本路径，避免浏览器把新界面与缓存旧资料混用。原资源地址保留，最近被替换的版本保留 15 分钟以覆盖 GitHub Pages 的 10 分钟缓存过渡；地图文件内容不改变。刷新普通入口后加载同一版本的界面和资料，长期开着的标签页请刷新再继续使用。

仅新仓库有此工作流。原 `china-dynasty-timeline` 网站不受影响。

## iOS / Android

### Android 测试 APK

[GitHub Releases](https://github.com/KingXcode/china-dynasty-flutter/releases) 提供可直接下载的通用测试 APK（ARM 32 位、ARM 64 位、x86_64）。这是 release 模式优化编译、Android debug/test 签名的安装包，不是商店上架包。临时签名可能随构建变化，后续更新可能需要卸载旧测试版；卸载会清除应用本地数据。

`.github/workflows/android-release.yml` 仅在 `releases/android-test.json` 更新或手动运行时构建。工作流先执行格式、分析、测试和资源校验，再验证 APK 包名、版本、架构、资源和签名，发布为明确标记的 prerelease。已有标签和 Release 不覆盖，发布后重新下载并核对 SHA-256。再次发布请更新清单中的测试版标签，应用版本改变时同步 `pubspec.yaml`；正式发布前仍需配置自己的长期签名。


- Android：安装 Android SDK/JDK 17，运行 `flutter doctor` 后使用 `flutter build apk --debug` 做设备测试。正式上架前配置独立发布签名、图标及商店资料，再构建 `appbundle`。模板的 release 配置仍用 debug 签名，不能当正式上架包。
- iOS：需要 macOS、Xcode 和适配的模拟器/真机。打开 `ios/Runner.xcworkspace`，选择自己的开发团队、Bundle ID/签名，再 `flutter run` 或 `flutter build ipa`。
- 当前云环境没有 Xcode / iOS 签名环境，也未提供 Android SDK。三平台代码与工程已生成，Web 构建与 Flutter 测试不等于 iOS/Android 真机验收，未声称产生可上架的 IPA/AAB。

## 资料与许可

见 [SOURCE.md](SOURCE.md)、[疆域资料说明](assets/map-data/README.md)、[固定版本与文件哈希](assets/map-data/manifest.json)。

- Cliopatria / Seshat Global History Databank v0.2.1，CC BY 4.0。
- Natural Earth 1:110m Land，公共领域。
- Noto Sans CJK SC，SIL Open Font License。展示字符子集打包，版权与完整许可见 `assets/fonts/NOTO-LICENSE.txt`。
- 时间轴保留其他条目的摘要、年代口径与引用；中华民国条目仅展示名称和年表区间。公开参考资料版权归各原作者。

## 目录

- `lib/app_style.dart`：共享颜色、页面标题与自适应胶囊导航。
- `lib/history.dart`：数据模型、搜索、无零年算术。
- `lib/timeline.dart`：手机时间轴、Cupertino 控件、年代表和详情。
- `lib/desktop_timeline.dart`：桌面并行轨道、折叠刻度、双轴滚动与无障碍。
- `lib/territory.dart`：地图资料审计、绘制与操作。
- `assets/`：完整年表和固定版本地图、许可、字体。
- `web/`、`android/`、`ios/`：平台入口。
- `test/`：数据、时间刻度、地图、窄屏和交互回归。
