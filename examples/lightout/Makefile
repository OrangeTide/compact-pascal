# Made by a machine. PUBLIC DOMAIN (CC0-1.0)
# Light's Out browser game build and serve

COMPILER := ../../snapshot/compiler.wasm
WASMTIME := wasmtime

.PHONY: lightout.wasm serve clean

lightout.wasm: lightout.pas
	$(WASMTIME) run $(COMPILER) < lightout.pas > lightout.wasm

serve: lightout.wasm
	python3 -m http.server

clean:
	rm -f lightout.wasm
