/* compact_pascal.h : embeddable Pascal-to-WASM compiler (bring-your-own runtime) */
/* PUBLIC DOMAIN or MIT-0 — See LICENSE for details. */

#ifndef COMPACT_PASCAL_H
#define COMPACT_PASCAL_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/****************************************************************
 * Status codes
 ****************************************************************/

enum {
	CP_OK = 0,
	CP_ERR = -1,
	CP_ERR_IO = -2,
	CP_ERR_COMPILE = -3,
	CP_ERR_RUNTIME = -4,
	CP_ERR_NOMEM = -5,
};

/****************************************************************
 * Opaque types
 ****************************************************************/

typedef struct cp_compiler cp_compiler_t;
typedef struct cp_instance cp_instance_t;

/****************************************************************
 * WASM engine vtable
 *
 * The user fills in this struct with function pointers that
 * bridge to their chosen WASM runtime (wasm3, WAMR, vmir, etc.).
 * All callbacks receive the engine's user_data pointer.
 ****************************************************************/

/** Signature for a host import function.
 *
 * The runtime calls this when guest code invokes an import.
 * args and results point to arrays of i32/i64/f32/f64 values
 * encoded as uint64_t. n_args and n_results give the counts.
 * Return 0 on success, non-zero on trap.
 */
typedef int (*cp_import_fn)(void *user_data,
                            const uint64_t *args, int n_args,
                            uint64_t *results, int n_results);

typedef struct cp_wasm_engine {
	/** Instantiate a WASM module from raw bytes.
	 *
	 * Returns an opaque instance handle, or NULL on failure.
	 * The engine should parse and validate the module.
	 */
	void *(*instantiate)(void *user_data,
	                     const unsigned char *wasm, size_t wasm_len);

	/** Call an exported function by name.
	 *
	 * args and results are arrays of uint64_t holding WASM values.
	 * Returns 0 on success, non-zero on trap or error.
	 */
	int (*call)(void *user_data, void *instance,
	            const char *name,
	            const uint64_t *args, int n_args,
	            uint64_t *results, int n_results);

	/** Get a pointer to linear memory and its current size.
	 *
	 * Writes the memory base pointer and byte length through the
	 * out-parameters. Returns 0 on success, non-zero if the
	 * instance has no exported memory.
	 */
	int (*get_memory)(void *user_data, void *instance,
	                  unsigned char **base, size_t *len);

	/** Register a host function as a WASM import.
	 *
	 * module and name identify the import (e.g. "env", "print_int").
	 * The engine should make fn available to subsequently
	 * instantiated modules. fn_user_data is passed through to fn.
	 * Returns 0 on success.
	 */
	int (*register_import)(void *user_data,
	                       const char *module, const char *name,
	                       cp_import_fn fn, void *fn_user_data);

	/** Destroy an instance returned by instantiate. */
	void (*destroy)(void *user_data, void *instance);

	/** User-supplied context pointer passed to all callbacks. */
	void *user_data;
} cp_wasm_engine_t;

/****************************************************************
 * Compilation result
 ****************************************************************/

typedef struct cp_result {
	unsigned char *wasm;    /* compiled WASM bytes (caller frees) */
	size_t wasm_len;        /* length in bytes */
	char *error;            /* error message, or NULL on success (caller frees) */
	int status;             /* CP_OK or CP_ERR_COMPILE */
} cp_result_t;

/****************************************************************
 * Compiler lifecycle
 ****************************************************************/

/** Create a new compiler context.
 *
 * The engine vtable must remain valid for the lifetime of the
 * compiler. Returns NULL on allocation failure.
 */
cp_compiler_t *cp_compiler_new(cp_wasm_engine_t *engine);

/** Free a compiler context and all associated resources. */
void cp_compiler_free(cp_compiler_t *compiler);

/** Load the compiler snapshot WASM from a file path.
 *
 * Returns CP_OK on success, CP_ERR_IO on read failure.
 */
int cp_load_compiler_from_file(cp_compiler_t *compiler,
                               const char *path);

/** Load the compiler snapshot WASM from a memory buffer.
 *
 * The buffer is copied; the caller may free it afterward.
 * Returns CP_OK on success, CP_ERR_NOMEM on allocation failure.
 */
int cp_load_compiler_from_string(cp_compiler_t *compiler,
                                 const unsigned char *wasm,
                                 size_t wasm_len);

/** Compile Pascal source to WASM.
 *
 * source is a pointer to Pascal source code, source_len its
 * byte length (not including any NUL terminator). The compiler
 * snapshot must have been loaded first.
 *
 * On success result.status is CP_OK and result.wasm holds the
 * compiled module. On failure result.status is CP_ERR_COMPILE
 * and result.error holds the diagnostic.
 *
 * The caller must free result.wasm and result.error.
 */
cp_result_t cp_compile(cp_compiler_t *compiler,
                       const char *source, size_t source_len);

/****************************************************************
 * Instance lifecycle
 ****************************************************************/

/** Instantiate a compiled WASM module.
 *
 * Returns NULL on failure. The engine vtable must remain valid
 * for the lifetime of the instance.
 */
cp_instance_t *cp_instantiate(cp_wasm_engine_t *engine,
                              const unsigned char *wasm,
                              size_t wasm_len);

/** Free an instance and all associated resources. */
void cp_instance_free(cp_instance_t *instance);

/** Call an exported function by name.
 *
 * Returns CP_OK on success, CP_ERR_RUNTIME on trap.
 */
int cp_call(cp_instance_t *instance, const char *name);

/****************************************************************
 * Host-guest FFI
 ****************************************************************/

/** Register a host function as a WASM import.
 *
 * Must be called before cp_instantiate for the module that
 * will use the import. The module and name identify the import
 * slot. fn_user_data is passed through to fn on each call.
 * Returns CP_OK on success.
 */
int cp_register_import(cp_wasm_engine_t *engine,
                       const char *module, const char *name,
                       cp_import_fn fn, void *fn_user_data);

/****************************************************************
 * WASI preview 1 helpers
 *
 * Ready-made host functions implementing the WASI imports that
 * the compiler and compiled programs need. Wire these into your
 * WASM runtime's import mechanism.
 ****************************************************************/

/** State for the WASI helpers.
 *
 * The caller fills in the fd callbacks or uses the provided
 * defaults that map to POSIX stdin/stdout/stderr.
 */
typedef struct cp_wasi_ctx {
	/** Read callback: read up to len bytes into buf.
	 *
	 * Returns number of bytes read, or -1 on error.
	 * fd is the WASI file descriptor (0=stdin, 1=stdout, 2=stderr).
	 */
	int (*fd_read)(void *user_data, int fd,
	               unsigned char *buf, size_t len);

	/** Write callback: write len bytes from buf.
	 *
	 * Returns number of bytes written, or -1 on error.
	 */
	int (*fd_write)(void *user_data, int fd,
	                const unsigned char *buf, size_t len);

	/** Exit callback: called on proc_exit.
	 *
	 * If NULL, the default calls exit().
	 */
	void (*proc_exit)(void *user_data, int code);

	void *user_data;

	/* Command-line arguments for args_get/args_sizes_get. */
	int argc;
	const char *const *argv;
} cp_wasi_ctx_t;

/** Initialize a WASI context with defaults.
 *
 * Sets up fd_read/fd_write to use POSIX read(2)/write(2) on
 * the real file descriptors, and proc_exit to call exit().
 */
void cp_wasi_ctx_init(cp_wasi_ctx_t *ctx);

/** WASI fd_read implementation.
 *
 * Reads from the iovec described in WASM linear memory.
 * Suitable for use as a cp_import_fn with cp_wasi_ctx_t as
 * fn_user_data.
 */
int cp_wasi_fd_read(void *user_data,
                    const uint64_t *args, int n_args,
                    uint64_t *results, int n_results);

/** WASI fd_write implementation. */
int cp_wasi_fd_write(void *user_data,
                     const uint64_t *args, int n_args,
                     uint64_t *results, int n_results);

/** WASI proc_exit implementation. */
int cp_wasi_proc_exit(void *user_data,
                      const uint64_t *args, int n_args,
                      uint64_t *results, int n_results);

/** WASI args_sizes_get implementation. */
int cp_wasi_args_sizes_get(void *user_data,
                           const uint64_t *args, int n_args,
                           uint64_t *results, int n_results);

/** WASI args_get implementation. */
int cp_wasi_args_get(void *user_data,
                     const uint64_t *args, int n_args,
                     uint64_t *results, int n_results);

/****************************************************************
 * String conversion helpers
 ****************************************************************/

/** Write a C string into WASM memory as a Pascal short string.
 *
 * Copies up to 255 bytes from str into the Pascal string at
 * offset addr in the instance's linear memory. The first byte
 * is set to the length. Returns the number of bytes written
 * (1 + length), or CP_ERR if the string is too long or addr
 * is out of bounds.
 */
int cp_str_to_pascal(cp_instance_t *instance, uint32_t addr,
                     const char *str, size_t len);

/** Read a Pascal short string from WASM memory into a C buffer.
 *
 * Copies the string data (without the length byte) into buf,
 * which must have room for at least 256 bytes. Writes a NUL
 * terminator. Returns the string length (not including NUL),
 * or CP_ERR if addr is out of bounds.
 */
int cp_pascal_to_str(cp_instance_t *instance, uint32_t addr,
                     char *buf, size_t buf_size);

#ifdef __cplusplus
}
#endif

#endif /* COMPACT_PASCAL_H */
