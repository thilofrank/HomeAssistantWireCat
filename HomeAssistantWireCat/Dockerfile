ARG BUILD_FROM=ghcr.io/hassio-addons/base:21.0.0
FROM ${BUILD_FROM}

# Install WireGuard and utilities (bash + jq + bashio are provided by the base)
RUN apk add --no-cache wireguard-tools iproute2 socat

# Copy the s6-overlay service definitions and scripts
COPY rootfs /

# Ensure the s6 service scripts are executable (Windows checkouts may drop +x)
RUN chmod a+x \
    /etc/s6-overlay/s6-rc.d/init-wireguard/run \
    /etc/s6-overlay/s6-rc.d/wireguard/run \
    /etc/s6-overlay/s6-rc.d/wireguard/finish \
    /etc/s6-overlay/s6-rc.d/socat/run

# No CMD: the base image's /init (s6-overlay) starts the services above.
