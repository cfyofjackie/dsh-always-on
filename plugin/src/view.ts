/** Viewing never navigates, answers an interaction, or changes DSH's own unread state. */
export interface ViewStatus { sessionId?: string; visible: boolean; focused: boolean; loaded: boolean; reportedAt: number }
export interface ViewCommand {
  requestId: string; sessionId: string; instanceId: string; sourceEpoch: string; throughSequence: number;
  expiresAt: number; state: string; reasons: string[];
}
export interface ViewingContext {
  sessions: {
    list: { getSnapshot(): { byId: Record<string, { retainedBy?: { mainView?: number } }> } };
    binding(id: string): { session: { getSnapshot(): { openState?: string; removed?: boolean; running?: boolean } } } | undefined;
  };
  layout: { panelInfo: { getSnapshot(): { activePanelId: string | null } } };
  uiSession: { sessionStatus: { getSnapshot(): Map<string, { running?: boolean; pendingInteraction?: { kind: string } }> } };
}
export function viewSnapshot(ctx: ViewingContext, document: Pick<Document, 'visibilityState' | 'hasFocus'>): ViewStatus {
  const selected = Object.entries(ctx.sessions.list.getSnapshot().byId).filter(([, row]) => (row.retainedBy?.mainView ?? 0) > 0);
  const sessionId = selected.length === 1 ? selected[0]![0] : undefined;
  const session = sessionId ? ctx.sessions.binding(sessionId)?.session.getSnapshot() : undefined;
  return { sessionId, visible: document.visibilityState === 'visible' && ctx.layout.panelInfo.getSnapshot().activePanelId === null,
    focused: document.hasFocus(), loaded: session?.openState === 'open' && !session.removed, reportedAt: 0 };
}
export function canConfirm(ctx: ViewingContext, doc: Pick<Document, 'visibilityState' | 'hasFocus'>, command: ViewCommand, now = Date.now()): boolean {
  const view = viewSnapshot(ctx, doc);
  if (command.expiresAt <= now || view.sessionId !== command.sessionId || !view.visible || !view.focused || !view.loaded) return false;
  const session = ctx.sessions.binding(command.sessionId)?.session.getSnapshot();
  const status = ctx.uiSession.sessionStatus.getSnapshot().get(command.sessionId);
  if (command.state === 'waiting') {
    const reason = status?.pendingInteraction?.kind.replace('plan-review', 'plan_review');
    return !!reason && command.reasons.includes(reason);
  }
  // The selected session can be retained while its displayed projection is still running.
  return session?.running === false && status?.running !== true && !status?.pendingInteraction;
}
export function normalizeView(raw: unknown, now = Date.now()): ViewStatus | undefined {
  if (!raw || typeof raw !== 'object') return;
  const v = raw as Partial<ViewStatus>;
  if (typeof v.visible !== 'boolean' || typeof v.focused !== 'boolean' || typeof v.loaded !== 'boolean' ||
      (v.sessionId !== undefined && (typeof v.sessionId !== 'string' || v.sessionId.length > 200))) return;
  return { sessionId: v.sessionId, visible: v.visible, focused: v.focused, loaded: v.loaded, reportedAt: now };
}
