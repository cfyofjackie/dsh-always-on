# DSH Always On 技术架构

更新日期：2026-10-04  
状态：V0.1 本机试用实现；真实全场景和发布验收见 [VALIDATION.md](VALIDATION.md)

本文的结构与渠道表描述当前实现。2026-10-03 已确定 [通知与已读修改方案](通知与已读修改方案.md)：两种模式隐藏伴侣 Dock 图标，角标交由 DSH client 呈现在 DSH 本体，并增加实际查看反馈与权威未读计数下发。其中实际查看反馈已于本轮接入，DSH 本体角标 / 两模式隐藏伴侣 Dock 尚未接入；不把当前智能提醒工作等同于整份旧方案完成。

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
  ├─ Native：UserNotifications + 自己的 Dock 角标
  ├─ Pet：AppKit 透明窗口 + SwiftUI 图片与气泡
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

`/open` 的结果必须关联原 `requestId`，host 7 秒超时返回未确认，App 请求上限 10 秒。只有确认打开时才标记点击瞬间已有的提醒为已读；点击过程中到达的新提醒保留，失败也保留未读。系统通知、气泡、角色与会话列表共用同一 Router。

## 5. 本地存储与渠道

私有 `state.json` 原子保存会话、提醒、已读、已处理、来源周期、游标与去重记录。系统偏好保存模式、配置目录、置顶与桌宠位置。只保存标题与简短提醒，不复制完整对话或工具输出。

去重包括事件 ID、同一 run 的终结语义以及同一等待 actionId。角标按存在未读的会话计数。已读与等待解除独立：查看问题可清除未读，但 waiting 保留至 DSH 真实处理。

已处理且已读提醒保留最多 7 天 / 500 条；未读和仍待处理的等待不通过普通历史清理丢弃。去重事件 ID 保留最多 2000 条。

| 渠道 | Native | Pet |
| --- | --- | --- |
| 系统通知 | 开 | 关 |
| 本 App Dock 角标 | 开 | 关 |
| 桌宠 | 关 | 开 |
| 气泡 | 关 | 开 |

UI 只暴露两个预设，渠道在 Coordinator 内统一分发。Native 使用普通应用策略，Pet 使用菜单栏应用策略。切换清除本 App 旧系统通知与气泡队列，保留未读，不补发历史提醒。

## 6. 桌宠与原生 UI

SwiftUI 设置界面；AppKit 管理角色与气泡两个透明、无边框窗口。桌宠窗口 208 × 240 pt，角色画布 208 × 208 pt。用户选定实验室 A 均衡 Q 版，五状态共 20 帧的透明图集与动作清单通过 `scripts/refresh-art.sh` 同步；原生绘制缓存标准画布帧，保留五张静态回退 PNG。参考图与实验室三版对比保持。成功 / 失败动作和所有气泡默认 10 秒，可在设置中选择 5 秒或一直保留直到打开；工作和等待不受此时长限制。队列最多 20 项且等待优先，永久气泡可被新提醒替换，旧提醒仍在会话列表。

`ReminderRetention` 与 `PetReminderQueue` 在共享核心维护期限、替换和按提醒 ID 移除。动作期限按真实事件时间安排下一次刷新，气泡期限按展示开始计算，不因轮询刷新延长。选项、关闭动作 ID 与当前永久气泡 ID 使用 App 偏好保存；保留私有事件存储和协议兼容。永久气泡断线保留，启动可恢复；成功跳转仅移除点击边界内的气泡，新提醒不被旧请求清除。Debug 提供隔离的 `--preview-retention` 界面，不连接 DSH 或写入真实提醒。

气泡窗口为 300 × 176 pt，共用 `BubblePlacement` 在可见屏幕内选择左右或上下位置，尾巴方向 / 偏移与窗口位置同步。单一轮廓路径保证描边在尾巴接缝处连续，按钮仍绑定固定提醒的会话并支持后台首击，关闭按钮独立。按提醒 ID 缓存 hosting view 的规则保持。

设置的 `AnimationPreview` 是不持久化的展示覆盖，只控制 `displayedTaskState`，隐藏真实气泡而不修改私有存储、未读或计时。手动退出恢复最新真实状态；真实提醒进入 `present` 时结束测试，模式切换也结束。设置小预览与桌宠共用 `CharacterView`；`CharacterPlaybackClock` 保存动作相位并排除暂停时间，状态变化从首帧开始。Debug 独立预览还隔离位置偏好，不写用户真实桌宠位置。

角色优先级：waiting > 近期 error > 近期 success > working > idle。离线显示 idle 和独立“未连接”文字。按实验室动作节奏逐帧播放，以单调时间定位帧，延迟时跳过已过期帧；系统减少动态效果使用静态帧，Native 隐藏与系统睡眠停止动画。右键菜单可查看会话、切换模式与退出。

拖动采用 AppKit 事件跟踪；16 pt 边缘吸附。保存显示器标识与归一化位置；屏幕变化时回退至可见屏幕并夹取位置。点击区域使用同一标准画布全部姿态的 alpha 轮廓并集与状态文字区域，减少手 / 发梢运动造成的点击抖动，透明角落透传。不同 Spaces、独占全屏和多显示器仍需实机验证。

开机启动通过 `SMAppService`，默认关闭，由用户自行启用。Native 通知权限在选择该模式后向系统申请，App 显示权限状态与系统设置入口。

## 7. 构建与交付

`macos/DSHAlwaysOn.xcodeproj` 为标准 macOS App 工程，关联现有界面源码、角色资源和测试；CompanionCore 作为本地 Swift Package library 接入。`plugin/` 使用 esbuild 与 TypeScript，Xcode 构建阶段编译并嵌入 host / client。构建脚本现在调用同一共享“DSH Always On”方案的 Release 构建；DMG 带 Applications 快捷方式和中文说明。Xcode 开发步骤见 [Xcode开发.md](Xcode开发.md)。

当前包为本机 Apple Silicon / macOS 14+ 试用版，采用 ad-hoc 签名。没有 Developer ID、Apple 公证、Intel 构建或自动更新，不能宣称已完成公开发布。构建及测试入口见根目录 [README.md](../README.md)。

## 本轮智能提醒与外观扩展（2026-10-04）

client 每 600 ms 及 focus / blur / visibilitychange 上报当前会话、会话面板是否可见、窗口焦点与加载状态。host 使用自己的时间戳，仅语义变化唤醒事件长轮询。原生端同时验证前台应用 bundle ID；前台时每约 900 ms 读取 `/view-state`，反馈超过 2500 ms 不采用。

每次查看探针捕获 App 当前未读 ID 集合、实例、周期与 throughSequence；client 只对唯一 mainView、会话面板、已加载且有焦点的内容确认，连续两次动画帧后重新核对。终结反馈要求展示投影已停止执行且无等待，waiting 要匹配具体交互类型。host 2400 ms 超时，原生请求 4 秒上限。查看结果需精确匹配捕获边界，并且原生前台切换代数、来源周期保持；只标记捕获 ID，新提醒继续走独立确认。查看接口与旧 `/open` 命令队列分离，不导航、不回答 / 批准。未确认时保留正常提醒并退避 5 秒后再试，重试不反复隐藏已呈现反馈；切换前台或目标会话时取消退避。

进入 DSH 只收起 Pet 展示，未读不变；已确认显示才撤回相应 Native 通知并更新同一 SessionStore。全屏选项通过 `.fullScreenAuxiliary` 的启用 / 移除、`.fullScreenNone` 和桌宠窗口自身 `isOnActiveSpace` 管理，400 ms 检查窗口 Space；不依靠覆盖程度、屏幕尺寸或全局最大化猜测，不要求屏幕录制 / 辅助功能权限。隐藏会清掉当前气泡队列和结果展示，保留未读；真实系统 / 视频全屏和多显示器仍待实测。实现参考 [Apple fullScreenAuxiliary](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/fullscreenauxiliary)、[isOnActiveSpace](https://developer.apple.com/documentation/appkit/nswindow/isonactivespace)。

`BubbleStyle` 为独立持久化外观，`BubblePreviewKind` 提供五类固定、已读的测试样例。桌面气泡测试只覆盖展示，不写事件历史，不跑真实期限；与动作测试互斥，真实提醒到来、模式切换或进入 DSH 时退出。两款外观复用同一轮廓、命中与固定 session 跳转。

App 图标由现有 idle 形象与原生蓝白背景组合，`--export-brand` 导出完整 AppIcon / DSMenuIcon asset；`--export-art` 的图标导出也使用同一组合，同步脚本未改。菜单栏使用 18 pt 模板头像，保留原菜单处理器。旧图标在 `docs/icon-preview/legacy-2026-10-04/`。角色播放器、生产帧与另一会话动画页面没有改动。
