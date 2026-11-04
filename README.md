# 华夏脉络 · Flutter

独立的 Flutter 多端项目：Web、iOS、Android 共用一套 Dart 界面与资料。

- 新仓库：https://github.com/KingXcode/china-dynasty-flutter
- 新 Web 地址：https://kingxcode.github.io/china-dynasty-flutter/
- 原 HTML 项目和原网站保持独立，不被此工程替换或部署。

## 功能

- 102 条王朝与并行政权记录，13 个时代/区域入口，56 项参考来源。
- 原生 Flutter 时间轴：同年对齐、并行轨道、手机一屏宽布局、紧凑与严格等比例刻度、缩放、完整年代表、全局搜索、详情与同期政权。
- 近现代记录保留大陆分期：中华民国（大陆时期）1912–1949，迁台后治理说明保留在注释；中华人民共和国延续至当前年。
- 原生 CustomPainter 疆域地图：秦至清、原始 GeoJSON、拖动/双指缩放、年份切换、来源变化播放、重叠多边形与可访问列表、年表对照和已知数据问题。
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
```

本地预览发布构建时保留子路径，例如把 `build/web` 放入服务根的 `china-dynasty-flutter/`，再访问该子路径。若部署至域名根目录，改为 `--base-href /`。

## GitHub Pages

`.github/workflows/deploy.yml` 会在新仓库 `main` 更新时检查、测试、构建和发布；PR 仅检查，不部署。仓库 Settings → Pages → Source 选择 GitHub Actions。

仅新仓库有此工作流。原 `china-dynasty-timeline` 网站不受影响。

## iOS / Android

- Android：安装 Android SDK/JDK 17，运行 `flutter doctor` 后使用 `flutter build apk --debug` 做设备测试。正式上架前配置独立发布签名、图标及商店资料，再构建 `appbundle`。模板的 release 配置仍用 debug 签名，不能当正式上架包。
- iOS：需要 macOS、Xcode 和适配的模拟器/真机。打开 `ios/Runner.xcworkspace`，选择自己的开发团队、Bundle ID/签名，再 `flutter run` 或 `flutter build ipa`。
- 当前云环境没有 Xcode / iOS 签名环境，也未提供 Android SDK。三平台代码与工程已生成，Web 构建与 Flutter 测试不等于 iOS/Android 真机验收，未声称产生可上架的 IPA/AAB。

## 资料与许可

见 [SOURCE.md](SOURCE.md)、[疆域资料说明](assets/map-data/README.md)、[固定版本与文件哈希](assets/map-data/manifest.json)。

- Cliopatria / Seshat Global History Databank v0.2.1，CC BY 4.0。
- Natural Earth 1:110m Land，公共领域。
- Noto Sans CJK SC，SIL Open Font License。展示字符子集打包，版权与完整许可见 `assets/fonts/NOTO-LICENSE.txt`。
- 每条时间轴记录的摘要、年代口径与引用均保留。公开参考资料版权归各原作者。

## 目录

- `lib/history.dart`：数据模型、搜索、无零年算术。
- `lib/timeline.dart`：共享年份映射、原生时间轴、年代表和详情。
- `lib/territory.dart`：地图资料审计、绘制与操作。
- `assets/`：完整年表和固定版本地图、许可、字体。
- `web/`、`android/`、`ios/`：平台入口。
- `test/`：数据、时间刻度、地图、窄屏和交互回归。
