'use client';

import clsx from 'clsx';
import { useCallback, useEffect, useRef, useState } from 'react';
import type { ClipboardEvent, CompositionEvent, FormEvent, KeyboardEvent as ReactKeyboardEvent, MouseEvent, ReactNode } from 'react';
import { latestScreenFrame, postBrowserLog, screenVideoWsUrl, sendScreenInput } from '@/lib/relay';
import type { MiraDevice, ScreenFrame, ScreenInputKind, ScreenInputResponse, ScreenVideoInfo } from '@/lib/types';

type LiveStatus = 'connecting' | 'waiting' | 'live' | 'error' | 'unsupported';
type RenderMode = 'canvas' | 'snapshot';

type VideoPacket = {
  keyFrame: boolean;
  seq: number;
  timestamp: number;
  data: Uint8Array;
  nalTypes: number[];
};

type DebugInfo = {
  title: string;
  message: string;
  codec?: string;
  width?: number;
  height?: number;
  seq?: number;
  keyFrame?: boolean;
  timestamp?: number;
  nalTypes?: number[];
  packetHead?: string;
  decoderState?: string;
  at: string;
};

type ScreenInputPayload =
  | { kind: 'tap'; x: number; y: number }
  | { kind: 'text'; text: string }
  | { kind: 'paste'; text: string }
  | { kind: 'key'; key: string }
  | { kind: 'copy' }
  | { kind: 'selectall' }
  | { kind: 'clear' };

const PACKET_HEADER_BYTES = 20;
const STALE_MS = 2500;
const SNAPSHOT_POLL_INTERVAL_MS = 1000;
const REMOTE_KEY_NAMES = new Set(['Backspace', 'Delete', 'Enter', 'Tab', 'Escape', 'ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown', 'Home', 'End']);

export function LiveScreenViewer({ device, fallback, className }: { device: MiraDevice; fallback: ReactNode; className?: string }) {
  const hostRef = useRef<HTMLDivElement | null>(null);
  const inputTrapRef = useRef<HTMLTextAreaElement | null>(null);
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const socketRef = useRef<WebSocket | null>(null);
  const decoderRef = useRef<any>(null);
  const infoRef = useRef<ScreenVideoInfo | null>(null);
  const retryTimerRef = useRef<number | null>(null);
  const snapshotTimerRef = useRef<number | null>(null);
  const snapshotInFlightRef = useRef(false);
  const lastSnapshotSeqRef = useRef(0);
  const lastSnapshotUrlRef = useRef('');
  const lastFrameAtRef = useRef(0);
  const waitingForKeyFrameRef = useRef(true);
  const renderModeRef = useRef<RenderMode>('canvas');
  const composingInputRef = useRef(false);
  const clientIdRef = useRef(`screen-${Math.random().toString(36).slice(2)}-${Date.now().toString(36)}`);
  const requestSeqRef = useRef(0);
  const pendingInputRequestsRef = useRef(new Set<string>());
  const logSeqRef = useRef(0);
  const [info, setInfo] = useState<ScreenVideoInfo | null>(null);
  const [status, setStatus] = useState<LiveStatus>('connecting');
  const [streamError, setStreamError] = useState<string | null>(null);
  const [renderMode, setRenderMode] = useState<RenderMode>('canvas');
  const [snapshotUrl, setSnapshotUrl] = useState<string | null>(null);
  const [debugInfo, setDebugInfo] = useState<DebugInfo | null>(null);
  const [showDebug, setShowDebug] = useState(false);
  const [, setInputStatus] = useState('input ready');
  const [, setLastSeq] = useState(0);
  const [now, setNow] = useState(() => Date.now());

  useEffect(() => {
    const timer = window.setInterval(() => setNow(Date.now()), 500);
    return () => window.clearInterval(timer);
  }, []);

  useEffect(() => {
    renderModeRef.current = renderMode;
  }, [renderMode]);

  const browserLog = useCallback(
    (scope: string, message: string, details?: Record<string, unknown>) => {
      const payload = {
        seq: ++logSeqRef.current,
        ...details,
      };
      void postBrowserLog(scope, message, device.installId, payload).catch(() => {});
    },
    [device.installId],
  );

  const closeDecoder = useCallback(() => {
    const decoder = decoderRef.current;
    decoderRef.current = null;
    if (!decoder) return;
    try {
      decoder.close();
    } catch {
      // ignore decoder close races
    }
  }, []);

  const stopSnapshotPolling = useCallback(() => {
    if (snapshotTimerRef.current !== null) {
      window.clearInterval(snapshotTimerRef.current);
      snapshotTimerRef.current = null;
    }
  }, []);

  const frameFromScreenFrame = useCallback((frame: ScreenFrame): ScreenVideoInfo => {
    return {
      type: 'screen.video.info',
      protocol: frame.protocol,
      installId: frame.installId,
      deviceName: frame.deviceName,
      codec: frame.format || 'jpeg',
      width: frame.sourceWidth || frame.width,
      height: frame.sourceHeight || frame.height,
      sourceWidth: frame.sourceWidth,
      sourceHeight: frame.sourceHeight,
      transport: 'http',
      receivedAt: typeof frame.receivedAt === 'number' ? frame.receivedAt : frame.receivedAt ? Number(frame.receivedAt) : undefined,
      format: frame.format,
    };
  }, []);

  const loadSnapshotFrame = useCallback(async () => {
    if (snapshotInFlightRef.current || renderModeRef.current !== 'snapshot') return;
    snapshotInFlightRef.current = true;
    try {
      const frame = await latestScreenFrame(device.installId);
      if (!frame || !frame.dataBase64) return;
      const seq = Number(frame.seq) || 0;
      if (seq !== lastSnapshotSeqRef.current || frame.dataBase64 !== lastSnapshotUrlRef.current) {
        const nextDataUrl = `data:image/jpeg;base64,${frame.dataBase64}`;
        setSnapshotUrl(nextDataUrl);
        lastSnapshotUrlRef.current = frame.dataBase64;
      }
      const nextInfo = frameFromScreenFrame(frame);
      infoRef.current = nextInfo;
      setInfo(nextInfo);
      lastSnapshotSeqRef.current = seq;
      lastFrameAtRef.current = Date.now();
      setStatus('live');
      setNow(Date.now());
      setStreamError(null);
    } catch (snapshotError) {
      browserLog('screen.snapshot', 'latestScreenFrame failed', {
        error: errorMessage(snapshotError),
      });
      setStatus((previous) => (previous === 'connecting' ? previous : 'unsupported'));
      setDebugInfo({
        title: 'Snapshot fallback failed',
        message: errorMessage(snapshotError),
        at: new Date().toLocaleTimeString(),
      });
      setShowDebug(true);
      console.error('Mira screen snapshot fallback failed', snapshotError);
    } finally {
      snapshotInFlightRef.current = false;
    }
  }, [browserLog, device.installId, frameFromScreenFrame]);

  const startSnapshotPolling = useCallback(() => {
    stopSnapshotPolling();
    loadSnapshotFrame();
    snapshotTimerRef.current = window.setInterval(() => {
      void loadSnapshotFrame();
    }, SNAPSHOT_POLL_INTERVAL_MS);
  }, [loadSnapshotFrame, stopSnapshotPolling]);

  const switchToSnapshotMode = useCallback(() => {
    if (renderModeRef.current === 'snapshot') return;
    browserLog('screen.decoder', 'switchToSnapshotMode', {
      userAgent: typeof navigator !== 'undefined' ? navigator.userAgent : '',
      hasVideoDecoder: typeof (window as unknown as { VideoDecoder?: unknown }).VideoDecoder !== 'undefined',
      hasEncodedVideoChunk: typeof (window as unknown as { EncodedVideoChunk?: unknown }).EncodedVideoChunk !== 'undefined',
    });
    closeDecoder();
    setRenderMode('snapshot');
    setStatus('unsupported');
    setStreamError(null);
    setShowDebug(false);
    startSnapshotPolling();
    setDebugInfo({
      title: 'WebCodecs unavailable',
      message: 'This browser cannot decode H.264 via WebCodecs. Fallback to JPEG snapshot is running.',
      at: new Date().toLocaleTimeString(),
    });
  }, [browserLog, closeDecoder, startSnapshotPolling]);

  const configureDecoder = useCallback(
    async (nextInfo: ScreenVideoInfo) => {
      const VideoDecoderCtor = (window as unknown as { VideoDecoder?: any }).VideoDecoder;
      if (!VideoDecoderCtor || typeof (window as unknown as { EncodedVideoChunk?: unknown }).EncodedVideoChunk === 'undefined') {
        browserLog('screen.decoder', 'webcodecs unavailable', {
          hasVideoDecoder: Boolean(VideoDecoderCtor),
          hasEncodedVideoChunk: typeof (window as unknown as { EncodedVideoChunk?: unknown }).EncodedVideoChunk !== 'undefined',
          userAgent: typeof navigator !== 'undefined' ? navigator.userAgent : '',
        });
        setStatus('unsupported');
        switchToSnapshotMode();
        return;
      }
      const width = Number(nextInfo.width) || 0;
      const height = Number(nextInfo.height) || 0;
      if (width <= 0 || height <= 0) return;

      closeDecoder();
      waitingForKeyFrameRef.current = true;
      const canvas = canvasRef.current;
      if (canvas) {
        canvas.width = width;
        canvas.height = height;
      }
      const decoder = new VideoDecoderCtor({
        output: (frame: any) => {
          const target = canvasRef.current;
          const context = target?.getContext('2d');
          if (target && context) {
            context.drawImage(frame, 0, 0, target.width, target.height);
            lastFrameAtRef.current = Date.now();
            setStatus('live');
            setNow(Date.now());
          }
          frame.close();
        },
        error: (decodeError: unknown) => {
          waitingForKeyFrameRef.current = true;
          const message = errorMessage(decodeError);
          console.error('Mira screen decoder error', decodeError, infoRef.current);
          setStatus('error');
          setStreamError(message);
          setDebugInfo({
            title: 'Decoder error',
            message,
            codec: infoRef.current?.codec,
            width: infoRef.current?.width,
            height: infoRef.current?.height,
            decoderState: decoderRef.current?.state,
            at: new Date().toLocaleTimeString(),
          });
          setShowDebug(true);
        },
      });
      const config = {
        codec: nextInfo.codec || 'avc1.42E01E',
        codedWidth: width,
        codedHeight: height,
        avc: { format: 'annexb' },
        optimizeForLatency: true,
        hardwareAcceleration: 'prefer-hardware',
      };
      const support = typeof VideoDecoderCtor.isConfigSupported === 'function' ? await VideoDecoderCtor.isConfigSupported(config).catch(() => null) : null;
      browserLog('screen.decoder', 'decoder support checked', {
        codec: config.codec,
        width,
        height,
        support,
      });
      if (support && support.supported === false) {
        setStatus('unsupported');
        setStreamError(`decoder unsupported: ${config.codec}`);
        switchToSnapshotMode();
        console.error('Mira screen decoder unsupported', config, support);
        setDebugInfo({
          title: 'Decoder unsupported',
          message: JSON.stringify(support),
          codec: config.codec,
          width,
          height,
          at: new Date().toLocaleTimeString(),
        });
        setShowDebug(true);
        return;
      }
      setRenderMode('canvas');
      stopSnapshotPolling();
      setSnapshotUrl(null);
      console.info('Mira screen decoder configure', config, support);
      decoder.configure(config);
      decoderRef.current = decoder;
    },
    [browserLog, closeDecoder, stopSnapshotPolling, switchToSnapshotMode],
  );

  const handleInputResult = useCallback((message: Partial<ScreenInputResponse> & { type?: string }) => {
    const requestId = typeof message.requestId === 'string' ? message.requestId : '';
    const clientId = typeof message.clientId === 'string' ? message.clientId : '';
    if (clientId && clientId !== clientIdRef.current) return;
    if (!clientId && requestId && !pendingInputRequestsRef.current.has(requestId)) return;

    const kind = String(message.kind || 'input') as ScreenInputKind;
    const label = inputLabel(kind);
    if (message.type === 'screen.input.queued') {
      if (message.ok) {
        setInputStatus(`${label} queued`);
      } else {
        if (requestId) pendingInputRequestsRef.current.delete(requestId);
        setInputStatus(`${label} failed: ${message.error || message.message || 'relay rejected'}`);
      }
      return;
    }

    if (requestId) pendingInputRequestsRef.current.delete(requestId);
    if (kind === 'copy' && message.ok) {
      const text = typeof message.text === 'string' ? message.text : '';
      if (navigator.clipboard?.writeText) {
        navigator.clipboard
          .writeText(text)
          .then(() => setInputStatus(`copy ${text.length} chars`))
          .catch((copyError: unknown) => setInputStatus(`copy failed: clipboard denied: ${errorMessage(copyError)}`));
      } else {
        setInputStatus('copy failed: clipboard unavailable');
      }
      return;
    }
    setInputStatus(message.ok ? `${label} ok: ${message.message || 'done'}` : `${label} failed: ${message.error || message.message || 'input failed'}`);
  }, []);

  const sendRemoteInput = useCallback(
    async (payload: ScreenInputPayload) => {
      const requestId = `${clientIdRef.current}-${++requestSeqRef.current}`;
      pendingInputRequestsRef.current.add(requestId);
      const message = {
        type: 'screen.input',
        protocol: 1,
        installId: device.installId,
        requestId,
        clientId: clientIdRef.current,
        ...payload,
      };
      const label = inputLabel(payload.kind);
      setInputStatus(`${label} sending`);
      const socket = socketRef.current;
      if (socket && socket.readyState === WebSocket.OPEN) {
        socket.send(JSON.stringify(message));
        return requestId;
      }
      if (payload.kind === 'copy') {
        pendingInputRequestsRef.current.delete(requestId);
        setInputStatus('copy failed: websocket disconnected');
        return requestId;
      }
      try {
        const response = await sendScreenInput(message);
        handleInputResult({ ...response, type: 'screen.input.queued' });
      } catch (inputError) {
        pendingInputRequestsRef.current.delete(requestId);
        setInputStatus(`${label} failed: ${errorMessage(inputError)}`);
      }
      return requestId;
    },
    [device.installId, handleInputResult],
  );

  const pasteClipboardToRemote = useCallback(async () => {
    try {
      if (!navigator.clipboard?.readText) {
        setInputStatus('paste failed: clipboard unavailable');
        return;
      }
      const text = await navigator.clipboard.readText();
      if (!text) {
        setInputStatus('paste skipped: clipboard empty');
        return;
      }
      await sendRemoteInput({ kind: 'paste', text });
    } catch (pasteError) {
      setInputStatus(`paste failed: ${errorMessage(pasteError)}`);
    }
  }, [sendRemoteInput]);

  const focusScreenInput = useCallback(() => {
    const inputTrap = inputTrapRef.current;
    if (inputTrap) {
      inputTrap.focus({ preventScroll: true });
      return;
    }
    hostRef.current?.focus({ preventScroll: true });
  }, []);

  const connect = useCallback(() => {
    browserLog('screen.ws', 'connect invoked', {
      renderMode: renderModeRef.current,
      wsUrl: screenVideoWsUrl(),
    });
    if (retryTimerRef.current !== null) {
      window.clearTimeout(retryTimerRef.current);
      retryTimerRef.current = null;
    }
    const oldSocket = socketRef.current;
    if (oldSocket) oldSocket.close();
    closeDecoder();
    stopSnapshotPolling();
    infoRef.current = null;
    setInfo(null);
    setRenderMode('canvas');
    setSnapshotUrl(null);
    lastSnapshotSeqRef.current = 0;
    lastSnapshotUrlRef.current = '';
    setStatus('connecting');
    setStreamError(null);
    setDebugInfo(null);
    setShowDebug(false);
    setLastSeq(0);
    lastFrameAtRef.current = 0;
    waitingForKeyFrameRef.current = true;

    const socket = new WebSocket(screenVideoWsUrl());
    socket.binaryType = 'arraybuffer';
    socketRef.current = socket;

    socket.addEventListener('open', () => {
      browserLog('screen.ws', 'socket open');
      setStatus('waiting');
      socket.send(JSON.stringify({ type: 'screen.browser.attach', protocol: 1, installId: device.installId }));
    });
    socket.addEventListener('message', (event) => {
      if (typeof event.data === 'string') {
        let message: ScreenVideoInfo & Partial<ScreenInputResponse> & { type?: string };
        try {
          message = JSON.parse(event.data) as ScreenVideoInfo & Partial<ScreenInputResponse> & { type?: string };
        } catch {
          return;
        }
        if (message.type === 'screen.video.info') {
          browserLog('screen.ws', 'screen.video.info', {
            codec: message.codec,
            width: message.width,
            height: message.height,
            format: message.format,
          });
          infoRef.current = message;
          setInfo(message);
          setStatus('waiting');
          setStreamError(null);
          setDebugInfo(null);
          const VideoDecoderCtor = (window as unknown as { VideoDecoder?: any }).VideoDecoder;
          if (!VideoDecoderCtor) {
            setStatus('unsupported');
            switchToSnapshotMode();
            return;
          }
          void configureDecoder(message);
        } else if (message.type === 'screen.video.waiting') {
          setStatus('waiting');
        } else if (message.type === 'screen.video.close') {
          setStatus('waiting');
          closeDecoder();
        } else if (message.type === 'screen.input.result' || message.type === 'screen.input.queued') {
          handleInputResult(message);
        } else if (message.type === 'error') {
          browserLog('screen.ws', 'socket error message', {
            error: message.error,
          });
          setStatus('error');
          setStreamError(message.error || 'screen relay error');
        }
        return;
      }
      const packet = parseVideoPacket(event.data);
      const decoder = decoderRef.current;
      const EncodedVideoChunkCtor = (window as unknown as { EncodedVideoChunk?: any }).EncodedVideoChunk;
      if (!packet || !decoder || !EncodedVideoChunkCtor || decoder.state !== 'configured') return;
      if (waitingForKeyFrameRef.current && !packet.keyFrame) return;
      if (packet.keyFrame) waitingForKeyFrameRef.current = false;
      try {
        const chunk = new EncodedVideoChunkCtor({
          type: packet.keyFrame ? 'key' : 'delta',
          timestamp: packet.timestamp,
          data: packet.data,
        });
        decoder.decode(chunk);
        setLastSeq(packet.seq);
      } catch (decodeError) {
        browserLog('screen.decoder', 'decode enqueue failed', {
          error: errorMessage(decodeError),
          seq: packet.seq,
          codec: infoRef.current?.codec,
        });
        waitingForKeyFrameRef.current = true;
        const message = errorMessage(decodeError);
        const packetHead = Array.from(packet.data.slice(0, 32)).map((value) => value.toString(16).padStart(2, '0')).join(' ');
        console.error('Mira screen decode enqueue failed', decodeError, {
          seq: packet.seq,
          keyFrame: packet.keyFrame,
          timestamp: packet.timestamp,
          nalTypes: packet.nalTypes,
          head: packetHead,
          info: infoRef.current,
        });
        setStatus('error');
        setStreamError(message);
        setDebugInfo({
          title: 'Decode enqueue failed',
          message,
          codec: infoRef.current?.codec,
          width: infoRef.current?.width,
          height: infoRef.current?.height,
          seq: packet.seq,
          keyFrame: packet.keyFrame,
          timestamp: packet.timestamp,
          nalTypes: packet.nalTypes,
          packetHead,
          decoderState: decoder.state,
          at: new Date().toLocaleTimeString(),
        });
        setShowDebug(true);
      }
    });
    socket.addEventListener('close', () => {
      browserLog('screen.ws', 'socket close', {
        activeSocket: socketRef.current === socket,
        renderMode: renderModeRef.current,
      });
      if (socketRef.current !== socket) return;
      setStatus('waiting');
      closeDecoder();
      if (renderModeRef.current === 'snapshot') startSnapshotPolling();
      retryTimerRef.current = window.setTimeout(connect, 1000);
    });
    socket.addEventListener('error', () => {
      browserLog('screen.ws', 'socket error event');
      setStatus('error');
      setStreamError('screen websocket error');
    });
  }, [browserLog, closeDecoder, configureDecoder, device.installId, handleInputResult, startSnapshotPolling, stopSnapshotPolling, switchToSnapshotMode]);

  useEffect(() => {
    browserLog('screen.lifecycle', 'effect mount');
    connect();
    return () => {
      browserLog('screen.lifecycle', 'effect cleanup');
      if (retryTimerRef.current !== null) window.clearTimeout(retryTimerRef.current);
      const socket = socketRef.current;
      socketRef.current = null;
      if (socket) socket.close();
      closeDecoder();
      stopSnapshotPolling();
    };
  }, [closeDecoder, connect, stopSnapshotPolling]);

  const handleClick = useCallback(
    (event: MouseEvent<HTMLDivElement>) => {
      const currentInfo = infoRef.current;
      if (!currentInfo?.width || !currentInfo?.height) return;
      const host = hostRef.current;
      if (!host) return;
      focusScreenInput();
      const rect = host.getBoundingClientRect();
      const layout = computeContainLayout(currentInfo.width, currentInfo.height, rect.width, rect.height);
      if (!layout) return;
      const localX = event.clientX - rect.left - layout.offsetX;
      const localY = event.clientY - rect.top - layout.offsetY;
      if (localX < 0 || localY < 0 || localX > layout.width || localY > layout.height) return;
      const frameX = clamp(localX / layout.scale, 0, currentInfo.width - 1);
      const frameY = clamp(localY / layout.scale, 0, currentInfo.height - 1);
      const roundedX = Math.round(frameX);
      const roundedY = Math.round(frameY);
      void sendRemoteInput({ kind: 'tap', x: roundedX, y: roundedY });
    },
    [focusScreenInput, sendRemoteInput],
  );

  const handleKeyDown = useCallback(
    (event: ReactKeyboardEvent<HTMLDivElement>) => {
      if (event.defaultPrevented || isLocalFormTarget(event.target)) return;
      const host = hostRef.current;
      const active = document.activeElement;
      if (!host || !(active === host || (active instanceof Node && host.contains(active)))) return;
      const key = event.key;
      const shortcut = event.metaKey || event.ctrlKey;
      if (shortcut) {
        claimKeyboardEvent(event);
        const lowerKey = key.toLowerCase();
        if (lowerKey === 'a') {
          void sendRemoteInput({ kind: 'selectall' });
        } else if (lowerKey === 'v') {
          void pasteClipboardToRemote();
        } else if (lowerKey === 'c') {
          void sendRemoteInput({ kind: 'copy' });
        } else if (lowerKey === 'x') {
          void sendRemoteInput({ kind: 'copy' });
        } else {
          setInputStatus(`shortcut blocked: ${describeShortcut(event)}`);
        }
        return;
      }
      if (event.altKey) {
        claimKeyboardEvent(event);
        setInputStatus(`shortcut blocked: ${describeShortcut(event)}`);
        return;
      }
      if (key.length === 1) {
        claimKeyboardEvent(event);
        void sendRemoteInput({ kind: 'text', text: key });
        return;
      }
      if (REMOTE_KEY_NAMES.has(key)) {
        claimKeyboardEvent(event);
        void sendRemoteInput({ kind: 'key', key });
        return;
      }
      if (isBrowserShortcutKey(key)) {
        claimKeyboardEvent(event);
        setInputStatus(`shortcut blocked: ${key}`);
      }
    },
    [pasteClipboardToRemote, sendRemoteInput],
  );

  const handlePaste = useCallback(
    (event: ClipboardEvent<HTMLDivElement>) => {
      if (isLocalFormTarget(event.target)) return;
      const text = event.clipboardData.getData('text');
      if (!text) return;
      event.preventDefault();
      void sendRemoteInput({ kind: 'paste', text });
    },
    [sendRemoteInput],
  );

  const handleInputTrapKeyDown = useCallback(
    (event: ReactKeyboardEvent<HTMLTextAreaElement>) => {
      if (event.defaultPrevented) return;
      const key = event.key;
      const shortcut = event.metaKey || event.ctrlKey;
      if (shortcut) {
        const lowerKey = key.toLowerCase();
        if (lowerKey === 'v') return;
        claimKeyboardEvent(event);
        if (lowerKey === 'a') {
          void sendRemoteInput({ kind: 'selectall' });
        } else if (lowerKey === 'c') {
          void sendRemoteInput({ kind: 'copy' });
        } else if (lowerKey === 'x') {
          void sendRemoteInput({ kind: 'copy' });
        } else {
          setInputStatus(`shortcut blocked: ${describeShortcut(event)}`);
        }
        return;
      }
      if (event.altKey) {
        claimKeyboardEvent(event);
        setInputStatus(`shortcut blocked: ${describeShortcut(event)}`);
        return;
      }
      if (REMOTE_KEY_NAMES.has(key)) {
        claimKeyboardEvent(event);
        void sendRemoteInput({ kind: 'key', key });
        return;
      }
      if (isBrowserShortcutKey(key)) {
        claimKeyboardEvent(event);
        setInputStatus(`shortcut blocked: ${key}`);
      }
    },
    [sendRemoteInput],
  );

  const handleInputTrapInput = useCallback(
    (event: FormEvent<HTMLTextAreaElement>) => {
      const target = event.currentTarget;
      if (composingInputRef.current) return;
      const text = target.value;
      if (!text) return;
      target.value = '';
      void sendRemoteInput({ kind: 'text', text });
    },
    [sendRemoteInput],
  );

  const handleInputTrapPaste = useCallback(
    (event: ClipboardEvent<HTMLTextAreaElement>) => {
      const text = event.clipboardData.getData('text');
      if (!text) return;
      event.preventDefault();
      event.currentTarget.value = '';
      void sendRemoteInput({ kind: 'paste', text });
    },
    [sendRemoteInput],
  );

  const handleInputTrapCompositionStart = useCallback(() => {
    composingInputRef.current = true;
  }, []);

  const handleInputTrapCompositionEnd = useCallback(
    (event: CompositionEvent<HTMLTextAreaElement>) => {
      composingInputRef.current = false;
      const text = event.currentTarget.value;
      if (!text) return;
      event.currentTarget.value = '';
      void sendRemoteInput({ kind: 'text', text });
    },
    [sendRemoteInput],
  );

  const lastFrameAge = lastFrameAtRef.current ? now - lastFrameAtRef.current : 0;
  const stale = status === 'live' && lastFrameAge > STALE_MS;
  const showCanvas = renderMode === 'canvas' && Boolean(info && status === 'live');
  const showSnapshot = renderMode === 'snapshot' && Boolean(snapshotUrl);
  const showInactiveOverlay = status === 'connecting' || status === 'error' || status === 'unsupported' || (!showCanvas && !showSnapshot) || stale;
  const overlayDisplayText = (() => {
    if (status === 'unsupported' || renderMode === 'snapshot') {
      return 'WebCodecs unavailable, fallback to JPEG snapshot';
    }
    if (status === 'error') {
      return streamError || 'screen relay error';
    }
    if (status === 'connecting') {
      return 'Connecting to device screen stream';
    }
    if (status === 'waiting') {
      return 'Waiting for screen stream frames';
    }
    if (stale) {
      return `No frame update within ${lastFrameAge}ms, reconnecting`;
    }
    return 'Device is not in foreground';
  })();

  return (
    <div
      ref={hostRef}
      className={clsx('relative h-full min-h-[420px] cursor-crosshair select-none overflow-hidden bg-[#111] outline-none focus-within:ring-1 focus-within:ring-[#54d6bd]', className)}
      onMouseDownCapture={focusScreenInput}
      onClick={handleClick}
      onKeyDownCapture={handleKeyDown}
      onPaste={handlePaste}
      role="application"
      tabIndex={0}
    >
      <textarea
        ref={inputTrapRef}
        aria-label="Mira remote screen input"
        autoCapitalize="off"
        autoComplete="off"
        autoCorrect="off"
        spellCheck={false}
        className="pointer-events-none absolute left-0 top-0 z-10 h-px w-px resize-none overflow-hidden border-0 bg-transparent p-0 text-[1px] opacity-0 outline-none"
        onCompositionEnd={handleInputTrapCompositionEnd}
        onCompositionStart={handleInputTrapCompositionStart}
        onInput={handleInputTrapInput}
        onKeyDown={handleInputTrapKeyDown}
        onPaste={handleInputTrapPaste}
      />
      <div className={clsx('absolute inset-0', showCanvas && 'hidden')}>{fallback}</div>
      {renderMode === 'snapshot' ? (
        <img
          src={snapshotUrl || ''}
          alt="Remote screen snapshot"
          className={clsx('absolute inset-0 h-full w-full object-contain', !showSnapshot && 'hidden')}
        />
      ) : null}
      <canvas ref={canvasRef} className={clsx('absolute inset-0 h-full w-full object-contain', !showCanvas && 'opacity-0')} />
      {showInactiveOverlay ? (
        <div className="pointer-events-none absolute inset-0 z-10 grid place-items-center bg-[#777]/85 p-6 text-center font-mono text-white">
          <div className="text-[13px] font-semibold tracking-[0.08em]">{overlayDisplayText}</div>
        </div>
      ) : null}
      {debugInfo ? (
        <button
          type="button"
          onClick={(event) => {
            event.stopPropagation();
            setShowDebug((value) => !value);
          }}
          className="absolute right-2 top-2 z-20 border border-[#6f5a24] bg-[#1f1a0d]/95 px-2 py-1 font-mono text-[11px] text-[#ffcf70] shadow"
          title="Show screen debug"
        >
          ⚠ decode
        </button>
      ) : null}
      {debugInfo && showDebug ? (
        <div
          className="absolute right-2 top-10 z-20 max-h-[62%] w-[min(360px,calc(100%-16px))] overflow-auto border border-[#6f5a24] bg-[#111]/95 p-2 font-mono text-[11px] leading-4 text-[#ffd98a] shadow"
          onClick={(event) => event.stopPropagation()}
        >
          <div className="mb-1 flex items-center justify-between gap-2 border-b border-[#6f5a24] pb-1">
            <span className="font-semibold">{debugInfo.title}</span>
            <button type="button" className="text-[#ffefc0]" onClick={() => setShowDebug(false)}>
              close
            </button>
          </div>
          <DebugRow label="message" value={debugInfo.message} />
          <DebugRow label="codec" value={debugInfo.codec} />
          <DebugRow label="size" value={debugInfo.width && debugInfo.height ? `${debugInfo.width} x ${debugInfo.height}` : undefined} />
          <DebugRow label="seq" value={debugInfo.seq} />
          <DebugRow label="key" value={debugInfo.keyFrame === undefined ? undefined : String(debugInfo.keyFrame)} />
          <DebugRow label="timestamp" value={debugInfo.timestamp} />
          <DebugRow label="nal" value={debugInfo.nalTypes?.join(',')} />
          <DebugRow label="state" value={debugInfo.decoderState} />
          <DebugRow label="head" value={debugInfo.packetHead} />
          <DebugRow label="at" value={debugInfo.at} />
        </div>
      ) : null}
    </div>
  );
}

function DebugRow({ label, value }: { label: string; value?: string | number }) {
  if (value === undefined || value === null || value === '') return null;
  return (
    <div className="grid grid-cols-[72px_minmax(0,1fr)] gap-2">
      <div className="text-[#b99b5a]">{label}</div>
      <div className="break-all text-[#ffefc0]">{String(value)}</div>
    </div>
  );
}

function errorMessage(value: unknown) {
  if (value instanceof Error) return value.message || value.name;
  if (value && typeof value === 'object' && 'message' in value) return String((value as { message?: unknown }).message);
  return String(value);
}

function inputLabel(kind: ScreenInputKind | string) {
  if (kind === 'tap') return 'tap';
  if (kind === 'text') return 'text';
  if (kind === 'paste') return 'paste';
  if (kind === 'key') return 'key';
  if (kind === 'copy') return 'copy';
  if (kind === 'selectall') return 'select all';
  if (kind === 'clear') return 'clear';
  return 'input';
}

function claimKeyboardEvent(event: ReactKeyboardEvent<HTMLElement>) {
  event.preventDefault();
  event.stopPropagation();
  event.nativeEvent.stopImmediatePropagation?.();
}

function describeShortcut(event: ReactKeyboardEvent<HTMLElement>) {
  const parts: string[] = [];
  if (event.metaKey) parts.push('Meta');
  if (event.ctrlKey) parts.push('Ctrl');
  if (event.altKey) parts.push('Alt');
  if (event.shiftKey) parts.push('Shift');
  parts.push(event.key);
  return parts.join('+');
}

function isBrowserShortcutKey(key: string) {
  return /^F\d{1,2}$/.test(key) || key === 'BrowserBack' || key === 'BrowserForward' || key === 'ContextMenu';
}

function isLocalFormTarget(target: EventTarget | null) {
  if (!(target instanceof HTMLElement)) return false;
  const tagName = target.tagName.toLowerCase();
  return tagName === 'input' || tagName === 'textarea' || target.isContentEditable || Boolean(target.closest('button'));
}

function parseVideoPacket(value: unknown): VideoPacket | null {
  if (!(value instanceof ArrayBuffer) || value.byteLength <= PACKET_HEADER_BYTES) return null;
  const view = new DataView(value);
  if (view.getUint8(0) !== 0x4d || view.getUint8(1) !== 0x48 || view.getUint8(2) !== 0x53 || view.getUint8(3) !== 0x31) return null;
  const flags = view.getUint8(4);
  return {
    keyFrame: Boolean(flags & 1),
    seq: view.getUint32(8, false),
    timestamp: Number(view.getBigUint64(12, false)),
    data: new Uint8Array(value, PACKET_HEADER_BYTES),
    nalTypes: readNalTypes(new Uint8Array(value, PACKET_HEADER_BYTES)),
  };
}

function readNalTypes(data: Uint8Array): number[] {
  const result: number[] = [];
  let index = 0;
  while (index < data.length - 3 && result.length < 8) {
    const length = startCodeLength(data, index);
    if (!length) {
      index += 1;
      continue;
    }
    const nalStart = index + length;
    if (nalStart < data.length) result.push(data[nalStart] & 0x1f);
    index = nalStart + 1;
  }
  return result;
}

function startCodeLength(data: Uint8Array, index: number) {
  if (index + 4 <= data.length && data[index] === 0 && data[index + 1] === 0 && data[index + 2] === 0 && data[index + 3] === 1) return 4;
  if (index + 3 <= data.length && data[index] === 0 && data[index + 1] === 0 && data[index + 2] === 1) return 3;
  return 0;
}

function computeContainLayout(frameWidth: number, frameHeight: number, hostWidth: number, hostHeight: number) {
  if (frameWidth <= 0 || frameHeight <= 0 || hostWidth <= 0 || hostHeight <= 0) return null;
  const scale = Math.min(hostWidth / frameWidth, hostHeight / frameHeight);
  if (!Number.isFinite(scale) || scale <= 0) return null;
  const width = frameWidth * scale;
  const height = frameHeight * scale;
  return {
    scale,
    width,
    height,
    offsetX: (hostWidth - width) / 2,
    offsetY: (hostHeight - height) / 2,
  };
}

function clamp(value: number, min: number, max: number) {
  return Math.max(min, Math.min(value, max));
}
