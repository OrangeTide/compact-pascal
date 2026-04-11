.POSIX:

#### Directories ##################################################

# base build directory
BUILD_DIR := build
TEST_DIR := tests

# these are the output directories used for the native (fpc), bootstrap, and
# wasm compilers. This allows us to control the staging of builds and testing.
NATIVE_OUTPUT_DIR := $(BUILD_DIR)/native
STRAP_OUTPUT_DIR := $(BUILD_DIR)/bootstrap
WASM_OUTPUT_DIR := $(BUILD_DIR)/wasm
WASM2_OUTPUT_DIR := $(BUILD_DIR)/wasm-stage2

#### External Toolchain ###########################################

CC      := cc
CFLAGS  := -std=c99 -W -Wall -Og -g
LDFLAGS :=
FPC     := fpc
FPCFLAGS := -Mtp
AR      := ar
WASMRUN	:= wasmtime
WASM_VALIDATE := wasm-validate

#### Your Compilers ###############################################

# fpc-built native compiler (bootstrap compiler)
STRAP_PC := $(NATIVE_OUTPUT_DIR)/pascom
# native-built wasm compiler
WASM_PC := $(STRAP_OUTPUT_DIR)/pascom.wasm
# wasm-built wasm compiler
WASM2_PC := $(WASM_OUTPUT_DIR)/pascom.wasm

#### Pattern Rules ################################################

# pascal (with fpc)
.SECONDEXPANSION:
$(NATIVE_OUTPUT_DIR)/% : %.pas | $$(@D)/
	$(FPC) $(FPCFLAGS) -o$@ $<
$(STRAP_OUTPUT_DIR)/%.wasm : %.pas | $$(@D)/ $(STRAP_PC)
	$(STRAP_PC) > $@  < $<
	@sha1sum $@
	@echo "Checking $@:" ; $(WASM_VALIDATE) $@ && echo "$@: wasm-validated passed" || ( echo "ERROR: $@: wasm-validate failed" ; mv -f $@ $@.failed )
$(WASM_OUTPUT_DIR)/%.wasm : %.pas | $$(@D)/ $(WASM_PC)
	$(WASMRUN) $(WASM_PC) > $@ < $<
	@sha1sum $@
	@echo "Checking $@:" ; $(WASM_VALIDATE) $@ && echo "$@: wasm-validated passed" || ( echo "ERROR: $@: wasm-validate failed" ; mv -f $@ $@.failed )
$(WASM2_OUTPUT_DIR)/%.wasm : %.pas | $$(@D)/ $(WASM2_PC)
	$(WASMRUN) $(WASM2_PC) > $@ < $<
	@sha1sum $@
	@echo "Checking $@:" ; $(WASM_VALIDATE) $@ && echo "$@: wasm-validated passed" || ( echo "ERROR: $@: wasm-validate failed" ; mv -f $@ $@.failed )
#
%/ : ; mkdir -p $@
.PRECIOUS: %/

# ## Top-level targets ############################################

.PHONY: help all clean clean-all
.PHONY: bootstrap compiler compiler2 run test

help:
	@echo "Your Pascal Compiler Project"
	@echo "----------------------------"
	@echo "build targets:"
	@echo ""
	@echo "  all          Build everything"
	@echo "  clean        Remove build artifacts"
	@echo "  tool-check   Check that you have every required tool installed"
	@echo ""
	@echo "  bootstrap            Build bootstrap compiler (requires fpc)"
	@echo "  compiler             Stage 1: Build wasm compiler using bootstrap compiler (requires WASM runtime)"
	@echo "  compiler2            Stage 2: Build wasm compiler using wasm compiler (requires WASM runtime)"
	@echo "  run                  Run the a simple demo (BOOTSTRAP=1 to build with bootstrap compiler)"
	@echo "  test                 Run compiler test suite (requires fpc + WASM runtime)"

all: $(WASM2_PC)

tool-check:
	@which $(CC) || echo "Error: No CC (${CC}) installed."
	@which $(FPC) || echo "Error: No FPC (${FPC}) installed."
	@which $(WASMRUN) || echo "Error: No WASMRUN (${WASMRUN}) installed."
	@which $(WASM_VALIDATE) || echo "Error: No WASM_VALIDATE (${WASM_VALIDATE}) installed."

validate-%: %
	@echo "Checking %*:" ; (WASM_VALIDATE) $* && echo "$*: valid"

compiler : $(WASM_PC)
compiler2 : $(WASM2_PC)


#### Pascal sources ###############################################

$(STRAP_PC) : pascom.pas
$(WASM_PC) : pascom.pas | $(STRAP_PC)
$(WASM2_PC) : pascom.pas | $(WASM_PC)

#### Examples #####################################################

## TODO ##

#### Test #########################################################

test: test-strap-empty test-strap-comments test-strap-calc test-strap-math test-strap-negation \
      test-strap-hello test-strap-vars test-strap-multivar test-strap-negwrite \
      test-strap-ifelse test-strap-fact5 test-strap-forsum test-strap-repeattest \
      test-strap-fizzbuzz \
      test-strap-proc test-strap-func test-strap-recurse test-strap-varparam \
      test-strap-nested \
      test-strap-t030_string_basic test-strap-t031_string_ops \
      test-strap-t035_record_basic test-strap-t036_record_copy \
      test-strap-t037_array_basic test-strap-t038_array_copy \
      test-strap-t039_array_record test-strap-t040_array_2d \
      test-strap-t043_record_param \
      test-strap-t045_const_basic test-strap-t047_enum \
      test-strap-t048_case_basic

clean-tests:
	$(RM) $(STRAP_OUTPUT_DIR)/$(TEST_DIR)/empty.wasm $(STRAP_OUTPUT_DIR)/$(TEST_DIR)/comments.wasm $(STRAP_OUTPUT_DIR)/$(TEST_DIR)/calc.wasm $(STRAP_OUTPUT_DIR)/$(TEST_DIR)/math.wasm $(STRAP_OUTPUT_DIR)/$(TEST_DIR)/negation.wasm $(STRAP_OUTPUT_DIR)/$(TEST_DIR)/hello.wasm $(STRAP_OUTPUT_DIR)/$(TEST_DIR)/vars.wasm $(STRAP_OUTPUT_DIR)/$(TEST_DIR)/multivar.wasm $(STRAP_OUTPUT_DIR)/$(TEST_DIR)/negwrite.wasm $(STRAP_OUTPUT_DIR)/$(TEST_DIR)/ifelse.wasm $(STRAP_OUTPUT_DIR)/$(TEST_DIR)/fact5.wasm $(STRAP_OUTPUT_DIR)/$(TEST_DIR)/forsum.wasm $(STRAP_OUTPUT_DIR)/$(TEST_DIR)/repeattest.wasm $(STRAP_OUTPUT_DIR)/$(TEST_DIR)/fizzbuzz.wasm $(STRAP_OUTPUT_DIR)/$(TEST_DIR)/proc.wasm $(STRAP_OUTPUT_DIR)/$(TEST_DIR)/func.wasm $(STRAP_OUTPUT_DIR)/$(TEST_DIR)/recurse.wasm $(STRAP_OUTPUT_DIR)/$(TEST_DIR)/varparam.wasm $(STRAP_OUTPUT_DIR)/$(TEST_DIR)/nested.wasm $(STRAP_OUTPUT_DIR)/$(TEST_DIR)/t030_string_basic.wasm $(STRAP_OUTPUT_DIR)/$(TEST_DIR)/t031_string_ops.wasm $(STRAP_OUTPUT_DIR)/$(TEST_DIR)/t035_record_basic.wasm $(STRAP_OUTPUT_DIR)/$(TEST_DIR)/t036_record_copy.wasm $(STRAP_OUTPUT_DIR)/$(TEST_DIR)/t037_array_basic.wasm $(STRAP_OUTPUT_DIR)/$(TEST_DIR)/t038_array_copy.wasm $(STRAP_OUTPUT_DIR)/$(TEST_DIR)/t039_array_record.wasm $(STRAP_OUTPUT_DIR)/$(TEST_DIR)/t040_array_2d.wasm $(STRAP_OUTPUT_DIR)/$(TEST_DIR)/t043_record_param.wasm $(STRAP_OUTPUT_DIR)/$(TEST_DIR)/t045_const_basic.wasm $(STRAP_OUTPUT_DIR)/$(TEST_DIR)/t047_enum.wasm $(STRAP_OUTPUT_DIR)/$(TEST_DIR)/t048_case_basic.wasm
	$(if $(wildcard $(STRAP_OUTPUT_DIR)),rmdir $(STRAP_OUTPUT_DIR),: No need to rmdir $(STRAP_OUTPUT_DIR))

test-strap-% : $(STRAP_OUTPUT_DIR)/$(TEST_DIR)/%.wasm | $(STRAP_PC)
	wasm-validate $<

test-strap-calc: $(STRAP_OUTPUT_DIR)/$(TEST_DIR)/calc.wasm
	wasm-validate $<
	$(WASMRUN) $< && false || test $$? -eq 42

test-strap-math: $(STRAP_OUTPUT_DIR)/$(TEST_DIR)/math.wasm
	wasm-validate $<
	$(WASMRUN) $< && false || test $$? -eq 66

test-strap-negation: $(STRAP_OUTPUT_DIR)/$(TEST_DIR)/negation.wasm
	wasm-validate $<
	$(WASMRUN) $< && false || test $$? -eq 43

test-strap-hello: $(STRAP_OUTPUT_DIR)/$(TEST_DIR)/hello.wasm
	wasm-validate $<
	$(WASMRUN) $< | diff - $(TEST_DIR)/hello.expected

test-strap-vars: $(STRAP_OUTPUT_DIR)/$(TEST_DIR)/vars.wasm
	wasm-validate $<
	$(WASMRUN) $< | diff - $(TEST_DIR)/vars.expected

test-strap-multivar: $(STRAP_OUTPUT_DIR)/$(TEST_DIR)/multivar.wasm
	wasm-validate $<
	$(WASMRUN) $< | diff - $(TEST_DIR)/multivar.expected

test-strap-negwrite: $(STRAP_OUTPUT_DIR)/$(TEST_DIR)/negwrite.wasm
	wasm-validate $<
	$(WASMRUN) $< | diff - $(TEST_DIR)/negwrite.expected

test-strap-ifelse: $(STRAP_OUTPUT_DIR)/$(TEST_DIR)/ifelse.wasm
	wasm-validate $<
	$(WASMRUN) $< && false || test $$? -eq 1

test-strap-fact5: $(STRAP_OUTPUT_DIR)/$(TEST_DIR)/fact5.wasm
	wasm-validate $<
	$(WASMRUN) $< && false || test $$? -eq 120

test-strap-forsum: $(STRAP_OUTPUT_DIR)/$(TEST_DIR)/forsum.wasm
	wasm-validate $<
	$(WASMRUN) $< && false || test $$? -eq 55

test-strap-repeattest: $(STRAP_OUTPUT_DIR)/$(TEST_DIR)/repeattest.wasm
	wasm-validate $<
	$(WASMRUN) $< && false || test $$? -eq 64

test-strap-fizzbuzz: $(STRAP_OUTPUT_DIR)/$(TEST_DIR)/fizzbuzz.wasm $(TEST_DIR)/fizzbuzz.expected
	wasm-validate $<
	$(WASMRUN) $< | diff - $(TEST_DIR)/fizzbuzz.expected

test-strap-proc: $(STRAP_OUTPUT_DIR)/$(TEST_DIR)/proc.wasm $(TEST_DIR)/proc.expected
	wasm-validate $<
	$(WASMRUN) $< | diff - $(TEST_DIR)/proc.expected

test-strap-func: $(STRAP_OUTPUT_DIR)/$(TEST_DIR)/func.wasm
	wasm-validate $<
	$(WASMRUN) $< && false || test $$? -eq 12

test-strap-recurse: $(STRAP_OUTPUT_DIR)/$(TEST_DIR)/recurse.wasm
	wasm-validate $<
	$(WASMRUN) $< && false || test $$? -eq 120

test-strap-varparam: $(STRAP_OUTPUT_DIR)/$(TEST_DIR)/varparam.wasm $(TEST_DIR)/varparam.expected
	wasm-validate $<
	$(WASMRUN) $< | diff - $(TEST_DIR)/varparam.expected

test-strap-nested: $(STRAP_OUTPUT_DIR)/$(TEST_DIR)/nested.wasm $(TEST_DIR)/nested.expected
	wasm-validate $<
	$(WASMRUN) $< | diff - $(TEST_DIR)/nested.expected

test-strap-t030_string_basic: $(STRAP_OUTPUT_DIR)/$(TEST_DIR)/t030_string_basic.wasm $(TEST_DIR)/t030_string_basic.expected
	wasm-validate $<
	$(WASMRUN) $< | diff - $(TEST_DIR)/t030_string_basic.expected

test-strap-t031_string_ops: $(STRAP_OUTPUT_DIR)/$(TEST_DIR)/t031_string_ops.wasm $(TEST_DIR)/t031_string_ops.expected
	wasm-validate $<
	$(WASMRUN) $< | diff - $(TEST_DIR)/t031_string_ops.expected

test-strap-t035_record_basic: $(STRAP_OUTPUT_DIR)/$(TEST_DIR)/t035_record_basic.wasm $(TEST_DIR)/t035_record_basic.expected
	wasm-validate $<
	$(WASMRUN) $< | diff - $(TEST_DIR)/t035_record_basic.expected

test-strap-t036_record_copy: $(STRAP_OUTPUT_DIR)/$(TEST_DIR)/t036_record_copy.wasm $(TEST_DIR)/t036_record_copy.expected
	wasm-validate $<
	$(WASMRUN) $< | diff - $(TEST_DIR)/t036_record_copy.expected

test-strap-t037_array_basic: $(STRAP_OUTPUT_DIR)/$(TEST_DIR)/t037_array_basic.wasm $(TEST_DIR)/t037_array_basic.expected
	wasm-validate $<
	$(WASMRUN) $< | diff - $(TEST_DIR)/t037_array_basic.expected

test-strap-t038_array_copy: $(STRAP_OUTPUT_DIR)/$(TEST_DIR)/t038_array_copy.wasm $(TEST_DIR)/t038_array_copy.expected
	wasm-validate $<
	$(WASMRUN) $< | diff - $(TEST_DIR)/t038_array_copy.expected

test-strap-t039_array_record: $(STRAP_OUTPUT_DIR)/$(TEST_DIR)/t039_array_record.wasm $(TEST_DIR)/t039_array_record.expected
	wasm-validate $<
	$(WASMRUN) $< | diff - $(TEST_DIR)/t039_array_record.expected

test-strap-t040_array_2d: $(STRAP_OUTPUT_DIR)/$(TEST_DIR)/t040_array_2d.wasm $(TEST_DIR)/t040_array_2d.expected
	wasm-validate $<
	$(WASMRUN) $< | diff - $(TEST_DIR)/t040_array_2d.expected

test-strap-t043_record_param: $(STRAP_OUTPUT_DIR)/$(TEST_DIR)/t043_record_param.wasm $(TEST_DIR)/t043_record_param.expected
	wasm-validate $<
	$(WASMRUN) $< | diff - $(TEST_DIR)/t043_record_param.expected

test-strap-t045_const_basic: $(STRAP_OUTPUT_DIR)/$(TEST_DIR)/t045_const_basic.wasm $(TEST_DIR)/t045_const_basic.expected
	wasm-validate $<
	$(WASMRUN) $< | diff - $(TEST_DIR)/t045_const_basic.expected

test-strap-t047_enum: $(STRAP_OUTPUT_DIR)/$(TEST_DIR)/t047_enum.wasm $(TEST_DIR)/t047_enum.expected
	wasm-validate $<
	$(WASMRUN) $< | diff - $(TEST_DIR)/t047_enum.expected

test-strap-t048_case_basic: $(STRAP_OUTPUT_DIR)/$(TEST_DIR)/t048_case_basic.wasm $(TEST_DIR)/t048_case_basic.expected
	wasm-validate $<
	$(WASMRUN) $< | diff - $(TEST_DIR)/t048_case_basic.expected

# generate tests with this makefile :
$(TEST_DIR)/empty.pas : | $$(@D)/
	echo 'program empty; begin end.' > $@

#### Cleanup ######################################################

clean: clean-tests
	$(RM) $(STRAP_PC).o $(STRAP_PC) $(WASM_PC) $(WASM2_PC)
	$(if $(wildcard $(NATIVE_OUTPUT_DIR)),rmdir $(NATIVE_OUTPUT_DIR),: No need to rmdir $(NATIVE_OUTPUT_DIR))
	$(if $(wildcard $(STRAP_OUTPUT_DIR)),rmdir $(STRAP_OUTPUT_DIR),: No need to rmdir $(STRAP_OUTPUT_DIR))
	$(if $(wildcard $(WASM_OUTPUT_DIR)),rmdir $(WASM_OUTPUT_DIR),: No need to rmdir $(WASM_OUTPUT_DIR))
	$(if $(wildcard $(WASM2_OUTPUT_DIR)),rmdir $(WASM2_OUTPUT_DIR),: No need to rmdir $(WASM2_OUTPUT_DIR))
	$(if $(wildcard $(BUILD_DIR)),rmdir $(BUILD_DIR),: No need to rmdir $(BUILD_DIR))
