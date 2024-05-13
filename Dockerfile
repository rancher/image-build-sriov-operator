# last commit on 2021-10-06
ARG TAG="v1.2.0"
ARG COMMIT="f2ca88418036a7836ea2c0bd1f648a47774997c4"
ARG GOBORING_VERSION=v1.21.8b1
ARG BCI_IMAGE=registry.suse.com/bci/bci-base
ARG HARDENED_IMAGE=rancher/hardened-build-base:${GOBORING_VERSION}
ARG ARCH

FROM ${HARDENED_IMAGE} as base
ARG TAG
ARG BUILD
ENV VERSION_OVERRIDE=${TAG}${BUILD}
RUN git clone https://github.com/k8snetworkplumbingwg/sriov-network-operator && \
    cd sriov-network-operator && \
    git checkout ${COMMIT} && \
    make clean

FROM base as builder
ENV CGO_ENABLED=0
ARG TAG
ARG BUILD
ENV VERSION_OVERRIDE=${TAG}${BUILD}
ENV GOFLAGS=-trimpath
RUN cd sriov-network-operator && \
    make _build-manager && \
    make _build-webhook && \
    make _build-sriov-network-config-daemon

# Create the config daemon image
FROM ${BCI_IMAGE} as config-daemon
ARG ARCH
WORKDIR /
COPY centos.repo /etc/yum.repos.d/centos.repo
RUN zypper update -y && \
    ARCH_DEP_PKGS=$(if [ "$(uname -m)" != "s390x" ]; then echo -n mstflint ; fi) && \
    zypper install -y hwdata $ARCH_DEP_PKGS
COPY --from=builder /go/sriov-network-operator/build/_output/linux/${ARCH}/sriov-network-config-daemon /usr/bin/
COPY --from=builder /go/sriov-network-operator/bindata /bindata
ENTRYPOINT ["/usr/bin/sriov-network-config-daemon"]

# Create the webhook image
FROM ${BCI_IMAGE} as webhook
ARG ARCH
WORKDIR /
LABEL io.k8s.display-name="sriov-network-webhook" \
      io.k8s.description="This is an admission controller webhook that mutates and validates customer resources of sriov network operator."
COPY --from=builder /go/sriov-network-operator/build/_output/linux/${ARCH}/webhook /usr/bin/webhook
CMD ["/usr/bin/webhook"]

# Create the operator image
FROM ${BCI_IMAGE} as operator
ARG ARCH
WORKDIR /
COPY --from=builder /go/sriov-network-operator/build/_output/linux/${ARCH}/manager /usr/bin/sriov-network-operator
COPY --from=builder /go/sriov-network-operator/bindata /bindata
ENTRYPOINT ["/usr/bin/sriov-network-operator"]
