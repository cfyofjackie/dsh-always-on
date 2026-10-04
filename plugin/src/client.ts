import { viewSnapshot, canConfirm, type ViewingContext, type ViewCommand } from './view.js';
import { navigate, type NavigationContext } from './navigation.js';

interface ClientContext extends ViewingContext {
  sessions: ViewingContext["sessions"] & NavigationContext["sessions"];
  uiWorkspace: NavigationContext["uiWorkspace"];
  uiSession: { sessionStatus: { getSnapshot(): Map<string, { running?: boolean; pendingInteraction?: { key: string; kind: string } }>; subscribe(callback: () => void): () => void } };
  connection: { rpc: { call(channel: string, endpoint: string, payload: unknown, signal?: AbortSignal): Promise<{ ok: boolean; value?: unknown }> } };
  effect(callback: () => (() => void), label?: string): unknown;
}
export const inject = ['connection', 'sessions', 'uiWorkspace', 'uiSession', 'layout'];
export function apply(ctx: ClientContext): void {
  ctx.effect(() => {
    const lifetime = new AbortController();
    const handled = new Set<string>();
    const rpc = (endpoint: string, payload: unknown) => ctx.connection.rpc.call('/api', `always-on/${endpoint}`, payload, lifetime.signal);
    let reporting = false;
    let dirty = true;
    const report = async () => {
      dirty = true;
      if (reporting) return;
      reporting = true;
      try {
        while (dirty && !lifetime.signal.aborted) {
          dirty = false;
          const statuses = ctx.uiSession.sessionStatus.getSnapshot();
          const pending = [...statuses].filter(([, value]) => value.pendingInteraction).map(([sessionId, value]) => ({ sessionId, key: value.pendingInteraction!.key, kind: value.pendingInteraction!.kind }));
          await rpc('status', { pending });
        }
      } catch { /* Re-send the baseline when the next command poll succeeds. */ }
      finally { reporting = false; }
    };
    const unsubscribe = ctx.uiSession.sessionStatus.subscribe(() => { void report(); });
    const loop = async () => {
      while (!lifetime.signal.aborted) {
        try {
          const result = await rpc('poll', {});
          if (!result.ok || !Array.isArray(result.value)) throw new Error('Bridge unavailable');
          await report();
          for (const command of result.value as { requestId: string; sessionId: string; expiresAt: number }[]) {
            if (handled.has(command.requestId) || command.expiresAt <= Date.now()) continue;
            handled.add(command.requestId);
            let status: string;
            try { status = await navigate(ctx, command.sessionId, lifetime.signal); } catch { status = 'failed'; }
            await rpc('complete', { requestId: command.requestId, status });
          }
          if (handled.size > 500) handled.clear();
        } catch {
          if (!lifetime.signal.aborted) await new Promise(resolve => setTimeout(resolve, 3000));
        }
      }
    };
    let viewing = false;
    // A separate endpoint preserves compatibility with older navigation-only clients.
    const frame = () => new Promise<void>(resolve => {
      let done = false;
      const finish = () => { if (done) return; done = true; clearTimeout(timer); cancelAnimationFrame(id); resolve(); };
      const id = requestAnimationFrame(finish), timer = setTimeout(finish, 120);
    });
    const reportViewing = async () => {
      if (viewing || lifetime.signal.aborted) return;
      viewing = true;
      try {
        const result = await rpc('view', { view: viewSnapshot(ctx, document) });
        if (result.ok && Array.isArray(result.value)) for (const command of result.value as ViewCommand[]) {
          if (!canConfirm(ctx, document, command)) continue;
          await frame(); await frame();
          if (lifetime.signal.aborted || !canConfirm(ctx, document, command)) continue;
          await rpc('view', { view: viewSnapshot(ctx, document), receipt: { ...command, status: 'viewed' } });
        }
      } catch { /* Old plugin or a reconnect: keep unread and fall back to notifications. */ }
      finally { viewing = false; }
    };
    const viewTimer = setInterval(() => { void reportViewing(); }, 600);
    window.addEventListener('focus', reportViewing); window.addEventListener('blur', reportViewing);
    document.addEventListener('visibilitychange', reportViewing);
    void report(); void reportViewing(); void loop(); return () => {
      lifetime.abort(); unsubscribe(); clearInterval(viewTimer);
      window.removeEventListener('focus', reportViewing); window.removeEventListener('blur', reportViewing);
      document.removeEventListener('visibilitychange', reportViewing);
    };
  }, 'always-on: exact session navigation');
}
