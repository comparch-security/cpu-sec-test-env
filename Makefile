# cpu-sec-test-env - lane dispatcher for cpu-sec-bench across architectures.
#
#   make ARCH=<lane> [enable_aarch64_<pa|bti|mte>=yes] <deploy|run|clean|dump>
#
# Lanes: x86_64 | aarch64 (variants selected with the enable_aarch64_* flags,
# whose results land in results/aarch64-<variant>/) | riscv64 (booted Linux
# under qemu-system-riscv64) | cheri_riscv64 and aarch64-morello (probe-only
# until the deferred CHERI bring-up lands).
#
# All pins, URLs, timeouts and roots live in env.sh - this Makefile only reads
# the few values its own recipes need.  One lane runs at a time: every entry
# that mutates the benchmark/ worktree takes an advisory flock on
# $(BUILD_DIR)/.lane.lock and fails fast naming the holding lane.  Every lane
# run, success or failure, collects its artifacts, runs `make -C benchmark
# clean` and asserts the submodule is clean (a shell trap wraps each body).

SHELL := /bin/bash
.ONESHELL:
.DEFAULT_GOAL := run

ARCH ?= $(shell arch)

# The CHERI enable flags select the scaffolded CHERI lanes directly.
ifneq ($(enable_riscv64_cheri),)
  override ARCH := cheri_riscv64
endif
ifneq ($(enable_aarch64_morello),)
  override ARCH := aarch64-morello
endif

# Values the recipes need, read from the single source of truth.
LANE_RUN_TIMEOUT := $(shell . ./env.sh && echo $$LANE_RUN_TIMEOUT)
LANE_DEPLOY_TIMEOUT := $(shell . ./env.sh && echo $$LANE_DEPLOY_TIMEOUT)
BUILD_DIR := $(shell . ./env.sh && echo $$BUILD_DIR)
RESULTS_DIR := $(shell . ./env.sh && echo $$RESULTS_DIR)
AARCH64_CXX := $(shell . ./env.sh && echo $$AARCH64_CXX)
AARCH64_AS := $(shell . ./env.sh && echo $$AARCH64_AS)
AARCH64_OBJDUMP := $(shell . ./env.sh && echo $$AARCH64_OBJDUMP)
AARCH64_TRIPLE := $(patsubst %-objdump,%,$(AARCH64_OBJDUMP))

# An empty timeout would make coreutils `timeout` fail at the wrong moment.
ifeq ($(strip $(LANE_RUN_TIMEOUT)),)
$(error env.sh did not yield LANE_RUN_TIMEOUT - refusing timeout with an empty interval)
endif
ifeq ($(strip $(LANE_DEPLOY_TIMEOUT)),)
$(error env.sh did not yield LANE_DEPLOY_TIMEOUT - refusing timeout with an empty interval)
endif
ifeq ($(strip $(BUILD_DIR)),)
$(error env.sh did not yield BUILD_DIR)
endif
ifeq ($(strip $(RESULTS_DIR)),)
$(error env.sh did not yield RESULTS_DIR)
endif

# aarch64 variant flags: enable_aarch64_{pa,bti,mte}=yes translates to
# ENABLE_FLAG (forwarded to the aarch64 scripts, which append it to the
# scheduler's MAKEFLAGS) and to the lane-name suffix for the results dir.
_AARCH64_SET :=
ifneq ($(enable_aarch64_pa),)
  _AARCH64_SET += pa
endif
ifneq ($(enable_aarch64_bti),)
  _AARCH64_SET += bti
endif
ifneq ($(enable_aarch64_mte),)
  _AARCH64_SET += mte
endif
_AARCH64_SET := $(strip $(_AARCH64_SET))
ENABLE_FLAG :=
LANE_NAME := $(ARCH)
ifneq ($(ARCH),aarch64)
  ifneq ($(_AARCH64_SET),)
$(error enable_aarch64_{pa,bti,mte} only apply to ARCH=aarch64 (ARCH=$(ARCH)))
  endif
else
  ifneq ($(_AARCH64_SET),)
    ifeq ($(words $(_AARCH64_SET)),1)
ENABLE_FLAG := enable_aarch64_$(word 1,$(_AARCH64_SET))
LANE_NAME := aarch64-$(word 1,$(_AARCH64_SET))
    else
$(error select at most one of enable_aarch64_{pa,bti,mte}=yes (got: $(_AARCH64_SET)))
    endif
  endif
endif

# The shared lane-lock body (advisory, fail-fast, names the holder).
define acquire_lane_lock
	mkdir -p $(BUILD_DIR)
	exec 9>$(BUILD_DIR)/.lane.lock
	if ! flock -n 9; then
	  echo "lane busy: $$(cat $(BUILD_DIR)/.lane.lock 2>/dev/null || echo unknown) holds $(BUILD_DIR)/.lane.lock" >&2
	  exit 1
	fi
	printf '%s\n' $(1) > $(BUILD_DIR)/.lane.lock
endef

ifeq ($(ARCH),x86_64)

deploy:
	@set -e
	echo "x86_64 deploy: host-toolchain validation only"
	command -v g++ >/dev/null
	command -v objdump >/dev/null
	g++ --version | sed -n '1p'
	objdump --version | sed -n '1p'
	. ./env.sh
	head=$$(git -C benchmark rev-parse HEAD)
	if [ "$$head" != "$$BENCH_COMMIT" ]; then
	  echo "benchmark submodule is at $$head but env.sh pins $$BENCH_COMMIT" >&2
	  exit 1
	fi
	echo "x86_64 deploy ok"

run:
	@set -e
	$(call acquire_lane_lock,x86_64)
	trap 'rc=$$?; set +e; \
	  if [ $$rc -ne 124 ]; then \
	    dest=$(RESULTS_DIR)/x86_64/$$(date -u +%Y%m%dT%H%M%SZ); \
	    mkdir -p "$$dest"; \
	    for f in results.json results.dat variables.json; do \
	      [ -f benchmark/"$$f" ] && cp -f benchmark/"$$f" "$$dest/"; \
	    done; \
	    bash scripts/common/version_stamp.sh x86_64 "$$dest/versions.txt"; \
	    echo "collected x86_64 lane artifacts into $$dest"; \
	  else \
	    echo "x86_64 lane aborted on timeout (124): publishing nothing" >&2; \
	  fi; \
	  make -C benchmark clean; \
	  assert_rc=0; \
	  if [ -n "$$(git -C benchmark status --short)" ]; then
	    echo "ERROR: benchmark submodule left dirty after clean:" >&2
	    git -C benchmark status --short >&2
	    assert_rc=1
	  fi; \
	  if [ $$rc -ne 0 ]; then exit $$rc; fi; \
	  exit $$assert_rc' EXIT
	make -C benchmark
	(cd benchmark && timeout $(LANE_RUN_TIMEOUT) ./run-test exhausted-run)

clean:
	@set -e
	$(call acquire_lane_lock,x86_64)
	make -C benchmark clean
	rm -rf $(BUILD_DIR)/x86_64

dump:
	@set -e
	make -C benchmark dump

.PHONY: deploy run clean dump

else ifeq ($(ARCH),aarch64)

deploy:
	@set -e
	ENABLE_FLAG=$(ENABLE_FLAG) bash scripts/aarch64/prepare.sh $(LANE_NAME)

run:
	@set -e
	ENABLE_FLAG=$(ENABLE_FLAG) bash scripts/aarch64/prepare.sh $(LANE_NAME)
	ENABLE_FLAG=$(ENABLE_FLAG) bash scripts/aarch64/run.sh $(LANE_NAME)

clean:
	@set -e
	$(call acquire_lane_lock,$(LANE_NAME))
	make -C benchmark clean
	rm -rf $(BUILD_DIR)/$(LANE_NAME)

dump:
	@set -e
	bash scripts/common/shim.sh $(AARCH64_TRIPLE) $(BUILD_DIR)/$(LANE_NAME)/shim
	PATH=$(BUILD_DIR)/$(LANE_NAME)/shim:$$PATH make -C benchmark dump \
	  ARCH=aarch64 CXX=$(AARCH64_CXX) ASM=$(AARCH64_AS) OBJDUMP=$(AARCH64_OBJDUMP)

.PHONY: deploy run clean dump

else ifeq ($(ARCH),riscv64)

deploy:
	@set -e
	timeout $(LANE_DEPLOY_TIMEOUT) bash scripts/riscv64/build_kernel.sh
	timeout $(LANE_DEPLOY_TIMEOUT) bash scripts/riscv64/build_busybox.sh
	timeout $(LANE_DEPLOY_TIMEOUT) bash scripts/riscv64/build_image.sh riscv64

run:
	@set -e
	bash scripts/riscv64/run.sh riscv64

clean:
	@set -e
	$(call acquire_lane_lock,riscv64)
	make -C benchmark clean
	rm -rf $(BUILD_DIR)/riscv64

dump:
	@echo "riscv64 dump is unsupported: the binaries live inside the guest image" >&2
	exit 1

.PHONY: deploy run clean dump

else ifeq ($(ARCH),cheri_riscv64)

deploy:
	@echo "CHERI lane not provisioned - see README (deferred issue: cheri-lanes-bringup-deferred)" >&2
	exit 1

run:
	@echo "CHERI lane not provisioned - see README (deferred issue: cheri-lanes-bringup-deferred)" >&2
	exit 1

clean:
	@set -e
	$(call acquire_lane_lock,cheri_riscv64)
	make -C benchmark clean
	rm -rf $(BUILD_DIR)/cheri_riscv64

dump:
	@echo "CHERI lane not provisioned - see README (deferred issue: cheri-lanes-bringup-deferred)" >&2
	exit 1

.PHONY: deploy run clean dump

else ifeq ($(ARCH),aarch64-morello)

deploy:
	@echo "CHERI lane not provisioned - see README (deferred issue: cheri-lanes-bringup-deferred)" >&2
	exit 1

run:
	@echo "CHERI lane not provisioned - see README (deferred issue: cheri-lanes-bringup-deferred)" >&2
	exit 1

clean:
	@set -e
	$(call acquire_lane_lock,aarch64-morello)
	make -C benchmark clean
	rm -rf $(BUILD_DIR)/aarch64-morello

dump:
	@echo "CHERI lane not provisioned - see README (deferred issue: cheri-lanes-bringup-deferred)" >&2
	exit 1

.PHONY: deploy run clean dump

else
  ifneq ($(filter aarch64-%,$(ARCH)),)
$(error unsupported ARCH=$(ARCH) - select the aarch64 variants as ARCH=aarch64 enable_aarch64_<pa|bti|mte>=yes (aarch64-morello is the CHERI scaffold))
  endif
$(error unsupported ARCH=$(ARCH) - expected x86_64|aarch64|riscv64|cheri_riscv64|aarch64-morello)
endif
