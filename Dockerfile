FROM alpine:3.20.1@sha256:b89d9c93e9ed3597455c90a0b88a8bbb5cb7188438f70953fede212a0c4394e0

# Install version-pinned system dependencies
RUN apk update && \
    apk add --no-cache \
    bash=5.2.26-r0 \
    gzip=1.13-r0 \
    rclone=1.66.0-r5 \
    tar=1.35-r2 \
    pcsc-lite=2.2.3-r0 \
    ccid=1.5.5-r0 \
    libfido2=1.14.0-r1 \
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

# Install age plugins (YubiKey & FIDO2)
RUN curl -sSfL "https://github.com/str4d/age-plugin-yubikey/releases/download/v0.5.0/age-plugin-yubikey-v0.5.0-x86_64-linux.tar.gz" -o /tmp/yubikey.tar.gz && \
    tar -xzf /tmp/yubikey.tar.gz -C /tmp && \
    mv /tmp/age-plugin-yubikey/age-plugin-yubikey /usr/local/bin/age-plugin-yubikey && \
    chmod +x /usr/local/bin/age-plugin-yubikey && \
    rm -rf /tmp/yubikey.tar.gz /tmp/age-plugin-yubikey && \
    \
    curl -sSfL "https://github.com/olastor/age-plugin-fido2-hmac/releases/download/v0.5.0/age-plugin-fido2-hmac-v0.5.0-linux-amd64.tar.gz" -o /tmp/fido2.tar.gz && \
    tar -xzf /tmp/fido2.tar.gz -C /tmp && \
    mv /tmp/age-plugin-fido2-hmac/age-plugin-fido2-hmac /usr/local/bin/age-plugin-fido2-hmac && \
    chmod +x /usr/local/bin/age-plugin-fido2-hmac && \
    rm -rf /tmp/fido2.tar.gz /tmp/age-plugin-fido2-hmac

# Setup paths and copy files
COPY vwbk /usr/local/bin/vwbk
RUN chmod +x /usr/local/bin/vwbk

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Mount points for backups
VOLUME ["/encrypt", "/keys", "/encrypted"]

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
