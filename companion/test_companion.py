#!/usr/bin/env python3
"""
Unit and integration tests for CodeFlow Companion.
Tests endpoints, authentication, path traversal protection, and MJPEG format.
"""

import asyncio
import hashlib
import json
import os
import shutil
import tempfile
import unittest
from aiohttp import ClientSession
from codeflow_streamer import CodeFlowCompanionServer, VERSION


class TestCodeFlowCompanion(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.temp_workspace = tempfile.mkdtemp(prefix="codeflow_test_workspace_")
        self.port = 8199
        self.token = "test-secret-token-12345"
        self.server = CodeFlowCompanionServer(
            host="127.0.0.1",
            port=self.port,
            fps=20,
            quality=50,
            monitor=1,
            workspace_dir=self.temp_workspace,
            token=self.token,
            enable_mdns=False,  # Don't broadcast in unit tests
        )
        await self.server.start()
        # Give a short moment for initialization
        await asyncio.sleep(0.1)

    async def asyncTearDown(self):
        await self.server.stop()
        if os.path.exists(self.temp_workspace):
            shutil.rmtree(self.temp_workspace, ignore_errors=True)

    async def test_health_endpoint(self):
        async with ClientSession() as session:
            async with session.get(f"http://127.0.0.1:{self.port}/health") as resp:
                self.assertEqual(resp.status, 200)
                data = await resp.json()
                self.assertEqual(data["status"], "ok")
                self.assertEqual(data["version"], VERSION)
                self.assertIn("uptime_seconds", data)

    async def test_info_endpoint(self):
        async with ClientSession() as session:
            async with session.get(f"http://127.0.0.1:{self.port}/info") as resp:
                self.assertEqual(resp.status, 200)
                data = await resp.json()
                self.assertEqual(data["companion_version"], VERSION)
                self.assertIn("hostname", data)
                self.assertIn("os", data)
                self.assertIn("stream_settings", data)
                self.assertTrue(data["auth_required"])
                self.assertEqual(data["workspace_dir"], self.temp_workspace)

    async def test_config_endpoint(self):
        async with ClientSession() as session:
            async with session.get(f"http://127.0.0.1:{self.port}/config") as resp:
                self.assertEqual(resp.status, 200)
                data = await resp.json()
                self.assertEqual(data["port"], self.port)
                self.assertEqual(data["target_fps"], 20)
                self.assertEqual(data["jpeg_quality"], 50)
                self.assertTrue(data["auth_enabled"])

    async def test_screenshot_endpoint(self):
        headers = {"Authorization": f"Bearer {self.token}"}
        async with ClientSession() as session:
            async with session.get(
                f"http://127.0.0.1:{self.port}/screenshot", headers=headers
            ) as resp:
                self.assertEqual(resp.status, 200)
                self.assertEqual(resp.content_type, "image/jpeg")
                data = await resp.read()
                # Verify JPEG SOI header
                self.assertTrue(len(data) > 10)
                self.assertEqual(data[:2], b"\xff\xd8")

    async def test_auth_protection_on_transfer(self):
        # Without token -> 401
        async with ClientSession() as session:
            payload = {
                "relative_path": "test.txt",
                "content": "hello world",
            }
            async with session.post(
                f"http://127.0.0.1:{self.port}/workspace/transfer", json=payload
            ) as resp:
                self.assertEqual(resp.status, 401)

    async def test_workspace_transfer_success(self):
        headers = {"Authorization": f"Bearer {self.token}"}
        content = "print('Hello CodeFlow from mobile')\n"
        expected_sha256 = hashlib.sha256(content.encode("utf-8")).hexdigest()

        payload = {
            "relative_path": "src/main.py",
            "content": content,
            "sha256": expected_sha256,
            "overwrite": True,
        }

        async with ClientSession() as session:
            async with session.post(
                f"http://127.0.0.1:{self.port}/workspace/transfer",
                json=payload,
                headers=headers,
            ) as resp:
                self.assertEqual(resp.status, 200)
                res_data = await resp.json()
                self.assertEqual(res_data["status"], "success")
                self.assertEqual(res_data["sha256"], expected_sha256)
                self.assertTrue(res_data["verified"])

        # Verify on filesystem
        expected_file = os.path.join(self.temp_workspace, "src", "main.py")
        self.assertTrue(os.path.exists(expected_file))
        with open(expected_file, "r") as f:
            self.assertEqual(f.read(), content)

    async def test_path_traversal_rejection(self):
        headers = {"Authorization": f"Bearer {self.token}"}
        payload = {
            "relative_path": "../../etc/shadow",
            "content": "bad data",
        }
        async with ClientSession() as session:
            async with session.post(
                f"http://127.0.0.1:{self.port}/workspace/transfer",
                json=payload,
                headers=headers,
            ) as resp:
                self.assertEqual(resp.status, 403)

    async def test_dashboard_rendering(self):
        async with ClientSession() as session:
            async with session.get(f"http://127.0.0.1:{self.port}/") as resp:
                self.assertEqual(resp.status, 200)
                self.assertEqual(resp.content_type, "text/html")
                body = await resp.text()
                self.assertIn("CodeFlow Companion", body)
                self.assertIn("Host Diagnostics", body)
                self.assertIn("Target FPS:", body)

    async def test_active_window_endpoint(self):
        async with ClientSession() as session:
            async with session.get(f"http://127.0.0.1:{self.port}/window/active") as resp:
                self.assertEqual(resp.status, 200)
                data = await resp.json()
                self.assertTrue(data["success"])
                self.assertIn("active_window", data)
                self.assertIn("is_vscode", data)

    async def test_ocr_endpoint(self):
        async with ClientSession() as session:
            async with session.get(f"http://127.0.0.1:{self.port}/ocr?query=test") as resp:
                self.assertEqual(resp.status, 200)
                data = await resp.json()
                self.assertTrue(data["success"])
                self.assertIn("has_tesseract", data)
                self.assertIn("active_window", data)
                self.assertIn("is_vscode", data)
                self.assertIn("query_found", data)
                self.assertIn("elapsed_ms", data)

    async def test_workspace_set_endpoint(self):
        new_ws = tempfile.mkdtemp(prefix="codeflow_new_ws_")
        try:
            headers = {"Authorization": f"Bearer {self.token}"}
            async with ClientSession() as session:
                async with session.post(
                    f"http://127.0.0.1:{self.port}/workspace/set",
                    json={"path": new_ws},
                    headers=headers,
                ) as resp:
                    self.assertEqual(resp.status, 200)
                    data = await resp.json()
                    self.assertEqual(data["status"], "success")
                    self.assertEqual(data["workspace_dir"], os.path.abspath(new_ws))
        finally:
            if os.path.exists(new_ws):
                shutil.rmtree(new_ws, ignore_errors=True)

    async def test_workspace_scaffold_endpoint(self):
        headers = {"Authorization": f"Bearer {self.token}"}
        payload = {
            "directories": ["lib/screens", "lib/models", "lib/widgets"],
            "files": [
                {"relative_path": "lib/main.dart", "content": "void main() {}"},
                {"relative_path": "lib/screens/home.dart", "content": ""},
                "lib/models/user.dart",
            ],
        }
        async with ClientSession() as session:
            async with session.post(
                f"http://127.0.0.1:{self.port}/workspace/scaffold",
                json=payload,
                headers=headers,
            ) as resp:
                self.assertEqual(resp.status, 200)
                data = await resp.json()
                self.assertEqual(data["status"], "success")
                self.assertTrue(data["directories_created"] >= 3)
                self.assertEqual(data["files_created"], 3)

        # Verify files and directories exist in workspace
        self.assertTrue(os.path.isdir(os.path.join(self.temp_workspace, "lib", "screens")))
        self.assertTrue(os.path.isfile(os.path.join(self.temp_workspace, "lib", "main.dart")))
        self.assertTrue(os.path.isfile(os.path.join(self.temp_workspace, "lib", "screens", "home.dart")))
        self.assertTrue(os.path.isfile(os.path.join(self.temp_workspace, "lib", "models", "user.dart")))

    async def test_workspace_scaffold_path_traversal_protection(self):
        headers = {"Authorization": f"Bearer {self.token}"}
        payload = {
            "directories": ["../../etc"],
            "files": ["../../../escaped.txt"],
        }
        async with ClientSession() as session:
            async with session.post(
                f"http://127.0.0.1:{self.port}/workspace/scaffold",
                json=payload,
                headers=headers,
            ) as resp:
                self.assertEqual(resp.status, 403)

    async def test_workspace_execute_endpoint(self):
        headers = {"Authorization": f"Bearer {self.token}"}
        payload = {"command": "echo 'CodeFlow Direct Setup'"}
        async with ClientSession() as session:
            async with session.post(
                f"http://127.0.0.1:{self.port}/workspace/execute",
                json=payload,
                headers=headers,
            ) as resp:
                self.assertEqual(resp.status, 200)
                data = await resp.json()
                self.assertEqual(data["status"], "success")
                self.assertEqual(data["returncode"], 0)
                self.assertIn("CodeFlow Direct Setup", data["stdout"])


if __name__ == "__main__":
    unittest.main()
