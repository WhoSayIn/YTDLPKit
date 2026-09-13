#include "PythonBootstrapProbe.h"
#include <Python/Python.h>

bool ytdlpkit_test_python_initialized(void) { return Py_IsInitialized() != 0; }

bool ytdlpkit_test_thread_detached(void) {
  return PyGILState_Check() == 0 && PyThreadState_GetUnchecked() == NULL;
}

bool ytdlpkit_test_gil_round_trip(void) {
  PyGILState_STATE gil = PyGILState_Ensure();
  bool clean = PyErr_Occurred() == NULL;
  PyGILState_Release(gil);
  return clean && ytdlpkit_test_thread_detached();
}
