# last commit on 2021-10-06
ARG TAG="v1.2.0"
ARG COMMIT="f2ca88418036a7836ea2c0bd1f648a47774997c4"
ARG BCI_IMAGE=registry.suse.com/bci/bci-base
ARG GO_IMAGE=rancher/hardened-build-base:v1.21.10b1
ARG ARCH

# Image that provides cross compilation tooling.
FROM --platform=$BUILDPLATFORM rancher/mirrored-tonistiigi-xx:1.3.0 as xx


FROM --platform=$BUILDPLATFORM ${GO_IMAGE} as base
ARG TAG
ARG BUILD
ENV VERSION_OVERRIDE=${TAG}${BUILD}
# copy xx scripts to your build stage
COPY --from=xx / /
RUN apk add file make git clang lld
ARG TARGETPLATFORM
# setup required packages
RUN set -x && \
    xx-apk --no-cache add musl-dev gcc lld 

FROM base as builder
ENV CGO_ENABLED=0
ARG TAG
ARG BUILD
ENV VERSION_OVERRIDE=${TAG}${BUILD}
ENV GOFLAGS=-trimpath
RUN git clone https://github.com/k8snetworkplumbingwg/sriov-network-operator && \
    cd sriov-network-operator && \
    git checkout ${COMMIT} && \
    make clean && \
    go mod download

# cross-compilation setup
ARG TARGETPLATFORM
RUN export GOOS=$(xx-info os) &&\
    export GOARCH=$(xx-info arch) &&\
    export ARCH=$(xx-info arch) &&\
    cd sriov-network-operator && \
    make _build-manager && \
    make _build-webhook && \
    make _build-sriov-network-config-daemon
RUN mv /go/sriov-network-operator/build/_output/linux/$(xx-info arch)/sriov-network-config-daemon /usr/bin/ && \
    mv /go/sriov-network-operator/build/_output/linux/$(xx-info arch)/webhook /usr/bin/webhook && \
    mv /go/sriov-network-operator/build/_output/linux/$(xx-info arch)/manager /usr/bin/sriov-network-operator

# Create the config daemon image
FROM ${BCI_IMAGE} as config-daemon
WORKDIR /
COPY centos.repo /etc/yum.repos.d/centos.repo
RUN zypper update -y && \
    ARCH_DEP_PKGS=$(if [ "$(uname -m)" != "s390x" ]; then echo -n mstflint ; fi) && \
    zypper install -y hwdata $ARCH_DEP_PKGS
COPY --from=builder /usr/bin/sriov-network-config-daemon /usr/bin/
COPY --from=builder /go/sriov-network-operator/bindata /bindata
ENTRYPOINT ["/usr/bin/sriov-network-config-daemon"]

# Create the webhook image
FROM ${BCI_IMAGE} as webhook
WORKDIR /
LABEL io.k8s.display-name="sriov-network-webhook" \
      io.k8s.description="This is an admission controller webhook that mutates and validates customer resources of sriov network operator."
COPY --from=builder /usr/bin/webhook /usr/bin/webhook
CMD ["/usr/bin/webhook"]

# Create the operator image
FROM ${BCI_IMAGE} as operator
WORKDIR /
COPY --from=builder /usr/bin/sriov-network-operator /usr/bin/sriov-network-operator
COPY --from=builder /go/sriov-network-operator/bindata /bindata
ENTRYPOINT ["/usr/bin/sriov-network-operator"]
