FROM alpine:latest

# Install WireGuard and utilities
RUN apk add --no-cache wireguard-tools iproute2 nano socat jq bash

COPY run.sh /run.sh
RUN chmod a+x /run.sh

CMD ["/run.sh"]
