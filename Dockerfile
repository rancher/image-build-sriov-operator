# last commit on 2021-10-06
ARG TAG="14bd335c17c1b4c6cb7d37c2972c05cc62cadeeb"
ARG UBI_IMAGE=registry.access.redhat.com/ubi7/ubi-minimal:latest
ARG GOBORING_IMAGE=goboring/golang:1.16.7b7
ARG HARDENED_IMAGE=rancher/hardened-build-base:v1.16.10b7

FROM ${HARDENED_IMAGE} as base-builder
ARG TAG
ARG BUILD
ENV VERSION_OVERRIDE=${TAG}${BUILD}
RUN git clone https://github.com/k8snetworkplumbingwg/sriov-network-operator \
    && cd sriov-network-operator \ 
    && git checkout ${TAG} \ 
    && make clean

FROM base-builder as builder
ENV CGO_ENABLED=0
RUN cd sriov-network-operator \
    && make _build-manager \
    && make _build-webhook

FROM ${GOBORING_IMAGE} as config-daemon-builder
ARG TAG
ARG BUILD
ENV VERSION_OVERRIDE=${TAG}${BUILD}
ENV GOFLAGS=-trimpath
COPY --from=base-builder /go/sriov-network-operator /go/sriov-network-operator
RUN cd sriov-network-operator \
    && make _build-sriov-network-config-daemon \
    && make plugins

# Create the config daemon image
FROM ${UBI_IMAGE} as config-daemon
WORKDIR /
COPY centos.repo /etc/yum.repos.d/centos.repo
RUN microdnf update -y \
    && ARCH_DEP_PKGS=$(if [ "$(uname -m)" != "s390x" ]; then echo -n mstflint ; fi) \
    && microdnf install hwdata $ARCH_DEP_PKGS \
    && microdnf clean all
COPY --from=config-daemon-builder /go/sriov-network-operator/build/_output/linux/amd64/sriov-network-config-daemon /usr/bin/
COPY --from=config-daemon-builder /go/sriov-network-operator/build/_output/linux/amd64/plugins /plugins
COPY --from=config-daemon-builder /go/sriov-network-operator/bindata /bindata
ENV PLUGINSPATH=/plugins
ENTRYPOINT ["/usr/bin/sriov-network-config-daemon"]

# Create the webhook image
FROM ${UBI_IMAGE} as webhook
WORKDIR /
LABEL io.k8s.display-name="sriov-network-webhook" \
      io.k8s.description="This is an admission controller webhook that mutates and validates customer resources of sriov network operator."
COPY --from=builder /go/sriov-network-operator/build/_output/linux/amd64/webhook /usr/bin/webhook
CMD ["/usr/bin/webhook"]

# Create the operator image
FROM ${UBI_IMAGE} as operator
WORKDIR /
COPY --from=builder /go/sriov-network-operator/build/_output/linux/amd64/manager /usr/bin/sriov-network-operator
COPY --from=builder /go/sriov-network-operator/bindata /bindata
ENTRYPOINT ["/usr/bin/sriov-network-operator"]
