FROM alpine:3.20

# Install server packages, BusyBox extras (for tftp/healthcheck), CA certs, and dos2unix for line-ending normalization.
RUN apk add --no-cache tftp-hpa busybox-extras ca-certificates dos2unix

# Copy entrypoint and healthcheck scripts into the image.
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY healthcheck.sh /usr/local/bin/healthcheck.sh
RUN dos2unix /usr/local/bin/entrypoint.sh /usr/local/bin/healthcheck.sh \
  && chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/healthcheck.sh

# Persist TFTP data via a named volume.
VOLUME /var/tftpboot

# Expose the TFTP UDP port.
EXPOSE 69/udp

# Default process and health probe.
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 CMD /usr/local/bin/healthcheck.sh
