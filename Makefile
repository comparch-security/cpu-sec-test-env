
ARCH ?= $(shell arch)

ifeq ($(ARCH), x86_64)
run:
	ARCH=$(ARCH) $(MAKE) -C benchmark run

.PHONY: run
endif

ifeq ($(ARCH), riscv64)

DEPLOY_HOME = ./riscv-linux-sdk/work/buildroot_initramfs_sysroot
RISCV = ../riscv-linux-sdk/toolchain

deploy:
	$(MAKE) -C riscv-linux-sdk -j8 toolchain/bin/riscv64-unknown-linux-gnu-g++
	ARCH=$(ARCH) RISCV=$(RISCV) $(MAKE) -C benchmark -j8
	rm -r $(DEPLOY_HOME)
	$(MAKE) -C riscv-linux-sdk -j8 buildroot_initramfs_sysroot
	mkdir -p $(DEPLOY_HOME)/root/cpu-sec-bench
	cp -r ./benchmark/test-$(ARCH)/* $(DEPLOY_HOME)/root/cpu-sec-bench/
	cp -r ./benchmark/script $(DEPLOY_HOME)/root/
	cp ./benchmark/configure.json $(DEPLOY_HOME)/root/
	touch $(DEPLOY_HOME)
	$(MAKE) -C riscv-linux-sdk -j8 bbl

run:
	$(MAKE) -C riscv-linux-sdk -j8 sim

.PHONY: deploy run

endif
