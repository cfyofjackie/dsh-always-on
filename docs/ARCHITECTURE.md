# DSH Always On 技术架构

更新日期：2026-10-08
状态：V0.1 本机试用实现；真实全场景和发布验收见 [VALIDATION.md](VALIDATION.md)

当前为任务通知伙伴 / 纯桌宠陪伴；2026-10-08 用户确认移除系统任务通知与 DSH 本体角标目标。旧方案留存历史，不作为当前范围。源码 / 隔离检查与实机验收边界见 [本轮清单](tasks/2026-10-08-桌宠双用途与提醒可靠性.md)。

## 1. 实际结构

```text
DeepSeek Harness 0.2.0-rc.2
  ├─ TypeScript / Cordis host 插件
  │    ├─ 订阅会话事件、执行状态与用户提问
  │    ├─ 当前状态快照 + 有界事件缓冲
  │    └─ 127.0.0.1 随机端口 HTTP 服务
  └─ bundled client 插件
       ├─ 上报界面已有的等待项
       └─ 打开指定 session，并确认实际选择与加载结果
                    ⇅
Swift macOS App
  ├─ Integration Manager：启用、更新、移除受管理集成
  ├─ Coordinator：鉴权长轮询、持久化、通知分发与跳转
  ├─ CompanionCore：顺序校验、去重、未读与角色优先级
  ├─ 任务伙伴：AppKit 透明窗口 + SwiftUI 动作 / 气泡
  ├─ 纯桌宠：独立 CompanionPlayback 随机 / 固定动作，无任务路由
  └─ 会话列表、菜单栏与设置
```

用户只下载一个 App / DMG。插件及浏览器端脚本在 App bundle 内，不要求用户运行 Node 或另行下载插件。原候选 WebSocket、SQLite 方案已被当前 HTTP 长轮询、原子 JSON 存储替代。

## 2. DSH 接入

已核验的桌面配置目录为 `~/.dsh/profiles/desktop/`，支持在 App 中选择其他 DSH 配置根目录。启用前验证桌面 profile 与已安装 DSH 版本；当前兼容检查限定本机已验证的 `0.2.0-rc.2`。

安装器把内置资源复制到 `~/Library/Application Support/DSH Always On/plugin-v0.1.0/`，在 `cordis.patch.yml` 追加带 BEGIN / END 标记的插入块。重复启用复用固定插件 ID。遇到不支持的 YAML 形式、异常标记、同名非本 App 内容或符号链接时保留原内容并报错。

配置写入前保留备份；更新已管理插件保留旧目录。移除只移除管理块，并保留配置备份和插件目录。当前支持空数组或标准块列表 patch，其他合法 YAML 写法暂不自动转换。已有文件读取失败不作为空配置处理。

本机首次启用已观察到 DSH 热加载。更新插件资源后仍提示用户在方便时重开 DSH；App 不主动结束 DSH 或其任务。安装注册成功与实际连接成功分别呈现。

host 依赖 `sessions`、`agents`、`sessionProjections`、`connection`；client 依赖 `sessions`、`uiWorkspace`、`uiSession`、`layout`、`connection`。前端资源使用 DSH 的模块加载器格式，RPC 通过原有 connection carrier 的 Fetch 路由传输，不引入独立远程服务。

## 3. 事件与恢复

原始事件映射见 [EVENTS.md](EVENTS.md)。只观察根会话，避免子 Agent 重复提醒。问答中间件始终调用 DSH 原有的 `next()`，不回答、不批准操作、不抢占处理器。

host 保存当前进程的状态和最多 500 条 / 10 分钟事件。每次 mount 产生新的来源周期 `sourceEpoch`；受管理安装的 `instanceId` 保存在私有文件。`runId` 由 Adapter 在开始执行时生成，代表一次整体活动，不直接冒充 DSH turn ID。

每次 `/poll` 一起返回当前会话快照、增量事件与序号边界。App 先验证整批数据、更新候选存储并原子保存，再推进游标、呈现提醒。存储失败不能确认该批事件。App 重启使用已保存游标请求增量；来源周期变化或缓冲缺口时建立新快照，不重播历史完成提醒。

快照范围是插件已观察到的根会话，并非所有持久化历史。重连恢复仍等待用户的会话；初始化基线本身不创建主动提醒。界面上报可恢复插件加载前已有的批准、提问或计划审阅等待。该上报不是审批或回答行为。

插件进程重启后无法补发此前丢失的历史终结事件；不承诺两端均离线期间的完整记录。DSH 重启后要等待其会话重新加载与界面连接。

## 4. 通信与会话定位

host 监听 `127.0.0.1` 随机端口；端点文件权限为 0600，目录为 0700。所有 App 请求使用随机令牌鉴权，拒绝携带浏览器 Origin 的直连请求。App 使用无代理的临时网络会话，避免本地令牌通过系统代理发送。令牌不写日志或文档。

App→host：`GET /poll`、`POST /open`、`GET /view-state`、`POST /view`。DSH client→host：`POST /api/always-on/poll`、`complete`、`status`、`view`；经 DSH 自身的 connection carrier 传递。仅提供专用状态和跳转接口，无通用执行接口。

长轮询最多 20 秒，没有变化时不持续高频刷新。App 故障后每 2 秒重新读取端点并尝试连接；client 故障后 3 秒重试。45 秒内没有 client 心跳视为界面未连接。任务连接与界面连接分别显示。

`dsh://open` 只负责唤起 DSH。精确跳转通过 client 的 `uiWorkspace.openSession(sessionId)`，再检查该 ID 确实由 mainView 保留、历史加载 `openState === open` 且未删除。仅唤起窗口或发送请求不算成功。

`/open` 的结果必须关联原 `requestId`，host 7 秒超时返回未确认，App 请求上限 10 秒。只有确认打开时才标记点击瞬间已有的提醒为已读；点击过程中到达的新提醒保留，失败也保留未读。气泡、角色与会话列表共用同一 Router；纯桌宠点击只打开设置。

## 5. 本地存储与渠道

私有 `state.json` 原子保存会话、提醒、已读、已处理、来源周期、游标与去重记录。系统偏好保存模式、配置目录、置顶与桌宠位置。只保存标题与简短提醒，不复制完整对话或工具输出。

去重包括事件 ID、同一 run 的终结语义以及同一等待 actionId。列表按存在未读的会话计数，不向任一 Dock 写角标。已读与等待解除独立：查看问题可清除未读，但 waiting 保留至 DSH 真实处理。

已处理且已读提醒保留最多 7 天 / 500 条；未读和仍待处理的等待不通过普通历史清理丢弃。去重事件 ID 保留最多 2000 条。

| 渠道 | 任务伙伴 | 纯桌宠 |
| --- | --- | --- |
| 系统任务通知 / Dock | 关闭 | 关闭 |
| 任务轮询 / 未读列表 | 开启 | 暂停轮询，隐藏列表，历史保留 |
| 桌宠 | 真实状态与待机生活 | 九动作随机 / 固定表演 |
| 气泡 | 真实提醒；支持测试 | 仅手动测试样例 |

两用途都使用 `.accessory` 和 `LSUIElement`，保留菜单栏。旧 `native` / `pet` 偏好迁移到 `pet`，新陪伴值为 `companion`。首次新版本启动只清理本 App 旧 UserNotifications，不申请权限；模块仅保留旧通知清理调用。

切换时失效模式 / 前台代数、停止旧轮询、清除展示而保留 SessionStore 与集成配置。返回任务伙伴重新请求基线，不补弹纯桌宠期间事件；初次启动和睡眠恢复使用保存游标，来源周期改变时重新同步。异步轮询 / 查看 / 打开结果均校验代数与来源周期，打开会话只清捕获的提醒 ID。

## 6. 桌宠与原生 UI

SwiftUI 设置界面；AppKit 管理角色与气泡两个透明、无边框窗口。桌宠窗口 208 × 240 pt，角色画布 208 × 208 pt。用户选定实验室 A 均衡 Q 版，五状态共 20 帧的透明图集与动作清单通过 `scripts/refresh-art.sh` 同步；原生绘制缓存标准画布帧，保留五张静态回退 PNG。参考图与实验室三版对比保持。成功 / 失败动作和所有气泡默认 10 秒，可在设置中选择 5 秒或一直保留直到打开；工作和等待不受此时长限制。队列最多 20 项且等待优先，永久气泡可被新提醒替换，旧提醒仍在会话列表。

`ReminderRetention` 与 `PetReminderQueue` 在共享核心维护期限、替换和按提醒 ID 移除。动作期限按真实事件时间安排下一次刷新，气泡期限按展示开始计算，不因轮询刷新延长。选项、关闭动作 ID 与当前永久气泡 ID 使用 App 偏好保存；保留私有事件存储和协议兼容。永久气泡断线保留，启动可恢复；成功跳转仅移除点击边界内的气泡，新提醒不被旧请求清除。Debug 提供隔离的 `--preview-retention` 界面，不连接 DSH 或写入真实提醒。

气泡窗口为 300 × 176 pt，共用 `BubblePlacement` 在可见屏幕内选择左右或上下位置，尾巴方向 / 偏移与窗口位置同步。单一轮廓路径保证描边在尾巴接缝处连续，按钮仍绑定固定提醒的会话并支持后台首击，关闭按钮独立。按提醒 ID 缓存 hosting view 的规则保持。

设置的 `AnimationPreview` 是不持久化的展示覆盖，只控制 `displayedTaskState`，隐藏真实气泡而不修改私有存储、未读或计时。手动退出恢复最新真实状态；真实提醒进入 `present` 时结束测试，模式切换也结束。设置小预览与桌宠共用 `CharacterView`；`CharacterPlaybackClock` 保存动作相位并排除暂停时间，状态变化从首帧开始。Debug 独立预览还隔离位置偏好，不写用户真实桌宠位置。

角色优先级：waiting > 近期 error > 近期 success > working > idle。离线显示 idle 和独立“未连接”文字。按实验室动作节奏逐帧播放，以单调时间定位帧，延迟时跳过已过期帧；系统减少动态效果使用静态帧，窗口隐藏与系统睡眠停止动画。右键菜单可查看会话、切换模式与退出。

拖动采用 AppKit 事件跟踪；16 pt 边缘吸附。保存显示器标识与归一化位置；屏幕变化时回退至可见屏幕并夹取位置。点击区域使用同一标准画布全部姿态的 alpha 轮廓并集与状态文字区域，减少手 / 发梢运动造成的点击抖动，透明角落透传。不同 Spaces、独占全屏和多显示器仍需实机验证。

开机启动通过 `SMAppService`，默认关闭，由用户自行启用；不申请系统通知权限。监听 NSWorkspace 睡眠 / 屏幕休眠 / 会话切换与对应恢复，用原因集合避免部分唤醒提前恢复。暂停时取消旧连接；恢复时创建新 URLSession 并重读端点，保留游标与未读，连续三次连接失败才显示离线。client 的 focus / pageshow / online / visibilitychange 重新发送等待基线和查看反馈；无需等待命令长轮询返回。

## 7. 构建与交付

`macos/DSHAlwaysOn.xcodeproj` 为标准 macOS App 工程，关联现有界面源码、角色资源和测试；CompanionCore 作为本地 Swift Package library 接入。`plugin/` 使用 esbuild 与 TypeScript，Xcode 构建阶段编译并嵌入 host / client。构建脚本现在调用同一共享“DSH Always On”方案的 Release 构建；DMG 带 Applications 快捷方式和中文说明。Xcode 开发步骤见 [Xcode开发.md](Xcode开发.md)。

当前包为本机 Apple Silicon / macOS 14+ 试用版，采用 ad-hoc 签名。没有 Developer ID、Apple 公证、Intel 构建或自动更新，不能宣称已完成公开发布。构建及测试入口见根目录 [README.md](../README.md)。

## 本轮智能提醒与外观扩展（2026-10-04）

client 每 600 ms 及 focus / blur / pageshow / online / visibilitychange 上报当前会话、会话面板是否可见、窗口焦点与加载状态。host 使用自己的时间戳，仅语义变化唤醒事件长轮询。原生端同时验证前台应用 bundle ID；前台时每约 900 ms 读取 `/view-state`，反馈超过 2500 ms 不采用。

每次查看探针捕获 App 当前未读 ID 集合、实例、周期与 throughSequence；client 只对唯一 mainView、会话面板、已加载且有焦点的内容确认，连续两次动画帧后重新核对。终结反馈要求展示投影已停止执行且无等待，waiting 要匹配具体交互类型。host 2400 ms 超时，原生请求 4 秒上限。查看结果需精确匹配捕获边界，并且原生前台切换代数、来源周期保持；只标记捕获 ID，新提醒继续走独立确认。查看接口与旧 `/open` 命令队列分离，不导航、不回答 / 批准。未确认时保留正常提醒并退避 5 秒后再试，重试不反复隐藏已呈现反馈；切换前台或目标会话时取消退避。

进入 DSH 收起已有展示，未读不变；已确认显示才标记固定边界已读。新事件优先使用新鲜 `/view-state`，避免长轮询返回旧界面状态时误弹。foregroundFeedback 独立于已读存储：默认完成仅动作，失败 / 等待仍气泡，可选择动作和气泡 / 静默；呈现偏好不代表确认已读。未获得精确确认时保留未读。

全屏策略由 FullScreenPolicy 管理。角色 / 气泡均具有 `.fullScreenAuxiliary`；独立、透明、忽略鼠标的普通 Space 探针带 `.canJoinAllSpaces` / `.fullScreenNone`，400 ms 查看其 `isOnActiveSpace`。探针不随着提醒 orderFront，避免使用已进入全屏的角色窗口本身造成“返回视频仍常驻”。完全隐藏时两窗口 orderOut，清展示而不清未读；仅提醒出现时由气泡 / 前台反馈 / 手动预览决定可见。无辅助功能 / 屏幕录制权限，无视频应用猜测；同 Space 视频不能自动分类，真实 Space / 多屏仍待验收。参考 [Apple fullScreenAuxiliary](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/fullscreenauxiliary)、[isOnActiveSpace](https://developer.apple.com/documentation/appkit/nswindow/isonactivespace)。

CompanionPlayback 不读取 SessionStore，随机候选排除上一次，生活动作按原完整周期播放，持续任务动作至少停留8秒；支持固定动作。隐藏 / 睡眠时停止并重置，减少动态效果使用固定动作或 idle 静态图，不补播。pure UI 文案明确“陪伴”，工作 / 失败只作表演。

`BubbleStyle` 为独立持久化外观，`BubblePreviewKind` 提供五类固定、已读的测试样例。桌面气泡测试只覆盖展示，不写事件历史，不跑真实期限；独立气泡测试与动作测试互斥；动作联合预览按 PreviewBubble 匹配 success / error / waiting，其他动作无气泡。真实提醒到来、模式切换、睡眠或进入 DSH 时退出。两款外观复用同一轮廓、命中与固定 session 跳转。

App 图标由现有 idle 形象与原生蓝白背景组合，`--export-brand` 导出完整 AppIcon / DSMenuIcon asset；`--export-art` 的图标导出也使用同一组合，同步脚本未改。菜单栏使用 18 pt 模板头像，保留原菜单处理器。旧图标在 `docs/icon-preview/legacy-2026-10-04/`。角色播放器、生产帧与另一会话动画页面没有改动。

本地 App 版本 0.2.0 / build 20261008.1；DMG 文件名从实际 bundle 读取版本，构建保留旧 dist App。已安装旧版图标不靠清系统缓存替换；用户安装新 App 后使用菜单栏入口，设置底部核对版本。
