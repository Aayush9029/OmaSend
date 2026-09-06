# OmaSend Web

A local browser companion for Windows, macOS and Linux. Send text, upload files, copy shared text, and download incoming images or files. The interface is embedded in one executable; no Node, .NET, browser extension or cloud account is required to run it.

## Run

Download and extract the `OmaSendWeb` archive for your OS and architecture from [OmaSend 0.2.0](https://github.com/Aayush9029/OmaSend/releases/tag/v0.2.0).

Windows PowerShell:

```powershell
.\omasend-web.exe
```

macOS / Linux:

```sh
./omasend-web
```

Open **http://localhost:53318** on the hosting computer. The companion has its own history and identity and uses native peer port **53319**, so it can coexist with the desktop app on port 53317. It does not monitor the host's OS clipboard.

To allow browsers on another computer, add `--lan YOUR_LAN_IP`, for example `--lan 192.168.1.20`. This keeps localhost available for settings and exposes only that interface. Alternatively, `--listen 0.0.0.0:53318` listens on all interfaces. Open the printed `http://192.168.…:53318` address on your other computer. The browser connection is unencrypted HTTP and all local browsers that can reach it share one inbox; do this only on a network you trust. Allow TCP 53318 (browser), TCP 53319 (native transfers) and UDP 5353 (discovery) through your firewall if necessary. The app does not change firewall rules.

Stop with Ctrl+C. `--data PATH` chooses the storage directory; `--port NUMBER` changes the native peer port. `--name NAME` sets and saves the displayed device name. Default data is in your OS user configuration directory under `omasend-web`. Uploads and received files remain there until you remove them. Removing history does not remove downloaded files.

## Connect

Encrypted sharing is the default. From the host's **localhost** page, choose **Change sharing mode**, paste the key from a native app and select **Use key**. Native devices with the same key are discovered automatically. If discovery is unavailable, use **Connect a device** with its local IP and port (normally 53317).

For key-free sharing, enable **Trusted LAN** in the companion and on every native device:

- **Windows:** Settings → Trusted LAN → Save.
- **macOS:** Settings → Devices → Trusted LAN.
- **Linux:** `omasend lan on`, or the Trusted LAN switch in the Omarchy panel. Use `omasend lan off` to restore encrypted mode.

Trusted LAN sends plaintext and does not authenticate devices. Anyone on that local network can read, inject or modify shared content. It is restricted to private, loopback and link-local IP addresses; it does not use Tailscale. Encrypted devices reject plaintext, and there is no automatic downgrade. Switching modes preserves your pairing key and clears current peer connections. All native apps must be updated to a version with this option.

Only the hosting computer's localhost page can change the companion's sharing mode or pairing key. Exact HTTP Host and Origin checks prevent unrelated websites from controlling the companion. No pairing key or local file path is returned in browser history.

## Browser behavior

- Paste or type text, then **Send**. Ctrl+Enter / ⌘Enter also sends.
- **Attach file** or drop one file (up to 100 MB). Incoming native images can be downloaded; browser uploads travel as files.
- **Copy** copies received text. On plain LAN HTTP, paste manually with Ctrl+V / ⌘V; if the browser refuses copying, select the text and copy it yourself.
- Browser clipboard APIs require a secure context and usually a user gesture. This companion does not promise automatic background clipboard sync. Use the native apps for that.
- Items sent while no devices are connected stay in the companion's history. They are not automatically resent later.

## Build from source

With Go 1.24 or newer, from the repository:

```sh
cd linux && go build -o omasend-web ./cmd/omasend-web
```

`VERSION=0.2.0 bash scripts/package-web.sh` packages Windows, macOS and Linux for x64 and ARM64 with no runtime dependencies. Native Windows Smart App Control and macOS Gatekeeper policies still apply to executable downloads.
