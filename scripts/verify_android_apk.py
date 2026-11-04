"""Validate and package a release-mode APK using the project's test signature.

This never creates or exports a production signing key. The Android build's
ephemeral debug certificate is deliberately disclosed in the release metadata.
"""

import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import ssl
import subprocess
import zipfile


def run(*command):
    return subprocess.check_output(command, text=True, stderr=subprocess.STDOUT)


def certificate_sha256(output):
    """Hash the verified public certificate, independent of CLI digest labels."""
    certificates = re.findall(
        r"-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----", output, re.S
    )
    assert len(certificates) == 1, "Expected one APK signing certificate"
    return hashlib.sha256(ssl.PEM_cert_to_DER_cert(certificates[0])).hexdigest()


release = json.loads(Path("releases/android-test.json").read_text())
apk = Path("build/app/outputs/flutter-apk/app-release.apk")
assert apk.is_file(), "APK was not produced"
sdk = Path(os.environ.get("ANDROID_SDK_ROOT") or os.environ["ANDROID_HOME"])
build_tools = sorted(
    (p for p in (sdk / "build-tools").iterdir() if (p / "apksigner").is_file()),
    key=lambda p: [int(n) for n in re.findall(r"\d+", p.name)],
)[-1]
signature = run(str(build_tools / "apksigner"), "verify", "--verbose", "--print-certs-pem", str(apk))
print(signature)
assert "CN=Android Debug" in signature, "Unexpected signing identity; stop for review"
certificate = certificate_sha256(signature)
badging = run(str(build_tools / "aapt"), "dump", "badging", str(apk))
print(badging)
assert f"name='{release['package_name']}'" in badging.splitlines()[0], "Wrong application ID"
assert f"versionCode='{release['version_code']}'" in badging.splitlines()[0], "Wrong version code"
assert f"versionName='{release['version_name']}'" in badging.splitlines()[0], "Wrong version name"
assert "application-debuggable" not in badging, "Expected an optimized non-debuggable release build"
minimum_sdk = int(re.search(r"^sdkVersion:'(\d+)'", badging, re.M).group(1))
target_sdk = int(re.search(r"^targetSdkVersion:'(\d+)'", badging, re.M).group(1))
with zipfile.ZipFile(apk) as archive:
    names = set(archive.namelist())
    for abi in ("armeabi-v7a", "arm64-v8a", "x86_64"):
        for library in ("libapp.so", "libflutter.so"):
            assert f"lib/{abi}/{library}" in names, f"Missing {abi}/{library}"
    for source in Path("assets").rglob("*"):
        if not source.is_file() or source.suffix in (".md",):
            continue
        # Verify every declared history/map/font asset byte-for-byte.
        if source.parts[1] in ("map-data", "fonts") or source.name == "history.json":
            key = "assets/flutter_assets/" + source.as_posix()
            assert key in names, f"Missing bundled asset: {source}"
            assert archive.read(key) == source.read_bytes(), f"Changed bundled asset: {source}"

out = Path("dist/android")
out.mkdir(parents=True, exist_ok=True)
filename = f"huaxia-timeline-{release['version_name']}-android-test-universal.apk"
shutil.copy2(apk, out / filename)
digest = hashlib.sha256(apk.read_bytes()).hexdigest()
source_sha = os.environ.get("GITHUB_SHA") or run("git", "rev-parse", "HEAD").strip()
repo = os.environ.get("GITHUB_REPOSITORY", "KingXcode/china-dynasty-flutter")
run_url = f"https://github.com/{repo}/actions/runs/{os.environ.get('GITHUB_RUN_ID', '')}"
info = {
    **release,
    "source_sha": source_sha,
    "workflow_url": run_url,
    "build_mode": "release",
    "signing": "ephemeral Android debug/test certificate; not a production signing key",
    "certificate_sha256": certificate,
    "apk": filename,
    "apk_sha256": digest,
    "apk_size_bytes": apk.stat().st_size,
    "minimum_sdk": minimum_sdk,
    "target_sdk": target_sdk,
    "abis": ["armeabi-v7a", "arm64-v8a", "x86_64"],
    "device_validation": "Not performed; automated checks do not replace device testing",
}
(out / "build-info.json").write_text(json.dumps(info, ensure_ascii=False, indent=2) + "\n")
(out / "apk-verification.txt").write_text(signature + "\n" + badging)
(out / "release-notes.md").write_text(f"""## 下载与安装

下载 **{filename}**，在 Android 手机上打开安装。通用 APK 包含 ARM 32 位、ARM 64 位和 x86_64，无需选择架构；最低 Android API {minimum_sdk}。

## 版本内容

- 华夏脉络 {release['version_name']}（构建号 {release['version_code']}）。
- 包含最新界面与疆域年份拖动优化，时间轴、地图资料和中文字体均随安装包提供。
- 已同步近现代时间轴的名称与详情调整。
- 原 HTML 项目与网站不受影响。

## 签名说明

**这是测试版，不是商店上架包。** 使用 release 模式优化编译，但沿用项目模板的 Android debug/test 签名。没有配置或生成长期发布密钥。各次构建的临时签名可能不同，未来更新时可能需要先卸载旧测试版；卸载会清除应用本地数据。正式发布前需配置独立且妥善保管的发布签名。

## 构建与校验

- 源码：[{source_sha[:12]}](https://github.com/{repo}/commit/{source_sha})
- [构建记录]({run_url})
- 已通过 Dart 格式、Flutter 静态分析、自动化测试、历史与地图资源校验，以及 APK 包名、版本、架构、内置资源与签名校验。
- 尚未进行 Android 真机或模拟器运行验收。
- APK SHA-256：`{digest}`
- 签名证书 SHA-256：`{certificate}`
- 附件 `SHA256SUMS.txt`、`build-info.json` 和 `apk-verification.txt` 提供可复核记录。
""")
files = [filename, "build-info.json", "apk-verification.txt"]
(out / "SHA256SUMS.txt").write_text("".join(
    f"{hashlib.sha256((out / name).read_bytes()).hexdigest()}  {name}\n" for name in files
))
print(json.dumps(info, ensure_ascii=False, indent=2))
