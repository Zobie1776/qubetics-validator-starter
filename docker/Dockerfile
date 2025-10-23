# syntax=docker/dockerfile:1
FROM golang:1.21-bullseye AS builder
ARG QUBETICS_REPO=https://github.com/Qubetics/qubetics
ARG QUBETICS_TAG=v1.0.0

RUN apt-get update -y && apt-get install -y make git && rm -rf /var/lib/apt/lists/*
RUN git clone "$QUBETICS_REPO" /src/qubetics && \
    cd /src/qubetics && \
    git checkout "$QUBETICS_TAG" && \
    make build

FROM debian:bookworm-slim
RUN apt-get update -y && apt-get install -y ca-certificates curl jq && rm -rf /var/lib/apt/lists/*
COPY --from=builder /src/qubetics/build/qubeticsd /usr/local/bin/qubeticsd
COPY docker/healthcheck.sh /usr/local/bin/q-sync-healthcheck
RUN chmod +x /usr/local/bin/qubeticsd /usr/local/bin/q-sync-healthcheck

RUN useradd -m -d /home/qubetics qubetics
USER qubetics
WORKDIR /home/qubetics

VOLUME ["/data"]
EXPOSE 26656

HEALTHCHECK --interval=30s --timeout=10s --retries=5 CMD /usr/local/bin/q-sync-healthcheck

ENTRYPOINT ["qubeticsd"]
CMD ["start", "--home", "/data/.qubeticsd"]
