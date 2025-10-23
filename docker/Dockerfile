# syntax=docker/dockerfile:1
ARG GO_IMAGE=golang:1.21.5-bullseye@sha256:7f030e66e4a79e927651c01fb9b31c8ed6dfa81857232ece2b2043614d248f90
FROM ${GO_IMAGE} AS builder
ARG QUBETICS_REPO=https://github.com/Qubetics/qubetics
ARG QUBETICS_SRC_REF=main

# hadolint ignore=DL3008,DL3015
RUN apt-get update -y && apt-get install -y --no-install-recommends git make ca-certificates && rm -rf /var/lib/apt/lists/*
RUN git clone "$QUBETICS_REPO" /src/qubetics && \
    cd /src/qubetics && \
    git checkout "$QUBETICS_SRC_REF" && \
    make build

ARG RUNTIME_IMAGE=debian:bookworm-slim@sha256:6f8a934f1db6f1d989ef2e724edc8458d7311ca4fb22d2ff8ae9e06cfaf08763
FROM ${RUNTIME_IMAGE}

# hadolint ignore=DL3008,DL3015
RUN apt-get update -y && apt-get install -y --no-install-recommends ca-certificates curl jq && rm -rf /var/lib/apt/lists/*

COPY --from=builder /src/qubetics/build/qubeticsd /usr/local/bin/qubeticsd
COPY scripts/ /app/scripts/
RUN chmod +x /usr/local/bin/qubeticsd /app/scripts/healthcheck.sh

RUN useradd -m -d /home/qubetics qubetics
USER qubetics
WORKDIR /home/qubetics

VOLUME ["/data"]
EXPOSE 26656

HEALTHCHECK --interval=30s --timeout=10s --retries=5 CMD ["/bin/bash", "/app/scripts/healthcheck.sh"]

ENTRYPOINT ["qubeticsd"]
CMD ["start", "--home", "/data/.qubeticsd"]
