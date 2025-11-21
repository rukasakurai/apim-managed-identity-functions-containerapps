"""Integration tests for APIM-protected backend endpoints.

Runs simple assertions against:
1. Direct Function App HTTP endpoint (expected auth failure / 401 or 403)
2. Function App via APIM (expected success / 200)
3. Direct WebSocket endpoint (expected failure)
4. WebSocket via APIM (expected success)

Usage (local):
    pip install -r tests/requirements.txt
    python tests/test_endpoints.py

Local mode derives resource names from `azd env get-values`.
CI mode expects environment variables:
    FUNCTION_APP_NAME
    APIM_SERVICE_NAME
    WEBSOCKET_APP_FQDN (the FQDN of the container app hosting the websocket, no scheme)

Exit code: 0 when all expected outcomes match; 1 otherwise.
"""
from __future__ import annotations

import asyncio
import json
import os
import subprocess
import sys
import uuid  # for per-request correlation id (rid) appended to query string
from dataclasses import dataclass
from typing import Callable, List, Optional

import requests
import websockets
from websockets.exceptions import InvalidHandshake
try:  # Prefer new name (websockets >= 12)
    from websockets.exceptions import InvalidStatus as StatusError  # type: ignore
except ImportError:  # pragma: no cover
    try:  # Fallback to old name (websockets < 12)
        from websockets.exceptions import InvalidStatusCode as StatusError  # type: ignore
    except ImportError:  # pragma: no cover
        StatusError = None  # type: ignore

# --- Config & Utilities -------------------------------------------------------------------------

COLOR = {
    "green": "\033[92m",
    "red": "\033[91m",
    "yellow": "\033[93m",
    "blue": "\033[94m",
    "reset": "\033[0m",
}

def color(txt: str, c: str) -> str:
    if not sys.stdout.isatty():  # avoid raw codes when output redirected
        return txt
    return f"{COLOR.get(c,'')}{txt}{COLOR['reset']}"


def load_env() -> dict:
    # Prefer explicit env vars (CI) then fall back to azd env get-values (local)
    # Added appGatewayFqdn so we can exercise Application Gateway endpoints, matching README manual tests.
    keys = ["functionAppName", "apimServiceName", "websocketAppFqdn", "appGatewayFqdn"]
    values = {}
    # Map CI variable names to internal keys
    mapping = {
        "FUNCTION_APP_NAME": "functionAppName",
        "APIM_SERVICE_NAME": "apimServiceName",
        "WEBSOCKET_APP_FQDN": "websocketAppFqdn",
        "APP_GW_FQDN": "appGatewayFqdn",  # explicit CI var for App Gateway
    }
    for ci_key, internal in mapping.items():
        if ci_key in os.environ and os.environ[ci_key]:
            values[internal] = os.environ[ci_key]

    missing = [k for k in keys if k not in values]
    if missing:
        try:
            result = subprocess.run(
                ["azd", "env", "get-values"], capture_output=True, text=True, check=True
            )
            for line in result.stdout.splitlines():
                if "=" in line:
                    k, v = line.split("=", 1)
                    v = v.strip().strip('"')
                    if k in keys and k not in values:
                        values[k] = v
        except Exception as ex:  # noqa: BLE001
            print(color(f"Failed to load values via 'azd env get-values': {ex}", "red"))

    still_missing = [k for k in keys if k not in values or not values[k]]
    if still_missing:
        print(color(f"Missing required environment values: {', '.join(still_missing)}", "red"))
        sys.exit(2)

    return values


@dataclass
class TestResult:
    name: str
    passed: bool
    detail: str = ""

# --- HTTP Tests ----------------------------------------------------------------------------------

def test_http(url: str, expected_status: int) -> TestResult:
    """Issue a simple GET expecting a particular status.

    Automatically appends a unique correlation id (rid) as a query parameter so the
    same value flows into downstream logs (e.g. AGWAccessLogs.requestUri and
    ApiManagementGatewayLogs.RequestUrl) for later correlation in KQL. We use a
    GUID per request (uniqueness > ability to group) per requirement.
    """
    rid = uuid.uuid4().hex  # short, lowercase hex form
    separator = '&' if '?' in url else '?'
    traced_url = f"{url}{separator}rid={rid}"
    name = f"HTTP {url} -> {expected_status}"  # keep name stable (no rid) for test summary grouping
    try:
        resp = requests.get(traced_url, timeout=15)
        if resp.status_code == expected_status:
            # Reduced redundancy: URL already appears in test name; include only status & rid for correlation
            return TestResult(name, True, f"status={resp.status_code} rid={rid}")
        return TestResult(
            name,
            False,
            f"expected={expected_status} got={resp.status_code} rid={rid} body={resp.text[:200]}",
        )
    except Exception as ex:  # noqa: BLE001
        return TestResult(name, False, f"error={ex} rid={rid}")


# --- WebSocket Tests ----------------------------------------------------------------------------

async def test_ws(url: str, should_succeed: bool) -> TestResult:
    """Attempt a websocket connection.

    Enhancements over the original implementation:
    - Retries (small) for transient network/opening timeouts.
    - Classifies opening handshake TimeoutError as an acceptable 'blocked' outcome when we *expect* failure.
    - Keeps overall runtime low (max extra ~3-4 seconds) by using short backoff.
    - Appends a unique correlation id (rid) as a query parameter so the WebSocket handshake
      (logged as HTTP) flows into downstream logs for correlation, matching HTTP test pattern.
    """
    rid = uuid.uuid4().hex  # short, lowercase hex form
    separator = '&' if '?' in url else '?'
    traced_url = f"{url}{separator}rid={rid}"
    name = f"WS {url} -> {'success' if should_succeed else 'fail'}"  # keep name stable (no rid) for test summary grouping

    max_retries_success = 2   # 2 retries (3 total attempts) for success path (e.g., cold start or transient race)
    max_retries_failure = 1   # usually one attempt enough when we *expect* failure; we only retry on timeout
    base_open_timeout = 15

    async def classify_exception(ex: Exception) -> TestResult:
        status_code = getattr(ex, 'status_code', None)
        ex_type = ex.__class__.__name__
        is_status_exception = (
            (StatusError and isinstance(ex, StatusError))
            or isinstance(ex, InvalidHandshake)
        )

        # Treat timeout during opening as *blocked* when failure is expected (ingress / network policy)
        if not should_succeed and (is_status_exception or status_code in (401, 403) or isinstance(ex, TimeoutError)):
            detail = (
                f"blocked status={status_code} rid={rid}" if status_code else f"blocked ({ex_type}) rid={rid}"
            )
            return TestResult(name, True, detail)

        if should_succeed:
            return TestResult(name, False, f"error={ex_type}: {ex} rid={rid}")
        return TestResult(name, False, f"unexpected failure type={ex_type}: {ex} rid={rid}")

    retries = max_retries_success if should_succeed else max_retries_failure
    attempt = 0
    while True:
        attempt += 1
        try:
            async with websockets.connect(traced_url, open_timeout=base_open_timeout) as ws:
                await ws.send(json.dumps({"type": "ping"}))
                _ = await ws.recv()
                if should_succeed:
                    return TestResult(name, True, f"connected & message round-trip rid={rid}")
                # We expected failure but succeeded -> classify as failure
                return TestResult(name, False, f"connection succeeded but should fail rid={rid}")
        except TimeoutError as tex:  # noqa: PERF203  # opening handshake timeout
            # Success path: retry if attempts remain. Failure path: classify as blocked.
            if should_succeed and attempt <= retries:
                await asyncio.sleep(1.0 * attempt)  # simple linear backoff
                continue
            return await classify_exception(tex)
        except Exception as ex:  # noqa: BLE001
            # For success case: retry ONLY for transient network issues
            transient_types = (ConnectionResetError, OSError)
            if should_succeed and isinstance(ex, transient_types) and attempt <= retries:
                await asyncio.sleep(1.0 * attempt)
                continue
            return await classify_exception(ex)


# --- Runner --------------------------------------------------------------------------------------

async def run_all() -> int:
    env = load_env()
    function_app = env["functionAppName"]
    apim = env["apimServiceName"]
    ws_fqdn = env["websocketAppFqdn"]
    app_gw = env["appGatewayFqdn"]  # Application Gateway is always deployed

    print(color("=== Integration Tests ===", "blue"))
    print(f"Function App: {function_app}")
    print(f"APIM Service: {apim}")
    print(f"WebSocket FQDN: {ws_fqdn}")
    print(f"App Gateway FQDN: {app_gw}")
    print("")

    tests: List[TestResult] = []

    # HTTP tests
    tests.append(test_http(f"https://{function_app}.azurewebsites.net/api/hello", 401))  # direct should fail
    tests.append(test_http(f"https://{apim}.azure-api.net/hello-api/hello", 200))  # via APIM
    # App Gateway currently exposes only HTTP (no TLS) per README; expect success (200)
    tests.append(test_http(f"http://{app_gw}/hello-api/hello", 200))  # via App Gateway should work

    # WebSocket tests
    tests.append(await test_ws(f"wss://{ws_fqdn}", should_succeed=False))
    tests.append(await test_ws(f"wss://{apim}.azure-api.net/wss", should_succeed=True))  # via APIM
    # App Gateway listener is ws:// (no TLS yet) per README; expect success
    tests.append(await test_ws(f"ws://{app_gw}/wss", should_succeed=True))

    # Summary
    passed = [t for t in tests if t.passed]
    print("")
    for t in tests:
        status = color("PASS", "green") if t.passed else color("FAIL", "red")
        print(f"[{status}] {t.name} - {t.detail}")

    print("")
    print(color(f"Result: {len(passed)}/{len(tests)} passed", "blue"))
    rc = 0 if len(passed) == len(tests) else 1
    return rc


def main() -> None:
    try:
        rc = asyncio.run(run_all())
        sys.exit(rc)
    except KeyboardInterrupt:
        print("Interrupted")
        sys.exit(130)


if __name__ == "__main__":  # pragma: no cover
    main()
