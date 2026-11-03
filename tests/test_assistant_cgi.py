"""CGI behavior tests for optional external companion, using isolated paths.

This exercises POSIX shell endpoints, not the target MIPS HTTP server.
"""
from pathlib import Path
import json
import os
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
API = ROOT / "web/cgi-bin/api"


class AssistantCGITests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        base = Path(self.tmp.name)
        self.flag = base / "services/llm_companion.enabled"
        self.heartbeat = base / "heartbeat"
        self.csrf_file = base / "csrf"
        self.csrf_file.write_text("token-for-tests\n")
        self.env = os.environ.copy()
        self.env.update(
            SERVICE_STATE_DIR=str(base / "services"),
            ASSISTANT_HEARTBEAT_FILE=str(self.heartbeat),
            CSRF_FILE=str(self.csrf_file),
            REMOTE_USER="admin",
            REQUEST_METHOD="GET",
        )

    def query(self, op, *, method="GET", body="", override=None):
        env = dict(self.env)
        env["REQUEST_METHOD"] = method
        env["QUERY_STRING"] = "op=" + op
        if override:
            env.update(override)
        process = subprocess.run(
            ["sh", str(API)], input=body, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env,
            timeout=10, check=True,
        )
        # CGI emits headers, blank line and a JSON document.
        self.assertIn("Content-Type: application/json", process.stdout)
        return json.loads(process.stdout.split("\n\n", 1)[-1])

    def test_default_disabled_without_any_daemon(self):
        response = self.query("assistant_status")
        self.assertTrue(response["ok"])
        self.assertFalse(response["enabled"])
        self.assertFalse(response["connected"])
        self.assertFalse(self.flag.exists())

    def test_csrf_and_post_required(self):
        self.assertFalse(self.query("assistant_toggle")["ok"])
        self.assertFalse(self.query("assistant_toggle", method="POST", body="enabled=1&csrf=wrong")["ok"])
        self.assertFalse(self.flag.exists())
        self.assertFalse(self.query("assistant_toggle", method="POST",
                                    body="enabled=1&csrf=token-for-tests",
                                    override={"REMOTE_USER": ""})["ok"])

    def test_enabled_heartbeat_disabled_lifecycle(self):
        on = self.query("assistant_toggle", method="POST", body="enabled=1&csrf=token-for-tests")
        self.assertTrue(on["enabled"])
        self.assertFalse(on["connected"])
        self.assertTrue(self.flag.exists())
        hb = self.query("assistant_heartbeat", method="POST", body="csrf=token-for-tests")
        self.assertTrue(hb["connected"])
        off = self.query("assistant_toggle", method="POST", body="enabled=0&csrf=token-for-tests")
        self.assertFalse(off["enabled"])
        self.assertFalse(off["connected"])
        self.assertFalse(self.flag.exists())
        self.assertFalse(self.heartbeat.exists())
        self.assertFalse(self.query("assistant_heartbeat", method="POST", body="csrf=token-for-tests")["ok"])

    def test_stale_heartbeat_is_not_connected(self):
        self.query("assistant_toggle", method="POST", body="enabled=1&csrf=token-for-tests")
        self.heartbeat.write_text("1\n")
        response = self.query("assistant_status")
        self.assertEqual(response["state"], "waiting")
        self.assertFalse(response["connected"])


if __name__ == "__main__":
    unittest.main()
