# Paste

Paste 是一个仅保留剪贴板历史能力的原生 macOS 26+ 工具，界面与交互直接沿用 TinyCast 的剪贴板实现。

## 功能

- 默认全局快捷键 `⌥W`
- 自动记录文本和图片，过滤密码、OTP 与系统标记的敏感内容
- SQLite + FTS5 本地历史与搜索
- 固定、复制、直接粘贴、保留窗口粘贴、删除与清空
- 来源 App、图片信息与文本统计
- 可配置保留期限、排除 App 与全局快捷键
- 菜单栏常驻，不显示 Dock 图标

直接粘贴需要在“系统设置 → 隐私与安全性 → 辅助功能”中允许 Paste。

## 构建

需要 macOS 26+ 与 Xcode 26+。

```bash
xcodegen generate
./script/build_and_run.sh --verify
```

## 来源与许可证

Paste 基于 [abue-ammar/tinycast](https://github.com/abue-ammar/tinycast) 提交
`79c07daece9a161e74f82a5735424fbaa121e997` 的剪贴板及视觉代码构建。

本项目遵循 GNU Affero General Public License v3，详见 `LICENSE`。
