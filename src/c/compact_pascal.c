/* compact_pascal.c : embeddable Pascal-to-WASM compiler (bring-your-own runtime) */
/* PUBLIC DOMAIN or MIT-0 -- See LICENSE for details. */

#define _POSIX_C_SOURCE 200809L

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
 * Internal structures
 ****************************************************************/

struct cp_compiler {
	cp_wasm_engine_t *engine;
	unsigned char *snapshot;
	size_t snapshot_len;
};

struct cp_instance {
	cp_wasm_engine_t *engine;
	void *wasm_instance; /* opaque handle from engine->instantiate */
};

/****************************************************************
 * Compiler lifecycle
 ****************************************************************/

cp_compiler_t *
cp_compiler_new(cp_wasm_engine_t *engine)
{
	cp_compiler_t *c;

	if (!engine)
		return NULL;
	c = calloc(1, sizeof(*c));
	if (!c)
		return NULL;
	c->engine = engine;
	return c;
}

void
cp_compiler_free(cp_compiler_t *compiler)
{
	if (!compiler)
		return;
	free(compiler->snapshot);
	free(compiler);
}

int
cp_load_compiler_from_file(cp_compiler_t *compiler, const char *path)
{
	FILE *fp;
	long len;
	unsigned char *buf;
	size_t nread;

	if (!compiler || !path)
		return CP_ERR;

	fp = fopen(path, "rb");
	if (!fp)
		return CP_ERR_IO;

	if (fseek(fp, 0, SEEK_END) != 0) {
		fclose(fp);
		return CP_ERR_IO;
	}
	len = ftell(fp);
	if (len < 0) {
		fclose(fp);
		return CP_ERR_IO;
	}
	rewind(fp);

	buf = malloc((size_t)len);
	if (!buf) {
		fclose(fp);
		return CP_ERR_NOMEM;
	}

	nread = fread(buf, 1, (size_t)len, fp);
	fclose(fp);
	if (nread != (size_t)len) {
		free(buf);
		return CP_ERR_IO;
	}

	free(compiler->snapshot);
	compiler->snapshot = buf;
	compiler->snapshot_len = (size_t)len;
	return CP_OK;
}

int
cp_load_compiler_from_string(cp_compiler_t *compiler,
                             const unsigned char *wasm, size_t wasm_len)
{
	unsigned char *buf;

	if (!compiler || !wasm || wasm_len == 0)
		return CP_ERR;

	buf = malloc(wasm_len);
	if (!buf)
		return CP_ERR_NOMEM;
	memcpy(buf, wasm, wasm_len);

	free(compiler->snapshot);
	compiler->snapshot = buf;
	compiler->snapshot_len = wasm_len;
	return CP_OK;
}

/** Compile Pascal source to WASM by running the compiler snapshot.
 *
 * The compiler reads source from fd 0 (stdin) and writes WASM to
 * fd 1 (stdout). We set up WASI-like I/O that feeds the source
 * buffer as stdin and captures stdout into the result buffer.
 * Errors go to stderr (fd 2) and are captured into result.error.
 */
cp_result_t
cp_compile(cp_compiler_t *compiler,
           const char *source, size_t source_len)
{
	cp_result_t result = {0};

	if (!compiler || !compiler->snapshot || !source) {
		result.status = CP_ERR;
		return result;
	}

	(void)source_len;

	/* TODO: instantiate the compiler snapshot with WASI imports
	 * that pipe source as stdin and capture stdout/stderr.
	 * This requires the engine vtable to be wired up. */
	result.status = CP_ERR;
	result.error = strdup("cp_compile: not yet implemented");
	return result;
}

/****************************************************************
 * Instance lifecycle
 ****************************************************************/

cp_instance_t *
cp_instantiate(cp_wasm_engine_t *engine,
               const unsigned char *wasm, size_t wasm_len)
{
	cp_instance_t *inst;
	void *wi;

	if (!engine || !engine->instantiate || !wasm)
		return NULL;

	wi = engine->instantiate(engine->user_data, wasm, wasm_len);
	if (!wi)
		return NULL;

	inst = calloc(1, sizeof(*inst));
	if (!inst) {
		if (engine->destroy)
			engine->destroy(engine->user_data, wi);
		return NULL;
	}
	inst->engine = engine;
	inst->wasm_instance = wi;
	return inst;
}

void
cp_instance_free(cp_instance_t *instance)
{
	if (!instance)
		return;
	if (instance->engine && instance->engine->destroy)
		instance->engine->destroy(instance->engine->user_data,
		                          instance->wasm_instance);
	free(instance);
}

int
cp_call(cp_instance_t *instance, const char *name)
{
	if (!instance || !instance->engine || !instance->engine->call)
		return CP_ERR;
	if (instance->engine->call(instance->engine->user_data,
	                           instance->wasm_instance,
	                           name, NULL, 0, NULL, 0) != 0)
		return CP_ERR_RUNTIME;
	return CP_OK;
}

/****************************************************************
 * Host-guest FFI
 ****************************************************************/

int
cp_register_import(cp_wasm_engine_t *engine,
                   const char *module, const char *name,
                   cp_import_fn fn, void *fn_user_data)
{
	if (!engine || !engine->register_import)
		return CP_ERR;
	return engine->register_import(engine->user_data,
	                               module, name,
	                               fn, fn_user_data);
}

/****************************************************************
 * WASI preview 1 helpers — default I/O callbacks
 ****************************************************************/

static int
default_fd_read(void *user_data, int fd,
                unsigned char *buf, size_t len)
{
	(void)user_data;
#ifdef _WIN32
	return _read(fd, buf, (unsigned)len);
#else
	return (int)read(fd, buf, len);
#endif
}

static int
default_fd_write(void *user_data, int fd,
                 const unsigned char *buf, size_t len)
{
	(void)user_data;
#ifdef _WIN32
	return _write(fd, buf, (unsigned)len);
#else
	return (int)write(fd, buf, len);
#endif
}

static void
default_proc_exit(void *user_data, int code)
{
	(void)user_data;
	exit(code);
}

void
cp_wasi_ctx_init(cp_wasi_ctx_t *ctx)
{
	if (!ctx)
		return;
	memset(ctx, 0, sizeof(*ctx));
	ctx->fd_read = default_fd_read;
	ctx->fd_write = default_fd_write;
	ctx->proc_exit = default_proc_exit;
}

/** Helper: get linear memory from the WASI context.
 *
 * The cp_wasi_* functions need access to the WASM instance's
 * linear memory to read/write iovecs. The WASI context stores
 * the instance pointer for this purpose.
 *
 * TODO: this needs a way to reach the instance from the WASI
 * context. For now the WASI helpers are stubs that document
 * the intended interface.
 */

int
cp_wasi_fd_read(void *user_data,
                const uint64_t *args, int n_args,
                uint64_t *results, int n_results)
{
	(void)user_data;
	(void)args;
	(void)n_args;

	/* TODO: read iovecs from linear memory, call ctx->fd_read,
	 * write nread to linear memory at args[3]. */
	if (n_results > 0)
		results[0] = 8; /* EBADF */
	return 0;
}

int
cp_wasi_fd_write(void *user_data,
                 const uint64_t *args, int n_args,
                 uint64_t *results, int n_results)
{
	(void)user_data;
	(void)args;
	(void)n_args;

	/* TODO: read iovecs from linear memory, call ctx->fd_write,
	 * write nwritten to linear memory at args[3]. */
	if (n_results > 0)
		results[0] = 8; /* EBADF */
	return 0;
}

int
cp_wasi_proc_exit(void *user_data,
                  const uint64_t *args, int n_args,
                  uint64_t *results, int n_results)
{
	cp_wasi_ctx_t *ctx = user_data;

	(void)n_results;
	(void)results;

	int code = (n_args > 0) ? (int)args[0] : 0;
	if (ctx && ctx->proc_exit)
		ctx->proc_exit(ctx->user_data, code);
	else
		exit(code);
	return 0; /* unreachable */
}

int
cp_wasi_args_sizes_get(void *user_data,
                       const uint64_t *args, int n_args,
                       uint64_t *results, int n_results)
{
	cp_wasi_ctx_t *ctx = user_data;

	(void)args;
	(void)n_args;

	/* TODO: write argc and total argv buf size to linear memory
	 * at the addresses given by args[0] and args[1]. */
	(void)ctx;
	if (n_results > 0)
		results[0] = 0; /* success */
	return 0;
}

int
cp_wasi_args_get(void *user_data,
                 const uint64_t *args, int n_args,
                 uint64_t *results, int n_results)
{
	cp_wasi_ctx_t *ctx = user_data;

	(void)args;
	(void)n_args;

	/* TODO: write argv pointers and string data to linear memory
	 * at the addresses given by args[0] and args[1]. */
	(void)ctx;
	if (n_results > 0)
		results[0] = 0; /* success */
	return 0;
}

/****************************************************************
 * String conversion helpers
 ****************************************************************/

int
cp_str_to_pascal(cp_instance_t *instance, uint32_t addr,
                 const char *str, size_t len)
{
	unsigned char *mem;
	size_t mem_len;

	if (!instance || !str)
		return CP_ERR;
	if (len > 255)
		return CP_ERR;
	if (!instance->engine || !instance->engine->get_memory)
		return CP_ERR;

	if (instance->engine->get_memory(instance->engine->user_data,
	                                 instance->wasm_instance,
	                                 &mem, &mem_len) != 0)
		return CP_ERR;

	if ((size_t)addr + 1 + len > mem_len)
		return CP_ERR;

	mem[addr] = (unsigned char)len;
	memcpy(mem + addr + 1, str, len);
	return (int)(1 + len);
}

int
cp_pascal_to_str(cp_instance_t *instance, uint32_t addr,
                 char *buf, size_t buf_size)
{
	unsigned char *mem;
	size_t mem_len;
	unsigned char slen;

	if (!instance || !buf || buf_size == 0)
		return CP_ERR;
	if (!instance->engine || !instance->engine->get_memory)
		return CP_ERR;

	if (instance->engine->get_memory(instance->engine->user_data,
	                                 instance->wasm_instance,
	                                 &mem, &mem_len) != 0)
		return CP_ERR;

	if ((size_t)addr >= mem_len)
		return CP_ERR;

	slen = mem[addr];
	if ((size_t)addr + 1 + slen > mem_len)
		return CP_ERR;
	if ((size_t)slen + 1 > buf_size)
		return CP_ERR;

	memcpy(buf, mem + addr + 1, slen);
	buf[slen] = '\0';
	return (int)slen;
}
