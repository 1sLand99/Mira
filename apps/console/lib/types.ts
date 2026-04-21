export type DeviceState = 'idle' | 'opening' | 'active' | 'offline' | 'unknown' | string;

export type MiraDevice = {
  type?: string;
  protocol?: number;
  installId: string;
  deviceName?: string;
  packageName?: string;
  androidIdHash?: string;
  model?: string;
  sdk?: number;
  arch?: string;
  state?: DeviceState;
  transport?: string;
  address?: string;
  wakeUrl?: string;
};

export type DevicesResponse = {
  devices: MiraDevice[];
};

export type OpenSessionResponse = {
  sessionId: string;
};

export type SessionStatus = 'idle' | 'opening' | 'active' | 'waiting for device' | 'device disconnected' | 'closed' | string;
