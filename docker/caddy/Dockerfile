# Edge Caddy with the Cloudflare DNS provider for ACME DNS-01.
ARG CADDY_VERSION=2.11.7

FROM docker.io/library/caddy:${CADDY_VERSION}-builder AS builder
# -p=1 keeps the Go build within this small server's memory. xcaddy builds the
# version in the builder image's own CADDY_VERSION env.
ENV GOFLAGS=-p=1
RUN xcaddy build --with github.com/caddy-dns/cloudflare@v0.2.4

FROM docker.io/library/caddy:${CADDY_VERSION}-alpine
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
# The pod binds 80/443 through the unprivileged-port sysctl instead. A file
# capability would make exec fail under allowPrivilegeEscalation=false.
RUN setcap -r /usr/bin/caddy \
 && caddy list-modules | grep -q '^dns.providers.cloudflare$'
