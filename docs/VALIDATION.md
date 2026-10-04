# V0.1 验证记录

日期：2026-10-03  
交付性质：本机试用，不等于正式发布验收全部通过

## 首个公开试用版构建（2026-10-04）

- 见 [GitHub 首发清单](tasks/2026-10-04-GitHub首发.md)。用户授权公开仓库；发布当前源码重新构建的安装包，不能据此认定与用户原先安装版本相同。
- 本轮 Swift 核心 38 项、Node 31 项和 TypeScript 检查通过。工作区及仅包含 88 个公开文件的独立副本 Release 构建通过，独立副本无旧实验室 / Godot / 归档，素材同步脚本回退检查通过。
- 独立构建严格签名验证、角色素材检查通过：A 均衡 Q 版、5 状态、20 帧、208 pt、透明命中区域。host / client 与该副本插件编译输出一致，生产源码 / 脚本 / 配置 / 素材与待提交文件一致。
- DMG 内部校验通过，下载附件 7,578,080 字节，SHA-256 `cf6546bd513cb654a27bde50591824e645a9d7ed5809acf4819d2cb84d8a41eb`。采用本地临时签名，未获得 Developer ID 公证。
- [公开仓库](https://github.com/cfyofjackie/dsh-always-on) 的 main 文件树与本地提交 88 文件一致，无旧实验 / 归档，公开页面 HTTP 200。[v0.1.0](https://github.com/cfyofjackie/dsh-always-on/releases/tag/v0.1.0) 为非草稿预发布，附件名 / 大小 / 服务端摘要正确；匿名重新下载 DMG 后 SHA-256 一致。构建源码对应 `292c855a786f291155d95bc642ba639605a980cc`。
- 旧归档 ZIP、归档索引与原参考图哈希未变；不修改另一会话实验室、已安装 App、DSH 集成配置、任务或系统权限。前台 / 真实全屏等功能仍按下面记录保留待验收状态。

## 气泡外观、智能提醒与图标（2026-10-04）

- [同一清单](tasks/2026-10-04-气泡外观与智能提醒.md) 五项代码已落地，已验证 3/5；前台查看和真实全屏两项保留未勾选。
- Swift Package / Xcode 各 38 项核心测试通过；TypeScript `npm run check` 与 31 项 Node 测试通过。新增覆盖精确目标、焦点 / 可见 / 加载 / 时效、等待类型、旧周期和固定边界、独立查看队列、超时与卸载、打包 client 两次渲染帧后确认、选择中途变化不确认及资源清理。既有并发新提醒不被旧点击清除、waiting 已读不解除继续通过。
- Debug 的 `--validate-reminder-preview <目录>` 使用随机测试偏好和内存事件，校验两款 / 五类样例、设置保存与重载测试关闭、真实提醒结束测试、隐藏时未读保留、返回不补弹、打开等待不处理 waiting、模式切换结束测试。输出 `isolatedPreviewChecks=passed`，没有读取真实 state / endpoint、注册集成、跑模型或申请通知权限。真实等待优先级仍保留，新完成提醒不会覆盖更高优先级的等待。
- 20 张气泡样例使用原生 ImageRenderer 渲染，浅 / 深色均核对。代表样例：[Q 版计划审阅](validation/smart-reminders-2026-10-04/chibi-planReview-light.png)、[半透明完成](validation/smart-reminders-2026-10-04/glass-success-dark.png)。设置中的 ScrollView 无法通过 ImageRenderer 捕获，生成的透明图片不作为设置界面证据；未宣称实际操作设置按钮通过。
- App 图标为已选 idle 形象的原生头像组合，旧图标在 备份目录（本地资料，不随仓库发布）；所有 10 个 PNG 尺寸按 Contents.json 核对（16～1024 px）。菜单头像模板在 bundle 的 Assets.car 内含 18 / 36 px 两项，isTemplate 和 18 pt 的原生检查通过；[浅色模板](validation/smart-reminders-2026-10-04/menu-light.png)、[深色模板](validation/smart-reminders-2026-10-04/menu-dark.png) 可读。菜单顺序、模式 / 设置 / 退出处理器与此前一致，实际点击尚待解锁。
- Release 构建与 `codesign --verify --deep --strict` 通过；bundle 内 host / client 与最终 plugin/lib 的字节一致。角色检查仍为 A 均衡 Q 版、5 状态、20 帧、208 pt、透明命中区域；CharacterView.swift、角色清单和 idle 参考字节与本轮修改前一致。图集、动作数据、同步脚本及另一会话动画页面未修改。
- 原生前台通过 `com.deepseek.dsh` 加 client 的唯一 mainView / 会话面板 / 加载与焦点判断；查看探针精确关联实例、周期、序号和捕获未读 ID，前台切换会否决旧确认。未确认回退正常提醒，5 秒后可重试且不反复隐藏已有反馈。进入 DSH 只收起旧 Pet 展示，不清其他会话的未读；已确认目标才撤回相应 Native 通知。真实插件仍是此前运行的版本，本轮未更新 / 重启 DSH，因此此链路尚未实机验收。
- 全屏开关默认关闭并保存；窗口用 fullScreenNone / fullScreenAuxiliary 与自身 isOnActiveSpace，隔离隐藏 / 恢复检查不等于系统全屏验证。没有增加屏幕录制 / 辅助功能权限，不以最大化或覆盖面积判断全屏。真实系统 / 视频全屏、最大化与多显示器保留待办；特别是同一 Space 内自行铺满屏幕的视频播放器不能仅凭本轮隔离检查保证隐藏，需按实际播放器验收。
- cua_repl 绑定独立预览时报告 Mac 锁屏且无法自动解锁；遵守提示，没有继续操作 UI 或绕过锁屏。本轮预览 PID 86827 已单独结束，无遗留预览进程；原先 App / DSH 与另一会话保留。
- 最新 App 为 `dist/DSH Always On.app`，旧 dist App 保留 previous 备份；已安装 App、旧 DMG、启用的插件、DSH 配置、凭据、系统权限 / 主题 / 登录项未替换或修改。回到解锁的 Mac 后，使用新版 App 的“更新集成”，在方便时重开 DSH，再验收当前会话静默 / 其他会话照常提醒和全屏切换。
- 最终日志：`dist/smart-reminders-xcode-test.log`、`smart-reminders-swift-test.log`、`smart-reminders-plugin-test.log`、`smart-reminders-release-build.log`、`smart-reminders-preview-check.log`。目录无 Git，初始化许可尚未回复，未提交或推送；本轮差异及修改前 / 后文件保存在 dist 的独立归档。

## Q 版气泡与五状态动画测试（2026-10-04）

- [同一清单](tasks/2026-10-03-气泡样式与动画测试.md)：两项按用户授权实现，多只 DS 娘仍暂缓。
- Swift Package / Xcode 各 34 项核心测试通过。新增四项覆盖暂停相位与继续播放、切状态重置、手动预览 / 恢复 / 新建默认关闭、两侧四角及负坐标显示器位置、狭窄空间上下避让。既有 5/10 秒边界、永久队列、关闭不清未读与旧点击不清新提醒继续通过。
- 独立 Debug 原生窗口验收：完成、失败、等待气泡的图标 / 色彩和浅深色文字可读；单一轮廓无尾巴接缝。整块 BubbleView 的打开按钮模拟成功后收起并减少对应未读，× 只收起不清未读；永久气泡超过 10 秒仍保留，5 秒 / 10 秒到期后收起。实际 DSH 跳转及后台首击为前轮实测，本轮保留原 Router、固定 sessionId、FirstClickHostingView 与面板配置，并未再次操作真实 DSH。
- 设置中的五状态逐项切换、播放 / 暂停、恢复真实状态通过；完成预览超过 10 秒仍显示，未读计数不变。使用新 Coordinator 重载偏好时测试关闭。内存等待事件进入实际 `present` 分发路径后自动关闭动画测试、显示等待气泡并恢复 waiting；它验证分发行为，不代替真实 DSH 源事件验收。
- Debug 验证使用随机偏好域及内存数据，不连接 DSH、不写真实存储 / 桌宠位置、不触发通知权限或登录项。深色预览只覆盖测试气泡外观，不改变系统主题。
- Release 构建、严格签名和 bundle 素材验证通过：A 均衡 Q 版，5 状态、20 帧、208 pt、透明命中区域。`dist/DSH Always On.app` 已更新，旧 dist App 保留 previous 备份；已安装 App 与旧 DMG 未替换。仅有既有可选 AppIntents 元数据提示，无编译错误。插件源码未改，未重跑 Node 检查。
- 测试进程已正常退出；关闭后一次 UI 状态读取自动重开了普通 Debug App，已按本轮新进程的确切 PID 结束。没有使用集成启用 / 更新、选择目录或真实会话按钮，没有停止原有 App / DSH。该短暂运行读取了已有会话缓存，不能计为新的真实连接验收。
- 边界：左右 / 上下 / 屏幕边缘由几何测试及代码核对验证；本轮未进行多显示器实机拖动、真实任务介入、Native 横幅或 DSH 角标验收。原 V0.1 未完成项与 DSH 本体角标方案保持。

## 桌宠提醒停留时间（2026-10-03）

- [本轮清单](tasks/2026-10-03-桌宠提醒停留时间.md)：完成 / 失败动作及所有桌宠气泡默认 10 秒，可选 5 秒或一直保留直到打开；偏好自动保存。工作和 waiting 仍依真实事件，Native 横幅由系统决定。
- Swift Package 30 项及 Xcode 30 项核心测试通过，新增 9 项覆盖反馈的 5/10 秒边界、永久反馈与历史基线、关闭不清未读、等待优先、偏好默认 / 序列化、队列真实展示期限、过期计时不关闭下一条、旧点击不清同会话新提醒、模式清理与改选项重计时。插件未改，未重跑 Node 检查。
- 原生 Debug 独立预览实测：默认 10 秒与选择 5 秒后，动作 / 气泡到期均收起；未读继续保留。永久模式超过 10 秒仍显示；点击同一 BubbleView 的打开按钮模拟成功后收起并已读，× 关闭后收起但未读保留；新的等待优先显示，打开后 waiting 仍保留。
- 三个选项完整显示；选项重载恢复、Native / Pet 切换后保留且不重播气泡通过。独立预览使用随机测试偏好域和内存事件，不写真实提醒、不连接 DSH、不启动模型或审批；窗口已关闭且进程正常退出。
- 代码核对：永久气泡在断线时保留，启动按保存的当前提醒 ID 恢复仍未读 / 未解除记录；关闭 ID 单独存储，事件协议及 state.json 格式保持。真实 DSH 断线 / 重启恢复仍需日常试用确认，本轮不冒充实机断线验收。
- Release 构建与严格签名校验通过，新 App 为 `dist/DSH Always On.app`，原 dist App 保留 previous 备份。`--validate-character` 输出 A 均衡 / 5 状态 / 20 帧 / 208 pt，透明交互区域通过；角色图集、动作与插件源码未修改。旧 DMG 和已安装 `/Applications/DSH Always On.app` 未替换。
- 日志：`dist/retention-xcode-test.log`、`dist/retention-release-build.log`。构建仅有既有的可选 AppIntents 元数据提示。
- 无系统权限、登录项、DSH 配置或用户任务操作；只关闭本轮启动的调试 / 独立预览。此前 DSH 本体角标与自动查看已读方案仍未实现，原主实现清单仍 3/6。

## 均衡 Q 版原生接入（2026-10-03）

- 用户已选定 A；五状态共 20 帧接入真实 App。实验室三版对比、参考、原简易素材及评审继续保留；以后从同一页面与资产目录调整。
- `production.json` 记录已选形象，`assets/motion-data.js` 共用节奏与成功小跳跃；`scripts/sync-pet-art.mjs` 复制图集并生成原生清单，`refresh-art.sh` 同步后导出五张静态回退图。默认不更换 App 图标。
- 原生渲染缓存全部 20 帧，统一脚底与缩放；窗口为 208 × 240 pt，减少动态效果时静态，Native 模式及睡眠时暂停。按实际透明轮廓的合并遮罩判断交互区域。
- Swift Package 21 项核心测试及 Xcode 21 项测试通过，覆盖原事件逻辑与新增的素材完整性、节奏边界、延迟追帧、无效清单。Release 构建与严格签名检查通过。插件源码未改，本轮未重跑 Node 测试。
- 真实 Debug App 的独立五状态窗口实测通过，播放 / 暂停和减少动态效果预览通过；没有切换系统设置。截图：原生五状态（本地资料，不随仓库发布）。独立入口不启动 Coordinator 或连接 DSH。
- Release bundle 的 `--validate-character` 通过：A、5 状态、20 帧、208 pt，缓存与透明角落检查正常。App 图集与实验室 A 原件 SHA-256 相同；原参考和 B / C 图集保持原样。
- 新 App 位于 `dist/DSH Always On.app`；“应用程序”中的旧 App 尚未替换，已询问用户是否更新，等待明确选择。旧 DMG 未更新。
- 保留生成素材本身的细节漂移；没有 Live2D 模型。此轮没有重验真实任务全事件、多显示器、拖动 / 贴边或测量能耗，系统减少动态效果与完整透明透传仍需真实桌面专项验收。
- 无 Git 仓库、分支、commit SHA 或推送；没有初始化。只停止本轮独立预览进程，未停止 DSH 或用户既有 App。

- 日志：`dist/pet-character-swift-test.log`、`dist/pet-character-xcode-test.log`、`dist/pet-character-release-build.log`。当前核心测试为 21 项，早先 17 / 40 项记录为历史验证，不冒充本轮重跑。

## 环境与证据

- 本机 DeepSeek Harness.app / CLI：`0.2.0-rc.2`，bundle ID `com.deepseek.dsh`。
- Swift 6.4，Apple Silicon，构建目标 macOS 14+；本机 macOS 26。
- 官方仓库检查版本：`da00f7f5358f2949383b35c14f548bc20187d80c`。同步核对已安装 bundle 的相关实现；没有读取 DSH 凭据。
- 资料：[DeepSeek Harness 官方仓库](https://github.com/deepseek-ai/deepseek-harness)、[Cordis 事件机制](https://deepseek-harness.github.io/deepseek-harness/develop/framework/events.html)。

| 能力 | 主源码位置 | 结论 |
| --- | --- | --- |
| 执行状态 | packages/core/agent/src/runtime-types.ts | agent/status 的 running / idle 可观察整体活动 |
| 会话审计事件 | packages/core/session/src/index.ts | session/event(session,event)；turn/end 保留终结原因；disposed 不是删除 |
| 操作批准 | packages/interaction/user-approval/src/types.ts | approval/asked / decided 的稳定 id |
| 提问与恢复 | packages/interaction/user-questions/、核心 session projection | 原 answerer 委托；active 问题可能在超时后继续存在 |
| 界面等待 | packages/client/ui-session/src/client/index.ts | pendingInteraction 的 key / kind 可恢复已存在等待 |
| 会话定位 | packages/client/ui-workspace/、ui-session 的 binding | openSession 与 retainedBy.mainView / openState 可确认具体 ID |
| URL scheme | apps/desktop/src/main.ts | dsh://open 仅唤起 App，不支持把任意 session 深链接当作已定位 |
| 加载与 patch | apps/cli/src/profile-boot.ts、app-boot 与 desktop 默认 profile | 标准 patch insert、固定 id 与 bundled client 资源可加载 |

路径均相对于上述官方仓库。实际采用的 API 与协议详见 [架构](ARCHITECTURE.md) 和 [事件](EVENTS.md)。

## 已通过

1. **真实集成加载**：从构建的 App 启用集成后，已运行的桌面 DSH 加载 host 与 client；App 收到已鉴权快照，host 与界面连接均成立。配置改动前建立备份，保留原 patch。没有发送新任务或修改 DSH 凭据。
2. **真实会话准确跳转**：先把 DSH 切到另一已有会话，再在 App 中打开目标；确认 DSH 返回指定会话。不是仅观察应用被唤起，也没有创建任务。
3. **真实完成与恢复**：用户已有任务自然完成时，观察到源序号推进、success 提醒写入 App 存储及未读计数为 1。App 重启后继续保留该提醒与未读。此项未触发付费模型调用或代用户完成任何批准。
4. **桌宠交互**：透明角色窗口可见、五张 PNG 已随 bundle 导出。拖动后保存的归一化位置发生正确变化；拖到右侧后 x=1 确认贴边，重启仍贴右侧且可见。右键菜单和 Native / Pet 切换已验证，Native 隐藏角色。原参考图未改动，角色为原创简化绘图。
5. **更新与权限反馈**：App 内“更新集成”成功，最终 host / client 文件与 bundle 的哈希一致，旧插件目录保留为备份。Native 显示系统通知已关闭，并提供设置入口；未修改系统权限。
6. **自动检查**：最新 23 项 Node + 17 项 Swift，共 40 项通过；TypeScript 检查通过，Xcode Debug / Release 构建成功。首次实现时为 38 项，本轮新增两项桥接生命周期检查。
7. **构建包**：App 内包含执行文件、host / client、五张状态图与图标，采用本地 ad-hoc 签名。DMG 校验和签名检查结果在下方交付检查中记录。

## 自动检查覆盖

- host 整体活动终结、重复终结、取消 / 未知结果不冒充成功、三类失败原因。
- 多等待项、稳定 actionId、新增与重复等待、初始化不重播、来源重启与缓冲缺口。
- mounted observer 的原始事件订阅、审批审计、计划审阅委托、超时问题 projection 恢复、client 基线与子 Agent 排除。
- App 已读 / 已处理分离、未读按会话计数、点击期间新提醒、事件及语义去重、整批顺序校验、未知协议字段、重连与 JSON 保存恢复。
- HTTP 令牌、浏览器 Origin 拒绝、命令关联、准确目标确认、加载错误与不存在目标。
- 卸载移除本桥接 endpoint 而保留其他文件；旧桥接卸载不移除已发布的新实例 endpoint，新实例仍可鉴权获取快照。这是临时目录的受控生命周期测试，不等于真实 DSH profile 更新/移除验收。
- managed patch 保留用户内容、重复启用、空数组及异常标记。

这些测试采用受控上下文与数据，不能替代全部真实模型任务或系统 UI 验收。

## 待完成的发布验收

- [ ] 真实 DSH 问题、批准、计划审阅出现及解除，尤其是插件加载前已有等待的恢复。
- [ ] 真实失败 / 阻塞 / 输出上限的最终状态及通知。
- [ ] Native 系统权限允许、横幅点击和真实 Dock 未读角标。已验证权限关闭时的提示、设置入口和会话列表。
- [ ] Pet 五类真实事件的可见气泡与点击、连续多会话场景。
- [x] 桌宠拖动、右侧边缘吸附、位置保存和重启恢复。自动操作与实际偏好保存结果相互核对；已修正使用当前指针位置导致快速拖动被误判为点击的问题。
- [ ] 多显示器拔插、Spaces、独占全屏、减少动态效果与透明区域透传。
- [ ] 集成更新与移除的完整真实生命周期、其他 DSH 版本与非默认安装位置。
- [ ] Developer ID 签名、公证、Intel 构建和正式分发流程。

不停止用户 DSH 任务来完成验收，不自动同意系统权限或用户批准请求。当前最终插件资源已通过“更新集成”部署并保留旧版本备份；运行中的 DSH 尚未被重启，最新恢复改进需要在方便时重开 DSH 后验收。

## 交付检查

- `codesign --verify --deep --strict` 通过，确认本地签名有效；这不代表 Apple 公证。
- App 版本 0.1.0、最低 macOS 14.0；执行文件、图标、两个插件脚本和五张状态图均非空，五张 PNG 均有透明通道。
- `hdiutil verify` 通过：`dist/DSH-Always-On-0.1.0-arm64-20261003-113735.dmg`。
- 构建脚本语法检查通过。

当前只承诺本机 Apple Silicon 试用；未测量完整事件到通知时延，不宣称全部低于 1 秒。


## 2026-10-03：Xcode 工程接入验证

- 创建 `macos/DSHAlwaysOn.xcodeproj`，App 与 XCTest 目标，共享方案 **DSH Always On**；本地 Swift Package 导出 CompanionCore library，关联现有源码。
- Xcode 27 成功解析工程及本地依赖；Debug 构建通过。初次发现脚本输出声明不完整，补齐每个目录和文件后通过；Xcode 脚本隔离始终开启。
- `xcodebuild test` 的 17 项 XCTest 全部通过；结果包为 `dist/XcodeTests-20261003.xcresult`。
- 在 Xcode GUI 打开项目并点击 Run，显示 Running DSH Always On；调试 App 的会话与设置窗口正常，显示真实 DSH 连接。随后用 Xcode Stop 结束本轮调试进程。
- `scripts/build-app.sh` 调用同一共享方案的 Release，构建与签名校验通过；原 dist App 保留为 previous 备份。本轮没有制作新 DMG。
- Debug / Release bundle 的五张 PNG、资产目录、插件 manifest 和两个脚本均存在；`refresh-art.sh` 真实导出成功，原参考图片保持原样。
- Xcode 构建存在可选 AppIntents 元数据未使用的提示，运行日志存在 linkd/autoShortcut 服务与 transient view geometry 诊断；调试会话持续正常，界面可见。工程迁移验证没有替代真实通知、等待事件或窗口全场景验收。
- 本轮没有修改 DSH profile、权限、登录项或 Apple 账户，没有停止用户 DSH；只结束本轮由 Run 启动的调试 App。既有试用 App 不由本轮停止。
- 操作说明：[Xcode开发.md](Xcode开发.md)。

## 2026-10-03：清单补查与气泡点击修复

- 三个主清单未勾选条目的功能均存在；未完成的是完整实机验收。重新把任务措辞明确为验收，保留原范围和待测项。
- 原气泡跳转只绑定内部文字按钮。现整块气泡绑定固定 notice 的 sessionId；× 为独立关闭按钮，不跳转、不标已读。增加后台首击支持和可接收点击的非激活面板；正常提醒出现时仍使用 orderFrontRegardless，不主动获取键盘焦点。
- 气泡高度调整为 132 点，留出三行正文空间；描边不接收点击。PetController 按 notice ID 保留当前 hosting view，轮询刷新相同提醒不再替换视图。
- Xcode Debug 增加明确标注“[预览]”的五类气泡，借用既有提醒的目标，不写入假提醒、不调用模型；预览为了定位控件临时聚焦面板，Release 不含此入口。它验证的是气泡呈现/交互，不能证明真实源事件发生与恢复。
- 实机检查：五类预览均显示；先将 DSH 切到另一已有会话，再从后台点击问题气泡，DSH 正确返回原目标；点击计划审阅预览的左下空白区域也返回目标；关闭批准预览后 DSH 仍保持在另一会话。未发送任务、回答或批准。
- 最新自动检查 40/40（23 Node + 17 XCTest）通过，TypeScript 通过。新增卸载/替换检查见上方覆盖范围。Xcode Debug test 和 Release 构建、App 严格签名校验通过；日志分别在 dist/bubble-xcode-test.log、dist/bubble-release-build.log。
- 新 Release App 已更新到 dist/DSH Always On.app，旧 App 保留 previous 备份。原 DMG 是旧版本，本轮未重新打包。已安装的 host/client 与新 bundle 哈希一致；这只是资源一致性证据，不能证明运行中的 DSH 已重新加载这些资源。
- 本轮未改变 DSH patch（其修改时间仍为 11:06）、系统通知权限、登录项或 Apple 账户。仅用 Xcode Stop 停止本轮启动的调试 App，未停止 DSH 和既有试用 App。
- 仍待：真实问题/批准/计划审阅及加载前等待恢复、失败场景、Native 权限允许和横幅点击、非零未读 Dock 角标、多会话连续真实气泡、多显示器/Spaces/全屏，以及完整真实集成更新/移除。保持主清单 3/6，本轮补查 2/2 完成。
