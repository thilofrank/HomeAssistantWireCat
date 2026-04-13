FROM lscr.io/linuxserver/wireguard:latest

# Add socat for port forwarding and jq for JSON config parsing
RUN apk add --no-cache socat jq bash

COPY run.sh /run.sh
RUN chmod a+x /run.sh

CMD ["/run.sh"]
