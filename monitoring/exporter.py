#!/usr/bin/env python3
"""Simple Prometheus exporter for Qubetics validator metrics."""

import argparse
import os
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from typing import Optional

import json
import urllib.request

from prometheus_client import CollectorRegistry, Gauge, generate_latest


class MetricsHandler(BaseHTTPRequestHandler):
    registry = CollectorRegistry()
    height_gauge = Gauge("qubetics_block_height", "Current block height", registry=registry)
    lag_gauge = Gauge("qubetics_block_lag", "Block lag versus reference", registry=registry)
    peer_gauge = Gauge("qubetics_peer_count", "Connected peers", registry=registry)
    catching = Gauge("qubetics_catching_up", "Node still catching up (1=yes)", registry=registry)

    rpc_url: str = "http://127.0.0.1:26657"
    reference_url: Optional[str] = None

    def do_GET(self):  # noqa: N802
        if self.path != "/metrics":
            self.send_response(404)
            self.end_headers()
            return

        try:
            local = fetch_status(self.rpc_url)
            reference = fetch_status(self.reference_url) if self.reference_url else local
            local_height = int(local.get("result", {}).get("sync_info", {}).get("latest_block_height", 0))
            reference_height = int(reference.get("result", {}).get("sync_info", {}).get("latest_block_height", 0))
            lag = max(reference_height - local_height, 0)
            peers = len(local.get("result", {}).get("peers", []))
            catching = 1 if str(local.get("result", {}).get("sync_info", {}).get("catching_up", "true")).lower() == "true" else 0

            self.height_gauge.set(local_height)
            self.lag_gauge.set(lag)
            self.peer_gauge.set(peers)
            self.catching.set(catching)
        except Exception as exc:  # pragma: no cover - exporter should always respond
            sys.stderr.write(f"Exporter error: {exc}\n")

        output = generate_latest(self.registry)
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; version=0.0.4")
        self.send_header("Content-Length", str(len(output)))
        self.end_headers()
        self.wfile.write(output)


def fetch_status(url: Optional[str]):
    if not url:
        return {}
    with urllib.request.urlopen(f"{url.rstrip('/')}/status", timeout=5) as response:  # nosec: B310
        return json.load(response)


def main():
    parser = argparse.ArgumentParser(description="Expose Qubetics RPC metrics to Prometheus")
    parser.add_argument("--listen", default=os.environ.get("METRICS_LISTEN_ADDR", "0.0.0.0:9300"))
    parser.add_argument("--rpc", default=os.environ.get("RPC", "http://127.0.0.1:26657"))
    parser.add_argument("--reference", default=os.environ.get("REFERENCE_RPC"))
    args = parser.parse_args()

    host, port = args.listen.split(":", 1)
    MetricsHandler.rpc_url = args.rpc
    MetricsHandler.reference_url = args.reference

    server = HTTPServer((host, int(port)), MetricsHandler)
    print(f"Starting exporter on {args.listen}, polling {args.rpc}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("Exporter shutting down")
        server.server_close()


if __name__ == "__main__":
    main()
