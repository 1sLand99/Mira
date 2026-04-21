import clsx from 'clsx';
import { stateTone } from '@/lib/format';

export function StatusPill({ state, label }: { state?: string; label?: string }) {
  const tone = stateTone(state);
  return (
    <span
      className={clsx(
        'inline-flex items-center gap-1 border px-1.5 py-0.5 font-mono text-[10px] uppercase tracking-[0.12em]',
        tone === 'good' && 'border-[#23a06f] bg-[#e9fff6] text-[#0f6d4a]',
        tone === 'warn' && 'border-[#b7791f] bg-[#fff7e6] text-[#7a4c00]',
        tone === 'bad' && 'border-[#c0392b] bg-[#fff0ef] text-[#8f1f15]',
        tone === 'muted' && 'border-[#999] bg-[#f2f2f2] text-[#555]',
      )}
    >
      <span
        className={clsx(
          'inline-block h-1.5 w-1.5',
          tone === 'good' && 'bg-[#23a06f]',
          tone === 'warn' && 'bg-[#b7791f]',
          tone === 'bad' && 'bg-[#c0392b]',
          tone === 'muted' && 'bg-[#777]',
        )}
      />
      {label || state || 'unknown'}
    </span>
  );
}
