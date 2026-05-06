<p align="right">
  English | <a href="./REMOTE-RELAY.zh-CN.md">简体中文</a>
</p>

# Remote On-Demand Terminal

## Goal

Remote On-Demand Terminal now uses a phone-initiated connection to Relay Server.

The main path no longer depends on LAN scanning or QR codes. After the desktop starts Relay, it produces a URL. The Android app home screen only needs that URL and a tap on `Connect Relay`. The browser triggers PTY creation only after the user clicks `Open Terminal`.

This phase keeps a minimal closed loop:

1. Android only keeps a lightweight control WebSocket and does not create PTY sessions in advance.
2. The browser opens Relay Console and immediately sees connected devices.
3. After the user clicks `Open Terminal`, Relay sends `session.open` through the control channel.
4. Android creates a real PTY, launches the shell, and connects to `/ws/device`.
5. The browser connects to `/ws/browser`, and Relay forwards both input and output.
6. After `Close Session`, the PTY and device WebSocket close, while the control channel stays idle.

## One-command public startup

Install and authenticate `cpolar` on the local machine first. On macOS, you can use the official binary or Homebrew:

```bash
brew tap probezy/core && brew install cpolar
cpolar authtoken <YOUR_AUTH_TOKEN>
```

Get `<YOUR_AUTH_TOKEN>` from `https://dashboard.cpolar.com/get-started`. Do not commit it into the repository or paste it into shared chat logs.

Start the public relay path:

```bash
./tools/relay/start-public-relay.sh
```

The script will:

1. Start the local Mira Relay first.
2. Start a cpolar HTTP tunnel.
3. Wait until the `https://*.cpolar.top` address passes HTTP validation.
4. Update Mira Relay with that public address.
5. Print the Browser URL and Android Relay URL.

Enter the printed Android Relay URL on the phone. No LAN scan and no QR code are needed.

Optional environment variables:

```bash
MIRA_RELAY_PORT=8765 ./tools/relay/start-public-relay.sh
MIRA_RELAY_HOST=127.0.0.1 ./tools/relay/start-public-relay.sh
```

If you still want Cloudflare Quick Tunnel, set it explicitly:

```bash
MIRA_TUNNEL_PROVIDER=cloudflare ./tools/relay/start-public-relay.sh
```

## Using an external public tunnel

If you already run cpolar, frp, NATAPP, or another tunneling service in a separate terminal, you can map local port `8765` to a public endpoint and let Mira reuse it.

After you get the public URL, pass it to Mira through `MIRA_PUBLIC_URL`:

```bash
MIRA_PUBLIC_URL=https://example.cpolar.top ./mira-web
```

In this mode the script will:

1. Start the local Mira Relay.
2. Wait until `MIRA_PUBLIC_URL` can reach the local Relay.
3. Skip automatic cpolar startup.
4. Print `MIRA_PUBLIC_URL` as both the Browser URL and Android Relay URL.

### Quick cpolar trial

After installation and authentication, you can start the tunnel separately first:

```bash
cpolar http 8765
```

Copy the public HTTP or HTTPS address printed by cpolar, for example:

```text
https://xxxx.r36.cpolar.top
```

Then start Mira:

```bash
MIRA_PUBLIC_URL=https://xxxx.r36.cpolar.top ./mira-web
```

Keep both the cpolar process and `./mira-web` running. On the phone, enter the Android Relay URL printed by Mira.

By default, `./mira-web` manages the cpolar process itself. If you already ran `cpolar http 8765` manually, prefer the `MIRA_PUBLIC_URL` path to avoid starting cpolar twice.

## LAN startup

If you only test within the local network, prefer:

```bash
./mira-local-web
```

The script prints two addresses:

```text
Browser URL: http://localhost:8765
Android Relay URL: http://<your-lan-ip>:8765
```

Open the `Browser URL` on the desktop, which should be the `localhost` address. This keeps WebCodecs available inside a localhost secure context so H.264 decoding for the remote view can work.

On the Android app home screen, enter the `Android Relay URL`, which uses the desktop LAN IP. Do not enter `localhost` on the phone, because phone localhost points to the phone itself.

If you need to start Relay manually, you can run the Python module entry point directly.

## Toolbox release timing

The toolbox is released only when a remote session opens, not when the device first connects. See `TOOLBOX.md` for details.
