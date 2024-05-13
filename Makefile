SEVERITIES = HIGH,CRITICAL

UNAME_M = $(shell uname -m)
ARCH=
ifeq ($(UNAME_M), x86_64)
	ARCH=amd64
else ifeq ($(UNAME_M), aarch64)
	ARCH=arm64
else 
	ARCH=$(UNAME_M)
endif

BUILD_META=-build$(shell date +%Y%m%d)
ORG ?= rancher
TAG ?= v1.2.0$(BUILD_META)
export DOCKER_BUILDKIT?=1

ifeq (,$(filter %$(BUILD_META),$(TAG)))
$(error TAG $(TAG) needs to end with build metadata: $(BUILD_META))
endif

.PHONY: image-build-operator
image-build-operator:
	docker buildx build \
		--load \
		--platform=$(ARCH) \
		--pull \
		--build-arg ARCH=$(ARCH) \
		--build-arg TAG=$(TAG:$(BUILD_META)=) \
		--build-arg BUILD=$(BUILD_META) \
		--target operator \
		--tag $(ORG)/hardened-sriov-network-operator:$(TAG) \
		--tag $(ORG)/hardened-sriov-network-operator:$(TAG)-$(ARCH) \
	.

.PHONY: image-push-operator
image-push-operator:
	docker push $(ORG)/hardened-sriov-network-operator:$(TAG)-$(ARCH)

.PHONY: image-scan-operator
image-scan-operator:
	trivy image --severity $(SEVERITIES) --no-progress --ignore-unfixed $(ORG)/hardened-sriov-network-operator:$(TAG)

.PHONY: image-build-network-config-daemon
image-build-network-config-daemon:
	docker buildx build \
		--pull \
		--platform=$(ARCH) \
		--build-arg ARCH=$(ARCH) \
		--build-arg TAG=$(TAG:$(BUILD_META)=) \
		--build-arg BUILD=$(BUILD_META) \
		--target config-daemon \
		--tag $(ORG)/hardened-sriov-network-config-daemon:$(TAG) \
		--tag $(ORG)/hardened-sriov-network-config-daemon:$(TAG)-$(ARCH) \
	.

.PHONY: image-push-network-config-daemon
image-push-network-config-daemon:
	docker push $(ORG)/hardened-sriov-network-config-daemon:$(TAG)-$(ARCH)

.PHONY: image-scan-network-config-daemon
image-scan-network-config-daemon:
	trivy image --severity $(SEVERITIES) --no-progress --ignore-unfixed $(ORG)/hardened-sriov-network-config-daemon:$(TAG)

.PHONY: image-build-sriov-network-webhook
image-build-sriov-network-webhook:
	docker buildx build \
		--pull \
		--platform=$(ARCH) \
		--build-arg ARCH=$(ARCH) \
		--build-arg TAG=$(TAG:$(BUILD_META)=) \
		--build-arg BUILD=$(BUILD_META) \
		--target webhook \
		--tag $(ORG)/hardened-sriov-network-webhook:$(TAG) \
		--tag $(ORG)/hardened-sriov-network-webhook:$(TAG)-$(ARCH) \
	.

.PHONY: image-push-sriov-network-webhook
image-push-sriov-network-webhook:
	docker push $(ORG)/hardened-sriov-network-webhook:$(TAG)-$(ARCH)

.PHONY: image-scan-sriov-network-webhook
image-scan-sriov-network-webhook:
	trivy image --severity $(SEVERITIES) --no-progress --ignore-unfixed $(ORG)/hardened-sriov-network-webhook:$(TAG)

PHONY: log
log:
	@echo "ARCH=$(ARCH)"
	@echo "TAG=$(TAG)"
	@echo "ORG=$(ORG)"
	@echo "PKG=$(PKG)"
	@echo "SRC=$(SRC)"
	@echo "BUILD_META=$(BUILD_META)"
	@echo "UNAME_M=$(UNAME_M)"
