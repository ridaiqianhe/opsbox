#!/usr/bin/env python3
import argparse
import hashlib
import ipaddress
import json
import subprocess
import sys


def fail(message: str) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(1)


def global_networks(interface: str):
    try:
        raw = subprocess.check_output(
            ["ip", "-j", "-6", "addr", "show", "dev", interface, "scope", "global"],
            text=True,
        )
    except subprocess.CalledProcessError as exc:
        fail(f"cannot inspect interface {interface}: {exc}")

    candidates = []
    for link in json.loads(raw):
        for item in link.get("addr_info", []):
            flags = set(item.get("flags", []))
            tentative = "tentative" in flags or item.get("tentative", False)
            deprecated = "deprecated" in flags or item.get("deprecated", False)
            temporary = "temporary" in flags or item.get("temporary", False)
            if item.get("family") != "inet6" or tentative or deprecated:
                continue
            address = ipaddress.IPv6Address(item["local"])
            network = ipaddress.IPv6Network((address, item["prefixlen"]), strict=False)
            candidates.append((address, network, temporary))

    candidates.sort(key=lambda value: value[2])
    return candidates


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--interface", required=True)
    parser.add_argument("--pool", default="")
    parser.add_argument("--prefix-len", type=int, default=120)
    parser.add_argument("--seed", default="random-ipv6-socks")
    parser.add_argument("--allow-large", action="store_true")
    args = parser.parse_args()

    candidates = global_networks(args.interface)
    if not candidates:
        fail(f"interface {args.interface} has no usable global IPv6 address")

    if args.pool:
        try:
            pool = ipaddress.ip_network(args.pool, strict=False)
        except ValueError as exc:
            fail(f"invalid IPV6_POOL: {exc}")
        if pool.version != 6:
            fail("IPV6_POOL must be IPv6")
        parent = next((network for _, network, _ in candidates if pool.subnet_of(network)), None)
        if parent is None:
            fail(f"IPV6_POOL {pool} is not inside a global prefix on {args.interface}")
    else:
        if not 1 <= args.prefix_len <= 127:
            fail("IPV6_POOL_PREFIX_LEN must be between 1 and 127")
        usable = [(address, network) for address, network, _ in candidates if network.prefixlen <= args.prefix_len]
        if not usable:
            fail(f"no interface prefix can contain a /{args.prefix_len} pool")
        address, parent = usable[0]
        slot_bits = args.prefix_len - parent.prefixlen
        slot_count = 1 << slot_bits
        digest = hashlib.sha256(f"{parent}|{args.seed}".encode()).digest()
        slot = int.from_bytes(digest, "big") % slot_count
        base = int(parent.network_address) | (slot << (128 - args.prefix_len))
        pool = ipaddress.IPv6Network((base, args.prefix_len))
        if address in pool and slot_count > 1:
            slot = (slot + 1) % slot_count
            base = int(parent.network_address) | (slot << (128 - args.prefix_len))
            pool = ipaddress.IPv6Network((base, args.prefix_len))

    if pool.prefixlen < 120 and not args.allow_large:
        fail(
            f"refusing broad pool {pool}; use /120 or narrower, or set "
            "ALLOW_LARGE_IPV6_POOL=true"
        )

    print(pool.compressed)


if __name__ == "__main__":
    main()
