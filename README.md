# CodeFlow — Cross-Platform System

**CodeFlow** is a complete, two-part cross-platform system designed to turn your phone into a smart, automated hardware Bluetooth keyboard for typing code, orchestrating terminal workflows, and streaming your PC's screen in real time with ultra-low latency.

---

## Architecture Overview

```
┌────────────────────────────────────────────────────────┐
│                   CodeFlow Mobile                      │
│            (Flutter / Android & iOS)                   │
│                                                        │
│  ┌──────────────────┐  ┌────────────────────────────┐  │
│  │ Project & Files  │  │ Typing Cadence Engine      │  │
│  │ Safe ZIP / GitHub│  │ 10-80 CPS, Jitter, Pauses  │  │
│  └────────┬─────────┘  └─────────────┬──────────────┘  │
│           │                          │                 │
│  ┌────────▼──────────────────────────▼──────────────┐  │
│  │       Workflow Orchestrator & Checkpoints        │  │
│  └────────┬──────────────────────────┬──────────────┘  │
│           │ Direct File Transfer     │ Bluetooth HID   │
│           │ & MJPEG Stream (LAN)     │ Keystrokes &    │
│           │                          │ Shortcuts       │
└───────────┼──────────────────────────┼─────────────────┘
            │ Local Network            │ Bluetooth 5.0+
            │ (HTTP / mDNS / MJPEG)    │ (HID Device Profile)
┌───────────▼──────────────────────────▼─────────────────┐
│              CodeFlow PC Companion                     │
│         (Python 3.11+ / Win, Linux, Mac)               │
│                                                        │
│  • mss Screen Capture Loop (30-60 FPS)                 │
│  • Async aiohttp Server (MJPEG /stream, /screenshot)   │
│  • Zeroconf mDNS Discovery (_codeflow._tcp.local.)     │
│  • Authenticated /workspace/transfer Endpoint          │
│  • Active Window Detection & Diagnostics               │
└────────────────────────────────────────────────────────┘
```

The system coordinates three communication channels:
1. **Bluetooth HID:** Sends keystrokes, navigation commands, and IDE shortcuts (`Ctrl + ~`, `Ctrl + S`, `Cmd + ~`) directly to the paired PC with no special host-side drivers.
2. **Local Network (HTTP/MJPEG):** Streams the PC monitor at high framerates and directly transfers full source files safely into an approved workspace.
3. **Local Storage:** Persists projects, preferences, and resumable checkpoints so interrupted typing sessions can be resumed smoothly.

---

## 1. Component One: PC Companion (`companion/`)

A lightweight, headless background process running on the target PC (Windows, Linux, macOS).

### Dependencies
Requires Python 3.11+. Dependencies are minimal with zero heavy frameworks:
- `mss`: Ultra-fast screen capture (typically 3–8 ms per frame).
- `aiohttp`: Asynchronous HTTP server and multipart MJPEG streamer.
- `zeroconf`: LAN mDNS broadcast for zero-setup discovery.
- `Pillow`: Efficient JPEG frame compression.

### Installation & Run

```bash
cd companion

# 1. Create and activate a virtual environment
python3 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# 2. Install dependencies
pip install -r requirements.txt

# 3. Start companion with default settings (port 8090, 30 FPS, quality 75)
python codeflow_streamer.py

# Or start with a specific authorized workspace and authentication token:
python codeflow_streamer.py --port 8090 --fps 30 --quality 75 --workspace-dir /path/to/my/project --token secret123
```

### CLI Parameters

| Flag | Default | Description |
|---|---|---|
| `--host` | `0.0.0.0` | Bind IP (default allows LAN access from mobile app) |
| `--port` | `8090` | HTTP listening port |
| `--fps` | `30` | Target screen capture FPS (1–60) |
| `--quality` | `75` | JPEG quality (10–100) |
| `--monitor` | `1` | Monitor index (`1` = primary, `0` = all combined) |
| `--crop` | `None` | Optional crop region format `X,Y,WIDTH,HEIGHT` |
| `--workspace-dir` | Current dir | Path to authorized workspace (prevents path traversal) |
| `--token` | `None` | Optional security token for protected endpoints |
| `--no-mdns` | `False` | Disables mDNS LAN advertisement |

### HTTP API Endpoints

- `GET /health`: Returns `{ "status": "ok", "version": "1.0.0", "uptime_seconds": ... }`
- `GET /info`: Returns hostname, OS, resolutions, active window title, stream metrics.
- `GET /config`: Current capture and stream settings.
- `GET /screenshot`: Captures a single on-demand JPEG frame.
- `GET /stream`: Low-latency continuous MJPEG video stream (`multipart/x-mixed-replace`).
- `POST /workspace/transfer`: Authenticated direct file write into approved workspace with SHA-256 verification and path-traversal prevention.

---

## 2. Component Two: Flutter Mobile App (`codeflow_app/`)

### Design System: Minimal, Flat, White-First
- **Light Theme:** Pure white primary background (`#FFFFFF`), subtle off-white surfaces (`#F9FAFB`), dark high-contrast typography (`#111827`), neutral gray secondary labels, and a single restrained blue accent (`#2563EB`).
- **Dark Theme:** Deep charcoal background (`#121212`), surface levels (`#1E1E1E`), soft white text (`#F3F4F6`), and Slate Blue accent (`#3B82F6`).
- **Layout:** Strictly flat, compact rows, subtle dividers, zero unnecessary shadows, glassmorphism, or card-heavy clutter. Fully respects `SafeArea` and Android gesture navigation bars.

### Platform Channel Contract (`BluetoothHidDevice`)

Communicates over:
- `MethodChannel`: `dev.codeflow.app/bluetooth_hid`
- `EventChannel`: `dev.codeflow.app/bluetooth_hid_events`

| Method | Arguments | Returns | Description |
|---|---|---|---|
| `isSupported` | None | `bool` | Checks if `BluetoothHidDevice` API is available (Android 9+) |
| `registerApp` | None | `bool` | Registers standard 63-byte USB HID keyboard SDP descriptor |
| `unregisterApp` | None | `bool` | Unregisters HID peripheral |
| `getPairedDevices`| None | `List<Map>` | Lists paired Bluetooth host PCs |
| `connectHost` | `{'address': String}` | `bool` | Connects HID profile to host PC |
| `disconnectHost`| None | `bool` | Disconnects from host PC |
| `sendReport` | `{'reportId': 0, 'data': List<int>}` | `bool` | Sends 8-byte USB HID keyboard input report |
| `sendEmergencyRelease` | None | `bool` | Sends `[0,0,0,0,0,0,0,0]` to release all stuck keys |

### Foreground Service
Android native foreground service (`CodeFlowHidService.kt`) runs with a persistent notification while connected, ensuring background keystroke automation isn't terminated by OS power management.

---

## 3. Step-by-Step Testing & Setup Guide

### Step 1: Start PC Companion
On your host PC, start the companion in your project folder:
```bash
python companion/codeflow_streamer.py --port 8090 --workspace-dir $(pwd)
```
Note the local LAN IP displayed (e.g. `http://192.168.1.15:8090`).

### Step 2: Pair Phone as Bluetooth Keyboard
1. Open CodeFlow on Android -> Navigate to **Settings** -> **Bluetooth HID Keyboard**.
2. Tap **Register HID**.
3. On your PC, open Bluetooth settings and pair with your Android device. It will connect as an input device ("CodeFlow Keyboard").
4. In CodeFlow Settings, select your PC from the paired devices list and tap **Connect Host**.

### Step 3: Connect Stream & Verify Health
1. In CodeFlow Settings, tap **Scan LAN for PC** (uses mDNS discovery). Or type the PC's IP and port directly.
2. Switch to the **Monitor** tab. The PC desktop screen will render in real time with live FPS and ping latency counters.

### Step 4: Import Project & Run Automation
1. Go to the **Projects** tab.
2. Tap **+** and choose **Create Sample Starter Workspace** or **Import from Public GitHub Repository**.
3. Select the project to open the **File Selector** tree. Filter files, select/deselect with tri-state checkboxes, then tap **Automate Workflow**.
4. Configure typing speed (10–80 CPS), focus countdown delay, and newline pauses.
5. Tap **Start Workflow**:
   - Focus delay counts down allowing you to switch focus to VS Code.
   - Triggers terminal shortcut (`Ctrl + ~`).
   - Transfers source files directly or types them out.
   - Saves editor (`Ctrl + S`).
6. If interrupted, the app saves a checkpoint. You can return and tap **Resume from Checkpoint** or **Start Fresh**.
7. If any key becomes stuck, press the red **PANIC** button to instantly send an all-keys-up HID report.

---

## 4. Running Automated Tests

### Python Companion Tests
```bash
cd companion
python test_companion.py
```
*Tests health, host info, config, JPEG screenshot, 401 token authentication, direct workspace file transfer, and path traversal rejection.*

### Flutter Mobile App Tests
```bash
cd codeflow_app
flutter test
```
*Tests typing cadence engine, start offsets, pause/resume/cancel, emergency stop, checkpoint persistence/resumption, file tree tri-state selection, and light/dark theme tokens.*

---

## 5. Zero-Python Standalone Executables (For Regular Users)

Regular users **do not need Python installed**. They can download pre-compiled, self-contained binaries from GitHub Releases:

- **Windows:** `codeflow-companion-windows-x64.exe` (or `.zip`)
- **Linux:** `codeflow-companion-linux-x64.tar.gz` (or raw binary)
- **macOS:** `codeflow-companion-macos.zip`
- **Android Phone (64-bit):** `CodeFlow-Android-arm64-v1.0.0.apk` (specifically compiled for modern 64-bit `arm64-v8a` architecture for minimal size and high performance)

### How It Works for a Regular User:
1. **Double-Click Executable:** Run `codeflow-companion.exe` on Windows or `./codeflow-companion` on Linux.
2. **Instant Host Dashboard:** The companion automatically opens your default web browser to `http://localhost:8090/`.
3. **Connect Mobile:** The dashboard displays your PC's IP address with a 1-click **Copy** button, live monitor preview, and step-by-step pairing instructions.
4. **Zero Configuration:** Open the CodeFlow Android app on the same Wi-Fi network; mDNS automatically finds the host with zero setup.

---

## 6. Build Scripts & Automated CI/CD Release Workflow

### Local Build Scripts

```bash
# Build standalone PC companion executable (using PyInstaller)
./scripts/build_companion.sh

# Build Android release APK
./scripts/build_android.sh

# Build everything into release/ folder
./scripts/build_all.sh

# Or using Makefile:
make build
```

### GitHub Actions Automated Release Workflow (`.github/workflows/release.yml`)

The repository includes a complete GitHub Actions matrix release pipeline:
- **Trigger Options:**
  - `workflow_dispatch` (Manual trigger with optional `version` input, e.g. `v1.0.0`, and `prerelease` flag).
  - Pushing any `v*` tag (`git push origin v1.0.0`).
- **Smart Tag & Version Resolution:**
  - If a version is provided in `workflow_dispatch`, it uses that tag.
  - If triggered via a Git tag, it uses the pushed tag.
  - If no tag exists, it reads the version from [`VERSION`](file:///home/roshan/dev/Bawaal/VERSION) (e.g. `1.0.0`). If `v1.0.0` already exists, it calculates the next patch version (`v1.0.1`), tags git, and pushes it automatically.
- **Cross-Platform Matrix Compilation:**
  - **Windows Runner (`windows-latest`):** Compiles `codeflow-companion-windows-x64.exe` and `.zip`.
  - **Linux Runner (`ubuntu-latest`):** Compiles `codeflow-companion-linux-x64.tar.gz` and standalone binary.
  - **macOS Runner (`macos-latest`):** Compiles `codeflow-companion-macos.zip`.
  - **Android Runner (`ubuntu-latest`):** Runs Flutter tests and compiles `CodeFlow-Android-vX.X.X.apk`.
- **GitHub Release Publishing:**
  - Gathers all 4 platform artifacts into a single GitHub Release.
  - Generates changelogs, installation guides, and direct download links.
