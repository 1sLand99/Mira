'use client';

import {
  Activity,
  Braces,
  Check,
  ChevronLeft,
  Clipboard,
  Cpu,
  Database,
  FileText,
  Gauge,
  Globe2,
  Layers3,
  MonitorSmartphone,
  Radio,
  RefreshCw,
  Search,
  Shield,
  Sparkles,
  TerminalSquare,
} from 'lucide-react';
import clsx from 'clsx';
import { useCallback, useEffect, useMemo, useState } from 'react';
import { DeviceCard } from '@/components/DeviceCard';
import { StatusPill } from '@/components/StatusPill';
import { ConsoleEvent, TerminalStage } from '@/components/TerminalStage';
import { copyText, deviceTitle, shortId, stateTone } from '@/lib/format';
import { listDevices } from '@/lib/relay';
import type { MiraDevice } from '@/lib/types';

const TOOL_TABS = [
  { name: 'Terminal', icon: TerminalSquare, ready: true },
  { name: 'Files', icon: FileText, ready: false },
  { name: 'UI', icon: MonitorSmartphone, ready: false },
  { name: 'Logs', icon: Activity, ready: false },
  { name: 'AI', icon: Sparkles, ready: false },
];

export default function RelayConsolePage() {
  const [devices, setDevices] = useState<MiraDevice[]>([]);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [relayUrl, setRelayUrl] = useState('');
  const [events, setEvents] = useState<ConsoleEvent[]>([]);
  const [copied, setCopied] = useState(false);

  const selectedDevice = useMemo(
    () => devices.find((device) => device.installId === selectedId) || null,
    [devices, selectedId],
  );
  const onlineDevices = devices.filter((device) => device.state !== 'offline');

  const pushEvent = useCallback((event: ConsoleEvent) => {
    setEvents((current) => [event, ...current].slice(0, 80));
  }, []);

  const refreshDevices = useCallback(async () => {
    try {
      const data = await listDevices();
      setDevices(data.devices || []);
      setError(null);
    } catch (fetchError) {
      setError(fetchError instanceof Error ? fetchError.message : String(fetchError));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    setRelayUrl(window.location.origin);
    const hash = new URLSearchParams(window.location.hash.replace(/^#/, ''));
    const initialDevice = hash.get('device');
    if (initialDevice) setSelectedId(initialDevice);
    refreshDevices();
    const timer = window.setInterval(refreshDevices, 2000);
    const onHash = () => {
      const nextHash = new URLSearchParams(window.location.hash.replace(/^#/, ''));
      setSelectedId(nextHash.get('device'));
    };
    window.addEventListener('hashchange', onHash);
    return () => {
      window.clearInterval(timer);
      window.removeEventListener('hashchange', onHash);
    };
  }, [refreshDevices]);

  const selectDevice = useCallback(
    (device: MiraDevice) => {
      setSelectedId(device.installId);
      window.location.hash = `device=${encodeURIComponent(device.installId)}`;
      pushEvent({ at: new Date().toLocaleTimeString(), type: 'device.select', detail: shortId(device.installId) });
    },
    [pushEvent],
  );

  const backToLobby = useCallback(() => {
    setSelectedId(null);
    window.location.hash = '';
  }, []);

  const handleCopyRelay = useCallback(async () => {
    await copyText(relayUrl);
    setCopied(true);
    window.setTimeout(() => setCopied(false), 1200);
  }, [relayUrl]);

  return (
    <main className="relative h-screen overflow-hidden bg-[#050816] text-slate-100">
      <BackgroundGlow />
      <div className="relative z-10 flex h-full flex-col p-4 lg:p-5">
        <TopBar
          relayUrl={relayUrl}
          devices={devices}
          onlineCount={onlineDevices.length}
          loading={loading}
          error={error}
          copied={copied}
          onCopyRelay={handleCopyRelay}
          onRefresh={refreshDevices}
        />
        {selectedDevice ? (
          <Workbench
            devices={devices}
            selectedDevice={selectedDevice}
            events={events}
            onSelect={selectDevice}
            onBack={backToLobby}
            onEvent={pushEvent}
            onRefreshDevices={refreshDevices}
          />
        ) : (
          <Lobby
            devices={devices}
            loading={loading}
            relayUrl={relayUrl}
            copied={copied}
            onCopyRelay={handleCopyRelay}
            onSelect={selectDevice}
          />
        )}
      </div>
    </main>
  );
}

function BackgroundGlow() {
  return (
    <div className="pointer-events-none absolute inset-0 overflow-hidden">
      <div className="absolute -left-32 top-[-18rem] h-[32rem] w-[32rem] rounded-full bg-emerald-500/12 blur-3xl" />
      <div className="absolute right-[-10rem] top-24 h-[30rem] w-[30rem] rounded-full bg-cyan-500/8 blur-3xl" />
      <div className="absolute bottom-[-16rem] left-1/2 h-[30rem] w-[42rem] -translate-x-1/2 rounded-full bg-indigo-500/10 blur-3xl" />
      <div className="absolute inset-0 bg-[linear-gradient(rgba(148,163,184,0.03)_1px,transparent_1px),linear-gradient(90deg,rgba(148,163,184,0.03)_1px,transparent_1px)] bg-[size:48px_48px]" />
    </div>
  );
}

function TopBar({
  relayUrl,
  devices,
  onlineCount,
  loading,
  error,
  copied,
  onCopyRelay,
  onRefresh,
}: {
  relayUrl: string;
  devices: MiraDevice[];
  onlineCount: number;
  loading: boolean;
  error: string | null;
  copied: boolean;
  onCopyRelay: () => void;
  onRefresh: () => void;
}) {
  return (
    <header className="mb-4 flex min-h-0 items-center justify-between gap-4 rounded-[1.75rem] border border-white/10 bg-slate-950/68 px-4 py-3 shadow-[0_18px_80px_rgba(0,0,0,0.25)] backdrop-blur-2xl lg:px-5">
      <div className="flex min-w-0 items-center gap-4">
        <div className="flex items-center gap-3">
          <div className="grid h-10 w-10 place-items-center rounded-2xl border border-emerald-300/20 bg-emerald-300/10 text-emerald-300 shadow-[0_0_36px_rgba(52,211,153,0.16)]">
            <Layers3 size={19} />
          </div>
          <div>
            <div className="flex items-baseline gap-2">
              <span className="text-lg font-black tracking-[-0.05em]">Mira</span>
              <span className="text-[11px] font-semibold uppercase tracking-[0.24em] text-slate-500">console</span>
            </div>
            <div className="text-[11px] text-slate-500">Android device workbench</div>
          </div>
        </div>
        <div className="hidden min-w-0 items-center gap-3 rounded-2xl border border-white/10 bg-white/[0.035] px-3 py-2 font-mono text-[11px] text-slate-400 xl:flex">
          <Globe2 size={14} className="shrink-0 text-emerald-300" />
          <span className="max-w-[360px] truncate">{relayUrl || 'relay origin'}</span>
          <button type="button" onClick={onCopyRelay} className="rounded-xl px-2 py-1 text-slate-200 transition hover:bg-white/10">
            {copied ? <Check size={14} /> : <Clipboard size={14} />}
          </button>
        </div>
      </div>
      <div className="flex items-center gap-2 lg:gap-3">
        {error ? (
          <StatusPill state="offline" label="relay error" />
        ) : (
          <StatusPill state={onlineCount > 0 ? 'active' : 'opening'} label={loading ? 'syncing' : `${onlineCount}/${devices.length} online`} />
        )}
        <button
          type="button"
          onClick={onRefresh}
          className="grid h-10 w-10 place-items-center rounded-2xl border border-white/10 bg-white/[0.035] text-slate-300 transition hover:bg-white/[0.07]"
          title="Refresh device list"
        >
          <RefreshCw size={16} />
        </button>
      </div>
    </header>
  );
}

function Lobby({
  devices,
  loading,
  relayUrl,
  copied,
  onCopyRelay,
  onSelect,
}: {
  devices: MiraDevice[];
  loading: boolean;
  relayUrl: string;
  copied: boolean;
  onCopyRelay: () => void;
  onSelect: (device: MiraDevice) => void;
}) {
  return (
    <section className="min-h-0 flex-1 overflow-hidden rounded-[2rem] border border-white/10 bg-slate-950/45 p-5 shadow-[0_24px_120px_rgba(0,0,0,0.32)] backdrop-blur-2xl lg:p-6">
      <div className="grid h-full min-h-0 grid-cols-1 gap-5 xl:grid-cols-[1.02fr_1.25fr]">
        <div className="flex min-h-0 flex-col justify-between rounded-[1.75rem] border border-white/10 bg-[radial-gradient(circle_at_18%_0%,rgba(52,211,153,0.16),transparent_32%),radial-gradient(circle_at_84%_20%,rgba(96,165,250,0.12),transparent_26%),rgba(15,23,42,0.66)] p-6 lg:p-7">
          <div>
            <div className="mb-5 inline-flex items-center gap-2 rounded-full border border-emerald-300/20 bg-emerald-300/10 px-3 py-1 text-xs font-semibold uppercase tracking-[0.2em] text-emerald-200">
              <Shield size={14} /> Remote PTY ready
            </div>
            <h1 className="max-w-xl text-4xl font-black leading-[0.96] tracking-[-0.08em] text-slate-50 md:text-6xl">
              Device control room.
            </h1>
            <p className="mt-5 max-w-lg text-sm leading-7 text-slate-400">
              保持 Android Mira 前台并连接 Relay URL. 选择已连接设备后进入三栏工作台, 中央终端直接承载交互主视图.
            </p>
          </div>
          <div className="mt-10 grid gap-3 rounded-[1.5rem] border border-white/10 bg-black/24 p-4">
            <div className="flex items-center justify-between gap-3">
              <div>
                <div className="text-xs font-semibold uppercase tracking-[0.2em] text-slate-500">Relay URL</div>
                <div className="mt-1 text-xs text-slate-500">手机端请填入该地址并连接.</div>
              </div>
              <StatusPill state={devices.length ? 'active' : 'opening'} label={devices.length ? 'devices visible' : 'waiting'} />
            </div>
            <div className="flex items-center gap-3 rounded-2xl border border-white/10 bg-slate-950/80 px-3 py-2">
              <code className="min-w-0 flex-1 truncate font-mono text-sm text-emerald-300">{relayUrl || 'loading...'}</code>
              <button type="button" onClick={onCopyRelay} className="inline-flex h-10 items-center gap-2 rounded-2xl bg-white/[0.07] px-3 text-sm font-semibold text-slate-200 transition hover:bg-white/[0.12]">
                {copied ? <Check size={15} /> : <Clipboard size={15} />}
                {copied ? 'Copied' : 'Copy'}
              </button>
            </div>
          </div>
        </div>
        <div className="min-h-0 overflow-hidden rounded-[1.75rem] border border-white/10 bg-slate-950/56 p-4 lg:p-5">
          <div className="mb-5 flex items-center justify-between gap-3">
            <div>
              <div className="text-2xl font-bold tracking-[-0.04em]">Connected devices</div>
              <div className="mt-1 text-sm text-slate-500">Select a device to enter the workbench.</div>
            </div>
            <div className="rounded-2xl border border-white/10 bg-white/[0.035] px-3 py-2 font-mono text-xs text-slate-400">{devices.length} total</div>
          </div>
          <div className="mira-scrollbar grid max-h-[calc(100vh-220px)] grid-cols-1 gap-3 overflow-auto pr-1 2xl:grid-cols-2">
            {devices.map((device) => (
              <DeviceCard key={device.installId} device={device} onSelect={onSelect} />
            ))}
            {!devices.length && (
              <div className="grid min-h-[18rem] place-items-center rounded-[1.5rem] border border-dashed border-white/10 bg-white/[0.025] text-center">
                <div>
                  <MonitorSmartphone className="mx-auto mb-3 text-slate-500" />
                  <div className="font-semibold text-slate-300">{loading ? 'Waiting for devices' : 'No devices connected'}</div>
                  <div className="mt-2 max-w-xs text-sm leading-6 text-slate-500">在 Android Mira 首页填入 Relay URL, 点击 Connect Relay.</div>
                </div>
              </div>
            )}
          </div>
        </div>
      </div>
    </section>
  );
}

function Workbench({
  devices,
  selectedDevice,
  events,
  onSelect,
  onBack,
  onEvent,
  onRefreshDevices,
}: {
  devices: MiraDevice[];
  selectedDevice: MiraDevice;
  events: ConsoleEvent[];
  onSelect: (device: MiraDevice) => void;
  onBack: () => void;
  onEvent: (event: ConsoleEvent) => void;
  onRefreshDevices: () => void;
}) {
  return (
    <section className="min-h-0 flex-1 overflow-hidden rounded-[2rem] border border-white/10 bg-slate-950/42 p-3 shadow-[0_24px_120px_rgba(0,0,0,0.32)] backdrop-blur-2xl lg:p-4">
      <div className="grid h-full min-h-0 grid-cols-1 gap-3 xl:grid-cols-[300px_minmax(0,1fr)_340px]">
        <DeviceRail devices={devices} selectedDevice={selectedDevice} onSelect={onSelect} onBack={onBack} />
        <div className="min-h-0 overflow-hidden rounded-[1.75rem] border border-white/10 bg-[#030712] shadow-[0_30px_120px_rgba(0,0,0,0.42)]">
          <TerminalStage device={selectedDevice} onEvent={onEvent} onRefreshDevices={onRefreshDevices} />
        </div>
        <InspectorRail device={selectedDevice} events={events} />
      </div>
    </section>
  );
}

function DeviceRail({
  devices,
  selectedDevice,
  onSelect,
  onBack,
}: {
  devices: MiraDevice[];
  selectedDevice: MiraDevice;
  onSelect: (device: MiraDevice) => void;
  onBack: () => void;
}) {
  return (
    <aside className="flex h-full min-h-0 flex-col rounded-[1.75rem] border border-white/10 bg-slate-950/48 p-4">
      <button
        type="button"
        onClick={onBack}
        className="mb-4 inline-flex items-center gap-2 self-start rounded-2xl border border-white/10 bg-white/[0.035] px-3 py-2 text-sm text-slate-300 transition hover:bg-white/[0.07]"
      >
        <ChevronLeft size={16} /> Lobby
      </button>
      <div className="mb-4 rounded-[1.5rem] border border-white/10 bg-[radial-gradient(circle_at_top,rgba(52,211,153,0.11),transparent_42%),rgba(255,255,255,0.03)] p-4">
        <div className="mb-3 flex items-center justify-between gap-2">
          <div className="text-sm font-semibold text-slate-200">Active device</div>
          <StatusPill state={selectedDevice.state || 'unknown'} />
        </div>
        <div className="text-2xl font-black tracking-[-0.06em]">{deviceTitle(selectedDevice)}</div>
        <div className="mt-2 font-mono text-xs text-slate-500">{shortId(selectedDevice.installId, 12)}</div>
      </div>
      <div className="mb-3 flex items-center gap-2 rounded-2xl border border-white/10 bg-slate-950/50 px-3 py-2 text-slate-500">
        <Search size={15} />
        <span className="text-xs">Connected devices</span>
      </div>
      <div className="mira-scrollbar min-h-0 flex-1 space-y-3 overflow-auto pr-1">
        {devices.map((device) => (
          <DeviceCard key={device.installId} device={device} selected={device.installId === selectedDevice.installId} onSelect={onSelect} />
        ))}
      </div>
      <div className="mt-4 grid grid-cols-1 gap-2">
        {TOOL_TABS.map((tool) => {
          const Icon = tool.icon;
          return (
            <button
              type="button"
              key={tool.name}
              disabled={!tool.ready}
              className={clsx(
                'flex items-center justify-between rounded-2xl border px-3 py-2.5 text-sm transition',
                tool.ready ? 'border-emerald-300/20 bg-emerald-300/10 text-emerald-200' : 'cursor-not-allowed border-white/10 bg-white/[0.025] text-slate-600',
              )}
            >
              <span className="inline-flex items-center gap-2">
                <Icon size={15} /> {tool.name}
              </span>
              {!tool.ready && <span className="text-[10px] uppercase tracking-[0.18em]">later</span>}
            </button>
          );
        })}
      </div>
    </aside>
  );
}

function InspectorRail({ device, events }: { device: MiraDevice; events: ConsoleEvent[] }) {
  return (
    <aside className="mira-scrollbar flex h-full min-h-0 flex-col gap-3 overflow-auto rounded-[1.75rem] border border-white/10 bg-slate-950/38 p-4">
      <div className="flex items-center justify-between">
        <div>
          <div className="text-sm font-semibold uppercase tracking-[0.18em] text-slate-500">Inspector</div>
          <div className="mt-1 text-xl font-bold tracking-[-0.04em]">Device context</div>
        </div>
        <Braces className="text-emerald-300" />
      </div>
      <InfoCard
        title="Identity"
        icon={Database}
        rows={[
          ['Install', device.installId],
          ['Package', device.packageName || 'unknown'],
          ['Android ID', device.androidIdHash || 'unknown'],
        ]}
      />
      <InfoCard
        title="Platform"
        icon={Cpu}
        rows={[
          ['Model', device.model || device.deviceName || 'unknown'],
          ['SDK', String(device.sdk || 'unknown')],
          ['ABI', device.arch || 'unknown'],
        ]}
      />
      <InfoCard
        title="Transport"
        icon={Radio}
        rows={[
          ['State', device.state || 'unknown'],
          ['Mode', device.transport || 'legacy'],
          ['Address', device.address || 'unknown'],
        ]}
      />
      <div className="rounded-[1.35rem] border border-white/10 bg-white/[0.035] p-4">
        <div className="mb-3 flex items-center justify-between">
          <div className="inline-flex items-center gap-2 text-sm font-semibold text-slate-200">
            <Gauge size={15} /> Protocol trace
          </div>
          <span className="font-mono text-[10px] text-slate-600">{events.length}</span>
        </div>
        <div className="space-y-2">
          {events.slice(0, 12).map((event, index) => (
            <div key={`${event.at}-${event.type}-${index}`} className="rounded-2xl bg-black/20 px-3 py-2">
              <div className="flex items-center justify-between gap-2">
                <span className="truncate font-mono text-[11px] text-emerald-300">{event.type}</span>
                <span className="font-mono text-[10px] text-slate-600">{event.at}</span>
              </div>
              <div className="mt-1 truncate text-xs text-slate-400">{event.detail}</div>
            </div>
          ))}
          {!events.length && <div className="rounded-2xl border border-dashed border-white/10 p-4 text-center text-xs text-slate-500">No protocol events yet.</div>}
        </div>
      </div>
    </aside>
  );
}

function InfoCard({ title, icon: Icon, rows }: { title: string; icon: typeof Database; rows: Array<[string, string]> }) {
  return (
    <section className="rounded-[1.35rem] border border-white/10 bg-white/[0.035] p-4">
      <div className="mb-3 inline-flex items-center gap-2 text-sm font-semibold text-slate-200">
        <Icon size={15} /> {title}
      </div>
      <div className="space-y-2">
        {rows.map(([key, value]) => (
          <div key={key} className="grid grid-cols-[72px_1fr] gap-3 text-xs">
            <div className="text-slate-600">{key}</div>
            <div className={clsx('truncate font-mono text-slate-300', stateTone(value) === 'good' && key === 'State' && 'text-emerald-300')}>
              {value}
            </div>
          </div>
        ))}
      </div>
    </section>
  );
}
