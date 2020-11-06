
ARCH ?= $(shell arch)

ifeq ($(ARCH), x86_64)
run:
	ARCH=$(ARCH) $(MAKE) -C benchmark run

.PHONY: run
endif

ifeq ($(ARCH), riscv64)

DEPLOY_HOME = ./riscv-linux-sdk/work/buildroot_initramfs_sysroot/root
RISCV = ../riscv-linux-sdk/toolchain

deploy:
	$(MAKE) -C riscv-linux-sdk bbl
	ARCH=$(ARCH) RISCV=$(RISCV) $(MAKE) -C benchmark
	cp -r benchmark/test-$(ARCH) $(DEPLOY_HOME)/cpu-sec-bench
	cp -r benchmark/script $(DEPLOY_HOME)/
	cp benchmark/configure.json $(DEPLOY_HOME)/
	touch $(DEPLOY_HOME)
	$(MAKE) -C riscv-linux-sdk bbl

run:
	$(MAKE) -C riscv-linux-sdk sim

.PHONY: deploy run

endif
