# 验证记录（2026-11-04，Cupertino v1.1.0）

## 界面更新

- 全面使用CupertinoApp、CupertinoTabScaffold、CupertinoNavigationBar、搜索、滑动分段控件、Action Sheet、Switch、Slider及AlertDialog，不使用Material界面祖先。
- 压缩手机首屏控件，地图年份/滑块/播放均首屏可用。
- 桌面恢复固定155px并行轨道、620px双轴滚动窗口和侧边详情，不再拉伸手机图。
- 中文动作文字与导航转场样式单独配置，避免字体回退和TextStyle插值冲突。

## 已通过

- Flutter 3.47.5 / Dart 3.13.4：`flutter analyze` 无问题。
- `flutter test`：42 项数据/模型/界面/手势回归通过，默认跳过3项可选渲染快照。
- 全部可选快照启用时45项测试全部通过，包含390px和1200px的真实中文/Cupertino字体完整页面，以及独立桌面多轨图。地图快照使用真实资产预载以避开测试FakeAsync与解析隔离线程的时序差异；异步竞态/失败独立测试。
- 完整资料：102条年表记录、56项来源、13个时代；中华民国大陆时期1912–1949及迁台延续注释保留。
- 时间轴：无零年、同年对齐、并行轨道、精确比例、紧凑压缩、全局搜索、详情关闭、320/390/1200px布局、200%系统文字。
- 地图：闭区间筛选、BCE世纪分片、877条记录/132个原名、原始Polygon洞/MultiPolygon、已知年代错位排除、变化年份、异步竞态、失败重试、手势和点选、年份0校验、前1年跨至公元1年、切页停止播放。
- `python3 scripts/verify_assets.py`：27个地图资产哈希与原始manifest完全相符。
- `flutter build web --release --base-href /china-dynasty-flutter/ --no-web-resources-cdn`：成功。
- 构建产物静态检查：正确新项目子路径、local CanvasKit、完整历史与地图资产。
- `qa/` 截图已人工检查，时间轴压缩注释和地图标签可读，无窄屏溢出。

## 未完成 / 验证边界

- 本机Chromium因容器系统socket权限无法启动；这是本地浏览器测试环境限制，不将Flutter渲染测试说成浏览器验收。生产地址部署后另做浏览器检查。
- 本机 `flutter doctor -v` 明确未找到Android SDK；没有执行APK/AAB构建或Android真机测试。
- 本机为Linux，无Xcode/Apple签名环境；没有执行iOS构建或iOS真机测试。
- Android/iOS标准平台工程已生成，但应用商店签名、隐私/发布资料、真机手势与无障碍验收仍需相应平台环境。
- 地图结构检查并不验证历史边界真实性或所有拓扑自交。来源缺漏和年代错位仍按界面说明展示。

可选渲染截图：

```sh
flutter test --dart-define=RENDER_SNAPSHOTS=true --dart-define=DESKTOP_SNAPSHOT=true --update-goldens
```
