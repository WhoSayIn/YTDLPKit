#ifndef CYTDLP_PYTHON_BRIDGE_H
#define CYTDLP_PYTHON_BRIDGE_H

#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*ytdlpkit_log_callback)(void *context, const char *level, const char *message);
typedef bool (*ytdlpkit_cancel_callback)(void *context);

typedef struct {
  unsigned char *bytes;
  size_t length;
  char *error;
  bool cancelled;
} ytdlpkit_python_result;

/// Initializes CPython exactly once and imports the selected yt-dlp module.
/// Every path must be an absolute, validated filesystem path.
bool ytdlpkit_python_initialize(
    const char *python_home,
    const char *stdlib_zip,
    const char *platform_library,
    const char *dynamic_modules,
    const char *ytdlp_module,
    const char *plugin_module,
    char **error);

/// Executes one JSON-encoded request through YoutubeDL.extract_info(download=False).
ytdlpkit_python_result ytdlpkit_python_execute(
    const unsigned char *request,
    size_t request_length,
    ytdlpkit_log_callback log_callback,
    ytdlpkit_cancel_callback cancel_callback,
    void *context);

void ytdlpkit_python_result_free(ytdlpkit_python_result result);
void ytdlpkit_python_string_free(char *value);

#ifdef __cplusplus
}
#endif

#endif
