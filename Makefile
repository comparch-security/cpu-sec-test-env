# cpu-sec-test-env - lane dispatcher for cpu-sec-bench across architectures.
#
#   make ARCH=<lane> [enable_aarch64_<pa|bti|mte>=yes] <deploy|run|clean|dump>
#
# Lanes: x86_64 | aarch64 (variants selected with the enable_aarch64_* flags,
# whose results land in results/aarch64-<variant>/) | riscv64 (booted Linux
# under qemu-system-riscv64) | riscv64-nemu (the bench's NEMU venue: a booted
# Linux guest under XiangShan NEMU - deploy first) | cheri_riscv64 and
# aarch64-morello (CheriBSD purecap guests booted under the CHERI/Morello
# qemu, corpus delivered over virtio-9p - real lanes since the CHERI
# bring-up landed).
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

# CHERI lane values the deploy recipe's hash-aware legs need.
QEMU_RISCV64XCHERI := $(shell . ./env.sh && echo $$QEMU_RISCV64XCHERI)
QEMU_MORELLO := $(shell . ./env.sh && echo $$QEMU_MORELLO)
CHERI_DISK_IMAGE_RISCV64 := $(shell . ./env.sh && echo $$CHERI_DISK_IMAGE_RISCV64)
CHERI_DISK_IMAGE_RISCV64_SHA256 := $(shell . ./env.sh && echo $$CHERI_DISK_IMAGE_RISCV64_SHA256)
CHERI_DISK_IMAGE_MORELLO := $(shell . ./env.sh && echo $$CHERI_DISK_IMAGE_MORELLO)
CHERI_DISK_IMAGE_MORELLO_SHA256 := $(shell . ./env.sh && echo $$CHERI_DISK_IMAGE_MORELLO_SHA256)
CHERI_BUILD_TIMEOUT := $(shell . ./env.sh && echo $$CHERI_BUILD_TIMEOUT)

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
ifeq ($(strip $(CHERI_BUILD_TIMEOUT)),)
$(error env.sh did not yield CHERI_BUILD_TIMEOUT - refusing timeout with an empty interval)
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

# The shared lane-lock body (advisory, fail-fast, names the holder).  The lock
# file is append-opened so a contender never truncates the holder's name before
# finding the lock taken; the name itself is written only after the lock is
# held.  Recipes that pass the lock to a script set LANE_LOCK_INHERITED=1 and
# leave fd 9 open for the child (flock is per open-file-description).
define acquire_lane_lock
	mkdir -p $(BUILD_DIR)
	exec 9>>$(BUILD_DIR)/.lane.lock
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
	  collect_rc=0; \
	  if [ $$rc -ne 124 ]; then \
	    dest=$(RESULTS_DIR)/x86_64/$$(date -u +%Y%m%dT%H%M%SZ); \
	    mkdir -p "$$dest"; \
	    for f in results.json results.dat; do \
	      if [ ! -f benchmark/"$$f" ]; then \
	        echo "ERROR: required artifact benchmark/$$f is absent - the run did not produce it" >&2; \
	        collect_rc=1; \
	      elif [ ! -s benchmark/"$$f" ]; then \
	        echo "ERROR: required artifact benchmark/$$f is empty" >&2; \
	        collect_rc=1; \
	      elif ! cp -f benchmark/"$$f" "$$dest/"; then \
	        echo "ERROR: could not collect benchmark/$$f into $$dest" >&2; \
	        collect_rc=1; \
	      fi; \
	    done; \
	    if [ -f benchmark/results.json ] && [ -s benchmark/results.json ] && \
	       ! python3 -c "import json,sys; json.load(open(sys.argv[1]))" benchmark/results.json 2>/dev/null; then \
	      echo "ERROR: required artifact benchmark/results.json is not parseable JSON" >&2; \
	      collect_rc=1; \
	    fi; \
	    if [ -f benchmark/variables.json ] && ! cp -f benchmark/variables.json "$$dest/"; then \
	      echo "ERROR: could not collect benchmark/variables.json into $$dest" >&2; \
	      collect_rc=1; \
	    fi; \
	    if ! RUN_STATUS="$$rc" bash scripts/common/version_stamp.sh x86_64 "$$dest/versions.txt" || \
	       [ ! -s "$$dest/versions.txt" ]; then \
	      echo "ERROR: version_stamp.sh did not write $$dest/versions.txt" >&2; \
	      collect_rc=1; \
	    fi; \
	    if [ $$collect_rc -eq 0 ]; then \
	      echo "collected x86_64 lane artifacts into $$dest"; \
	    else \
	      echo "ERROR: the stamp in $$dest is INCOMPLETE (see the errors above)" >&2; \
	    fi; \
	  else \
	    echo "x86_64 lane aborted on timeout (124): publishing nothing" >&2; \
	  fi; \
	  make -C benchmark clean; \
	  assert_rc=0; \
	  dirty=$$(git -C benchmark status --short); git_rc=$$?; \
	  if [ $$git_rc -ne 0 ]; then \
	    echo "ERROR: cannot verify the benchmark submodule is clean: git status failed (rc=$$git_rc)" >&2; \
	    assert_rc=1; \
	  elif [ -n "$$dirty" ]; then \
	    echo "ERROR: benchmark submodule left dirty after clean:" >&2; \
	    printf "%s\n" "$$dirty" >&2; \
	    assert_rc=1; \
	  fi; \
	  if [ $$rc -ne 0 ]; then exit $$rc; fi; \
	  if [ $$collect_rc -ne 0 ]; then exit $$collect_rc; fi; \
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
	$(call acquire_lane_lock,$(LANE_NAME))
	ENABLE_FLAG=$(ENABLE_FLAG) LANE_LOCK_INHERITED=1 bash scripts/aarch64/prepare.sh $(LANE_NAME)
	ENABLE_FLAG=$(ENABLE_FLAG) LANE_LOCK_INHERITED=1 bash scripts/aarch64/run.sh $(LANE_NAME)

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

else ifeq ($(ARCH),riscv64-nemu)

# The bench's NEMU venue, wrapped as a lane: the platform scripts under
# benchmark/platform/riscv64-nemu-linux/ own every venue mechanism, the lane
# scripts own the lock, the preflights, the supervision and the stamp.  The
# run leg's bound lives in scripts/riscv64_nemu/run.sh (it supervises the
# platform leg as its own session), so no outer timeout here.
deploy:
	@set -e
	timeout $(LANE_DEPLOY_TIMEOUT) bash scripts/riscv64_nemu/prepare.sh riscv64-nemu

run:
	@set -e
	LANE_RUN_TIMEOUT='$(LANE_RUN_TIMEOUT)' bash scripts/riscv64_nemu/run.sh riscv64-nemu

clean:
	@set -e
	$(call acquire_lane_lock,riscv64-nemu)
	make -C benchmark clean
	rm -rf $(BUILD_DIR)/riscv64-nemu

# The corpus is staged host-side under corpus-keyed paths
# ($OUT/$RUNSET/bench/test/<program>__<key>), so the bench's dump target has
# no in-tree test/<program> builds to disassemble.
dump:
	@echo "riscv64-nemu dump is unsupported: the corpus is staged corpus-keyed, so there are no in-tree test/<program> builds to disassemble" >&2
	exit 1

.PHONY: deploy run clean dump

else ifeq ($(ARCH),cheri_riscv64)

# deploy: sources-if-missing -> emulator-if-missing -> image-if-missing-and-
# hash-mismatched -> prepare.  The timeout layering is deliberate: only the
# cheap legs (sources, prepare) carry LANE_DEPLOY_TIMEOUT; the emulator and
# image legs carry the CHERI_BUILD_TIMEOUT, because a 7200 s outer cap would
# fire mid-world-build (exit 124) and make the inner bound dead.  The image leg
# is hash-aware, not existence-aware, so a stale pinned image is rebuilt.
deploy:
	@set -e
	if [ ! -d $(BUILD_DIR)/cheri/sources/qemu ]; then \
	  timeout $(LANE_DEPLOY_TIMEOUT) bash scripts/cheri/stage_sources.sh; fi
	if [ ! -x $(BUILD_DIR)/cheri/output/sdk/bin/$(QEMU_RISCV64XCHERI) ]; then \
	  timeout $(CHERI_BUILD_TIMEOUT) bash scripts/cheri/build_emulator.sh; fi
	if [ ! -f $(CHERI_DISK_IMAGE_RISCV64) ] || \
	   [ "$$(sha256sum $(CHERI_DISK_IMAGE_RISCV64) | cut -d' ' -f1)" != "$(CHERI_DISK_IMAGE_RISCV64_SHA256)" ]; then \
	  timeout $(CHERI_BUILD_TIMEOUT) bash scripts/cheri/build_image.sh; fi
	timeout $(LANE_DEPLOY_TIMEOUT) bash scripts/cheri_riscv64/prepare.sh cheri_riscv64 enable_riscv64_cheri=yes

run:
	@set -e
	LANE_RUN_TIMEOUT=$(LANE_RUN_TIMEOUT) bash scripts/cheri_riscv64/run.sh cheri_riscv64

clean:
	@set -e
	$(call acquire_lane_lock,cheri_riscv64)
	make -C benchmark clean
	rm -rf $(BUILD_DIR)/cheri_riscv64

dump:
	@echo "cheri_riscv64 dump is unsupported: the binaries live inside the guest image" >&2
	exit 1

.PHONY: deploy run clean dump

else ifeq ($(ARCH),aarch64-morello)

# Same deploy shape as cheri_riscv64 (both CHERI lanes share the emulator and
# the image build); the Morello boot uses its own emulator binary and pinned
# disk image.  The bench token is aarch64, so its enable flag is
# enable_aarch64_morello=yes.
deploy:
	@set -e
	if [ ! -d $(BUILD_DIR)/cheri/sources/qemu ]; then \
	  timeout $(LANE_DEPLOY_TIMEOUT) bash scripts/cheri/stage_sources.sh; fi
	if [ ! -x $(BUILD_DIR)/cheri/output/sdk/bin/$(QEMU_MORELLO) ]; then \
	  timeout $(CHERI_BUILD_TIMEOUT) bash scripts/cheri/build_emulator.sh; fi
	if [ ! -f $(CHERI_DISK_IMAGE_MORELLO) ] || \
	   [ "$$(sha256sum $(CHERI_DISK_IMAGE_MORELLO) | cut -d' ' -f1)" != "$(CHERI_DISK_IMAGE_MORELLO_SHA256)" ]; then \
	  timeout $(CHERI_BUILD_TIMEOUT) bash scripts/cheri/build_image.sh; fi
	timeout $(LANE_DEPLOY_TIMEOUT) bash scripts/morello/prepare.sh aarch64-morello enable_aarch64_morello=yes

run:
	@set -e
	LANE_RUN_TIMEOUT=$(LANE_RUN_TIMEOUT) bash scripts/morello/run.sh aarch64-morello

clean:
	@set -e
	$(call acquire_lane_lock,aarch64-morello)
	make -C benchmark clean
	rm -rf $(BUILD_DIR)/aarch64-morello

dump:
	@echo "aarch64-morello dump is unsupported: the binaries live inside the guest image" >&2
	exit 1

.PHONY: deploy run clean dump

else
  ifneq ($(filter aarch64-%,$(ARCH)),)
$(error unsupported ARCH=$(ARCH) - select the aarch64 variants as ARCH=aarch64 enable_aarch64_<pa|bti|mte>=yes (aarch64-morello is the CHERI scaffold))
  endif
$(error unsupported ARCH=$(ARCH) - expected x86_64|aarch64|riscv64|riscv64-nemu|cheri_riscv64|aarch64-morello)
endif
