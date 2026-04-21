import type { MiraDevice } from './types';

export function shortId(value?: string, size = 8): string {
  if (!value) return 'unknown';
  return value.slice(0, size);
}

export function deviceTitle(device?: MiraDevice | null): string {
  if (!device) return 'No device';
  return device.deviceName || device.model || 'Mira Device';
}

export function stateTone(state?: string): 'good' | 'warn' | 'bad' | 'muted' {
  if (state === 'active' || state === 'idle') return 'good';
  if (state === 'opening' || state === 'waiting for device') return 'warn';
  if (state === 'offline' || state === 'device disconnected') return 'bad';
  return 'muted';
}

export function copyText(text: string): Promise<void> {
  if (navigator.clipboard) return navigator.clipboard.writeText(text);
  const area = document.createElement('textarea');
  area.value = text;
  document.body.appendChild(area);
  area.select();
  document.execCommand('copy');
  area.remove();
  return Promise.resolve();
}
