#!/usr/bin/env bash
# Run on a trusted machine with Python 3 and gh logged in as an organization owner:
#   bash scripts/create-publisher-app.sh
# If using act-lin-1 over SSH, forward the callback port from your workstation:
#   ssh -L 8765:127.0.0.1:8765 act-lin-1
# Open the printed localhost URL in your workstation's browser.
# This replaces only the App secrets; it does not create or rotate GPG keys.
# The generated PEM is backed up outside the checkout under ~/.local/share.
set -euo pipefail
umask 077

for tool in gh python3; do
    command -v "$tool" >/dev/null || {
        echo "Required tool missing: $tool" >&2
        exit 1
    }
done
gh auth status --hostname github.com
if ! gh api orgs/vtiinstruments/actions/secrets --jq '.total_count' >/dev/null; then
    echo "Organization-secret access is required. Run:" >&2
    echo "gh auth refresh --hostname github.com --scopes admin:org" >&2
    exit 1
fi
echo "This creates a NEW organization App and replaces VTI_PPA_APP_ID and"
echo "VTI_PPA_APP_PRIVATE_KEY for DiscoveryTool, nextgen-libVTEX and VTEX10xxA-PnP-Driver."
echo "Existing organization-secret repository selections for these names will be replaced."
read -r -p "Continue? Type yes: " answer
[[ "$answer" == yes ]] || {
    echo "Cancelled; no App or secrets changed."
    exit 0
}

python3 - <<'PY'
import html
import http.server
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

ORG = "vtiinstruments"
REPOSITORIES = "DiscoveryTool,nextgen-libVTEX,VTEX10xxA-PnP-Driver"


def set_secret(name, value):
    result = subprocess.run(
        [
            "gh", "secret", "set", name, "--org", ORG,
            "--visibility", "selected", "--repos", REPOSITORIES,
        ],
        input=value, text=True, capture_output=True,
    )
    if result.returncode:
        raise RuntimeError(
            f"Failed to set {name} (gh exit {result.returncode}). "
            "Some secrets may already have changed. Recover using the saved App ID/PEM."
        )


def provision(callback, state, backup_root):
    query = urllib.parse.parse_qs(urllib.parse.urlsplit(callback).query)
    if query.get("state") != [state] or len(query.get("code", [])) != 1:
        raise ValueError("Invalid callback state or code; no credentials exchanged.")
    code = query["code"][0]
    request = urllib.request.Request(
        "https://api.github.com/app-manifests/"
        + urllib.parse.quote(code, safe="")
        + "/conversions",
        data=b"",
        method="POST",
        headers={
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "vti-publisher-app-setup",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            app = json.load(response)
    except (urllib.error.URLError, ValueError) as error:
        raise RuntimeError(
            "GitHub manifest exchange failed. Check connectivity and the App settings; "
            "the code may have expired or already been consumed."
        ) from error
    app_id, pem, slug = app.get("id"), app.get("pem"), app.get("slug")
    if (
        type(app_id) is not int or app_id <= 0
        or not isinstance(pem, str)
        or not pem.startswith(("-----BEGIN RSA PRIVATE KEY-----", "-----BEGIN PRIVATE KEY-----"))
        or not isinstance(slug, str) or not slug
    ):
        raise RuntimeError("GitHub returned incomplete App credentials; no secrets updated.")

    backup_root.mkdir(mode=0o700, parents=True, exist_ok=True)
    backup = Path(tempfile.mkdtemp(prefix="publisher-", dir=backup_root))
    for name, value in (("app-id.txt", str(app_id)), ("private-key.pem", pem)):
        with (backup / name).open("x") as file:
            os.chmod(backup / name, 0o600)
            file.write(value)
    print(f"App ID: {app_id}. Restricted credential backup: {backup}", flush=True)
    set_secret("VTI_PPA_APP_ID", str(app_id))
    set_secret("VTI_PPA_APP_PRIVATE_KEY", pem)
    return "https://github.com/apps/" + urllib.parse.quote(slug, safe="") + "/installations/new"


def main():
    os.umask(0o077)
    state = secrets.token_urlsafe(32)
    backup_root = Path.home() / ".local" / "share" / "vti-publisher-apps"
    deadline = time.monotonic() + 3600
    result = {}

    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, *args):
            # Callback URLs contain a one-use credential; never log requests.
            pass

        def reply(self, status, body):
            data = body.encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Referrer-Policy", "no-referrer")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            path = urllib.parse.urlsplit(self.path).path
            if path == "/":
                self.reply(200, page)
            elif path == "/callback":
                try:
                    install_url = provision(self.path, state, backup_root)
                except ValueError as error:
                    self.reply(400, html.escape(str(error)))
                    return
                except (RuntimeError, OSError) as error:
                    result["error"] = str(error)
                    self.reply(500, "Setup failed. See the terminal for recovery instructions.")
                    return
                result["install_url"] = install_url
                self.reply(
                    200,
                    'App credentials saved and organization secrets updated. '
                    '<b>Installation is still required.</b> '
                    f'<a href="{html.escape(install_url, quote=True)}">Install the App</a> '
                    'on vtiinstruments, choose <b>Only select repositories</b>, and select '
                    '<b>vti-linux-packages</b> only.',
                )
            else:
                self.reply(404, "Not found.")

    with http.server.HTTPServer(("127.0.0.1", 8765), Handler) as server:
        server.timeout = 1
        manifest = {
            "name": "VTI Linux Package Publisher " + time.strftime("%Y%m%d-%H%M%S"),
            "url": "https://github.com/vtiinstruments/vti-linux-packages",
            "description": "Upload Linux package releases and request package-feed publication.",
            "public": False,
            "hook_attributes": {
                "url": "https://github.com/vtiinstruments/vti-linux-packages",
                "active": False,
            },
            "redirect_url": "http://127.0.0.1:8765/callback",
            "default_permissions": {"contents": "write"},
            "default_events": [],
        }
        action = f"https://github.com/organizations/{ORG}/settings/apps/new?state={state}"
        page = (
            '<!doctype html><meta charset="utf-8"><title>Create VTI publisher App</title>'
            f'<form method="post" action="{html.escape(action, quote=True)}">'
            f'<input type="hidden" name="manifest" value="{html.escape(json.dumps(manifest), quote=True)}">'
            '<button type="submit">Create organization GitHub App on GitHub</button></form>'
            '<p>After approval, install on vtiinstruments with access to vti-linux-packages only.</p>'
        )
        print("Open http://127.0.0.1:8765 in your browser and approve App creation.", flush=True)
        print("Remote host? Use: ssh -L 8765:127.0.0.1:8765 act-lin-1", flush=True)
        while not result and time.monotonic() < deadline:
            server.handle_request()
    if "error" in result:
        raise RuntimeError(result["error"])
    if "install_url" not in result:
        raise RuntimeError("Timed out waiting for approval. Check App settings before creating another App.")
    print("Organization App secrets updated. GPG signing secrets were not changed.")
    print("REQUIRED: install the App using " + result["install_url"])
    print("Choose vtiinstruments -> Only select repositories -> vti-linux-packages.")
    print("Keep the PEM backup secure. Repository-level App secrets override these organization secrets.")
    print("If old repository-level App secrets exist, update or remove them before using the new App.")


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, KeyboardInterrupt) as error:
        print(f"ERROR: {error or 'Interrupted; check App settings and secrets before retrying.'}", file=sys.stderr)
        sys.exit(1)
PY
