#!/usr/bin/env python3
"""Minimal CLI to query Qubetics node status."""

import argparse
import json
import subprocess
from typing import Any, Dict

import urllib.request


def fetch_json(url: str) -> Dict[str, Any]:
    with urllib.request.urlopen(url, timeout=5) as response:  # nosec B310
        return json.load(response)


def status(args: argparse.Namespace) -> None:
    data = fetch_json(f"{args.rpc.rstrip('/')}/status")
    info = data.get("result", {})
    sync = info.get("sync_info", {})
    peers = info.get("peers", [])
    print(f"Height: {sync.get('latest_block_height')}")
    print(f"Catching up: {sync.get('catching_up')}")
    print(f"Peers: {len(peers)}")


def peers(args: argparse.Namespace) -> None:
    data = fetch_json(f"{args.rpc.rstrip('/')}/net_info")
    peers = data.get("result", {}).get("peers", [])
    for peer in peers:
        node_info = peer.get("node_info", {})
        remote_ip = peer.get("remote_ip")
        print(f"{node_info.get('id')}@{remote_ip}")


def version(args: argparse.Namespace) -> None:  # noqa: ARG001
    output = subprocess.check_output(["qubeticsd", "version"])
    print(output.decode())


def main() -> None:
    parser = argparse.ArgumentParser(description="Qubetics control utility")
    parser.add_argument("--rpc", default="http://127.0.0.1:26657")
    subparsers = parser.add_subparsers(dest="command", required=True)

    subparsers.add_parser("status", help="Show node status").set_defaults(func=status)
    subparsers.add_parser("peers", help="List connected peers").set_defaults(func=peers)
    subparsers.add_parser("version", help="Print qubeticsd version").set_defaults(func=version)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
