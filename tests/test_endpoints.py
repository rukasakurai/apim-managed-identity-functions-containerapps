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
    keys = ["functionAppName", "apimServiceName", "websocketAppFqdn"]
    values = {}
    # Map CI variable names to internal keys
    mapping = {
        "FUNCTION_APP_NAME": "functionAppName",
        "APIM_SERVICE_NAME": "apimServiceName",
        "WEBSOCKET_APP_FQDN": "websocketAppFqdn",
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
    name = f"HTTP {url} -> {expected_status}"
    try:
        resp = requests.get(url, timeout=15)
        if resp.status_code == expected_status:
            return TestResult(name, True, f"status={resp.status_code}")
        return TestResult(name, False, f"expected={expected_status} got={resp.status_code} body={resp.text[:200]}")
    except Exception as ex:  # noqa: BLE001
        return TestResult(name, False, f"error={ex}")


# --- WebSocket Tests ----------------------------------------------------------------------------

async def test_ws(url: str, should_succeed: bool) -> TestResult:
    """Attempt a websocket connection.

    Enhancements over the original implementation:
    - Retries (small) for transient network/opening timeouts.
    - Classifies opening handshake TimeoutError as an acceptable 'blocked' outcome when we *expect* failure.
    - Keeps overall runtime low (max extra ~3-4 seconds) by using short backoff.
    """
    name = f"WS {url} -> {'success' if should_succeed else 'fail'}"

    max_retries_success = 2   # retry once for success path (e.g., cold start or transient race)
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
                f"blocked status={status_code}" if status_code else f"blocked ({ex_type})"
            )
            return TestResult(name, True, detail)

        if should_succeed:
            return TestResult(name, False, f"error={ex_type}: {ex}")
        return TestResult(name, False, f"unexpected failure type={ex_type}: {ex}")

    retries = max_retries_success if should_succeed else max_retries_failure
    attempt = 0
    while True:
        attempt += 1
        try:
            async with websockets.connect(url, open_timeout=base_open_timeout) as ws:
                await ws.send(json.dumps({"type": "ping"}))
                _ = await ws.recv()
                if should_succeed:
                    return TestResult(name, True, "connected & message round-trip")
                # We expected failure but succeeded -> classify as failure
                return TestResult(name, False, "connection succeeded but should fail")
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

    print(color("=== Integration Tests ===", "blue"))
    print(f"Function App: {function_app}")
    print(f"APIM Service: {apim}")
    print(f"WebSocket FQDN: {ws_fqdn}\n")

    tests: List[TestResult] = []

    # HTTP tests
    tests.append(test_http(f"https://{function_app}.azurewebsites.net/api/hello", 401))  # direct should fail
    tests.append(test_http(f"https://{apim}.azure-api.net/hello-api/hello", 200))  # via APIM should pass

    # WebSocket tests
    tests.append(await test_ws(f"wss://{ws_fqdn}", should_succeed=False))
    tests.append(await test_ws(f"wss://{apim}.azure-api.net/wss", should_succeed=True))

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
