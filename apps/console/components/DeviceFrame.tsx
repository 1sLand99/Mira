import type { MiraDevice } from '@/lib/types';
import { OutlineViewer } from './OutlineViewer';

export function DeviceFrame({ device }: { device: MiraDevice }) {
  return (
    <section className="h-full min-h-0 border-r border-[#cfcfcf] bg-[#111]">
      <OutlineViewer outline={device.outline} className="h-full min-h-0 border-0" />
    </section>
  );
}
