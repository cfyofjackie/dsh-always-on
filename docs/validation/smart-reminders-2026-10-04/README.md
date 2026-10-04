# 气泡与图标渲染证据

日期：2026-10-04。图片由 Debug App 的原生 ImageRenderer / 隔离验证入口产生，是组件渲染，不是解锁后截取的真实桌面。

- `chibi-planReview-light.png`：Q 版蓝白 / 计划审阅。
- `glass-success-dark.png`：简洁半透明 / 完成 / 深色。
- `menu-light.png`、`menu-dark.png`：18 pt 模板头像在两种背景。

完整 20 张气泡样例可在 Debug App 执行 `--validate-reminder-preview <独立输出目录>` 后重建；入口使用随机偏好域与内存数据，不连接真实 DSH，不写真实提醒。它还检查偏好恢复、预览退出、真实提醒接管、隐藏不清未读 / 不补弹、查看不解除 waiting。

图标源在 `macos/Resources/Assets.xcassets/`；旧 AppIcon 在 `docs/icon-preview/legacy-2026-10-04/`。Debug / Release 都支持 `--export-brand <独立输出目录>`，生成 AppIcon.appiconset 与 DSMenuIcon.imageset；该入口不改角色资源。

Mac 锁屏，设置实际点击、真实 DSH 前台、系统 / 视频全屏和多显示器尚未实机验收。ScrollView 不能由 ImageRenderer 完整捕获，未使用透明输出充当设置界面证据。详见 [完整验证记录](../../VALIDATION.md)。
