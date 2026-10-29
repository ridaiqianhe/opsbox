FROM debian:bookworm-slim AS downloader

ARG TARGETARCH
ARG XRAY_VERSION=26.3.27

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl unzip \
    && rm -rf /var/lib/apt/lists/* \
    && set -eux; \
       arch="${TARGETARCH:-$(dpkg --print-architecture)}"; \
       case "$arch" in \
         amd64) asset="Xray-linux-64.zip" ;; \
         arm64) asset="Xray-linux-arm64-v8a.zip" ;; \
         *) echo "Unsupported architecture: $arch" >&2; exit 1 ;; \
       esac; \
       base="https://github.com/XTLS/Xray-core/releases/download/v${XRAY_VERSION}"; \
       curl -fsSL "$base/$asset" -o /tmp/xray.zip; \
       curl -fsSL "$base/$asset.dgst" -o /tmp/xray.zip.dgst; \
       checksum="$(sed -n 's/^SHA2-256= //p' /tmp/xray.zip.dgst)"; \
       test -n "$checksum"; \
       echo "$checksum  /tmp/xray.zip" | sha256sum -c -; \
       mkdir -p /out; \
       unzip -j /tmp/xray.zip xray -d /out; \
       chmod 0755 /out/xray

FROM debian:bookworm-slim

ARG XRAY_VERSION=26.3.27

LABEL org.opencontainers.image.title="Random IPv6 SOCKS5" \
      org.opencontainers.image.description="Authenticated Xray SOCKS5 with random IPv6 and optional IPv4 egress" \
      org.opencontainers.image.source="https://github.com/ridaiqianhe/opsbox" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.version="$XRAY_VERSION"

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       bash ca-certificates gosu iproute2 jq ndppd procps python3 tini \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --system xray \
    && useradd --system --gid xray --home-dir /nonexistent --shell /usr/sbin/nologin xray \
    && install -d -m 0750 -o xray -g xray /var/log/xray

COPY --from=downloader /out/xray /usr/local/bin/xray
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY docker/select_pool.py /usr/local/libexec/select_pool.py
COPY docker/xray-config.jq /usr/local/libexec/xray-config.jq

RUN chmod 0755 /usr/local/bin/entrypoint.sh /usr/local/libexec/select_pool.py \
    && chmod 0644 /usr/local/libexec/xray-config.jq

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
STOPSIGNAL SIGTERM
