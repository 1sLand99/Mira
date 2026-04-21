import clsx from 'clsx';
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
        'grid w-full grid-cols-[minmax(120px,1fr)_96px_92px] gap-2 border p-2 text-left font-mono text-[12px]',
        selected ? 'border-[#3f7fd3] bg-[#eef5ff]' : 'border-[#cfcfcf] bg-white hover:bg-[#f3f7ff]',
        offline && 'opacity-60',
      )}
    >
      <span className="truncate font-semibold text-[#111]">{deviceTitle(device)}</span>
      <span className="truncate text-[#555]">{shortId(device.installId)}</span>
      <StatusPill state={device.state || 'unknown'} />
    </button>
  );
}
