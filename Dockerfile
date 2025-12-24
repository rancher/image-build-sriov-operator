ARG BCI_IMAGE=registry.suse.com/bci/bci-base
ARG GO_IMAGE=rancher/hardened-build-base:v1.24.11b2

# Image that provides cross compilation tooling.
FROM --platform=$BUILDPLATFORM rancher/mirrored-tonistiigi-xx:1.6.1 AS xx


FROM --platform=$BUILDPLATFORM ${GO_IMAGE} AS base
# copy xx scripts to your build stage
COPY --from=xx / /
RUN apk add file make git clang lld
ARG TARGETPLATFORM
# setup required packages
RUN set -x && \
    xx-apk --no-cache add musl-dev gcc lld 

FROM base AS builder
ENV CGO_ENABLED=0
ARG TAG=v1.5.0
ARG BUILD
ENV VERSION_OVERRIDE=${TAG}${BUILD}
ENV GOFLAGS=-trimpath
RUN git clone --depth=1 https://github.com/k8snetworkplumbingwg/sriov-network-operator
WORKDIR sriov-network-operator
RUN git fetch --all --tags --prune
RUN git checkout tags/${TAG} -b ${TAG}
RUN make clean && go mod download

# cross-compilation setup
ARG TARGETARCH
RUN export GOOS=$(xx-info os) &&\
    export GOARCH=${TARGETARCH} &&\
    export ARCH=${TARGETARCH} &&\
    make _build-manager && \
    make _build-webhook && \
    make _build-sriov-network-config-daemon
RUN mv /go/sriov-network-operator/build/_output/linux/${TARGETARCH}/sriov-network-config-daemon /usr/bin/ && \
    mv /go/sriov-network-operator/build/_output/linux/${TARGETARCH}/webhook /usr/bin/webhook && \
    mv /go/sriov-network-operator/build/_output/linux/${TARGETARCH}/manager /usr/bin/sriov-network-operator

# Create the config daemon image
FROM ${BCI_IMAGE} AS config-daemon
WORKDIR /
COPY centos.repo /etc/yum.repos.d/centos.repo
RUN zypper update -y && \
    ARCH_DEP_PKGS=$(if [ "$(uname -m)" != "s390x" ]; then echo -n mstflint ; fi) && \
    zypper install -y hwdata $ARCH_DEP_PKGS
COPY --from=builder /usr/bin/sriov-network-config-daemon /usr/bin/
COPY --from=builder /go/sriov-network-operator/bindata /bindata
ENTRYPOINT ["/usr/bin/sriov-network-config-daemon"]

# Create the webhook image
FROM ${BCI_IMAGE} AS webhook
WORKDIR /
LABEL io.k8s.display-name="sriov-network-webhook" \
      io.k8s.description="This is an admission controller webhook that mutates and validates customer resources of sriov network operator."
USER 1001
COPY --from=builder /usr/bin/webhook /usr/bin/webhook
CMD ["/usr/bin/webhook"]

# Create the operator image
FROM ${BCI_IMAGE} AS operator
WORKDIR /
COPY --from=builder /usr/bin/sriov-network-operator /usr/bin/sriov-network-operator
COPY --from=builder /go/sriov-network-operator/bindata /bindata
ENTRYPOINT ["/usr/bin/sriov-network-operator"]
