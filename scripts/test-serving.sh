#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
image="${SERVING_TEST_IMAGE:-template-react-vite:serving-test}"
container=""
cleanup() {
  if [[ -n "$container" ]]; then
    docker rm -f "$container" >/dev/null
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

docker build --platform linux/amd64 -t "$image" .
ports="$(docker image inspect --format '{{json .Config.ExposedPorts}}' "$image")"
[[ "$ports" == '{"5173/tcp":{}}' ]] || { echo "FAIL exposed ports: $ports" >&2; exit 1; }
echo "PASS exposed ports: $ports"
container="$(docker run -d -p 127.0.0.1::5173 -e DATABASE_URL=serving-test-secret-not-for-browser "$image")"
port="$(docker inspect --format '{{(index (index .NetworkSettings.Ports "5173/tcp") 0).HostPort}}' "$container")"
python3 - "$container" "$port" <<'PY'
import http.client
import io
import json
import re
import subprocess
import sys
import tarfile
import time

container, port = sys.argv[1:]
secret = b"serving-test-secret-not-for-browser"

def docker(*args):
    return subprocess.check_output(["docker", *args], timeout=10)

def request(path, method="GET", host="localhost"):
    connection = http.client.HTTPConnection("127.0.0.1", int(port), timeout=2)
    try:
        connection.request(method, path, headers={"Host": host})
        response = connection.getresponse()
        return response.status, dict(response.getheaders()), response.read()
    finally:
        connection.close()

def check(condition, message):
    if not condition:
        raise AssertionError(message)
    print("PASS " + message, flush=True)

# One deadline covers startup and Docker's actual HEALTHCHECK, not just a TCP port.
deadline = time.monotonic() + 60
while time.monotonic() < deadline:
    state = json.loads(docker("inspect", container))[0]["State"]
    if not state["Running"]:
        raise AssertionError("container exited: " + docker("logs", container).decode())
    if state["Health"]["Status"] == "healthy":
        break
    time.sleep(1)
else:
    raise AssertionError("container did not become healthy within 60s")
check(True, "Docker HEALTHCHECK healthy")
check(docker("exec", container, "id", "-u").strip() != b"0", "non-root runtime")
check(docker("exec", container, "id", "-un").strip() == b"nginx", "runtime user nginx")
config = json.loads(docker("inspect", container))[0]["Config"]
check(config["Cmd"] == ["nginx", "-g", "daemon off;"], "nginx foreground command")
check(docker("exec", container, "sh", "-c", "test ! -e /app && ! command -v node && ! command -v npm").strip() == b"", "no source or Node build tooling in runtime")

status, headers, index = request("/")
check(status == 200 and "text/html" in headers.get("Content-Type", "") and b'id="root"' in index, "/ 200 HTML")
check(headers.get("Cache-Control") == "no-cache", "/ no-cache")
status, headers, body = request("/projects/example/deep-link")
check(status == 200 and body == index and headers.get("Cache-Control") == "no-cache", "deep route 200 index HTML no-cache")
status, headers, body = request("/", "HEAD")
check(status == 200 and body == b"" and headers.get("Cache-Control") == "no-cache", "HEAD / 200 no-cache")
status, headers, body = request("/", host="arbitrary.published.example:5173")
check(status == 200 and body == index, "arbitrary Host accepted")
assets = re.findall(rb'(?:src|href)="(/assets/[^"?]+)"', index)
check(bool(assets), "hashed assets referenced by index")
for asset in assets:
    path = asset.decode()
    check(bool(re.search(r'-[A-Za-z0-9_-]{8,}\.(?:js|css)$', path)), "hashed filename " + path)
    status, headers, body = request(path)
    check(status == 200 and len(body) > 0 and headers.get("Cache-Control") == "public, max-age=31536000, immutable", path + " 200 immutable")
    check(("javascript" if path.endswith(".js") else "text/css") in headers.get("Content-Type", ""), path + " correct MIME")
    check(secret not in body, path + " excludes runtime secret")
status, headers, body = request("/assets/missing.js")
check(status == 404 and "immutable" not in headers.get("Cache-Control", ""), "missing asset 404 without immutable caching")
status, headers, body = request("/healthz")
check(status == 200 and body == b"ok" and "text/plain" in headers.get("Content-Type", "") and headers.get("Cache-Control") == "no-store", "/healthz 200 ok no-store")
for path in ("/.env", "/assets/.hidden", "/api", "/api/missing", "/assets/"):
    status, headers, body = request(path)
    check(status in (403, 404) and body != index, path + " denied without SPA fallback")
check("nginx/" not in headers.get("Server", ""), "server version not disclosed")
archive = docker("cp", container + ":/usr/share/nginx/html/.", "-")
with tarfile.open(fileobj=io.BytesIO(archive)) as files:
    for member in files:
        if member.isfile():
            content = files.extractfile(member).read()
            check(secret not in content, member.name + " served file excludes runtime DATABASE_URL value")
check(secret not in index, "HTML excludes runtime secret")
print("PASS production serving contract", flush=True)
PY
