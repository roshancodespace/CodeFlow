#!/usr/bin/env python3
"""
CodeFlow Companion - Lightweight, Headless Screen Streamer & Workspace Agent
-----------------------------------------------------------------------------
Fast, low-latency screen capture and streaming daemon with LAN discovery (mDNS),
diagnostic endpoints, and authenticated direct workspace file transfer.

Requirements:
    pip install mss aiohttp zeroconf Pillow
"""

import os
import sys

# Auto re-exec into local virtualenv if running under base python and venv exists
def _bootstrap_venv():
    if os.environ.get("VIRTUAL_ENV"):
        return
    cur_dir = os.path.dirname(os.path.abspath(__file__))
    candidates = [
        os.path.join(cur_dir, "venv", "bin", "python"),
        os.path.join(cur_dir, "venv", "Scripts", "python.exe"),
        os.path.join(cur_dir, ".venv", "bin", "python"),
        os.path.join(cur_dir, ".venv", "Scripts", "python.exe"),
    ]
    for cand in candidates:
        if os.path.isfile(cand) and os.access(cand, os.X_OK) and sys.executable != cand:
            try:
                os.execv(cand, [cand] + sys.argv)
            except Exception:
                pass

_bootstrap_venv()

import argparse
import asyncio
import contextlib
import difflib
import hashlib
import io
import json
import logging
import platform
import re
import shutil
import socket
import subprocess
import time
import webbrowser
from typing import Any, Dict, List, Optional, Tuple

try:
    import mss
    from PIL import Image
except ImportError:
    mss = None
    Image = None

try:
    from aiohttp import web
except ImportError:
    web = None

def _safe_middleware(handler):
    if web is not None and hasattr(web, "middleware"):
        return web.middleware(handler)
    return handler

try:
    from zeroconf import IPVersion, ServiceInfo, Zeroconf
    from zeroconf.asyncio import AsyncZeroconf
except ImportError:
    Zeroconf = None
    AsyncZeroconf = None
    ServiceInfo = None
    IPVersion = None

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    datefmt="%H:%M:%S",
)
logger = logging.getLogger("CodeFlowCompanion")

VERSION = "1.0.0"


class ActiveWindowDetector:
    """Lightweight, zero-heavy-dependency active window detector."""

    @staticmethod
    def get_active_window_title() -> Optional[str]:
        system = platform.system()
        try:
            if system == "Windows":
                import ctypes
                user32 = ctypes.windll.user32
                hwnd = user32.GetForegroundWindow()
                if hwnd:
                    length = user32.GetWindowTextLengthW(hwnd)
                    if length > 0:
                        buff = ctypes.create_unicode_buffer(length + 1)
                        user32.GetWindowTextW(hwnd, buff, length + 1)
                        return buff.value
                return None

            elif system == "Darwin":  # macOS
                cmd = (
                    "osascript -e 'tell application \"System Events\" "
                    "to get name of first application process whose frontmost is true'"
                )
                res = subprocess.run(
                    cmd, shell=True, capture_output=True, text=True, timeout=1.0
                )
                if res.returncode == 0 and res.stdout.strip():
                    return res.stdout.strip()
                return None

            elif system == "Linux":
                # Check Wayland compositors (Hyprland / Sway)
                if shutil.which("hyprctl"):
                    try:
                        res = subprocess.run(
                            ["hyprctl", "activewindow", "-j"],
                            capture_output=True,
                            text=True,
                            timeout=0.5,
                        )
                        if res.returncode == 0 and res.stdout.strip():
                            data = json.loads(res.stdout)
                            title = data.get("title") or data.get("initialTitle") or data.get("class")
                            if title:
                                return title
                    except Exception:
                        pass

                if shutil.which("swaymsg"):
                    try:
                        res = subprocess.run(
                            ["swaymsg", "-t", "get_tree"],
                            capture_output=True,
                            text=True,
                            timeout=0.5,
                        )
                        if res.returncode == 0 and res.stdout.strip():
                            tree = json.loads(res.stdout)
                            def _find_focused(node):
                                if node.get("focused"):
                                    return node.get("name")
                                for child in node.get("nodes", []) + node.get("floating_nodes", []):
                                    found = _find_focused(child)
                                    if found:
                                        return found
                                return None
                            title = _find_focused(tree)
                            if title:
                                return title
                    except Exception:
                        pass

                # Check for xdotool or xprop (X11)
                try:
                    res = subprocess.run(
                        ["xdotool", "getactivewindow", "getwindowname"],
                        capture_output=True,
                        text=True,
                        timeout=0.8,
                    )
                    if res.returncode == 0 and res.stdout.strip():
                        return res.stdout.strip()
                except (FileNotFoundError, subprocess.SubprocessError):
                    pass

                # Fallback to xprop
                try:
                    res = subprocess.run(
                        "xprop -root _NET_ACTIVE_WINDOW",
                        shell=True,
                        capture_output=True,
                        text=True,
                        timeout=0.8,
                    )
                    if res.returncode == 0 and "window id #" in res.stdout:
                        win_id = res.stdout.split("window id #")[-1].strip().split()[0]
                        res2 = subprocess.run(
                            f"xprop -id {win_id} WM_NAME _NET_WM_NAME",
                            shell=True,
                            capture_output=True,
                            text=True,
                            timeout=0.8,
                        )
                        if res2.returncode == 0:
                            for line in res2.stdout.splitlines():
                                if "=" in line:
                                    val = line.split("=", 1)[1].strip().strip('"')
                                    if val:
                                        return val
                except (FileNotFoundError, subprocess.SubprocessError):
                    pass
                return None
        except Exception as e:
            logger.debug(f"Error detecting active window: {e}")
            return None
        return None


class ScreenCaptureManager:
    """Manages continuous desktop screen capture decoupled from HTTP streaming."""

    def __init__(
        self,
        monitor_index: int = 1,
        target_fps: int = 30,
        jpeg_quality: int = 75,
        crop: Optional[Tuple[int, int, int, int]] = None,
    ):
        self.monitor_index = monitor_index
        self.target_fps = max(1, min(60, target_fps))
        self.frame_interval = 1.0 / self.target_fps
        self.jpeg_quality = max(10, min(100, jpeg_quality))
        self.crop = crop  # (x, y, w, h)

        # Detect Wayland on Linux (requires grim for non-black frame capture)
        self.is_wayland = bool(
            platform.system() == "Linux"
            and (
                os.environ.get("WAYLAND_DISPLAY")
                or os.environ.get("XDG_SESSION_TYPE") == "wayland"
            )
        )
        self._grim_path = shutil.which("grim") if self.is_wayland else None
        self.has_grim = bool(self._grim_path)
        self.backend = (
            "grim (Wayland Native)"
            if (self.is_wayland and self.has_grim)
            else ("mss (X11/Desktop)" if mss else "Synthetic")
        )

        self._running = False
        self._task: Optional[asyncio.Task] = None
        self._sct: Optional[Any] = None

        # Frame broadcasting state
        self.latest_jpeg: Optional[bytes] = None
        self.latest_timestamp: float = 0.0
        self.latest_capture_duration_ms: float = 0.0
        self.frame_sequence: int = 0
        self.measured_fps: float = 0.0
        self.new_frame_event = asyncio.Event()

        # Metrics
        self._fps_counter = 0
        self._fps_timer = time.time()
        self._total_capture_ms = 0.0

    def _get_mss_instance(self):
        if not mss:
            return None
        factory = getattr(mss, "MSS", getattr(mss, "mss", None))
        return factory() if factory else None

    def list_monitors(self) -> List[Dict[str, Any]]:
        """List available monitors and their dimensions."""
        if self.is_wayland and shutil.which("hyprctl"):
            try:
                res = subprocess.run(
                    ["hyprctl", "monitors", "-j"],
                    capture_output=True,
                    text=True,
                    timeout=1.0,
                )
                if res.returncode == 0 and res.stdout.strip():
                    data = json.loads(res.stdout)
                    monitors = []
                    for i, m in enumerate(data):
                        monitors.append(
                            {
                                "id": i + 1,
                                "name": m.get("name", f"output-{i}"),
                                "is_all": False,
                                "left": m.get("x", 0),
                                "top": m.get("y", 0),
                                "width": m.get("width", 1920),
                                "height": m.get("height", 1080),
                            }
                        )
                    if monitors:
                        return monitors
            except Exception as e:
                logger.debug(f"Failed to query hyprctl monitors: {e}")

        if not mss:
            return [{"id": 0, "width": 1920, "height": 1080, "left": 0, "top": 0}]
        try:
            with self._get_mss_instance() as sct:
                monitors = []
                # sct.monitors[0] is all monitors combined, 1..N are individual monitors
                for i, m in enumerate(sct.monitors):
                    monitors.append(
                        {
                            "id": i,
                            "is_all": (i == 0),
                            "left": m["left"],
                            "top": m["top"],
                            "width": m["width"],
                            "height": m["height"],
                        }
                    )
                return monitors
        except Exception as e:
            logger.error(f"Failed to list monitors: {e}")
            return [{"id": 1, "width": 1920, "height": 1080, "left": 0, "top": 0}]

    async def start(self):
        """Start the continuous background capture loop."""
        if self._running:
            return
        if not self.has_grim and (not mss or not Image):
            logger.warning(
                "mss/grim or Pillow not installed. Generating dummy synthetic frames."
            )
        self._running = True
        self._task = asyncio.create_task(self._capture_loop())
        logger.info(
            f"Screen capture started: Backend [{self.backend}], Monitor {self.monitor_index}, "
            f"Target {self.target_fps} FPS, JPEG Quality {self.jpeg_quality}"
        )
        if self.is_wayland and not self.has_grim:
            logger.warning(
                "Wayland session detected without 'grim' installed! Screen capture under Wayland "
                "requires 'grim' to avoid black screen frames. "
                "Install with: 'sudo pacman -S grim' or 'sudo apt install grim'."
            )

    async def stop(self):
        """Stop background capture and clean up."""
        self._running = False
        if self._task:
            self._task.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await self._task
            self._task = None
        if self._sct:
            self._sct.close()
            self._sct = None
        logger.info("Screen capture stopped.")

    def _encode_frame(self, sct_img) -> bytes:
        """Encode raw mss screenshot to JPEG bytes."""
        # Convert raw BGRA to RGB PIL Image
        # sct_img.rgb is raw RGB bytes, shape is (height, width, 3)
        img = Image.frombytes("RGB", sct_img.size, sct_img.rgb)

        if self.crop:
            cx, cy, cw, ch = self.crop
            # Ensure crop bounds fit within image
            w, h = img.size
            cx = max(0, min(cx, w - 1))
            cy = max(0, min(cy, h - 1))
            cw = min(cw, w - cx)
            ch = min(ch, h - cy)
            if cw > 0 and ch > 0:
                img = img.crop((cx, cy, cx + cw, cy + ch))

        buffer = io.BytesIO()
        img.save(buffer, format="JPEG", quality=self.jpeg_quality, optimize=False)
        return buffer.getvalue()

    def _generate_synthetic_frame(self) -> bytes:
        """Fallback synthetic frame when native screen capture is unavailable."""
        img = Image.new("RGB", (1280, 720), color=(24, 24, 24))
        buffer = io.BytesIO()
        img.save(buffer, format="JPEG", quality=self.jpeg_quality)
        return buffer.getvalue()

    def _capture_frame_grim(self) -> bytes:
        """Capture real desktop frame on Wayland via grim directly into JPEG bytes."""
        cmd = [self._grim_path, "-c", "-t", "jpeg", "-q", str(self.jpeg_quality)]
        if self.crop:
            cx, cy, cw, ch = self.crop
            cmd.extend(["-g", f"{cx},{cy} {cw}x{ch}"])
        cmd.append("-")
        try:
            proc = subprocess.run(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                check=False,
            )
            if proc.returncode == 0 and len(proc.stdout) > 10:
                return proc.stdout
        except Exception as e:
            logger.debug(f"grim capture error: {e}")
        return self._generate_synthetic_frame()

    async def _capture_loop(self):
        """Asynchronous decoupled capture loop."""
        loop = asyncio.get_running_loop()

        if not (self.is_wayland and self.has_grim) and mss:
            try:
                self._sct = self._get_mss_instance()
            except Exception as e:
                logger.error(f"Cannot initialize mss screen capture: {e}")
                self._sct = None

        while self._running:
            t_start = time.perf_counter()
            try:
                if self.is_wayland and self.has_grim:
                    # Native Wayland capture with cursor and zero-black-frame guarantees
                    jpeg_bytes = await loop.run_in_executor(
                        None, self._capture_frame_grim
                    )
                elif self._sct and mss and Image:
                    # Determine monitor bounding box
                    mons = self._sct.monitors
                    mon_idx = (
                        self.monitor_index
                        if 0 <= self.monitor_index < len(mons)
                        else 1
                    )
                    monitor = mons[mon_idx]

                    # Capture in thread pool so it does not block asyncio loop
                    sct_img = await loop.run_in_executor(None, self._sct.grab, monitor)
                    jpeg_bytes = await loop.run_in_executor(
                        None, self._encode_frame, sct_img
                    )
                else:
                    # Synthetic fallback
                    jpeg_bytes = await loop.run_in_executor(
                        None, self._generate_synthetic_frame
                    )

                t_end = time.perf_counter()
                dur_ms = (t_end - t_start) * 1000.0

                # Update latest frame state
                self.latest_jpeg = jpeg_bytes
                self.latest_timestamp = time.time()
                self.latest_capture_duration_ms = round(dur_ms, 2)
                self.frame_sequence += 1

                # Notify waiting stream connections
                self.new_frame_event.set()
                self.new_frame_event.clear()

                # FPS tracking
                self._fps_counter += 1
                now = time.time()
                if now - self._fps_timer >= 1.0:
                    self.measured_fps = round(
                        self._fps_counter / (now - self._fps_timer), 1
                    )
                    self._fps_counter = 0
                    self._fps_timer = now

            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error(f"Capture error: {e}", exc_info=True)
                await asyncio.sleep(0.5)

            # Frame rate pacing
            elapsed = time.perf_counter() - t_start
            sleep_time = max(0.001, self.frame_interval - elapsed)
            await asyncio.sleep(sleep_time)


class FirewallManager:
    """Detects and helps automatically configure host firewall for zero-friction LAN streaming."""

    @staticmethod
    def ensure_ports_open(port: int = 8090) -> Dict[str, Any]:
        """Detect active firewall and attempt to allow companion streaming & mDNS ports."""
        status = {
            "firewall_name": "None / Unrestricted",
            "ports_open": True,
            "auto_configured": False,
            "hint": None,
        }

        system = platform.system()
        if system == "Linux":
            # 1. firewalld
            if shutil.which("firewall-cmd"):
                try:
                    res = subprocess.run(
                        ["firewall-cmd", "--state"],
                        capture_output=True,
                        text=True,
                        timeout=5.0,
                    )
                    if res.returncode == 0 and "running" in res.stdout:
                        status["firewall_name"] = "firewalld"
                        q_res = subprocess.run(
                            ["firewall-cmd", f"--query-port={port}/tcp"],
                            capture_output=True,
                            text=True,
                            timeout=5.0,
                        )
                        if q_res.returncode == 0 and "yes" in q_res.stdout:
                            status["ports_open"] = True
                        else:
                            # Try to open automatically via polkit (often succeeds for local desktop user)
                            add_res = subprocess.run(
                                [
                                    "firewall-cmd",
                                    f"--add-port={port}/tcp",
                                    "--add-port=5353/udp",
                                ],
                                capture_output=True,
                                text=True,
                                timeout=5.0,
                            )
                            if add_res.returncode == 0:
                                status["ports_open"] = True
                                status["auto_configured"] = True
                                logger.info(
                                    f"Automatically opened LAN ports in firewalld: {port}/tcp & 5353/udp"
                                )
                                subprocess.run(
                                    [
                                        "firewall-cmd",
                                        "--permanent",
                                        f"--add-port={port}/tcp",
                                        "--add-port=5353/udp",
                                    ],
                                    capture_output=True,
                                    timeout=5.0,
                                )
                            else:
                                status["ports_open"] = False
                                status["hint"] = (
                                    f"sudo firewall-cmd --add-port={port}/tcp --add-port=5353/udp"
                                )
                                logger.warning(
                                    f"firewalld is active and port {port} is not open! "
                                    f"If your mobile phone cannot connect, run: {status['hint']}"
                                )
                except Exception as e:
                    logger.debug(f"firewalld check error: {e}")

            # 2. UFW
            elif shutil.which("ufw"):
                try:
                    res = subprocess.run(
                        ["ufw", "status"],
                        capture_output=True,
                        text=True,
                        timeout=3.0,
                    )
                    if res.returncode == 0 and "Status: active" in res.stdout:
                        status["firewall_name"] = "UFW"
                        if f"{port}" not in res.stdout:
                            status["ports_open"] = False
                            status["hint"] = f"sudo ufw allow {port}/tcp"
                            logger.warning(
                                f"UFW is active. If your phone cannot connect, run: {status['hint']}"
                            )
                except Exception:
                    pass

        elif system == "Windows":
            status["firewall_name"] = "Windows Defender"
            status["hint"] = (
                f'netsh advfirewall firewall add rule name="CodeFlow Companion" dir=in action=allow protocol=TCP localport={port}'
            )

        return status


class CodeFlowCompanionServer:
    """Async HTTP API, MJPEG Stream, and Workspace Management Server."""

    def __init__(
        self,
        host: str = "0.0.0.0",
        port: int = 8090,
        fps: int = 30,
        quality: int = 75,
        monitor: int = 1,
        crop: Optional[Tuple[int, int, int, int]] = None,
        workspace_dir: Optional[str] = None,
        token: Optional[str] = None,
        enable_mdns: bool = True,
    ):
        self.host = host
        self.port = port
        self.token = token
        self.enable_mdns = enable_mdns
        self.start_time = time.time()

        # Workspace directory security: Auto-detect project root if launched inside companion/
        if workspace_dir:
            self.workspace_dir = os.path.abspath(workspace_dir)
        else:
            cwd = os.path.abspath(os.getcwd())
            parent = os.path.dirname(cwd)
            if os.path.basename(cwd) == "companion" and (
                os.path.exists(os.path.join(parent, ".git"))
                or os.path.exists(os.path.join(parent, "VERSION"))
                or os.path.exists(os.path.join(parent, "codeflow_app"))
            ):
                self.workspace_dir = parent
            else:
                self.workspace_dir = cwd
        os.makedirs(self.workspace_dir, exist_ok=True)
        logger.info(f"Authorized workspace directory: {self.workspace_dir}")

        self.capture_mgr = ScreenCaptureManager(
            monitor_index=monitor,
            target_fps=fps,
            jpeg_quality=quality,
            crop=crop,
        )

        # Check and auto-configure local firewall
        self.firewall_status = FirewallManager.ensure_ports_open(self.port)

        self.app = web.Application(middlewares=[self._auth_middleware])
        self._setup_routes()
        self.runner: Optional[web.AppRunner] = None
        self.site: Optional[web.TCPSite] = None

        # mDNS state
        self.zeroconf: Optional[AsyncZeroconf] = None
        self.service_info: Optional[ServiceInfo] = None

    @_safe_middleware
    async def _auth_middleware(self, request: web.Request, handler):
        # Allow open access to dashboard, health, info, config, ocr, and window/active
        if request.path in ["/", "/health", "/info", "/config", "/ocr", "/window/active"]:
            return await handler(request)

        # Check authentication if token is set
        if self.token:
            auth_header = request.headers.get("Authorization", "")
            x_token = request.headers.get("X-CodeFlow-Token", "")
            query_token = request.query.get("token", "")

            provided_token = ""
            if auth_header.startswith("Bearer "):
                provided_token = auth_header[7:].strip()
            elif x_token:
                provided_token = x_token.strip()
            elif query_token:
                provided_token = query_token.strip()

            if provided_token != self.token:
                return web.json_response(
                    {"error": "Unauthorized: Invalid or missing authentication token."},
                    status=401,
                )

        return await handler(request)

    def _setup_routes(self):
        self.app.router.add_get("/", self.handle_dashboard)
        self.app.router.add_get("/health", self.handle_health)
        self.app.router.add_get("/info", self.handle_info)
        self.app.router.add_get("/config", self.handle_config)
        self.app.router.add_get("/ocr", self.handle_ocr)
        self.app.router.add_get("/window/active", self.handle_active_window)
        self.app.router.add_post("/workspace/set", self.handle_workspace_set)
        self.app.router.add_get("/stream", self.handle_stream)
        self.app.router.add_get("/screenshot", self.handle_screenshot)
        self.app.router.add_post("/workspace/transfer", self.handle_workspace_transfer)

    async def handle_dashboard(self, request: web.Request) -> web.Response:
        """User-friendly host dashboard."""
        local_ip = self._get_local_ip()
        active_win = ActiveWindowDetector.get_active_window_title() or "None / Unsupported"
        local_ip = self._get_local_ip()

        fw_color = "#10b981" if self.firewall_status.get("ports_open") else "#ef4444"
        fw_text = f"Allowed ({self.firewall_status.get('firewall_name')})" if self.firewall_status.get("ports_open") else f"Blocked by {self.firewall_status.get('firewall_name')}"
        fw_alert = ""
        if not self.firewall_status.get("ports_open") and self.firewall_status.get("hint"):
            fw_alert = f"""
        <div class="card" style="border-color: #ef4444; background: #fef2f2; color: #991b1b;">
            <div style="font-weight: 600; font-size: 14px;">⚠️ Firewall Warning: Mobile Devices May Be Blocked</div>
            <p style="font-size: 13px; margin: 6px 0 10px 0;">Your system firewall ({self.firewall_status.get('firewall_name')}) is active and may block incoming connections from your phone. Run this terminal command to allow access:</p>
            <div class="ip-box" style="font-size: 13px; background: #ffffff; color: #111827;">
                <span>{self.firewall_status.get('hint')}</span>
                <button class="btn" onclick="navigator.clipboard.writeText('{self.firewall_status.get('hint')}'); alert('Copied command!')">Copy Command</button>
            </div>
        </div>"""

        html = f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>CodeFlow Companion - Host Ready</title>
    <style>
        :root {{
            --bg: #ffffff;
            --surface: #f9fafb;
            --border: #e5e7eb;
            --text-main: #111827;
            --text-sub: #4b5563;
            --accent: #2563eb;
            --success: #10b981;
        }}
        body {{
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
            background: var(--bg);
            color: var(--text-main);
            margin: 0;
            padding: 32px 16px;
            display: flex;
            justify-content: center;
        }}
        .container {{
            max-width: 680px;
            width: 100%;
        }}
        .header {{
            display: flex;
            align-items: center;
            justify-content: space-between;
            border-bottom: 1px solid var(--border);
            padding-bottom: 16px;
            margin-bottom: 24px;
        }}
        .logo {{
            font-size: 20px;
            font-weight: 700;
            letter-spacing: -0.5px;
        }}
        .status-badge {{
            display: flex;
            align-items: center;
            gap: 6px;
            font-size: 12px;
            font-weight: 600;
            color: var(--success);
            background: #ecfdf5;
            padding: 4px 10px;
            border-radius: 999px;
            border: 1px solid #a7f3d0;
        }}
        .status-dot {{
            width: 8px;
            height: 8px;
            background: var(--success);
            border-radius: 50%;
        }}
        .card {{
            background: var(--surface);
            border: 1px solid var(--border);
            border-radius: 8px;
            padding: 20px;
            margin-bottom: 20px;
        }}
        .ip-box {{
            display: flex;
            align-items: center;
            justify-content: space-between;
            background: #ffffff;
            border: 1px solid var(--border);
            border-radius: 6px;
            padding: 12px 16px;
            margin: 12px 0;
            font-family: monospace;
            font-size: 16px;
            font-weight: 600;
        }}
        .btn {{
            background: var(--accent);
            color: #ffffff;
            border: none;
            border-radius: 6px;
            padding: 8px 14px;
            font-size: 13px;
            font-weight: 500;
            cursor: pointer;
        }}
        .btn:hover {{ background: #1d4ed8; }}
        .preview-box {{
            width: 100%;
            border-radius: 6px;
            overflow: hidden;
            border: 1px solid var(--border);
            background: #000;
            margin-top: 12px;
        }}
        .preview-box img {{
            width: 100%;
            display: block;
        }}
        .steps {{
            padding-left: 20px;
            line-height: 1.6;
            font-size: 14px;
            color: var(--text-sub);
        }}
        .meta-row {{
            display: flex;
            justify-content: space-between;
            padding: 6px 0;
            font-size: 13px;
            border-bottom: 1px dashed var(--border);
        }}
        .meta-row:last-child {{ border-bottom: none; }}
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <div class="logo">⚡ CodeFlow Companion</div>
            <div class="status-badge">
                <span class="status-dot"></span> Ready & Streaming
            </div>
        </div>

        {fw_alert}

        <div class="card">
            <div style="display: flex; gap: 20px; align-items: center; justify-content: space-between;">
                <div style="flex: 1;">
                    <div style="font-weight: 600; font-size: 14px;">Connect from CodeFlow Mobile:</div>
                    <p style="font-size: 13px; color: var(--text-sub); margin: 6px 0 10px 0;">
                        Your mobile app automatically detects this PC via mDNS. If prompted, use this LAN address:
                    </p>
                    <div class="ip-box">
                        <span id="ipText">{local_ip}:{self.port}</span>
                        <button class="btn" onclick="navigator.clipboard.writeText('{local_ip}:{self.port}'); alert('Copied address!')">Copy</button>
                    </div>
                    <div style="font-size: 12px; color: var(--text-sub);">
                        Localhost: <a href="http://127.0.0.1:{self.port}/info" target="_blank">http://127.0.0.1:{self.port}</a>
                    </div>
                </div>
                <div style="text-align: center;">
                    <img src="https://api.qrserver.com/v1/create-qr-code/?size=110x110&margin=4&data=http://{local_ip}:{self.port}" width="110" height="110" alt="Scan QR Code" style="border-radius: 6px; border: 1px solid var(--border);" onerror="this.style.display='none'" />
                    <div style="font-size: 11px; color: var(--text-sub); margin-top: 4px;">Scan with phone</div>
                </div>
            </div>
        </div>

        <div class="card">
            <div style="font-weight: 600; font-size: 14px;">Host Diagnostics</div>
            <div style="margin-top: 10px;">
                <div class="meta-row"><span>Hostname:</span><b>{socket.gethostname()}</b></div>
                <div class="meta-row"><span>Operating System:</span><b>{platform.system()} {platform.release()}</b></div>
                <div class="meta-row"><span>Active Window:</span><b style="max-width: 350px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">{active_win}</b></div>
                <div class="meta-row"><span>Workspace Directory:</span><b style="max-width: 350px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">{self.workspace_dir}</b></div>
                <div class="meta-row"><span>Target FPS:</span><b>{self.capture_mgr.target_fps} FPS</b></div>
                <div class="meta-row"><span>Capture Engine:</span><b>{self.capture_mgr.backend}</b></div>
                <div class="meta-row"><span>LAN Firewall:</span><b style="color: {fw_color};">{fw_text}</b></div>
            </div>
        </div>

        <div class="card">
            <div style="font-weight: 600; font-size: 14px;">Live Screen Stream Preview</div>
            <div class="preview-box">
                <img src="/stream" alt="Live Screen Stream" />
            </div>
        </div>

        <div class="card">
            <div style="font-weight: 600; font-size: 14px;">Quick Setup Guide</div>
            <ol class="steps">
                <li><b>Open CodeFlow on your phone:</b> Tap <i>Monitor</i> to view your PC screen instantly.</li>
                <li><b>Bluetooth Keyboard Pairing:</b> In CodeFlow Settings, tap <i>Register HID</i> and pair this PC in your Bluetooth settings.</li>
                <li><b>Run Automation:</b> Select project files and watch CodeFlow automate terminal and code injection effortlessly!</li>
            </ol>
        </div>
    </div>
</body>
</html>"""
        return web.Response(text=html, content_type="text/html")

    async def handle_health(self, request: web.Request) -> web.Response:
        """Health check endpoint."""
        return web.json_response(
            {
                "status": "ok",
                "version": VERSION,
                "timestamp": round(time.time(), 3),
                "uptime_seconds": round(time.time() - self.start_time, 1),
            }
        )

    async def handle_info(self, request: web.Request) -> web.Response:
        """Detailed host and stream information."""
        monitors = self.capture_mgr.list_monitors()
        active_window = ActiveWindowDetector.get_active_window_title()

        return web.json_response(
            {
                "hostname": socket.gethostname(),
                "os": platform.system(),
                "os_release": platform.release(),
                "os_version": platform.version(),
                "companion_version": VERSION,
                "capture_backend": self.capture_mgr.backend,
                "is_wayland": self.capture_mgr.is_wayland,
                "monitors": monitors,
                "selected_monitor": self.capture_mgr.monitor_index,
                "active_window": active_window,
                "stream_settings": {
                    "target_fps": self.capture_mgr.target_fps,
                    "jpeg_quality": self.capture_mgr.jpeg_quality,
                    "crop": self.capture_mgr.crop,
                    "port": self.port,
                },
                "current_capture_fps": self.capture_mgr.measured_fps,
                "latest_capture_duration_ms": self.capture_mgr.latest_capture_duration_ms,
                "auth_required": bool(self.token),
                "workspace_dir": self.workspace_dir,
                "capabilities": {
                    "mjpeg_stream": True,
                    "screenshot": True,
                    "workspace_transfer": True,
                    "active_window_detection": bool(active_window is not None),
                    "ocr": bool(shutil.which("tesseract")),
                },
            }
        )

    async def handle_config(self, request: web.Request) -> web.Response:
        """Return current configuration."""
        return web.json_response(
            {
                "host": self.host,
                "port": self.port,
                "target_fps": self.capture_mgr.target_fps,
                "jpeg_quality": self.capture_mgr.jpeg_quality,
                "monitor": self.capture_mgr.monitor_index,
                "crop": self.capture_mgr.crop,
                "auth_enabled": bool(self.token),
                "workspace_dir": self.workspace_dir,
            }
        )

    async def handle_screenshot(self, request: web.Request) -> web.Response:
        """Return a single JPEG screenshot."""
        frame = self.capture_mgr.latest_jpeg
        if not frame:
            # Wait up to 1 second for first frame
            for _ in range(10):
                await asyncio.sleep(0.1)
                frame = self.capture_mgr.latest_jpeg
                if frame:
                    break

        if not frame:
            return web.Response(text="No screen frame available yet.", status=503)

        return web.Response(
            body=frame,
            content_type="image/jpeg",
            headers={
                "Cache-Control": "no-cache, no-store, must-revalidate",
                "X-Frame-Timestamp": str(self.capture_mgr.latest_timestamp),
                "X-Capture-Duration-Ms": str(
                    self.capture_mgr.latest_capture_duration_ms
                ),
            },
        )

    async def handle_ocr(self, request: web.Request) -> web.Response:
        """OCR-based screen analysis to verify active windows and open editor tabs."""
        t_start = time.perf_counter()
        query = request.query.get("query", "").strip()
        region = request.query.get("region", "top").strip().lower()

        # 1. Query active window title
        active_window = ActiveWindowDetector.get_active_window_title() or ""
        is_vscode = any(
            term in active_window.lower()
            for term in [
                "visual studio code",
                "code",
                "vscodium",
                "antigravity",
                "cursor",
                "windsurf",
            ]
        )

        tesseract_bin = shutil.which("tesseract")
        has_tesseract = bool(tesseract_bin)

        # 2. Grab screen frame
        frame = self.capture_mgr.latest_jpeg
        if not frame:
            for _ in range(10):
                await asyncio.sleep(0.05)
                frame = self.capture_mgr.latest_jpeg
                if frame:
                    break

        ocr_text = ""
        if frame and has_tesseract and Image:
            loop = asyncio.get_running_loop()
            try:
                def _run_tesseract(jpeg_bytes: bytes, reg: str) -> str:
                    img = Image.open(io.BytesIO(jpeg_bytes))
                    w, h = img.size
                    if reg == "top":
                        # Crop top 35% where VS Code tabs, title bar, and command palette reside
                        img = img.crop((0, 0, w, max(10, int(h * 0.35))))
                    elif reg == "editor":
                        img = img.crop((0, 0, w, max(10, int(h * 0.60))))

                    buf = io.BytesIO()
                    img.save(buf, format="PNG")
                    png_data = buf.getvalue()

                    res = subprocess.run(
                        [tesseract_bin, "stdin", "stdout", "--psm", "6"],
                        input=png_data,
                        capture_output=True,
                        timeout=3.0,
                    )
                    return res.stdout.decode("utf-8", errors="ignore")

                ocr_text = await loop.run_in_executor(
                    None, _run_tesseract, frame, region
                )
            except Exception as e:
                logger.warning(f"OCR execution failed: {e}")

        # 3. Match query against OCR text and active window title
        query_found = False
        if query:
            query_found = self._fuzzy_match_query(query, ocr_text, active_window)
        else:
            query_found = bool(active_window)

        elapsed_ms = round((time.perf_counter() - t_start) * 1000.0, 1)

        return web.json_response(
            {
                "success": True,
                "has_tesseract": has_tesseract,
                "tesseract_path": tesseract_bin,
                "active_window": active_window,
                "is_vscode": is_vscode,
                "query": query,
                "query_found": query_found,
                "text": ocr_text[:1200],
                "elapsed_ms": elapsed_ms,
                "timestamp": time.time(),
            }
        )

    async def handle_active_window(self, request: web.Request) -> web.Response:
        """Fast active window check without OCR."""
        active_window = ActiveWindowDetector.get_active_window_title() or ""
        is_vscode = any(
            term in active_window.lower()
            for term in [
                "visual studio code",
                "code",
                "vscodium",
                "antigravity",
                "cursor",
                "windsurf",
            ]
        )
        return web.json_response(
            {
                "success": True,
                "active_window": active_window,
                "is_vscode": is_vscode,
            }
        )

    async def handle_workspace_set(self, request: web.Request) -> web.Response:
        """Update authorized workspace directory dynamically."""
        try:
            data = await request.json()
            new_path = data.get("path")
            if not new_path or not os.path.exists(new_path) or not os.path.isdir(new_path):
                return web.json_response(
                    {"error": f"Invalid or non-existent directory path: {new_path}"},
                    status=400,
                )
            self.workspace_dir = os.path.abspath(new_path)
            logger.info(f"Workspace directory updated to: {self.workspace_dir}")
            return web.json_response(
                {"status": "success", "workspace_dir": self.workspace_dir}
            )
        except Exception as e:
            return web.json_response({"error": str(e)}, status=500)

    @staticmethod
    def _fuzzy_match_query(query: str, ocr_text: str, window_title: str) -> bool:
        """Smart match query across window title, OCR text, and normalized tokens."""
        if not query:
            return True
        clean_q = re.sub(r"[^a-zA-Z0-9]", "", query.lower())
        if not clean_q:
            return True

        # Check window title first (fastest)
        clean_win = re.sub(r"[^a-zA-Z0-9]", "", window_title.lower())
        if query.lower() in window_title.lower() or clean_q in clean_win:
            return True

        # Check exact substring in OCR text
        clean_ocr = re.sub(r"[^a-zA-Z0-9]", " ", ocr_text.lower())
        if query.lower() in ocr_text.lower() or clean_q in re.sub(r"[^a-zA-Z0-9]", "", clean_ocr):
            return True

        # Fuzzy sequence matcher over word tokens
        words = clean_ocr.split()
        q_len = len(query)
        combined = ""
        for w in words:
            combined += w
            if len(combined) >= max(3, q_len - 2):
                chunk = combined[-q_len - 4 :]
                ratio = difflib.SequenceMatcher(None, clean_q, chunk).ratio()
                if ratio >= 0.72:
                    return True
        return False

    async def handle_stream(self, request: web.Request) -> web.StreamResponse:
        """Continuous ultra-low-latency MJPEG stream."""
        response = web.StreamResponse(
            status=200,
            reason="OK",
            headers={
                "Content-Type": "multipart/x-mixed-replace; boundary=frame",
                "Cache-Control": "no-cache, no-store, must-revalidate",
                "Pragma": "no-cache",
                "Connection": "close",
            },
        )
        await response.prepare(request)

        last_sent_seq = -1
        client_ip = request.remote or "unknown"
        logger.info(f"MJPEG stream client connected: {client_ip}")

        try:
            while True:
                # Wait for a new frame or timeout to check connection
                if self.capture_mgr.frame_sequence == last_sent_seq:
                    try:
                        await asyncio.wait_for(
                            self.capture_mgr.new_frame_event.wait(), timeout=0.1
                        )
                    except asyncio.TimeoutError:
                        continue

                frame = self.capture_mgr.latest_jpeg
                seq = self.capture_mgr.frame_sequence
                if not frame or seq == last_sent_seq:
                    await asyncio.sleep(0.005)
                    continue

                last_sent_seq = seq
                header = (
                    b"--frame\r\n"
                    b"Content-Type: image/jpeg\r\n"
                    b"Content-Length: " + str(len(frame)).encode("ascii") + b"\r\n"
                    b"X-Frame-Timestamp: "
                    + str(self.capture_mgr.latest_timestamp).encode("ascii")
                    + b"\r\n"
                    b"X-Capture-Duration-Ms: "
                    + str(self.capture_mgr.latest_capture_duration_ms).encode("ascii")
                    + b"\r\n\r\n"
                )

                await response.write(header + frame + b"\r\n")

        except (asyncio.CancelledError, ConnectionResetError, ConnectionError):
            logger.info(f"MJPEG stream client disconnected: {client_ip}")
        except Exception as e:
            logger.warning(f"MJPEG client error ({client_ip}): {e}")
        return response

    async def handle_workspace_transfer(self, request: web.Request) -> web.Response:
        """
        Direct authenticated workspace file transfer.
        Writes source file safely to the approved workspace directory,
        validating relative path to prevent any path traversal.
        """
        try:
            data = await request.json()
        except Exception:
            return web.json_response({"error": "Invalid JSON body"}, status=400)

        rel_path = data.get("relative_path")
        content = data.get("content")
        encoding = data.get("encoding", "utf-8")
        expected_sha256 = data.get("sha256")
        overwrite = data.get("overwrite", True)

        if not rel_path or content is None:
            return web.json_response(
                {"error": "Missing 'relative_path' or 'content' in payload."},
                status=400,
            )

        # Path traversal security checks
        norm_rel_path = os.path.normpath(rel_path).lstrip("/\\")
        if (
            norm_rel_path.startswith("..")
            or ".." in norm_rel_path.split(os.sep)
            or os.path.isabs(norm_rel_path)
        ):
            return web.json_response(
                {"error": f"Path traversal attempt rejected: {rel_path}"},
                status=403,
            )

        target_file_path = os.path.abspath(
            os.path.join(self.workspace_dir, norm_rel_path)
        )
        if not target_file_path.startswith(self.workspace_dir):
            return web.json_response(
                {"error": "Target path escapes authorized workspace."},
                status=403,
            )

        if os.path.exists(target_file_path) and not overwrite:
            return web.json_response(
                {"error": f"File already exists and overwrite=false: {norm_rel_path}"},
                status=409,
            )

        # Prepare bytes
        try:
            if encoding == "base64":
                import base64
                file_bytes = base64.b64decode(content)
            else:
                file_bytes = content.encode("utf-8")
        except Exception as e:
            return web.json_response(
                {"error": f"Failed to decode content with encoding '{encoding}': {e}"},
                status=400,
            )

        # Verify checksum if provided
        actual_sha256 = hashlib.sha256(file_bytes).hexdigest()
        if expected_sha256 and expected_sha256.lower() != actual_sha256.lower():
            return web.json_response(
                {
                    "error": "SHA-256 checksum mismatch.",
                    "expected": expected_sha256,
                    "actual": actual_sha256,
                },
                status=422,
            )

        # Write to disk atomically
        parent_dir = os.path.dirname(target_file_path)
        os.makedirs(parent_dir, exist_ok=True)

        temp_target = target_file_path + ".codeflow_tmp"
        try:
            with open(temp_target, "wb") as f:
                f.write(file_bytes)
            os.replace(temp_target, target_file_path)
        except Exception as e:
            if os.path.exists(temp_target):
                os.remove(temp_target)
            return web.json_response(
                {"error": f"Failed to write file to workspace: {e}"},
                status=500,
            )

        logger.info(
            f"Successfully transferred file: {norm_rel_path} ({len(file_bytes)} bytes)"
        )
        return web.json_response(
            {
                "status": "success",
                "relative_path": norm_rel_path,
                "bytes_written": len(file_bytes),
                "sha256": actual_sha256,
                "verified": True,
            }
        )

    def _get_local_ip(self) -> str:
        """Get the primary local LAN IP address."""
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            # Doesn't actually send packets
            s.connect(("8.8.8.8", 80))
            ip = s.getsockname()[0]
            s.close()
            return ip
        except Exception:
            return "127.0.0.1"

    async def _register_mdns(self):
        """Broadcast mDNS service for zero-setup LAN discovery."""
        if not self.enable_mdns or not AsyncZeroconf or not ServiceInfo:
            logger.info("mDNS discovery disabled or zeroconf package not installed.")
            return

        try:
            local_ip = self._get_local_ip()
            hostname = socket.gethostname()
            clean_host = hostname.split(".")[0].replace(" ", "-")
            service_type = "_codeflow._tcp.local."
            service_name = f"CodeFlow-{clean_host}-{self.port}.{service_type}"

            properties = {
                "version": VERSION,
                "hostname": hostname,
                "os": platform.system(),
                "auth_required": "true" if self.token else "false",
                "port": str(self.port),
            }

            self.service_info = ServiceInfo(
                service_type,
                service_name,
                addresses=[socket.inet_aton(local_ip)],
                port=self.port,
                properties=properties,
                server=f"{clean_host}.local.",
            )

            self.zeroconf = AsyncZeroconf(ip_version=IPVersion.V4Only)
            await self.zeroconf.async_register_service(
                self.service_info,
                allow_name_change=True,
                cooperating_responders=True,
            )
            logger.info(
                f"mDNS service broadcasted: {service_name} on {local_ip}:{self.port}"
            )
        except Exception as e:
            err_msg = str(e) if str(e) else type(e).__name__
            logger.warning(f"Failed to register mDNS service: {err_msg}")
            self.zeroconf = None
            self.service_info = None

    async def _unregister_mdns(self):
        """Unregister mDNS service cleanly."""
        if self.zeroconf and self.service_info:
            try:
                await self.zeroconf.async_unregister_service(self.service_info)
                await self.zeroconf.async_close()
                logger.info("mDNS service unregistered.")
            except Exception as e:
                logger.debug(f"Error unregistering mDNS: {e}")
            self.zeroconf = None
            self.service_info = None

    async def start(self):
        """Start capture, HTTP server, and mDNS discovery."""
        await self.capture_mgr.start()

        self.runner = web.AppRunner(self.app, access_log=None)
        await self.runner.setup()
        self.site = web.TCPSite(self.runner, self.host, self.port)
        await self.site.start()

        local_ip = self._get_local_ip()
        logger.info("=" * 60)
        logger.info(f" CodeFlow Companion v{VERSION} is RUNNING")
        logger.info(f" Local Access:   http://127.0.0.1:{self.port}")
        logger.info(f" Network Access: http://{local_ip}:{self.port}")
        logger.info(f" Workspace Dir:  {self.workspace_dir}")
        if self.firewall_status.get("firewall_name") != "None / Unrestricted":
            fw_state = "OPEN" if self.firewall_status.get("ports_open") else "BLOCKED"
            logger.info(f" LAN Firewall:   {self.firewall_status.get('firewall_name')} [{fw_state}]")
            if not self.firewall_status.get("ports_open") and self.firewall_status.get("hint"):
                logger.warning(f" -> Allow mobile access with: {self.firewall_status.get('hint')}")
        if self.token:
            logger.info(f" Auth Token:     {self.token}")
        else:
            logger.info(" Auth Token:     [DISABLED - open local access]")
        logger.info("=" * 60)

        await self._register_mdns()

    async def stop(self):
        """Stop server cleanly."""
        logger.info("Shutting down CodeFlow Companion...")
        await self._unregister_mdns()
        if self.site:
            await self.site.stop()
        if self.runner:
            await self.runner.cleanup()
        await self.capture_mgr.stop()
        logger.info("Shutdown complete.")


def parse_args():
    parser = argparse.ArgumentParser(
        description="CodeFlow Companion - Lightweight Host Screen Streamer & Workspace Agent"
    )
    parser.add_argument(
        "--host",
        default="0.0.0.0",
        help="Host address to bind HTTP server (default: 0.0.0.0)",
    )
    parser.add_argument(
        "--port",
        type=int,
        default=8090,
        help="Port to bind HTTP server (default: 8090)",
    )
    parser.add_argument(
        "--fps",
        type=int,
        default=30,
        help="Target screen capture FPS (default: 30, max: 60)",
    )
    parser.add_argument(
        "--quality",
        type=int,
        default=75,
        help="JPEG compression quality (10-100, default: 75)",
    )
    parser.add_argument(
        "--monitor",
        type=int,
        default=1,
        help="Target monitor index (1 = primary monitor, 0 = all monitors, default: 1)",
    )
    parser.add_argument(
        "--crop",
        type=str,
        default=None,
        help="Crop region format 'X,Y,WIDTH,HEIGHT' (e.g. 0,0,1920,1080)",
    )
    parser.add_argument(
        "--workspace-dir",
        type=str,
        default=None,
        help="Authorized local directory for direct file transfers (default: current working directory)",
    )
    parser.add_argument(
        "--token",
        type=str,
        default=None,
        help="Optional authentication token for protected endpoints",
    )
    parser.add_argument(
        "--no-mdns",
        action="store_true",
        help="Disable automatic LAN mDNS discovery broadcast",
    )
    parser.add_argument(
        "--no-browser",
        action="store_true",
        help="Do not automatically open the host dashboard in the default web browser",
    )
    parser.add_argument(
        "--headless",
        action="store_true",
        help="Run purely in background without launching browser window",
    )
    return parser.parse_args()


async def main():
    args = parse_args()

    crop = None
    if args.crop:
        try:
            parts = [int(p.strip()) for p in args.crop.split(",")]
            if len(parts) == 4:
                crop = (parts[0], parts[1], parts[2], parts[3])
        except Exception:
            logger.warning(f"Invalid --crop argument '{args.crop}', ignoring.")

    server = CodeFlowCompanionServer(
        host=args.host,
        port=args.port,
        fps=args.fps,
        quality=args.quality,
        monitor=args.monitor,
        crop=crop,
        workspace_dir=args.workspace_dir,
        token=args.token,
        enable_mdns=not args.no_mdns,
    )

    await server.start()

    # Automatically open web dashboard for regular users if not headless
    if not args.no_browser and not args.headless:
        try:
            # Short sleep to ensure listener is fully up
            await asyncio.sleep(0.3)
            webbrowser.open(f"http://127.0.0.1:{args.port}")
        except Exception:
            pass

    stop_event = asyncio.Event()

    def _signal_handler():
        stop_event.set()

    loop = asyncio.get_running_loop()
    if sys.platform != "win32":
        import signal
        for sig in (signal.SIGINT, signal.SIGTERM):
            loop.add_signal_handler(sig, _signal_handler)

    try:
        await stop_event.wait()
    except (asyncio.CancelledError, KeyboardInterrupt):
        pass
    finally:
        await server.stop()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except (KeyboardInterrupt, SystemExit):
        pass
