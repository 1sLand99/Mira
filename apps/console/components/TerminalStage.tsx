'use client';

import { FitAddon } from '@xterm/addon-fit';
import { Terminal } from '@xterm/xterm';
import clsx from 'clsx';
import { Maximize2, Play, Power, RotateCw, TerminalSquare } from 'lucide-react';
import { useCallback, useEffect, useRef, useState } from 'react';
import { base64ToBytes, browserWsUrl, bytesToBase64, closeSession, openSession } from '@/lib/relay';
import type { MiraDevice, SessionStatus } from '@/lib/types';
import { deviceTitle, shortId } from '@/lib/format';
import { StatusPill } from './StatusPill';

type RelayMessage = {
  type?: string;
  sessionId?: string;
  state?: SessionStatus;
  dataBase64?: string;
  error?: string;
};

export type ConsoleEvent = {
  at: string;
  type: string;
  detail: string;
};

export function TerminalStage({
  device,
  onEvent,
  onRefreshDevices,
}: {
  device: MiraDevice | null;
  onEvent: (event: ConsoleEvent) => void;
  onRefreshDevices: () => void;
}) {
  const terminalHost = useRef<HTMLDivElement | null>(null);
  const terminalRef = useRef<Terminal | null>(null);
  const fitRef = useRef<FitAddon | null>(null);
  const socketRef = useRef<WebSocket | null>(null);
  const sessionIdRef = useRef<string | null>(null);
  const deviceAttachedRef = useRef(false);
  const [sessionId, setSessionId] = useState<string | null>(null);
  const [sessionStatus, setSessionStatus] = useState<SessionStatus>('idle');
  const [transportStatus, setTransportStatus] = useState<'idle' | 'connecting' | 'connected' | 'closed' | 'error'>('idle');
  const [size, setSize] = useState({ cols: 120, rows: 36 });

  const record = useCallback((type: string, detail: string) => {
    onEvent({ at: new Date().toLocaleTimeString(), type, detail });
  }, [onEvent]);

  const send = useCallback((message: Record<string, unknown>) => {
    const socket = socketRef.current;
    if (socket && socket.readyState === WebSocket.OPEN) socket.send(JSON.stringify(message));
  }, []);

  const fitAndResize = useCallback(() => {
    const terminal = terminalRef.current;
    const fit = fitRef.current;
    if (!terminal || !fit) return;
    fit.fit();
    setSize({ cols: terminal.cols, rows: terminal.rows });
    if (sessionIdRef.current && deviceAttachedRef.current) {
      send({ type: 'terminal.resize', sessionId: sessionIdRef.current, cols: terminal.cols, rows: terminal.rows });
    }
  }, [send]);

  useEffect(() => {
    if (!terminalHost.current || terminalRef.current) return;
    const terminal = new Terminal({
      cursorBlink: true,
      convertEol: true,
      fontFamily: '"JetBrains Mono", "SFMono-Regular", "SF Mono", Menlo, Consolas, monospace',
      fontSize: 13,
      lineHeight: 1.16,
      letterSpacing: 0,
      scrollback: 5000,
      theme: {
        background: '#030712',
        foreground: '#E5E7EB',
        cursor: '#34D399',
        selectionBackground: '#334155',
        black: '#020617',
        brightBlack: '#475569',
        red: '#F87171',
        brightRed: '#FCA5A5',
        green: '#34D399',
        brightGreen: '#86EFAC',
        yellow: '#FBBF24',
        brightYellow: '#FDE68A',
        blue: '#60A5FA',
        brightBlue: '#93C5FD',
        magenta: '#C084FC',
        brightMagenta: '#D8B4FE',
        cyan: '#22D3EE',
        brightCyan: '#67E8F9',
        white: '#CBD5E1',
        brightWhite: '#F8FAFC',
      },
    });
    const fit = new FitAddon();
    terminal.loadAddon(fit);
    terminal.open(terminalHost.current);
    terminalRef.current = terminal;
    fitRef.current = fit;
    terminal.writeln('\x1b[38;5;245mSelect a device and open a Mira PTY session.\x1b[0m');
    window.setTimeout(fitAndResize, 0);

    const inputDisposable = terminal.onData((data) => {
      if (!sessionIdRef.current || !deviceAttachedRef.current) return;
      send({ type: 'terminal.input', sessionId: sessionIdRef.current, dataBase64: bytesToBase64(data) });
    });
    const resizeObserver = new ResizeObserver(() => window.setTimeout(fitAndResize, 60));
    resizeObserver.observe(terminalHost.current);

    return () => {
      inputDisposable.dispose();
      resizeObserver.disconnect();
      terminal.dispose();
      terminalRef.current = null;
      fitRef.current = null;
    };
  }, [fitAndResize, send]);

  const connectBrowser = useCallback((targetDevice: MiraDevice, nextSessionId: string) => {
    const oldSocket = socketRef.current;
    if (oldSocket) oldSocket.close();
    deviceAttachedRef.current = false;
    sessionIdRef.current = nextSessionId;
    setSessionId(nextSessionId);
    setSessionStatus('opening');
    setTransportStatus('connecting');
    terminalRef.current?.clear();
    terminalRef.current?.writeln('\x1b[38;5;245mMira relay session requested. Waiting for Android PTY attach...\x1b[0m');
    const socket = new WebSocket(browserWsUrl());
    socketRef.current = socket;
    socket.addEventListener('open', () => {
      setTransportStatus('connected');
      record('browser.attach', shortId(nextSessionId));
      send({ type: 'browser.attach', protocol: 1, installId: targetDevice.installId, sessionId: nextSessionId });
    });
    socket.addEventListener('message', (event) => {
      let message: RelayMessage;
      try {
        message = JSON.parse(event.data as string) as RelayMessage;
      } catch {
        return;
      }
      if (message.type === 'terminal.output') {
        deviceAttachedRef.current = true;
        terminalRef.current?.write(base64ToBytes(message.dataBase64 || ''));
      } else if (message.type === 'session.status') {
        const nextState = message.state || 'unknown';
        deviceAttachedRef.current = nextState === 'active';
        setSessionStatus(nextState);
        record('session.status', nextState);
        if (nextState === 'active') fitAndResize();
      } else if (message.type === 'session.close') {
        deviceAttachedRef.current = false;
        sessionIdRef.current = null;
        setSessionId(null);
        setSessionStatus('closed');
        record('session.close', shortId(message.sessionId));
        onRefreshDevices();
      } else if (message.type === 'error') {
        setTransportStatus('error');
        record('error', message.error || 'unknown error');
        terminalRef.current?.writeln(`\r\n\x1b[31m${message.error || 'relay error'}\x1b[0m`);
      }
    });
    socket.addEventListener('close', () => {
      setTransportStatus('closed');
      deviceAttachedRef.current = false;
      record('ws.close', shortId(nextSessionId));
    });
    socket.addEventListener('error', () => {
      setTransportStatus('error');
      record('ws.error', shortId(nextSessionId));
    });
  }, [fitAndResize, onRefreshDevices, record, send]);

  const handleOpen = useCallback(async () => {
    if (!device) return;
    fitAndResize();
    setSessionStatus('opening');
    record('session.open', device.installId);
    try {
      const terminal = terminalRef.current;
      const opened = await openSession(device.installId, terminal?.cols || size.cols, terminal?.rows || size.rows);
      connectBrowser(device, opened.sessionId);
      onRefreshDevices();
    } catch (error) {
      setSessionStatus('error');
      setTransportStatus('error');
      const message = error instanceof Error ? error.message : String(error);
      record('open.failed', message);
      terminalRef.current?.writeln(`\r\n\x1b[31m${message}\x1b[0m`);
    }
  }, [connectBrowser, device, fitAndResize, onRefreshDevices, record, size.cols, size.rows]);

  const handleClose = useCallback(async () => {
    const closingSession = sessionIdRef.current;
    if (!closingSession) return;
    record('session.close.request', shortId(closingSession));
    await closeSession(closingSession).catch((error) => record('close.failed', error instanceof Error ? error.message : String(error)));
    socketRef.current?.close();
    socketRef.current = null;
    sessionIdRef.current = null;
    deviceAttachedRef.current = false;
    setSessionId(null);
    setSessionStatus('closed');
    setTransportStatus('closed');
    onRefreshDevices();
  }, [onRefreshDevices, record]);

  useEffect(() => {
    return () => {
      socketRef.current?.close();
    };
  }, []);

  const canOpen = Boolean(device && device.state !== 'offline' && device.state !== 'active' && device.state !== 'opening' && !sessionId);

  return (
    <section className="flex h-full min-h-0 flex-col overflow-hidden rounded-[2rem] border border-white/10 bg-[#030712] shadow-[0_30px_120px_rgba(0,0,0,0.42)]">
      <header className="flex items-center justify-between border-b border-white/10 bg-slate-950/80 px-5 py-4 backdrop-blur">
        <div className="flex min-w-0 items-center gap-3">
          <div className="grid h-10 w-10 place-items-center rounded-2xl border border-emerald-300/20 bg-emerald-300/10 text-emerald-300">
            <TerminalSquare size={19} />
          </div>
          <div className="min-w-0">
            <div className="truncate text-sm font-semibold text-slate-100">{device ? deviceTitle(device) : 'Mira Terminal'}</div>
            <div className="mt-1 flex items-center gap-2 font-mono text-[11px] text-slate-500">
              <span>{sessionId ? shortId(sessionId) : 'no-session'}</span>
              <span>·</span>
              <span>{size.cols} x {size.rows}</span>
              <span>·</span>
              <span>{transportStatus}</span>
            </div>
          </div>
        </div>
        <div className="flex items-center gap-2">
          <StatusPill state={sessionStatus} label={sessionStatus} />
          <button
            type="button"
            onClick={fitAndResize}
            className="grid h-10 w-10 place-items-center rounded-2xl border border-white/10 bg-white/[0.035] text-slate-300 transition hover:border-white/20 hover:bg-white/[0.07]"
            title="Fit terminal"
          >
            <Maximize2 size={16} />
          </button>
          {sessionId ? (
            <button type="button" onClick={handleClose} className="inline-flex h-10 items-center gap-2 rounded-2xl bg-red-400/12 px-4 text-sm font-semibold text-red-200 transition hover:bg-red-400/18">
              <Power size={15} /> Close
            </button>
          ) : (
            <button
              type="button"
              onClick={handleOpen}
              disabled={!canOpen}
              className={clsx(
                'inline-flex h-10 items-center gap-2 rounded-2xl px-4 text-sm font-semibold transition',
                canOpen ? 'bg-emerald-400 text-slate-950 hover:bg-emerald-300' : 'cursor-not-allowed bg-slate-700/60 text-slate-400',
              )}
            >
              <Play size={15} /> Open Terminal
            </button>
          )}
        </div>
      </header>
      <div className="relative min-h-0 flex-1 overflow-hidden bg-[radial-gradient(circle_at_20%_0%,rgba(16,185,129,0.08),transparent_28%),linear-gradient(180deg,#030712,#020617)]">
        {!device && (
          <div className="absolute inset-0 z-10 grid place-items-center bg-slate-950/30 text-center backdrop-blur-[1px]">
            <div className="max-w-sm rounded-3xl border border-white/10 bg-slate-950/80 p-7 shadow-2xl">
              <RotateCw className="mx-auto mb-4 text-emerald-300" />
              <div className="text-lg font-semibold">Select a device</div>
              <div className="mt-2 text-sm leading-6 text-slate-400">Android Mira 保持前台连接后, 在左侧选择设备进入真实 PTY。</div>
            </div>
          </div>
        )}
        <div ref={terminalHost} className="h-full w-full" />
      </div>
    </section>
  );
}
