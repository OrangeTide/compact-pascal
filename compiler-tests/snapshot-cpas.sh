#!/bin/sh
# Stand in for the native compiler, running the snapshot under a WASM runtime
# with the working directory preopened. check-objects runs every compiler
# invocation from inside its temporary directory and names files relative to
# it, so that one preopen is all this needs.
#
# Made by a machine. PUBLIC DOMAIN (CC0-1.0)
set -eu
here=$(cd "$(dirname "$0")" && pwd)
export WASMTIME_HOME="${WASMTIME_HOME:-$HOME/.wasmtime}"
export PATH="$WASMTIME_HOME/bin:$PATH"
exec ${WASMRUN:-wasmtime run} --dir=. "$here/../snapshot/compiler.wasm" "$@"
