import clsx from 'clsx';
import { Cpu, Radio, Smartphone } from 'lucide-react';
import type { MiraDevice } from '@/lib/types';
import { deviceTitle, shortId } from '@/lib/format';
import { StatusPill } from './StatusPill';

export function DeviceCard({
  device,
  selected,
  onSelect,
}: {
  device: MiraDevice;
  selected?: boolean;
  onSelect: (device: MiraDevice) => void;
}) {
  const offline = device.state === 'offline';
  return (
    <button
      type="button"
      onClick={() => onSelect(device)}
      className={clsx(
        'group w-full rounded-3xl border p-4 text-left transition duration-200',
        'bg-slate-950/45 hover:-translate-y-0.5 hover:border-emerald-300/30 hover:bg-slate-900/80 hover:shadow-[0_18px_60px_rgba(0,0,0,0.28)]',
        selected ? 'border-emerald-300/50 shadow-[0_0_0_1px_rgba(52,211,153,0.24),0_24px_80px_rgba(16,185,129,0.10)]' : 'border-white/10',
        offline && 'opacity-65',
      )}
    >
      <div className="flex items-start justify-between gap-3">
        <div className="flex min-w-0 items-center gap-3">
          <div className="grid h-11 w-11 shrink-0 place-items-center rounded-2xl border border-white/10 bg-white/[0.035] text-emerald-300">
            <Smartphone size={20} />
          </div>
          <div className="min-w-0">
            <div className="truncate text-base font-semibold text-slate-100">{deviceTitle(device)}</div>
            <div className="mt-1 font-mono text-[11px] text-slate-500">{shortId(device.installId)}</div>
          </div>
        </div>
        <StatusPill state={device.state || 'unknown'} />
      </div>
      <div className="mt-4 grid grid-cols-2 gap-2 text-xs text-slate-400">
        <div className="rounded-2xl bg-white/[0.035] px-3 py-2">
          <div className="mb-1 flex items-center gap-1.5 text-slate-500"><Cpu size={13} /> ABI</div>
          <div className="truncate font-mono text-slate-200">{device.arch || 'unknown'}</div>
        </div>
        <div className="rounded-2xl bg-white/[0.035] px-3 py-2">
          <div className="mb-1 flex items-center gap-1.5 text-slate-500"><Radio size={13} /> Transport</div>
          <div className="truncate font-mono text-slate-200">{device.transport || 'legacy'}</div>
        </div>
      </div>
      <div className="mt-3 flex items-center justify-between text-xs text-slate-500">
        <span className="truncate">{device.address || 'no address'}</span>
        <span className="font-semibold text-emerald-300/80 opacity-0 transition group-hover:opacity-100">Enter</span>
      </div>
    </button>
  );
}
