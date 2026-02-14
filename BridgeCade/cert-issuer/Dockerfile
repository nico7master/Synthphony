FROM alpine:3.20

RUN apk add --no-cache bash curl jq python3 py3-pip tini docker && \
    pip3 install docker --break-system-packages

RUN MKCERT_VERSION=v1.4.4 && \
    ARCH=$(uname -m) && \
    if [ "$ARCH" = "x86_64" ]; then \
        MKCERT_ARCH="amd64"; \
    elif [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then \
        MKCERT_ARCH="arm64"; \
    elif [ "$ARCH" = "armv7l" ]; then \
        MKCERT_ARCH="arm"; \
    else \
        echo "Unsupported architecture: $ARCH" && exit 1; \
    fi && \
    echo "Downloading mkcert for architecture: $MKCERT_ARCH" && \
    curl -fsSL -o /usr/local/bin/mkcert \
        https://github.com/FiloSottile/mkcert/releases/download/${MKCERT_VERSION}/mkcert-${MKCERT_VERSION}-linux-${MKCERT_ARCH} && \
    chmod +x /usr/local/bin/mkcert && \
    /usr/local/bin/mkcert --version

WORKDIR /app
COPY issuer.py /app/issuer.py

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["python3", "/app/issuer.py"]
