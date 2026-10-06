# 用 Xcode 开发 DSH Always On

## 打开与运行

1. 用 Xcode 打开 `macos/DSHAlwaysOn.xcodeproj`。
2. 顶部方案选 **DSH Always On**，运行设备选 **My Mac**。
3. 点击左上角 **Run ▶**，或按 `⌘R`。Debug 启动会显示会话与设置，方便调试。
4. 按 `⌘U` 运行已有 42 项核心测试（含角色素材 / 节奏、提醒期限、预览与查看边界检查）；测试无需运行模型任务或启用 DSH 集成。

列表里还可能看到没有空格的 `DSHAlwaysOn`，它是原 Swift Package 的可执行方案。日常 App 开发使用 **DSH Always On**。

当前本机已经安装 Xcode 与 Node，插件开发依赖也已安装，可直接构建。新机器需准备 Xcode 27 / Swift 6.4、Node.js 24+，再在 `plugin/` 运行一次 `npm ci`。Xcode 构建期间不自动联网安装依赖。

## 在哪里修改

- **App**：现有 SwiftUI / AppKit 界面、通知、桌宠和设置。
- **Resources**：A 均衡 Q 版图集、角色动作清单、五张静态回退图、AppIcon 图标和 Info.plist。
- **Tests**：现有核心状态与集成配置测试。
- **DSH Plugin**：host / client 的 TypeScript 源码。
- **Package Dependencies → DSHAlwaysOn**：本地 Swift Package，App 链接其 CompanionCore 库。

工程引用现有源码，核心库仍由本地 Swift Package 管理。App 与测试在 Xcode 中构建，不复制第二套业务代码。

## 内置插件与角色资源

每次构建会编译 TypeScript，并把 host / client 和 package.json 嵌入 App 的 Resources/plugin；正常用户仍只安装一个 App。脚本需要 Node，但最终 App 运行不要求用户另装 Node。

Xcode 的构建脚本隔离保持开启，输入和输出路径逐项声明。若提示缺少 Node 或 esbuild，按错误提示补齐开发依赖。

角色形象与动作统一在长期保留的 `playground/pet-design/` 实验室调整。当前选择由 `production.json` 指定为 A 均衡 Q 版；图集在 `assets/a-balanced.png`，分帧矩形在 `assets/atlas-data.js`，五状态节奏与小跳跃在 `assets/motion-data.js`。原参考图片、B / C 对照及替换前的简易素材均保留。

调整后运行 `bash scripts/refresh-art.sh`：先从实验室同步图集与动作清单及认可生活动作，再用同一原生绘制逻辑导出五张静态回退 PNG，最后在 Xcode 构建。直接修改 Resources 会在同步时被源素材更新。默认不更新 App 图标；显式 `--icons` 才刷新图标。原简易 CharacterView 绘图归档在实验室 `archive/`，不参与生产渲染。

生活动作由 `scripts/sync-life-art.mjs` 同步到 `Resources/characters/life.json` 与4张PNG；吃饭24姿势 / 5.04秒＋2.96秒收尾，扔小鲸鱼23姿势 / 4.13秒＋2秒收尾。保留原水平 / 脚底登记，浮空道具按全动作范围缩放以适应原生画布，不重新生成图片。运行素材独立保存，公开克隆无需实验室；待机5 / 10秒设置与提醒停留时间分开。

App 使用缓存逐帧 PNG 播放，208 × 208 pt 角色画布与 208 × 240 pt 窗口。切到 Native 或系统睡眠时停止动作；系统减少动态效果使用静态帧。成功 / 失败仍由原事件规则控制短暂反馈，等待不会因动画循环解除。

Debug 构建可带 `--preview-character` 启动独立原生五状态窗口，复用真实资源 / 播放器但不创建 Coordinator、不读会话或启动 DSH 连接。`--validate-character` 仅校验图集和透明点击区域，不启动正常 App。

Debug 的 `--validate-life-preview <输出目录>` 使用独立UserDefaults与内存Coordinator检查七动作、暂停 / 从头 / 恢复、间隔保存及提醒优先，并导出47张原生帧和设置离屏图，不接入真实任务。自动摸鱼一轮结束后重新计时，测试模式循环，二者复用同一播放器。

## 本机签名与打包

工程默认使用 **Sign to Run Locally** 的本地临时签名，没有指定 Apple Team，不修改 Apple 账户。无需在本轮配置公开发布证书。正式发布时再配置 Developer ID 和公证。

`bash scripts/build-app.sh` 已改为调用同一个 Xcode App 方案的 Release 构建，输出 `dist/DSH Always On.app`；已有试用 App 会保留为 previous 备份。

`bash scripts/build-dmg.sh` 继续将这个 App 制作为安装包。日常调试使用 Xcode Run，不需要每次制作 DMG。

## 运行注意

Debug 和 Release 使用同一个 App 标识，继续使用既有模式、提醒和配置。避免同时运行旧试用 App 与 Xcode 调试版，以免桌宠或提醒重复；可自行先退出旧 App。

Debug 运行时，“开发预览”菜单提供问题、批准、计划审阅、完成和失败气泡。需处于桌面伙伴模式并已有提醒记录；预览只借用既有提醒的会话目标，标注“[预览]”，不会创建任务或写入假未读记录。预览保留到点击或关闭，便于检查交互。Release 不包含此菜单。

工程接入没有修改 DSH 配置、系统通知权限或开机启动。连接、真实通知与等待事件的验收边界仍见 [VALIDATION.md](VALIDATION.md)。
