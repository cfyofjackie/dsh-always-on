/** Public DSH client services, expressed structurally to avoid bundling DSH code. */
export interface NavigationContext {
  sessions: { refresh(): Promise<void>; list: { getSnapshot(): { byId: Record<string, { retainedBy?: { mainView?: number } }> } }; binding(id: string): { session: { getSnapshot(): { openState?: string; removed?: boolean } } } | undefined };
  uiWorkspace: { openSession(id: string): void };
}

export async function navigate(ctx: NavigationContext, sessionId: string, signal: AbortSignal): Promise<string> {
  await ctx.sessions.refresh();
  signal.throwIfAborted();
  if (!ctx.sessions.list.getSnapshot().byId[sessionId]) return 'not_found';
  ctx.uiWorkspace.openSession(sessionId);
  const end = Date.now() + 4500;
  while (Date.now() < end) {
    signal.throwIfAborted();
    const row = ctx.sessions.list.getSnapshot().byId[sessionId];
    const snapshot = ctx.sessions.binding(sessionId)?.session.getSnapshot();
    if ((row?.retainedBy?.mainView ?? 0) > 0 && snapshot?.openState === 'open' && !snapshot.removed) return 'opened';
    if (snapshot?.openState === 'error' || snapshot?.removed) return 'failed';
    await new Promise(resolve => setTimeout(resolve, 50));
  }
  return 'unconfirmed';
}
