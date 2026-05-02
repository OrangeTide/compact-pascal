/* compact_pascal.c : embeddable Pascal-to-WASM compiler (bring-your-own runtime) */
/* PUBLIC DOMAIN or MIT-0 -- See LICENSE for details. */
/* Made by a machine. PUBLIC DOMAIN (CC0-1.0) */

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
 * Include file expansion
 ****************************************************************/

#define CP_MAX_INCLUDE_DEPTH 16

struct cp_include_state {
	size_t allocated;
	size_t used;
	char *buffer;
	int depth;
	char *err_buf;
	size_t err_buf_size;
};

static void
set_error(struct cp_include_state *state, const char *msg)
{
	if (state->err_buf && state->err_buf_size > 0) {
		size_t len = strlen(msg);
		if (len > state->err_buf_size - 1)
			len = state->err_buf_size - 1;
		memcpy(state->err_buf, msg, len);
		state->err_buf[len] = '\0';
	}
}

static int
append_buffer(struct cp_include_state *state, const char *data, size_t len)
{
	size_t new_size;
	char *new_buffer;

	if (state->used + len > state->allocated) {
		new_size = (state->allocated == 0) ? 16384 : state->allocated * 2;
		while (new_size < state->used + len)
			new_size *= 2;

		new_buffer = realloc(state->buffer, new_size);
		if (!new_buffer)
			return -1;

		state->buffer = new_buffer;
		state->allocated = new_size;
	}

	memcpy(state->buffer + state->used, data, len);
	state->used += len;
	return 0;
}

static char *
read_file(const char *path, size_t *out_len)
{
	FILE *fp;
	long len;
	char *buf;
	size_t nread;

	fp = fopen(path, "rb");
	if (!fp)
		return NULL;

	if (fseek(fp, 0, SEEK_END) != 0) {
		fclose(fp);
		return NULL;
	}
	len = ftell(fp);
	if (len < 0) {
		fclose(fp);
		return NULL;
	}
	rewind(fp);

	buf = malloc((size_t)len + 1);
	if (!buf) {
		fclose(fp);
		return NULL;
	}

	nread = fread(buf, 1, (size_t)len, fp);
	fclose(fp);

	if (nread != (size_t)len) {
		free(buf);
		return NULL;
	}
	buf[nread] = '\0';
	*out_len = (size_t)len;
	return buf;
}

static char *
build_path(const char *base_dir, const char *filename)
{
	size_t base_len, file_len;
	char *result;
	int has_sep;

	if (!filename || !*filename)
		return NULL;

	if (!base_dir || !*base_dir)
		return strdup(filename);

	base_len = strlen(base_dir);
	file_len = strlen(filename);

	has_sep = (base_dir[base_len - 1] == '/' || base_dir[base_len - 1] == '\\');

	result = malloc(base_len + (has_sep ? 0 : 1) + file_len + 1);
	if (!result)
		return NULL;

	strcpy(result, base_dir);
	if (!has_sep)
		strcat(result, "/");
	strcat(result, filename);

	return result;
}

static int
expand_includes_impl(struct cp_include_state *state,
                     const char *source,
                     const char *base_dir);

static int
scan_and_expand(struct cp_include_state *state,
                const char *source,
                const char *base_dir,
                size_t *pos)
{
	const char *p = source + *pos;

	if (*p != '{') {
		(*pos)++;
		return 0;
	}
	p++;

	if (*p != '$') {
		(*pos)++;
		return 0;
	}
	p++;

	if ((p[0] == 'I' || p[0] == 'i') && (p[1] == ' ' || p[1] == '\'' || p[1] == '"')) {
		p++;
		while (*p && (*p == ' ' || *p == '\t'))
			p++;

		int has_quote = (*p == '\'' || *p == '"');
		char quote_char = *p;
		if (has_quote)
			p++;

		const char *filename_start = p;
		while (*p && *p != quote_char && *p != '}')
			p++;

		const char *filename_end = p;

		if (!has_quote) {
			while (filename_end > filename_start &&
			       (*(filename_end - 1) == ' ' || *(filename_end - 1) == '\t' || *(filename_end - 1) == '}'))
				filename_end--;
		}

		if (!has_quote && *p != '}') {
			(*pos)++;
			return 0;
		}

		if (has_quote && *p != quote_char) {
			(*pos)++;
			return 0;
		}

		if (has_quote)
			p++;

		while (*p && *p != '}')
			p++;

		if (*p != '}') {
			(*pos)++;
			return 0;
		}
		p++;

		size_t filename_len = filename_end - filename_start;
		char *filename = malloc(filename_len + 1);
		if (!filename)
			return -1;

		memcpy(filename, filename_start, filename_len);
		filename[filename_len] = '\0';

		if (state->depth >= CP_MAX_INCLUDE_DEPTH) {
			free(filename);
			set_error(state, "include nesting too deep");
			return -1;
		}

		char *full_path = build_path(base_dir, filename);
		free(filename);
		if (!full_path)
			return -1;

		size_t file_len = 0;
		char *file_content = read_file(full_path, &file_len);
		free(full_path);

		if (!file_content) {
			set_error(state, "cannot open include file");
			return -1;
		}

		state->depth++;
		int ret = expand_includes_impl(state, file_content, base_dir);
		state->depth--;
		free(file_content);

		if (ret != 0)
			return ret;

		*pos = p - source;
		return 1;
	} else if ((p[0] == 'I' && p[1] == 'N' && p[2] == 'C' && p[3] == 'L' && p[4] == 'U' && p[5] == 'D' && p[6] == 'E') ||
	           (p[0] == 'i' && p[1] == 'n' && p[2] == 'c' && p[3] == 'l' && p[4] == 'u' && p[5] == 'd' && p[6] == 'e')) {
		p += 7;
		while (*p && (*p == ' ' || *p == '\t'))
			p++;

		int has_quote = (*p == '\'' || *p == '"');
		char quote_char = *p;
		if (has_quote)
			p++;

		const char *filename_start = p;
		while (*p && *p != quote_char && *p != '}')
			p++;

		const char *filename_end = p;

		if (!has_quote) {
			while (filename_end > filename_start &&
			       (*(filename_end - 1) == ' ' || *(filename_end - 1) == '\t' || *(filename_end - 1) == '}'))
				filename_end--;
		}

		if (!has_quote && *p != '}') {
			(*pos)++;
			return 0;
		}

		if (has_quote && *p != quote_char) {
			(*pos)++;
			return 0;
		}

		if (has_quote)
			p++;

		while (*p && *p != '}')
			p++;

		if (*p != '}') {
			(*pos)++;
			return 0;
		}
		p++;

		size_t filename_len = filename_end - filename_start;
		char *filename = malloc(filename_len + 1);
		if (!filename)
			return -1;

		memcpy(filename, filename_start, filename_len);
		filename[filename_len] = '\0';

		if (state->depth >= CP_MAX_INCLUDE_DEPTH) {
			free(filename);
			set_error(state, "include nesting too deep");
			return -1;
		}

		char *full_path = build_path(base_dir, filename);
		free(filename);
		if (!full_path)
			return -1;

		size_t file_len = 0;
		char *file_content = read_file(full_path, &file_len);
		free(full_path);

		if (!file_content) {
			set_error(state, "cannot open include file");
			return -1;
		}

		state->depth++;
		int ret = expand_includes_impl(state, file_content, base_dir);
		state->depth--;
		free(file_content);

		if (ret != 0)
			return ret;

		*pos = p - source;
		return 1;
	}

	(*pos)++;
	return 0;
}

static int
find_string_end(const char *source, size_t *pos)
{
	char quote = source[*pos];
	(*pos)++;

	while (source[*pos]) {
		if (source[*pos] == quote) {
			(*pos)++;
			if (source[*pos] == quote) {
				(*pos)++;
			} else {
				return 0;
			}
		} else {
			(*pos)++;
		}
	}
	return -1;
}

static int
expand_includes_impl(struct cp_include_state *state,
                     const char *source,
                     const char *base_dir)
{
	size_t pos = 0;

	while (source[pos]) {
		if (source[pos] == '\'' || source[pos] == '"') {
			size_t string_start = pos;
			if (find_string_end(source, &pos) != 0)
				return -1;
			if (append_buffer(state, source + string_start, pos - string_start) != 0)
				return -1;
		} else if (source[pos] == '(' && source[pos + 1] == '*') {
			size_t comment_start = pos;
			pos += 2;
			while (source[pos]) {
				if (source[pos] == '*' && source[pos + 1] == ')') {
					pos += 2;
					break;
				}
				pos++;
			}
			if (append_buffer(state, source + comment_start, pos - comment_start) != 0)
				return -1;
		} else if (source[pos] == '{') {
			int ret = scan_and_expand(state, source, base_dir, &pos);
			if (ret < 0)
				return ret;
			if (ret == 0) {
				if (append_buffer(state, source + pos - 1, 1) != 0)
					return -1;
			}
		} else {
			size_t start = pos;
			while (source[pos] && source[pos] != '\'' && source[pos] != '"' &&
			       source[pos] != '(' && source[pos] != '{')
				pos++;
			if (append_buffer(state, source + start, pos - start) != 0)
				return -1;
		}
	}

	return 0;
}

char *
cp_expand_includes(const char *source, const char *base_dir,
                   char *err_buf, size_t err_buf_size)
{
	struct cp_include_state state;
	char *result;

	if (!source) {
		if (err_buf && err_buf_size > 0)
			err_buf[0] = '\0';
		return NULL;
	}

	memset(&state, 0, sizeof(state));
	state.err_buf = err_buf;
	state.err_buf_size = err_buf_size;
	state.depth = 0;

	if (expand_includes_impl(&state, source, base_dir ? base_dir : ".") != 0) {
		free(state.buffer);
		return NULL;
	}

	if (append_buffer(&state, "", 1) != 0) {
		free(state.buffer);
		return NULL;
	}

	result = state.buffer;
	return result;
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
