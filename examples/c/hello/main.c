/* main.c : run a Compact Pascal WASM program using wasm3 */
/* PUBLIC DOMAIN or MIT-0 -- See LICENSE for details. */

/*
 * Usage: hello <program.wasm>
 *
 * Loads a WASM binary compiled by the Compact Pascal compiler and
 * runs its _start export. WASI preview 1 I/O (fd_write, fd_read,
 * proc_exit) is provided so that write/writeln/readln work.
 *
 * Build:
 *   make examples/c/hello/hello
 *
 * Run:
 *   ./examples/c/hello/hello program.wasm
 */

#include "wasm3.h"
#include "compact_pascal.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <io.h>
#else
#include <unistd.h>
#endif

/****************************************************************
 * WASI preview 1 host functions for wasm3
 *
 * The Compact Pascal compiler emits calls to these imports from
 * the wasi_snapshot_preview1 module. We provide minimal
 * implementations that map to POSIX I/O.
 ****************************************************************/

m3ApiRawFunction(wasi_fd_write)
{
	m3ApiReturnType(uint32_t);
	m3ApiGetArg(uint32_t, fd);
	m3ApiGetArg(uint32_t, iovs_offset);
	m3ApiGetArg(uint32_t, iovs_len);
	m3ApiGetArg(uint32_t, nwritten_offset);

	uint32_t total = 0;
	uint32_t mem_size = m3_GetMemorySize(runtime);

	for (uint32_t i = 0; i < iovs_len; i++) {
		uint32_t iov_addr = iovs_offset + i * 8;
		if (iov_addr + 8 > mem_size)
			m3ApiTrap("out of bounds iovec");

		uint32_t buf_offset = m3ApiReadMem32(_mem + iov_addr);
		uint32_t buf_len = m3ApiReadMem32(_mem + iov_addr + 4);

		if (buf_offset + buf_len > mem_size)
			m3ApiTrap("out of bounds write buffer");

		int n;
#ifdef _WIN32
		n = _write(fd, (char *)_mem + buf_offset, buf_len);
#else
		n = (int)write(fd, (char *)_mem + buf_offset, buf_len);
#endif
		if (n < 0) {
			m3ApiReturn(8); /* EBADF */
		}
		total += (uint32_t)n;
	}

	m3ApiWriteMem32(_mem + nwritten_offset, total);
	m3ApiReturn(0); /* success */
}

m3ApiRawFunction(wasi_fd_read)
{
	m3ApiReturnType(uint32_t);
	m3ApiGetArg(uint32_t, fd);
	m3ApiGetArg(uint32_t, iovs_offset);
	m3ApiGetArg(uint32_t, iovs_len);
	m3ApiGetArg(uint32_t, nread_offset);

	uint32_t total = 0;
	uint32_t mem_size = m3_GetMemorySize(runtime);

	for (uint32_t i = 0; i < iovs_len; i++) {
		uint32_t iov_addr = iovs_offset + i * 8;
		if (iov_addr + 8 > mem_size)
			m3ApiTrap("out of bounds iovec");

		uint32_t buf_offset = m3ApiReadMem32(_mem + iov_addr);
		uint32_t buf_len = m3ApiReadMem32(_mem + iov_addr + 4);

		if (buf_offset + buf_len > mem_size)
			m3ApiTrap("out of bounds read buffer");

		int n;
#ifdef _WIN32
		n = _read(fd, (char *)_mem + buf_offset, buf_len);
#else
		n = (int)read(fd, (char *)_mem + buf_offset, buf_len);
#endif
		if (n < 0) {
			m3ApiReturn(8); /* EBADF */
		}
		total += (uint32_t)n;
		if ((uint32_t)n < buf_len)
			break; /* short read */
	}

	m3ApiWriteMem32(_mem + nread_offset, total);
	m3ApiReturn(0); /* success */
}

m3ApiRawFunction(wasi_proc_exit)
{
	m3ApiGetArg(uint32_t, code);

	(void)runtime;
	exit((int)code);

	m3ApiTrap("unreachable");
}

m3ApiRawFunction(wasi_args_sizes_get)
{
	m3ApiReturnType(uint32_t);
	m3ApiGetArg(uint32_t, argc_offset);
	m3ApiGetArg(uint32_t, argv_buf_size_offset);

	m3ApiWriteMem32(_mem + argc_offset, 0);
	m3ApiWriteMem32(_mem + argv_buf_size_offset, 0);
	m3ApiReturn(0);
}

m3ApiRawFunction(wasi_args_get)
{
	m3ApiReturnType(uint32_t);
	m3ApiGetArg(uint32_t, argv_offset);
	m3ApiGetArg(uint32_t, argv_buf_offset);

	(void)argv_offset;
	(void)argv_buf_offset;
	m3ApiReturn(0);
}

/****************************************************************
 * File loading
 ****************************************************************/

static unsigned char *
load_file(const char *path, size_t *out_len)
{
	FILE *fp;
	long len;
	unsigned char *buf;
	size_t nread;

	fp = fopen(path, "rb");
	if (!fp) {
		fprintf(stderr, "error: cannot open '%s'\n", path);
		return NULL;
	}
	fseek(fp, 0, SEEK_END);
	len = ftell(fp);
	rewind(fp);

	buf = malloc((size_t)len);
	if (!buf) {
		fclose(fp);
		fprintf(stderr, "error: out of memory\n");
		return NULL;
	}
	nread = fread(buf, 1, (size_t)len, fp);
	fclose(fp);

	if (nread != (size_t)len) {
		free(buf);
		fprintf(stderr, "error: short read on '%s'\n", path);
		return NULL;
	}
	*out_len = (size_t)len;
	return buf;
}

/****************************************************************
 * Main
 ****************************************************************/

static int
link_wasi(IM3Module module)
{
	const char *wasi = "wasi_snapshot_preview1";
	M3Result r;

	r = m3_LinkRawFunction(module, wasi, "fd_write",
	                       "i(iiii)", wasi_fd_write);
	if (r && r != m3Err_functionLookupFailed)
		return -1;

	r = m3_LinkRawFunction(module, wasi, "fd_read",
	                       "i(iiii)", wasi_fd_read);
	if (r && r != m3Err_functionLookupFailed)
		return -1;

	r = m3_LinkRawFunction(module, wasi, "proc_exit",
	                       "v(i)", wasi_proc_exit);
	if (r && r != m3Err_functionLookupFailed)
		return -1;

	r = m3_LinkRawFunction(module, wasi, "args_sizes_get",
	                       "i(ii)", wasi_args_sizes_get);
	if (r && r != m3Err_functionLookupFailed)
		return -1;

	r = m3_LinkRawFunction(module, wasi, "args_get",
	                       "i(ii)", wasi_args_get);
	if (r && r != m3Err_functionLookupFailed)
		return -1;

	return 0;
}

int
main(int argc, char **argv)
{
	unsigned char *wasm;
	size_t wasm_len;
	IM3Environment env;
	IM3Runtime rt;
	IM3Module module;
	IM3Function func;
	M3Result result;

	if (argc < 2) {
		fprintf(stderr, "usage: %s <program.wasm>\n",
		        argc > 0 ? argv[0] : "hello");
		return 1;
	}

	wasm = load_file(argv[1], &wasm_len);
	if (!wasm)
		return 1;

	env = m3_NewEnvironment();
	if (!env) {
		fprintf(stderr, "error: m3_NewEnvironment failed\n");
		free(wasm);
		return 1;
	}

	rt = m3_NewRuntime(env, 64 * 1024, NULL);
	if (!rt) {
		fprintf(stderr, "error: m3_NewRuntime failed\n");
		m3_FreeEnvironment(env);
		free(wasm);
		return 1;
	}

	result = m3_ParseModule(env, &module, wasm, (uint32_t)wasm_len);
	if (result) {
		fprintf(stderr, "error: m3_ParseModule: %s\n", result);
		m3_FreeRuntime(rt);
		m3_FreeEnvironment(env);
		free(wasm);
		return 1;
	}

	result = m3_LoadModule(rt, module);
	if (result) {
		fprintf(stderr, "error: m3_LoadModule: %s\n", result);
		m3_FreeModule(module);
		m3_FreeRuntime(rt);
		m3_FreeEnvironment(env);
		free(wasm);
		return 1;
	}
	/* module is now owned by runtime -- do not free separately */

	if (link_wasi(module) != 0) {
		fprintf(stderr, "error: failed to link WASI imports\n");
		m3_FreeRuntime(rt);
		m3_FreeEnvironment(env);
		free(wasm);
		return 1;
	}

	result = m3_FindFunction(&func, rt, "_start");
	if (result) {
		fprintf(stderr, "error: m3_FindFunction(_start): %s\n",
		        result);
		m3_FreeRuntime(rt);
		m3_FreeEnvironment(env);
		free(wasm);
		return 1;
	}

	result = m3_CallV(func);
	if (result) {
		/* proc_exit calls exit() directly, so we only get here
		 * on a trap or error. */
		fprintf(stderr, "error: m3_CallV: %s\n", result);
		m3_FreeRuntime(rt);
		m3_FreeEnvironment(env);
		free(wasm);
		return 1;
	}

	m3_FreeRuntime(rt);
	m3_FreeEnvironment(env);
	free(wasm);
	return 0;
}
