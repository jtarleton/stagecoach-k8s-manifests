# Edge Caddy with the Cloudflare DNS provider for ACME DNS-01.
ARG CADDY_VERSION=2.11.7

FROM docker.io/library/caddy:${CADDY_VERSION}-builder AS builder
ARG CADDY_VERSION
# -p=1 keeps the Go build within this small server's memory.
ENV GOFLAGS=-p=1
RUN xcaddy build v${CADDY_VERSION} --with github.com/caddy-dns/cloudflare@v0.2.4

FROM docker.io/library/caddy:${CADDY_VERSION}-alpine
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
RUN caddy list-modules | grep -q '^dns.providers.cloudflare$'
