FROM alpine:3.20.1@sha256:b89d9c93e9ed3597455c90a0b88a8bbb5cb7188438f70953fede212a0c4394e0

# Install version-pinned system dependencies
RUN apk update && \
    apk add --no-cache \
    bash=5.2.26-r0 \
    gzip=1.13-r0 \
    rclone=1.66.0-r5 \
    tar=1.35-r2 \
    curl

# Install age v1.3.1 from official GitHub releases (multi-arch support)
RUN ARCH=$(uname -m) && \
    case "$ARCH" in \
      x86_64) AGE_ARCH="linux-amd64" ;; \
      aarch64|arm64) AGE_ARCH="linux-arm64" ;; \
      armv7l) AGE_ARCH="linux-arm" ;; \
      *) echo "Unsupported arch: $ARCH" && exit 1 ;; \
    esac && \
    curl -sSfL "https://github.com/FiloSottile/age/releases/download/v1.3.1/age-v1.3.1-${AGE_ARCH}.tar.gz" -o /tmp/age.tar.gz && \
    tar -xzf /tmp/age.tar.gz -C /tmp && \
    mv /tmp/age/age /usr/local/bin/age && \
    mv /tmp/age/age-keygen /usr/local/bin/age-keygen && \
    chmod +x /usr/local/bin/age /usr/local/bin/age-keygen && \
    rm -rf /tmp/age*

# Setup paths and copy files
COPY vwbk /usr/local/bin/vwbk
RUN chmod +x /usr/local/bin/vwbk

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Mount points for backups
VOLUME ["/encrypt", "/keys", "/encrypted"]

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
