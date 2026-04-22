'use client';

import { useEffect, useMemo, useRef, useState } from 'react';
import { DeviceFrame } from '@/components/DeviceFrame';
import { ConsoleEvent, TerminalStage } from '@/components/TerminalStage';
import { deviceTitle, shortId } from '@/lib/format';
import type { MiraDevice } from '@/lib/types';

export function Workbench({
  selectedDevice,
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
  const hostRef = useRef<HTMLElement | null>(null);
  const [hostSize, setHostSize] = useState({ width: 0, height: 0 });
  const leftWidth = useMemo(() => adaptiveDevicePaneWidth(selectedDevice, hostSize), [hostSize, selectedDevice]);

  useEffect(() => {
    const host = hostRef.current;
    if (!host) return;
    const update = () => setHostSize({ width: host.clientWidth, height: host.clientHeight });
    update();
    const observer = new ResizeObserver(update);
    observer.observe(host);
    return () => observer.disconnect();
  }, []);

  return (
    <section
      ref={hostRef}
      className="grid min-h-0 flex-1 overflow-hidden bg-[#f5f5f5] text-[#111]"
      style={{ gridTemplateColumns: `${leftWidth}px minmax(0,1fr)` }}
    >
      <DeviceFrame device={selectedDevice} />
      <div className="grid min-h-0 grid-rows-[minmax(0,1fr)_168px]">
        <TerminalStage device={selectedDevice} onEvent={onEvent} onRefreshDevices={onRefreshDevices} />
        <InfoPanel device={selectedDevice} />
      </div>
    </section>
  );
}

function adaptiveDevicePaneWidth(device: MiraDevice, hostSize: { width: number; height: number }) {
  const screen = device.outline?.screen;
  const screenWidth = Number(screen?.width) || 1080;
  const screenHeight = Number(screen?.height) || 2280;
  const aspect = screenWidth > 0 && screenHeight > 0 ? screenWidth / screenHeight : 9 / 19.5;
  const target = (hostSize.height || 720) * aspect;
  const maxByWidth = hostSize.width ? hostSize.width * 0.48 : 620;
  const max = Math.max(240, Math.min(640, maxByWidth));
  const min = Math.min(300, max);
  return Math.round(Math.max(min, Math.min(target, max)));
}

function InfoPanel({ device }: { device: MiraDevice }) {
  const screen = device.outline?.screen;
  const screenText = screen?.width && screen?.height ? `${screen.width} x ${screen.height}` : 'unknown';
  const rows: Array<[string, string]> = [
    ['Architecture', device.arch || 'unknown'],
    ['Model', device.model || device.deviceName || 'unknown'],
    ['Device ID', shortId(device.installId, 36)],
    ['Screen', screenText],
    ['Components', String(device.outline?.nodeCount ?? device.outline?.nodes?.length ?? 'unknown')],
    ['Outline', device.outline?.stale ? `stale: ${device.outline.staleReason || 'cached'}` : device.outline?.available === false ? device.outline.reason || 'unavailable' : 'live'],
    ['Proxy', 'none'],
    ['Cur Application', device.packageName || 'unknown'],
    ['Cur Activity', device.outline?.activityName || 'unknown'],
    ['Status', device.state || 'unknown'],
  ];

  return (
    <section className="relative border-t border-[#cfcfcf] bg-[#f5f5f5] text-[#111]">
      <div className="h-full overflow-auto px-3 py-2 pr-[180px] font-mono text-[12px] leading-5">
        <div className="mb-2 border-b border-[#d8d8d8] pb-1 text-[13px] font-semibold tracking-[0.12em] text-[#3f7fd3]">INFO</div>
        <div className="grid max-w-[920px] grid-cols-[132px_minmax(0,1fr)] gap-x-6">
          {rows.map(([key, value]) => (
            <div key={key} className="contents">
              <div className="text-[#555]">{key}:</div>
              <div className="truncate text-[#111]">{value}</div>
            </div>
          ))}
        </div>
        <div className="mt-2 text-[11px] text-[#666]">Selected: {deviceTitle(device)}</div>
      </div>
      <DeviceMetricsPanel device={device} />
    </section>
  );
}

type MetricPoint = {
  at: number;
  cpu: number;
  mem: number;
  net: number;
};

function DeviceMetricsPanel({ device }: { device: MiraDevice }) {
  const [history, setHistory] = useState<MetricPoint[]>([]);

  useEffect(() => {
    setHistory([]);
  }, [device.installId]);

  useEffect(() => {
    const metrics = device.metrics;
    if (!metrics) return;
    const next: MetricPoint = {
      at: Number(metrics.sampledAt) || Date.now(),
      cpu: normalizedMetric(metrics.cpuPercent),
      mem: normalizedMetric(metrics.memoryPercent),
      net: Math.min(100, Math.max(0, (Number(metrics.networkBps) || 0) / 2048)),
    };
    setHistory((current) => {
      const last = current[current.length - 1];
      if (last && last.at === next.at) return current;
      return [...current, next].slice(-48);
    });
  }, [device.metrics]);

  const latest = history[history.length - 1];
  const stale = !latest || Date.now() - latest.at > 3000;
  const netBps = Number(device.metrics?.networkBps) || 0;

  return (
    <div className="absolute bottom-2 right-2 w-[164px] border border-[#d8d8d8] bg-[#f5f5f5]/95 font-mono text-[10px] leading-3 text-[#555] shadow-sm">
      <MetricChart label="CPU" value={latest?.cpu ?? -1} history={history.map((point) => point.cpu)} stale={stale} />
      <MetricChart label="MEM" value={latest?.mem ?? -1} history={history.map((point) => point.mem)} stale={stale} />
      <MetricChart label="NET" value={netBps} history={history.map((point) => point.net)} stale={stale} format={formatBytesPerSecond} />
    </div>
  );
}

function MetricChart({
  label,
  value,
  history,
  stale,
  format = formatPercent,
}: {
  label: string;
  value: number;
  history: number[];
  stale: boolean;
  format?: (value: number) => string;
}) {
  return (
    <div className="grid grid-cols-[1fr_52px] items-end gap-1 border-b border-[#e2e2e2] px-1 py-0.5 last:border-b-0">
      <svg viewBox="0 0 92 22" className="h-[22px] w-full overflow-visible">
        <path d={sparkPath(history, 92, 22)} fill="none" stroke={stale ? '#bdbdbd' : '#59ca58'} strokeWidth="1.2" />
        <line x1="0" y1="21" x2="92" y2="21" stroke="#d7d7d7" strokeWidth="0.8" />
      </svg>
      <div className="text-right">
        <div className="text-[#333]">{format(value)}</div>
        <div className="text-[9px] text-[#777]">{label}</div>
      </div>
    </div>
  );
}

function normalizedMetric(value: unknown) {
  const numeric = Number(value);
  if (!Number.isFinite(numeric) || numeric < 0) return 0;
  return Math.max(0, Math.min(100, numeric));
}

function sparkPath(values: number[], width: number, height: number) {
  if (!values.length) return '';
  if (values.length === 1) {
    const y = height - (normalizedMetric(values[0]) / 100) * height;
    return `M 0 ${y.toFixed(1)} L ${width} ${y.toFixed(1)}`;
  }
  return values
    .map((value, index) => {
      const x = (index / Math.max(1, values.length - 1)) * width;
      const y = height - (normalizedMetric(value) / 100) * height;
      return `${index === 0 ? 'M' : 'L'} ${x.toFixed(1)} ${y.toFixed(1)}`;
    })
    .join(' ');
}

function formatPercent(value: number) {
  if (!Number.isFinite(value) || value < 0) return '--';
  return `${value.toFixed(1)}%`;
}

function formatBytesPerSecond(value: number) {
  if (!Number.isFinite(value) || value < 0) return '--';
  if (value < 1024) return `${value.toFixed(0)}B/s`;
  if (value < 1024 * 1024) return `${(value / 1024).toFixed(1)}K/s`;
  return `${(value / 1024 / 1024).toFixed(1)}M/s`;
}
