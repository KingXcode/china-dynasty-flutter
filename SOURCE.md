# 来源与迁移边界

本工程是独立 Flutter 项目，不覆盖、移动或部署原 HTML 项目。

- 原项目：https://github.com/KingXcode/china-dynasty-timeline
- 原网站：https://kingxcode.github.io/china-dynasty-timeline/
- `assets/history.json` 从原 `data.js` 的 `HISTORY_DATA` 无损转换；2026-11-04 数据，102 条记录 / 56 项来源 / 13 个分期。
- 对照的原 `data.js` Git blob SHA：`e5b2c660e4ed8ffefeec1c77f0dc177405cc5133`。
- 仅 `ongoing: true` 的结束年在运行时取当前年。中华民国（大陆时期）保持 1912–1949，迁台后治理说明保持在注释中。
- `assets/map-data/` 原样保留来源、版本、原始坐标、许可证、manifest 文件哈希与已知问题审计。没有新增或插值古代边界。
- UI 使用 Flutter widgets / CustomPainter 原生重写，不是嵌入 WebView。
- Noto Sans CJK SC 字体经子集处理，仅保留项目展示使用字符；原始字体版权和 SIL OFL 见 `assets/fonts/NOTO-LICENSE.txt`。可用 `scripts/subset_font.py` 重建。
