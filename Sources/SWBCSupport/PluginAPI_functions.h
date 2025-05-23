//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_C_CAS_PLUGINAPI_FUNCTIONS_H
#define LLVM_C_CAS_PLUGINAPI_FUNCTIONS_H

#include "PluginAPI_types.h"

/**
 * Returns the \c LLCAS_VERSION_MAJOR and \c LLCAS_VERSION_MINOR values that the
 * plugin was compiled with.
 * Intended for assisting compatibility with different versions.
 */
static void llcas_get_plugin_version(unsigned *major, unsigned *minor);

/**
 * Releases memory of C string pointers provided by other functions.
 */
static void llcas_string_dispose(char *);

/**
 * Cancels the asynchronous query associated with the \c llcas_cancellable_t.
 */
static void llcas_cancellable_cancel(llcas_cancellable_t);

/**
 * Releases memory associated with given \c llcas_cancellable_t.
 */
static void llcas_cancellable_dispose(llcas_cancellable_t);

/**
 * Options object to configure creation of \c llcas_cas_t. After passing to
 * \c llcas_cas_create, its memory can be released via
 * \c llcas_cas_options_dispose.
 */
static llcas_cas_options_t llcas_cas_options_create(void);

static void llcas_cas_options_dispose(llcas_cas_options_t);

/**
 * Receives the \c LLCAS_VERSION_MAJOR and \c LLCAS_VERSION_MINOR values that
 * the client was compiled with.
 * Intended for assisting compatibility with different versions.
 */
static void llcas_cas_options_set_client_version(llcas_cas_options_t,
                                                       unsigned major,
                                                       unsigned minor);

/**
 * Receives a local file-system path that the plugin should use for any on-disk
 * resources/caches.
 */
static void llcas_cas_options_set_ondisk_path(llcas_cas_options_t,
                                                    const char *path);

/**
 * Receives a name/value strings pair, for the plugin to set as a custom option
 * it supports. These are usually passed through as invocation options and are
 * opaque to the client.
 *
 * \param error optional pointer to receive an error message if an error
 * occurred. If set, the memory it points to needs to be released via
 * \c llcas_string_dispose.
 * \returns true if there was an error, false otherwise.
 */
static bool llcas_cas_options_set_option(llcas_cas_options_t,
                                               const char *name,
                                               const char *value, char **error);

/**
 * Creates a new \c llcas_cas_t object. The objects returned from the other
 * functions are only valid to use while the \c llcas_cas_t object that they
 * came from is still valid.
 *
 * \param error optional pointer to receive an error message if an error
 * occurred. If set, the memory it points to needs to be released via
 * \c llcas_string_dispose.
 * \returns \c NULL if there was an error.
 */
static llcas_cas_t llcas_cas_create(llcas_cas_options_t, char **error);

/**
 * Releases memory of \c llcas_cas_t. After calling this it is invalid to keep
 * using objects that originated from this \c llcas_cas_t instance.
 */
static void llcas_cas_dispose(llcas_cas_t);

/**
 * Get the local storage size of the CAS/cache data in bytes.
 *
 * \param error optional pointer to receive an error message if an error
 * occurred. If set, the memory it points to needs to be released via
 * \c llcas_string_dispose.
 * \returns the local storage size of the CAS/cache data, or -1 if the
 * implementation does not support reporting such size, or -2 if an error
 * occurred.
 */
static int64_t llcas_cas_get_ondisk_size(llcas_cas_t, char **error);

/**
 * Set the size for limiting disk storage growth.
 *
 * \param size_limit the maximum size limit in bytes. 0 means no limit. Negative
 * values are invalid.
 * \param error optional pointer to receive an error message if an error
 * occurred. If set, the memory it points to needs to be released via
 * \c llcas_string_dispose.
 * \returns true if there was an error, false otherwise.
 */
static bool
llcas_cas_set_ondisk_size_limit(llcas_cas_t, int64_t size_limit, char **error);

/**
 * Prune local storage to reduce its size according to the desired size limit.
 * Pruning can happen concurrently with other operations.
 *
 * \returns true if there was an error, false otherwise.
 */
static bool llcas_cas_prune_ondisk_data(llcas_cas_t, char **error);

/**
 * \returns the hash schema name that the plugin is using. The string memory it
 * points to needs to be released via \c llcas_string_dispose.
 */
static char *llcas_cas_get_hash_schema_name(llcas_cas_t);

/**
 * Parses the printed digest and returns the digest hash bytes.
 *
 * \param printed_digest a C string that was previously provided by
 * \c llcas_digest_print.
 * \param bytes pointer to a buffer for writing the digest bytes. Can be \c NULL
 * if \p bytes_size is 0.
 * \param bytes_size the size of the buffer.
 * \param error optional pointer to receive an error message if an error
 * occurred. If set, the memory it points to needs to be released via
 * \c llcas_string_dispose.
 * \returns 0 if there was an error. If \p bytes_size is smaller than the
 * required size to fit the digest bytes, returns the required buffer size
 * without writing to \c bytes. Otherwise writes the digest bytes to \p bytes
 * and returns the number of written bytes.
 */
static unsigned llcas_digest_parse(llcas_cas_t,
                                         const char *printed_digest,
                                         uint8_t *bytes, size_t bytes_size,
                                         char **error);

/**
 * Returns a string for the given digest bytes that can be passed to
 * \c llcas_digest_parse.
 *
 * \param printed_id pointer to receive the printed digest string. The memory it
 * points to needs to be released via \c llcas_string_dispose.
 * \param error optional pointer to receive an error message if an error
 * occurred. If set, the memory it points to needs to be released via
 * \c llcas_string_dispose.
 * \returns true if there was an error, false otherwise.
 */
static bool llcas_digest_print(llcas_cas_t, llcas_digest_t,
                                     char **printed_id, char **error);

/**
 * Provides the \c llcas_objectid_t value for the given \c llcas_digest_t.
 *
 * \param digest the digest bytes that the returned \c llcas_objectid_t
 * represents.
 * \param p_id pointer to store the returned \c llcas_objectid_t object.
 * \param error optional pointer to receive an error message if an error
 * occurred. If set, the memory it points to needs to be released via
 * \c llcas_string_dispose.
 * \returns true if there was an error, false otherwise.
 */
static bool llcas_cas_get_objectid(llcas_cas_t, llcas_digest_t digest,
                                         llcas_objectid_t *p_id, char **error);

/**
 * \returns the \c llcas_digest_t value for the given \c llcas_objectid_t.
 * The memory that the buffer points to is valid for the lifetime of the
 * \c llcas_cas_t object.
 */
static llcas_digest_t llcas_objectid_get_digest(llcas_cas_t,
                                                      llcas_objectid_t);

/**
 * Checks whether a \c llcas_objectid_t points to an existing object.
 *
 * \param globally For CAS implementations that distinguish between local CAS
 * and remote/distributed CAS, \p globally set to false indicates that the
 * lookup will be restricted to the local CAS, returning "not found" even if the
 * object might exist in the remote CAS.
 * \param error optional pointer to receive an error message if an error
 * occurred. If set, the memory it points to needs to be released via
 * \c llcas_string_dispose.
 * \returns one of \c llcas_lookup_result_t.
 */
static llcas_lookup_result_t llcas_cas_contains_object(llcas_cas_t,
                                                             llcas_objectid_t,
                                                             bool globally,
                                                             char **error);

/**
 * Loads the object that \c llcas_objectid_t points to.
 *
 * \param error optional pointer to receive an error message if an error
 * occurred. If set, the memory it points to needs to be released via
 * \c llcas_string_dispose.
 * \returns one of \c llcas_lookup_result_t.
 */
static llcas_lookup_result_t llcas_cas_load_object(
    llcas_cas_t, llcas_objectid_t, llcas_loaded_object_t *, char **error);

/**
 * Like \c llcas_cas_load_object but loading happens via a callback function.
 * Whether the call is asynchronous or not depends on the implementation.
 *
 * \param ctx_cb pointer to pass to the callback function.
 *
 * \param[out] cancel_tok optional pointer to receive a \c llcas_cancellable_t.
 */
static void llcas_cas_load_object_async(llcas_cas_t, llcas_objectid_t,
                                              void *ctx_cb,
                                              llcas_cas_load_object_cb,
                                              llcas_cancellable_t *cancel_tok);

/**
 * Stores the object with the provided data buffer and \c llcas_objectid_t
 * references, and provides its associated \c llcas_objectid_t.
 *
 * \param refs pointer to array of \c llcas_objectid_t. Can be \c NULL if
 * \p refs_count is 0.
 * \param refs_count number of \c llcas_objectid_t objects in the array.
 * \param p_id pointer to store the returned \c llcas_objectid_t object.
 * \param error optional pointer to receive an error message if an error
 * occurred. If set, the memory it points to needs to be released via
 * \c llcas_string_dispose.
 * \returns true if there was an error, false otherwise.
 */
static bool llcas_cas_store_object(llcas_cas_t, llcas_data_t,
                                         const llcas_objectid_t *refs,
                                         size_t refs_count,
                                         llcas_objectid_t *p_id, char **error);

/**
 * \returns the data buffer of the provided \c llcas_loaded_object_t. The buffer
 * pointer must be 8-byte aligned and \c NULL terminated. The memory that the
 * buffer points to is valid for the lifetime of the \c llcas_cas_t object.
 */
static llcas_data_t llcas_loaded_object_get_data(llcas_cas_t,
                                                       llcas_loaded_object_t);

/**
 * \returns the references of the provided \c llcas_loaded_object_t.
 */
static llcas_object_refs_t
    llcas_loaded_object_get_refs(llcas_cas_t, llcas_loaded_object_t);

/**
 * \returns the number of references in the provided \c llcas_object_refs_t.
 */
static size_t llcas_object_refs_get_count(llcas_cas_t,
                                                llcas_object_refs_t);

/**
 * \returns the \c llcas_objectid_t of the reference at \p index. It is invalid
 * to pass an index that is out of the range of references.
 */
static llcas_objectid_t llcas_object_refs_get_id(llcas_cas_t,
                                                       llcas_object_refs_t,
                                                       size_t index);

/**
 * Retrieves the \c llcas_objectid_t value associated with a \p key.
 *
 * \param p_value pointer to store the returned \c llcas_objectid_t object.
 * \param globally if true it is a hint to the underlying implementation that
 * the lookup is profitable to be done on a distributed caching level, not just
 * locally. The implementation is free to ignore this flag.
 * \param error optional pointer to receive an error message if an error
 * occurred. If set, the memory it points to needs to be released via
 * \c llcas_string_dispose.
 * \returns one of \c llcas_lookup_result_t.
 */
static llcas_lookup_result_t llcas_actioncache_get_for_digest(
    llcas_cas_t, llcas_digest_t key, llcas_objectid_t *p_value, bool globally,
    char **error);

/**
 * Like \c llcas_actioncache_get_for_digest but result is provided to a callback
 * function. Whether the call is asynchronous or not depends on the
 * implementation.
 *
 * \param ctx_cb pointer to pass to the callback function.
 *
 * \param[out] cancel_tok optional pointer to receive a \c llcas_cancellable_t.
 */
static void llcas_actioncache_get_for_digest_async(
    llcas_cas_t, llcas_digest_t key, bool globally, void *ctx_cb,
    llcas_actioncache_get_cb, llcas_cancellable_t *cancel_tok);

/**
 * Associates a \c llcas_objectid_t \p value with a \p key. It is invalid to set
 * a different \p value to the same \p key.
 *
 * \param globally if true it is a hint to the underlying implementation that
 * the association is profitable to be done on a distributed caching level, not
 * just locally. The implementation is free to ignore this flag.
 * \param error optional pointer to receive an error message if an error
 * occurred. If set, the memory it points to needs to be released via
 * \c llcas_string_dispose.
 * \returns true if there was an error, false otherwise.
 */
static bool llcas_actioncache_put_for_digest(llcas_cas_t,
                                                   llcas_digest_t key,
                                                   llcas_objectid_t value,
                                                   bool globally, char **error);

/**
 * Like \c llcas_actioncache_put_for_digest but result is provided to a callback
 * function. Whether the call is asynchronous or not depends on the
 * implementation.
 *
 * \param ctx_cb pointer to pass to the callback function.
 *
 * \param[out] cancel_tok optional pointer to receive a \c llcas_cancellable_t.
 */
static void llcas_actioncache_put_for_digest_async(
    llcas_cas_t, llcas_digest_t key, llcas_objectid_t value, bool globally,
    void *ctx_cb, llcas_actioncache_put_cb, llcas_cancellable_t *cancel_tok);


#endif /* LLVM_C_CAS_PLUGINAPI_FUNCTIONS_H */

