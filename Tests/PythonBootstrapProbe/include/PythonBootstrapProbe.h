#ifndef YTDLPKIT_PYTHON_BOOTSTRAP_PROBE_H
#define YTDLPKIT_PYTHON_BOOTSTRAP_PROBE_H

#include <stdbool.h>

bool ytdlpkit_test_python_initialized(void);
bool ytdlpkit_test_thread_detached(void);
bool ytdlpkit_test_gil_round_trip(void);

#endif
