# DSH Always On 统一事件与状态

更新日期：2026-10-04  
状态：协议 1.0 已实现；兼容 DSH 0.2.0-rc.2，验证边界见 [VALIDATION.md](VALIDATION.md)

本文记录当前协议。2026-10-03 已确定的 [通知与已读修改方案](通知与已读修改方案.md) 将增加 DSH 前台会话查看反馈、伴侣可见摘要的已读确认及 DSH 角标计数同步；其中 DSH 前台查看反馈已作为协议 1.0 的可选兼容扩展接入；伴侣摘要确认和 DSH 角标计数下发仍未实现。

## 1. 状态、提醒与已读

状态为 `idle / working / waiting / success / error`。连接、会话状态、提醒、已读及角色选择独立维护；断开不代表失败，查看不代表处理，气泡收起不清除未读。

来源固定 `deepseek-harness`。当前只连接一个受管理实例；会话按稳定 `sessionId` 定位，`instanceId` 隔离安装，`sourceEpoch` 隔离来源进程，`runId` 代表 Adapter 观察到的一次整体执行活动。

## 2. 实际 DSH 映射

| 统一语义 | 原始来源 | 处理规则 |
| --- | --- | --- |
| 工作开始 | `agent/status` 的 running | 新活动生成 runId；同轮状态更新不反复通知 |
| 整体完成 | `turn/end` reason.kind = completed，随后 `agent/status` idle | 只在整体 idle 时通知，不能用单次工具结束判断 |
| 整体失败 | idle 与 error / blocked / max-tokens 终结原因 | 不同简短文案，不复制原始错误内容 |
| 中止或未知结束 | idle，且原因不在上述终结集合 | 停止、回 idle，不伪造成功或审批 |
| 操作批准 | `approval/asked` / `approval/decided` 会话审计事件 | ID 为 approval:id；监听不批准 |
| 提问 | `user-questions/request` 中间件及 userQuestions projection | 使用 callId；委托 next，不截获答案；超时但 projection 仍 active 时继续 waiting |
| 计划审阅 | 问题 intent.kind = plan-review | 同一 waiting 状态，reason = plan_review |
| 加载前等待恢复 | `uiSession.sessionStatus.pendingInteraction` | client 上报 key、kind，作为基线，不主动重播 |
| 标题 | title projection / `session/title` | 更新快照标题，不创建提醒 |
| 精确跳转 | `uiWorkspace.openSession` + retainedBy.mainView + binding.openState | 三者确认目标身份与加载，不能只唤起窗口 |

`session/disposed` 表示当前加载对象释放，不等于用户删除会话，故不映射成 session.closed。子 Agent 不单独产生重复父会话提醒。DSH turn 与一次整体工作活动不是同一概念。

## 3. 事件类型

| type | state | 主动提醒 |
| --- | --- | --- |
| session.started | working | 否 |
| session.waiting | waiting | 仅新增等待 actionId |
| session.resumed | working | 否 |
| session.stopped | idle | 否 |
| task.succeeded | success | 是 |
| task.failed | error | 是 |

等待 reason 为 `question / approval / plan_review`。`activeWaits` 是完整集合，必须非空且 ID 唯一；非等待状态为空。多个等待项须全部消失后才能离开 waiting。同一等待项更新不新增提醒。

## 4. 传输包

App `GET /poll?after=<sequence>&epoch=<sourceEpoch>`，通过 Bearer 令牌鉴权。返回：

```json
{
  "protocolVersion": "1.0",
  "instanceId": "example-installation",
  "sourceEpoch": "example-epoch",
  "throughSequence": 42,
  "reset": false,
  "clientConnected": true,
  "sessions": [],
  "events": []
}
```

`sessions` 是插件已观察到的根会话快照，不表示完整历史数据库。记录字段：`sessionId / title / runId / state / activeWaits / updatedAt / lastOutcome?`，其中 updatedAt 为 Unix 毫秒。

`events` 的每项包含记录字段及下列字段：

| 字段 | 说明 |
| --- | --- |
| protocolVersion | 1.0；校验主版本 |
| eventId | 随机稳定 ID，同一缓冲事件重发不变 |
| source / instanceId / sourceEpoch | 来源身份与周期 |
| sequence | 同周期单调递增，从 1 开始 |
| type / state | 必须符合上表 |
| occurredAt | UTC ISO 8601，辅助展示，不排序 |
| summary | 简短中文提醒，不包含完整工具参数 |
| notify | 是否为主动提醒；仅 waiting / success / error 可为 true |

所有样例 ID 为虚构值，真实令牌不属于业务 payload。

## 5. 顺序、去重与恢复

首次请求、周期变化、无效游标或缓冲溢出时 `reset=true`，返回快照且不返回历史事件。正常请求返回游标之后的增量和同一序号边界的当前快照，App 最终以快照作为当前状态，不由旧终结事件覆盖新轮次。

App 校验整批再修改：来源一致、完整序号、已知事件及状态、已知等待 reason、非空身份。非法数据或序号缺口不能部分更新存储。保存成功后才推进游标，失败可重试。没有独立 ack 消息，下一次请求携带的游标承担确认作用。

提醒按 eventId 去重；终结按 instanceId + sessionId + runId + state 幂等；等待按 actionId 幂等。新周期重建基线不误判序号回退，原实例未读继续保存。实例切换不混用提醒。

host 缓冲仅存在于进程内，最多 500 条 / 10 分钟。App 重启从保存游标请求可用增量；host 重启或历史缺口只能恢复当前状态，无法保证补齐离线期间全部任务结果。初始化的现有等待进入待处理列表，基线不新增未读或弹气泡。

## 6. 提醒与角色

角标为至少有一条未读提醒的会话数；同一会话多条提醒计为 1。等待解除后旧提醒标已处理，已读独立保存，并移除过期气泡及系统通知。

角色：waiting > 有效 error 反馈 > 有效 success 反馈 > working > idle。完成 / 失败反馈和所有气泡共用 `ReminderRetention`，默认 10 秒，可选 5 秒或直到打开。动作按 session.updatedAt 计算期限；气泡从实际展示开始计时，后台轮询不重置期限。没有未读提醒的历史完成基线不进入永久反馈。

气泡固定绑定创建时会话；等待优先、每个会话最多一个排队摘要，队列最多 20 项。永久模式的新提醒可以替换当前气泡，当前等待优先于其他会话的完成提醒；被替换提醒仍在底层列表。成功打开按点击时捕获的提醒 ID 收起，不能关闭点击期间出现的新气泡。关闭按钮只收起特定提醒的气泡 / 终结动作，保留未读和 waiting。

停留选项与关闭动作 ID 使用 App 偏好保存，不改变事件协议或 state.json 格式。永久气泡的当前 ID 单独保存，启动时只恢复仍未读且未解除的记录；断线保留该气泡，模式切换收起，恢复连接后继续核对真实状态。固定时长和队列超限均不丢失底层未读。Native 系统横幅不受此选项控制。

模式切换清除渠道展示与排队提醒，保留存储，不重播历史。离线不把缓存 working 当作实时状态。

## 7. 跳转

App `POST /open`：

```json
{"requestId":"example-click","sessionId":"example-session"}
```

host 向 DSH client 提供命令 `{requestId, sessionId, expiresAt}`；client 检查目标存在、调用 openSession 并核对真实加载/选中，再提交结果。App 只接受匹配 requestId 的结果。

| status | 含义 |
| --- | --- |
| opened | 目标确已打开且加载成功 |
| unconfirmed | 7 秒超时或无法确认 |
| not_found | 目标删除、缺失或不存在 |
| disconnected | client 未连接 |
| unsupported | 能力不支持，保留为兼容结果 |
| failed | 操作失败 |

仅 opened 标记点击前捕获的提醒 ID 为已读。跳转期间到达的新提醒、失败结果、仅打开 DSH 窗口都不能自动清除未读。

上述为当前跳转协议行为。新方案另增加“前台可见且目标会话已加载”与“前台列表摘要实际可见”的查看确认；按查看时捕获的提醒边界清除，不能因后台选中或一次旧确认而清除后来到达的新提醒。已读与等待解除继续分离。

## 8. 自动检查范围

已覆盖：整体完成边界、三类等待映射、超时问题保留、加载前等待基线、子 Agent 排除、重发与语义去重、顺序缺口、旧包拒绝、多会话角标、已读与等待分离、点击边界、实例周期恢复、HTTP 鉴权与 Origin 拒绝、跳转关联与目标加载检查。

自动检查使用受控数据，不宣称已经运行完整真实模型任务。真实验收与代码证据记录见 [VALIDATION.md](VALIDATION.md)。

## 8. 可选查看反馈（2026-10-04）

`/poll` 可含 `viewStatus`：`sessionId? / visible / focused / loaded / reportedAt`，reportedAt 由 host 生成。旧插件不提供该字段时，App 继续正常提醒，不把仅仅激活 DSH 判定为已读。`GET /view-state` 使用同一 loopback 鉴权，只返回最新展示事实。

App `POST /view` 携带 `requestId / sessionId / instanceId / sourceEpoch / throughSequence`。host 验证实例与周期、有效序号和请求上限，生成 2400 ms 有效的探针；探针还携带 state 与 activeWaits 的 reason 供 client 核对。DSH client 经 `POST /api/always-on/view` 上报 view，取得独立探针数组，返回 `receipt`，字段包括原身份 / 序号及 `status=viewed`。只有确实显示的目标、加载 / 焦点成立且渲染后仍满足条件时确认。接口不进入 navigation poll 队列，旧 client 绝不会把它当成打开会话命令。

原生端自行保存捕获的未读 ID，探针不扩大其范围。host 返回同一身份 / 序号和 `status=viewed / unconfirmed / disconnected`；原生还核对前台代数与来源周期，匹配后只标记捕获 ID，后来的提醒保留。查看 waiting 只影响已读，不决定请求已处理。反馈缺失、错误、过期或加载未完成时保留未读；真实全链路验收尚待新插件加载和解锁的 Mac。
