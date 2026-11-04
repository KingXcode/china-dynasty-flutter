#!/usr/bin/env python3
"""Rebuild bundled display font from official Noto Sans CJK SC TTC/OTF.
Requires fonttools. Example: python scripts/subset_font.py /path/NotoSansCJK-Regular.ttc
All displayed dataset/UI characters plus printable ASCII are retained.
"""
import pathlib, sys
from fontTools import subset
from fontTools.ttLib import TTFont
root = pathlib.Path(__file__).resolve().parent.parent
font = TTFont(sys.argv[1], fontNumber=2 if sys.argv[1].endswith('.ttc') else -1)
text = ''.join(chr(c) for c in range(32,127))
# Include GB2312 common Simplified Chinese so searches, platform menus, and
# future dataset wording do not immediately require an external fallback font.
for high in range(0xA1, 0xF8):
 for low in range(0xA1, 0xFF):
  try: text += bytes([high,low]).decode('gb2312')
  except UnicodeDecodeError: pass
for folder in ('lib','assets'):
 for path in (root/folder).rglob('*'):
  if path.suffix in ('.dart','.json','.geojson','.md'):
   text += path.read_text()
text += '华夏脉络中国历史朝代疆域地图年公元前至今缩放恢复开始暂停上下一年关闭取消确定错误重试加载复制来源许可详情屏幕阅读器阅读说明选择返回搜索清除未找到记录版本十六国五代十国南北朝三国东周战国秦汉隋唐宋元明清中华民国大陆时期中华人民共和国一览华夏纵贯古今地图浏览器资料边界时间范围并行政权原始分片无零年已排除保留没有中国时间轴当前结束继续修改设置语言所有许可证字体自然地球现代陆地轮廓不是古代海岸线名称数量';
options = subset.Options(); options.name_IDs = ['*']; options.name_legacy = True
s = subset.Subsetter(options=options); s.populate(text=text); s.subset(font)
font.save(root/'assets/fonts/NotoSansSC-Subset.otf')
print('Retained', len(set(text)), 'characters')
