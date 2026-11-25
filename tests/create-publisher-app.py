import io
import html
import json
from pathlib import Path
import re
import tempfile
import types
import unittest
from unittest.mock import patch


script = Path(__file__).resolve().parents[1] / "scripts" / "create-publisher-app.sh"
source = script.read_text().split("python3 - <<'PY'\n", 1)[1].rsplit("\nPY", 1)[0]
app = types.ModuleType("publisher_app")
exec(compile(source, str(script), "exec"), app.__dict__)


class PublisherAppTests(unittest.TestCase):
    def test_manifest_requires_only_package_publication_permissions(self):
        pages = []

        class Server:
            def __init__(self, address, handler):
                self.handler = handler
                self.address = address

            def __enter__(self):
                return self

            def __exit__(self, *args):
                pass

            def handle_request(self):
                for path in ("/", "/callback?state=test&code=test"):
                    request = types.SimpleNamespace(
                        path=path,
                        reply=lambda status, body: pages.append((status, body)),
                    )
                    self.handler.do_GET(request)

        with (
            patch.object(app.http.server, "HTTPServer", Server),
            patch.object(app, "provision", return_value="https://github.com/apps/test/installations/new"),
            patch.object(app.os, "umask"),
            patch("builtins.print"),
        ):
            app.main()
        manifest = json.loads(html.unescape(re.search(r'name="manifest" value="([^"]+)"', pages[0][1]).group(1)))
        self.assertEqual(manifest["default_permissions"], {"contents": "write"})
        self.assertFalse(manifest["public"])
        self.assertFalse(manifest["hook_attributes"]["active"])
        self.assertEqual(manifest["default_events"], [])
        self.assertEqual(manifest["redirect_url"], "http://127.0.0.1:8765/callback")
        self.assertIn("Installation is still required", pages[1][1])

    def test_invalid_callback_never_exchanges_credentials(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(app.urllib.request, "urlopen") as exchange:
            for query in (
                "?state=wrong&code=test",
                "?state=expected",
                "?state=expected&code=first&code=second",
                "?state=expected&state=wrong&code=test",
            ):
                with self.assertRaises(ValueError):
                    app.provision("/callback" + query, "expected", Path(directory))
            exchange.assert_not_called()

    def test_saves_credentials_and_limits_secret_visibility(self):
        credentials = {
            "id": 123,
            "pem": "-----BEGIN RSA PRIVATE KEY-----\ntest-only\n",
            "slug": "test-publisher",
        }
        with (
            tempfile.TemporaryDirectory() as directory,
            patch.object(app.urllib.request, "urlopen", return_value=io.BytesIO(json.dumps(credentials).encode())) as exchange,
            patch.object(app.subprocess, "run", return_value=types.SimpleNamespace(returncode=0)) as gh,
            patch("builtins.print"),
        ):
            root = Path(directory)
            url = app.provision("/callback?state=expected&code=one-use", "expected", root)
            self.assertEqual(url, "https://github.com/apps/test-publisher/installations/new")
            self.assertEqual(exchange.call_args.args[0].method, "POST")
            backup = next(root.iterdir())
            self.assertEqual((backup / "private-key.pem").read_text(), credentials["pem"])
            self.assertEqual((backup / "app-id.txt").read_text(), "123")
            for call, name, value in zip(
                gh.call_args_list,
                ("VTI_PPA_APP_ID", "VTI_PPA_APP_PRIVATE_KEY"),
                ("123", credentials["pem"]),
            ):
                self.assertEqual(
                    call.args[0],
                    ["gh", "secret", "set", name, "--org", "vtiinstruments",
                     "--visibility", "selected", "--repos",
                     "DiscoveryTool,nextgen-libVTEX,VTEX10xxA-PnP-Driver"],
                )
                self.assertEqual(call.kwargs["input"], value)
                self.assertNotIn(value, call.args[0])

    def test_incomplete_credentials_never_update_secrets(self):
        with (
            tempfile.TemporaryDirectory() as directory,
            patch.object(app.urllib.request, "urlopen", return_value=io.BytesIO(b'{"id":123}')),
            patch.object(app.subprocess, "run") as gh,
        ):
            with self.assertRaisesRegex(RuntimeError, "incomplete"):
                app.provision("/callback?state=expected&code=test", "expected", Path(directory))
            gh.assert_not_called()
            self.assertEqual(list(Path(directory).iterdir()), [])

    def test_failed_secret_update_preserves_backup_without_echoing_key(self):
        pem = "-----BEGIN PRIVATE KEY-----\ntest-only\n"
        credentials = {"id": 123, "pem": pem, "slug": "test"}
        with (
            tempfile.TemporaryDirectory() as directory,
            patch.object(app.urllib.request, "urlopen", return_value=io.BytesIO(json.dumps(credentials).encode())),
            patch.object(app.subprocess, "run", return_value=types.SimpleNamespace(returncode=1)),
            patch("builtins.print"),
        ):
            with self.assertRaisesRegex(RuntimeError, "Recover") as error:
                app.provision("/callback?state=expected&code=test", "expected", Path(directory))
            self.assertNotIn(pem, str(error.exception))
            self.assertEqual(next(Path(directory).glob("*/private-key.pem")).read_text(), pem)


if __name__ == "__main__":
    unittest.main()
