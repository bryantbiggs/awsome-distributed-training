FROM public.ecr.aws/docker/library/golang:1.24.1-bookworm AS build

ARG NODE_EXPORTER_VERSION=v1.9.0
ARG PROCFS_EXPORTER_VERSION=v0.16.0

# Install ProcFS
RUN git clone -b $PROCFS_EXPORTER_VERSION https://github.com/prometheus/procfs.git /workspace/procfs
COPY class_amazon_efa.go  /workspace/procfs/sysfs/
RUN cd /workspace/procfs && make test

# Install Node Exporter
RUN git clone -b $NODE_EXPORTER_VERSION https://github.com/prometheus/node_exporter.git /workspace/node_exporter
COPY amazon_efa_linux.go /workspace/node_exporter/collector/

WORKDIR /workspace/node_exporter
RUN  go mod edit --replace=github.com/prometheus/procfs=/workspace/procfs
RUN  go mod tidy && CGO_ENABLE=0 go build -o /go/bin/node_exporter

FROM gcr.io/distroless/static-debian12
COPY --from=build /go/bin/node_exporter /workspace/
WORKDIR /workspace
ENTRYPOINT ["./node_exporter"]
