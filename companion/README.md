# CodeFlow Companion (PC Daemon)

The **CodeFlow Companion** is a lightweight, headless screen-streaming daemon and workspace agent designed for Windows, Linux, and macOS. It provides low-latency screen capture via `mss`, an async HTTP/MJPEG streaming API, mDNS local-network discovery (`_codeflow._tcp.local.`), and secure direct workspace file transfers.

---

## 1. Quick Start

### Installation

Requires Python 3.11 or newer.

```bash
# Optional: Create and activate virtual environment
python3 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt
```

### Launch Companion

```bash
# Default: Listen on 0.0.0.0:8090, 30 FPS, JPEG Quality 75, Monitor 1
python codeflow_streamer.py

# Custom settings:
python codeflow_streamer.py --port 8090 --fps 30 --quality 80 --monitor 1 --workspace-dir /path/to/my/project --token mysecrettoken
```

---

## 2. CLI Options

| Flag | Default | Description |
|---|---|---|
| `--host` | `0.0.0.0` | IP address to bind HTTP server (`0.0.0.0` allows LAN access from phone) |
| `--port` | `8090` | TCP port |
| `--fps` | `30` | Target screen capture FPS (1–60) |
| `--quality` | `75` | JPEG quality (10–100) |
| `--monitor` | `1` | Monitor index (`1` = primary, `0` = all combined) |
| `--crop` | `None` | Optional crop region formatted as `X,Y,WIDTH,HEIGHT` |
| `--workspace-dir` | `cwd` | Authorized directory for direct file transfers (prevents path traversal) |
| `--token` | `None` | Authentication token for protected endpoints |
| `--no-mdns` | `False` | Disables Zeroconf mDNS advertisement |

---

## 3. Endpoints

| Endpoint | Method | Auth | Description |
|---|---|---|---|
| `/health` | GET | No | Basic heartbeat and uptime status |
| `/info` | GET | No | Hostname, OS version, monitors, active window title, stream metrics |
| `/config` | GET | No | Current stream and capture configuration |
| `/screenshot` | GET | Optional | Returns a single `image/jpeg` frame |
| `/stream` | GET | Optional | Ultra-low-latency multipart MJPEG continuous stream |
| `/workspace/transfer` | POST | If token set | Direct authenticated file write into the approved workspace |

### Direct Workspace Transfer Payload

```json
{
  "relative_path": "lib/models/user.dart",
  "content": "class User { final String id; ... }",
  "encoding": "utf-8",
  "sha256": "5e884898da28047151d0e56f8dc6292773603d0d6aabbdd62a11ef721d1542d8",
  "overwrite": true
}
```

---

## 4. Troubleshooting

- **Firewall:** Ensure port 8090 (or chosen port) is open in your local firewall (`sudo ufw allow 8090/tcp` on Ubuntu, or Windows Defender Firewall prompt).
- **Active Window Detection:**
  - **Linux (X11):** Install `xdotool` or `x11-utils` (`sudo pacman -S xdotool` or `sudo apt install xdotool`).
  - **Linux (Wayland):** Wayland protocol restricts querying foreign window titles by design; `/info` safely returns `null` for active window.
  - **Windows & macOS:** Uses native Win32 `GetForegroundWindow` / macOS `osascript` with zero external dependencies.
- **mDNS Discovery:** Some enterprise Wi-Fi networks block multicast UDP. If auto-discovery does not find your PC, enter your PC's LAN IP address (shown on startup) directly in CodeFlow Mobile.
