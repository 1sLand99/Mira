'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import type { PointerEvent as ReactPointerEvent } from 'react';
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
  const [manualLeftWidth, setManualLeftWidth] = useState<number | null>(null);
  const [infoHeight, setInfoHeight] = useState(168);
  const adaptiveLeftWidth = useMemo(() => adaptiveDevicePaneWidth(selectedDevice, hostSize), [hostSize, selectedDevice]);
  const leftWidth = clampPaneSize(manualLeftWidth ?? adaptiveLeftWidth, minDevicePaneWidth(hostSize), maxDevicePaneWidth(hostSize));

  useEffect(() => {
    const host = hostRef.current;
    if (!host) return;
    const update = () => setHostSize({ width: host.clientWidth, height: host.clientHeight });
    update();
    const observer = new ResizeObserver(update);
    observer.observe(host);
    return () => observer.disconnect();
  }, []);

  useEffect(() => {
    setManualLeftWidth(null);
  }, [selectedDevice.installId]);

  useEffect(() => {
    setInfoHeight((current) => clampPaneSize(current, minInfoPanelHeight(hostSize), maxInfoPanelHeight(hostSize)));
  }, [hostSize]);

  const startDeviceResize = useCallback(
    (event: ReactPointerEvent<HTMLDivElement>) => {
      event.preventDefault();
      const pointerId = event.pointerId;
      event.currentTarget.setPointerCapture(pointerId);
      const startX = event.clientX;
      const startWidth = leftWidth;
      const minWidth = minDevicePaneWidth(hostSize);
      const maxWidth = maxDevicePaneWidth(hostSize);

      const onMove = (moveEvent: PointerEvent) => {
        setManualLeftWidth(clampPaneSize(startWidth + moveEvent.clientX - startX, minWidth, maxWidth));
      };
      const onUp = () => {
        window.removeEventListener('pointermove', onMove);
        window.removeEventListener('pointerup', onUp);
        window.removeEventListener('pointercancel', onUp);
      };
      window.addEventListener('pointermove', onMove);
      window.addEventListener('pointerup', onUp);
      window.addEventListener('pointercancel', onUp);
    },
    [hostSize, leftWidth],
  );

  const startInfoResize = useCallback(
    (event: ReactPointerEvent<HTMLDivElement>) => {
      event.preventDefault();
      const pointerId = event.pointerId;
      event.currentTarget.setPointerCapture(pointerId);
      const startY = event.clientY;
      const startHeight = infoHeight;
      const minHeight = minInfoPanelHeight(hostSize);
      const maxHeight = maxInfoPanelHeight(hostSize);

      const onMove = (moveEvent: PointerEvent) => {
        setInfoHeight(clampPaneSize(startHeight + startY - moveEvent.clientY, minHeight, maxHeight));
      };
      const onUp = () => {
        window.removeEventListener('pointermove', onMove);
        window.removeEventListener('pointerup', onUp);
        window.removeEventListener('pointercancel', onUp);
      };
      window.addEventListener('pointermove', onMove);
      window.addEventListener('pointerup', onUp);
      window.addEventListener('pointercancel', onUp);
    },
    [hostSize, infoHeight],
  );

  return (
    <section
      ref={hostRef}
      className="grid min-h-0 flex-1 overflow-hidden bg-[#f5f5f5] text-[#111]"
      style={{ gridTemplateColumns: `${leftWidth}px 6px minmax(0,1fr)` }}
    >
      <DeviceFrame device={selectedDevice} />
      <div
        role="separator"
        aria-label="Resize screen pane"
        className="relative z-20 cursor-col-resize border-r border-[#cfcfcf] bg-[#f5f5f5] hover:bg-[#dceaff]"
        onPointerDown={startDeviceResize}
      />
      <div className="grid min-h-0" style={{ gridTemplateRows: `minmax(0,1fr) 6px ${infoHeight}px` }}>
        <TerminalStage device={selectedDevice} onEvent={onEvent} onRefreshDevices={onRefreshDevices} />
        <div
          role="separator"
          aria-label="Resize info pane"
          className="relative z-20 cursor-row-resize border-y border-[#cfcfcf] bg-[#f5f5f5] hover:bg-[#dceaff]"
          onPointerDown={startInfoResize}
        />
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

function minDevicePaneWidth(hostSize: { width: number; height: number }) {
  return Math.min(220, Math.max(160, hostSize.width - 360));
}

function maxDevicePaneWidth(hostSize: { width: number; height: number }) {
  if (!hostSize.width) return 640;
  return Math.max(minDevicePaneWidth(hostSize), Math.min(hostSize.width - 360, Math.round(hostSize.width * 0.72)));
}

function minInfoPanelHeight(hostSize: { width: number; height: number }) {
  return Math.min(96, Math.max(72, hostSize.height - 260));
}

function maxInfoPanelHeight(hostSize: { width: number; height: number }) {
  if (!hostSize.height) return 360;
  return Math.max(minInfoPanelHeight(hostSize), hostSize.height - 220);
}

function clampPaneSize(value: number, min: number, max: number) {
  return Math.round(Math.max(min, Math.min(value, max)));
}

function InfoPanel({ device }: { device: MiraDevice }) {
  const platform = devicePlatform(device);
  const rows: Array<[string, string]> = [];
  addKnownRow(rows, 'Architecture', device.arch);
  addKnownRow(rows, 'Model', modelSummary(device));
  rows.push(['Device ID', shortId(device.installId, 36)]);
  addKnownRow(rows, 'Screen', screenStateText(device));
  rows.push(...currentSurfaceRows(device, platform));

  return (
    <section className="grid h-full min-h-0 grid-cols-[minmax(0,1fr)_180px] border-t border-[#cfcfcf] bg-[#f5f5f5] text-[#111]">
      <div className="h-full overflow-auto px-3 py-2 font-mono text-[12px] leading-5">
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

function addKnownRow(rows: Array<[string, string]>, key: string, value: string | number | null | undefined) {
  if (value === null || value === undefined) return;
  const text = String(value).trim();
  if (!text || text === 'unknown' || text === 'not reported') return;
  rows.push([key, text]);
}

type DevicePlatform = 'android' | 'ios' | 'unknown';

function devicePlatform(device: MiraDevice): DevicePlatform {
  const platform = `${device.platform || ''} ${device.osName || ''}`.toLowerCase();
  if (platform.includes('ios')) return 'ios';
  if (platform.includes('android')) return 'android';

  const model = String(device.model || '').toLowerCase();
  const packageName = String(device.packageName || '').toLowerCase();
  if (model === 'ios' || model.includes('iphone') || model.includes('ipad') || packageName.endsWith('.ios')) return 'ios';
  if (device.androidIdHash || device.outline?.activityName) return 'android';
  return 'unknown';
}

function modelSummary(device: MiraDevice) {
  const model = String(device.model || device.deviceName || '').trim();
  if (!model) return null;
  const details = [systemVersionText(device), screenSizeText(device)].filter(Boolean);
  if (!details.length) return model;
  return `${model} (${details.join(', ')})`;
}

function systemVersionText(device: MiraDevice): string | null {
  const osName = String(device.osName || device.platform || '').trim();
  const osVersion = String(device.osVersion || '').trim();
  if (osName && osVersion) return `${osName} ${osVersion}`;
  if (osVersion) return osVersion;
  if (isAndroidDevice(device) && device.sdk) return androidVersionText(device.sdk);
  return null;
}

function isAndroidDevice(device: MiraDevice) {
  return devicePlatform(device) === 'android';
}

function androidVersionText(sdk: number | string) {
  const apiLevel = Number(sdk);
  const release = androidReleaseByApi[apiLevel];
  if (release) return `Android ${release}`;
  return Number.isFinite(apiLevel) && apiLevel > 0 ? `Android SDK ${Math.round(apiLevel)}` : null;
}

const androidReleaseByApi: Record<number, string> = {
  21: '5.0',
  22: '5.1',
  23: '6.0',
  24: '7.0',
  25: '7.1',
  26: '8.0',
  27: '8.1',
  28: '9',
  29: '10',
  30: '11',
  31: '12',
  32: '12L',
  33: '13',
  34: '14',
  35: '15',
  36: '16',
};

function screenSizeText(device: MiraDevice) {
  const outlineScreen = device.outline?.screen;
  const info = device.screenInfo;
  const width = positiveNumber(info?.sourceWidth) ?? positiveNumber(outlineScreen?.width) ?? positiveNumber(device.outline?.width);
  const height = positiveNumber(info?.sourceHeight) ?? positiveNumber(outlineScreen?.height) ?? positiveNumber(device.outline?.height);
  return width && height ? `${width}x${height}` : null;
}

function screenStateText(device: MiraDevice) {
  if (device.screenSource || device.screenInfo || device.screenLastSeen || device.outline) return 'on,unlocked';
  return null;
}

function currentSurfaceRows(device: MiraDevice, platform: DevicePlatform): Array<[string, string]> {
  if (platform === 'ios') {
    const rows: Array<[string, string]> = [];
    addKnownRow(rows, 'Application', device.packageName || device.outline?.packageName);
    addKnownRow(rows, 'View', iosViewText(device));
    return rows;
  }

  const rows: Array<[string, string]> = [];
  addKnownRow(rows, 'Application', device.outline?.packageName || device.packageName);
  addKnownRow(rows, 'Activity', device.outline?.activityName);
  return rows;
}

function iosViewText(device: MiraDevice) {
  if (device.screenSource === 'app-key-window') return 'App key window';
  return device.screenSource || 'App view';
}

function positiveNumber(value: unknown) {
  const numberValue = Number(value);
  return Number.isFinite(numberValue) && numberValue > 0 ? Math.round(numberValue) : null;
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
      net: Math.max(0, Number(metrics.networkBps) || 0),
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
  const netScale = Math.max(1024, ...history.map((point) => point.net)) * 1.25;

  return (
    <div className="grid h-full min-h-0 grid-rows-3 border-l border-[#d8d8d8] bg-[#f5f5f5] font-mono text-[10px] leading-3 text-[#555]">
      <MetricChart label="CPU" value={latest?.cpu ?? -1} history={history.map((point) => point.cpu)} stale={stale} color="#59ca58" />
      <MetricChart label="MEM" value={latest?.mem ?? -1} history={history.map((point) => point.mem)} stale={stale} color="#3f7fd3" />
      <MetricChart label="NET" value={netBps} history={history.map((point) => point.net)} stale={stale} format={formatBytesPerSecond} scaleMax={netScale} color="#e29b3f" />
    </div>
  );
}

function MetricChart({
  label,
  value,
  history,
  stale,
  format = formatPercent,
  scaleMax = 100,
  color,
}: {
  label: string;
  value: number;
  history: number[];
  stale: boolean;
  format?: (value: number) => string;
  scaleMax?: number;
  color: string;
}) {
  return (
    <div className="grid min-h-0 grid-cols-[1fr_54px] items-stretch gap-1 border-b border-[#e1e1e1] px-1 py-1 last:border-b-0">
      <svg viewBox="0 0 104 36" className="h-full w-full overflow-visible">
        <path d={sparkPath(history, 104, 36, scaleMax)} fill="none" stroke={stale ? '#bdbdbd' : color} strokeWidth="1.3" />
        <line x1="0" y1="35" x2="104" y2="35" stroke="#d7d7d7" strokeWidth="0.8" />
      </svg>
      <div className="flex flex-col justify-center text-right">
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

function sparkPath(values: number[], width: number, height: number, maxValue = 100) {
  if (!values.length) return '';
  const scale = Math.max(1, maxValue);
  if (values.length === 1) {
    const y = height - (Math.max(0, Math.min(scale, values[0])) / scale) * height;
    return `M 0 ${y.toFixed(1)} L ${width} ${y.toFixed(1)}`;
  }
  return values
    .map((value, index) => {
      const x = (index / Math.max(1, values.length - 1)) * width;
      const y = height - (Math.max(0, Math.min(scale, value)) / scale) * height;
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
