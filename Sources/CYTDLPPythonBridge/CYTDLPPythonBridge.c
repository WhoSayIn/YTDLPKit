#include "CYTDLPPythonBridge.h"

#include <Python/Python.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static pthread_mutex_t execution_lock = PTHREAD_MUTEX_INITIALIZER;
static ytdlpkit_log_callback active_log_callback = NULL;
static ytdlpkit_cancel_callback active_cancel_callback = NULL;
static void *active_context = NULL;
static bool initialized = false;

static char *copy_string(const char *value) {
  if (value == NULL) return NULL;
  size_t length = strlen(value);
  char *copy = malloc(length + 1);
  if (copy != NULL) memcpy(copy, value, length + 1);
  return copy;
}

static char *python_error(void) {
  if (!PyErr_Occurred()) return copy_string("Unknown Python error");
  PyObject *type = NULL, *value = NULL, *traceback = NULL;
  PyErr_Fetch(&type, &value, &traceback);
  PyErr_NormalizeException(&type, &value, &traceback);

  char *type_name = copy_string("PythonError");
  if (type != NULL) {
    PyObject *name = PyObject_GetAttrString(type, "__name__");
    const char *borrowed_name = name != NULL && PyUnicode_Check(name) ? PyUnicode_AsUTF8(name) : NULL;
    char *stable_type = copy_string(borrowed_name == NULL ? "PythonError" : borrowed_name);
    Py_XDECREF(name);
    if (stable_type != NULL) {
      free(type_name);
      type_name = stable_type;
    }
  }

  PyObject *rendered = value == NULL ? NULL : PyObject_Str(value);
  const char *message = rendered == NULL ? "Python operation failed" : PyUnicode_AsUTF8(rendered);
  if (type_name == NULL) type_name = copy_string("PythonError");
  size_t needed = strlen(type_name) + (message == NULL ? 0 : strlen(message)) + 3;
  char *result = malloc(needed);
  if (result != NULL) snprintf(result, needed, "%s: %s", type_name, message == NULL ? "" : message);

  free(type_name);
  Py_XDECREF(rendered);
  Py_XDECREF(type);
  Py_XDECREF(value);
  Py_XDECREF(traceback);
  return result;
}

static PyObject *bridge_log(PyObject *self, PyObject *args) {
  (void)self;
  const char *level = NULL;
  const char *message = NULL;
  if (!PyArg_ParseTuple(args, "ss", &level, &message)) return NULL;
  if (active_log_callback != NULL) active_log_callback(active_context, level, message);
  Py_RETURN_NONE;
}

static PyObject *bridge_cancelled(PyObject *self, PyObject *args) {
  (void)self;
  (void)args;
  if (active_cancel_callback != NULL && active_cancel_callback(active_context)) Py_RETURN_TRUE;
  Py_RETURN_FALSE;
}

static PyMethodDef bridge_methods[] = {
    {"log", bridge_log, METH_VARARGS, NULL},
    {"cancelled", bridge_cancelled, METH_NOARGS, NULL},
    {NULL, NULL, 0, NULL},
};

static struct PyModuleDef bridge_module = {
    PyModuleDef_HEAD_INIT,
    "_ytdlpkit_native",
    NULL,
    -1,
    bridge_methods,
    NULL,
    NULL,
    NULL,
    NULL,
};

PyMODINIT_FUNC PyInit__ytdlpkit_native(void) { return PyModule_Create(&bridge_module); }

static bool append_path(PyConfig *config, const char *path, char **error) {
  if (path == NULL || path[0] == '\0') return true;
  wchar_t *wide = Py_DecodeLocale(path, NULL);
  if (wide == NULL) {
    if (error != NULL) *error = copy_string("Could not decode a Python module path");
    return false;
  }
  PyStatus status = PyWideStringList_Append(&config->module_search_paths, wide);
  PyMem_RawFree(wide);
  if (PyStatus_Exception(status)) {
    if (error != NULL)
      *error = copy_string(status.err_msg == NULL ? "Could not configure Python module paths" : status.err_msg);
    return false;
  }
  return true;
}

bool ytdlpkit_python_initialize(
    const char *python_home,
    const char *stdlib_zip,
    const char *platform_library,
    const char *dynamic_modules,
    const char *certifi_module,
    const char *ytdlp_module,
    const char *plugin_module,
    char **error) {
  if (error != NULL) *error = NULL;
  pthread_mutex_lock(&execution_lock);
  if (initialized) {
    pthread_mutex_unlock(&execution_lock);
    return true;
  }

  PyPreConfig preconfig;
  PyPreConfig_InitIsolatedConfig(&preconfig);
  preconfig.configure_locale = 0;
  preconfig.utf8_mode = 1;
  PyStatus status = Py_PreInitialize(&preconfig);
  if (PyStatus_Exception(status)) {
    if (error != NULL) *error = copy_string(status.err_msg);
    pthread_mutex_unlock(&execution_lock);
    return false;
  }

  if (PyImport_AppendInittab("_ytdlpkit_native", PyInit__ytdlpkit_native) == -1) {
    if (error != NULL) *error = copy_string("Could not register the native Python bridge");
    pthread_mutex_unlock(&execution_lock);
    return false;
  }

  PyConfig config;
  PyConfig_InitIsolatedConfig(&config);
  config.install_signal_handlers = 0;
  config.parse_argv = 0;
  config.site_import = 0;
  config.user_site_directory = 0;
  config.write_bytecode = 0;
  config.buffered_stdio = 0;
  config.module_search_paths_set = 1;

  wchar_t *home = Py_DecodeLocale(python_home, NULL);
  status = home == NULL
      ? PyStatus_Error("Could not decode the Python home path")
      : PyConfig_SetString(&config, &config.home, home);
  PyMem_RawFree(home);
  if (!PyStatus_Exception(status) && !append_path(&config, stdlib_zip, error))
    status = PyStatus_Error("Could not add the standard-library path");
  if (!PyStatus_Exception(status) && !append_path(&config, platform_library, error))
    status = PyStatus_Error("Could not add the platform-library path");
  if (!PyStatus_Exception(status) && !append_path(&config, dynamic_modules, error))
    status = PyStatus_Error("Could not add the dynamic-module path");
  if (!PyStatus_Exception(status) && !append_path(&config, certifi_module, error))
    status = PyStatus_Error("Could not add the certifi path");
  if (!PyStatus_Exception(status) && !append_path(&config, ytdlp_module, error))
    status = PyStatus_Error("Could not add the yt-dlp path");
  if (!PyStatus_Exception(status) && !append_path(&config, plugin_module, error))
    status = PyStatus_Error("Could not add the plugin path");
  if (PyStatus_Exception(status)) {
    if (error != NULL && *error == NULL) *error = copy_string(status.err_msg);
    PyConfig_Clear(&config);
    pthread_mutex_unlock(&execution_lock);
    return false;
  }

  status = Py_InitializeFromConfig(&config);
  PyConfig_Clear(&config);
  if (PyStatus_Exception(status)) {
    if (error != NULL) *error = copy_string(status.err_msg);
    pthread_mutex_unlock(&execution_lock);
    return false;
  }

  static const char *bootstrap =
      "import json\n"
      "import yt_dlp\n"
      "from yt_dlp.version import __version__ as _ytdlpkit_version\n"
      "from yt_dlp.dependencies import certifi as _ytdlpkit_certifi\n"
      "from _ytdlpkit_native import log as _native_log, cancelled as _native_cancelled\n"
      "if not hasattr(yt_dlp, 'YoutubeDL') or not hasattr(yt_dlp.YoutubeDL, 'sanitize_info'):\n"
      "    raise RuntimeError('yt-dlp is missing the required YoutubeDL API')\n"
      "if _ytdlpkit_certifi is None:\n"
      "    raise RuntimeError('certifi is unavailable')\n"
      "try: _ytdlpkit_version_tuple = tuple(int(part) for part in _ytdlpkit_version.split('.')[:3])\n"
      "except (TypeError, ValueError): raise RuntimeError('yt-dlp reported an invalid version')\n"
      "if len(_ytdlpkit_version_tuple) != 3 or _ytdlpkit_version_tuple < (2025, 1, 1):\n"
      "    raise RuntimeError('yt-dlp is older than the supported API baseline')\n"
      "class _YTDLPKitCancelled(Exception): pass\n"
      "class _YTDLPKitLogger:\n"
      "    def debug(self, message): _native_log('debug', str(message))\n"
      "    def info(self, message): _native_log('info', str(message))\n"
      "    def warning(self, message): _native_log('warning', str(message))\n"
      "    def error(self, message): _native_log('error', str(message))\n"
      "def _ytdlpkit_check(*args, **kwargs):\n"
      "    if _native_cancelled(): raise _YTDLPKitCancelled('Request cancelled')\n"
      "def _ytdlpkit_execute(payload):\n"
      "    request = json.loads(payload)\n"
      "    _ytdlpkit_check()\n"
      "    timeout = max(0.001, float(request['timeout']))\n"
      "    options = {\n"
      "        'logger': _YTDLPKitLogger(), 'socket_timeout': timeout,\n"
      "        'skip_download': True, 'simulate': True, 'cachedir': False,\n"
      "        'quiet': True, 'no_warnings': True, 'noprogress': True,\n"
      "        'writesubtitles': False, 'writeautomaticsub': False,\n"
      "        'writethumbnail': False, 'writeinfojson': False,\n"
      "        'progress_hooks': [_ytdlpkit_check], 'match_filter': _ytdlpkit_check,\n"
      "    }\n"
      "    if request['kind'] == 'extract':\n"
      "        target = request['url']\n"
      "        options['noplaylist'] = not bool(request['includePlaylists'])\n"
      "    elif request['kind'] == 'search':\n"
      "        target = 'ytsearch%d:%s' % (int(request['limit']), request['query'])\n"
      "        options['noplaylist'] = False\n"
      "        options['extract_flat'] = True\n"
      "    else: raise ValueError('Unsupported invocation kind')\n"
      "    with yt_dlp.YoutubeDL(options) as ydl:\n"
      "        info = ydl.extract_info(target, download=False)\n"
      "        _ytdlpkit_check()\n"
      "        clean = ydl.sanitize_info(info)\n"
      "    return json.dumps(clean, ensure_ascii=False, separators=(',', ':')).encode('utf-8')\n";

  PyObject *main = PyImport_AddModule("__main__");
  PyObject *globals = main == NULL ? NULL : PyModule_GetDict(main);
  PyObject *code = Py_CompileString(bootstrap, "<YTDLPKit bootstrap>", Py_file_input);
  PyObject *bootstrap_result = (code == NULL || globals == NULL)
      ? NULL
      : PyEval_EvalCode(code, globals, globals);
  Py_XDECREF(code);
  if (bootstrap_result == NULL) {
    if (error != NULL) *error = python_error();
    pthread_mutex_unlock(&execution_lock);
    return false;
  }
  Py_DECREF(bootstrap_result);

  initialized = true;
  PyEval_SaveThread();
  pthread_mutex_unlock(&execution_lock);
  return true;
}

ytdlpkit_python_result ytdlpkit_python_execute(
    const unsigned char *request,
    size_t request_length,
    ytdlpkit_log_callback log_callback,
    ytdlpkit_cancel_callback cancel_callback,
    void *context) {
  ytdlpkit_python_result result = {0};
  pthread_mutex_lock(&execution_lock);
  if (!initialized) {
    result.error = copy_string("Python has not been initialized");
    pthread_mutex_unlock(&execution_lock);
    return result;
  }

  active_log_callback = log_callback;
  active_cancel_callback = cancel_callback;
  active_context = context;
  PyGILState_STATE gil = PyGILState_Ensure();

  PyObject *main = PyImport_AddModule("__main__");
  PyObject *function = main == NULL ? NULL : PyObject_GetAttrString(main, "_ytdlpkit_execute");
  PyObject *payload = PyBytes_FromStringAndSize((const char *)request, (Py_ssize_t)request_length);
  PyObject *returned = (function == NULL || payload == NULL) ? NULL : PyObject_CallOneArg(function, payload);

  if (returned != NULL && PyBytes_Check(returned)) {
    char *bytes = NULL;
    Py_ssize_t length = 0;
    if (PyBytes_AsStringAndSize(returned, &bytes, &length) == 0 && length >= 0) {
      result.bytes = malloc((size_t)length);
      if (result.bytes != NULL) {
        memcpy(result.bytes, bytes, (size_t)length);
        result.length = (size_t)length;
      } else {
        result.error = copy_string("Could not allocate metadata output");
      }
    }
  } else if (PyErr_Occurred()) {
    result.error = python_error();
    result.cancelled = cancel_callback != NULL && cancel_callback(context);
  } else {
    result.error = copy_string("The Python bridge returned a non-bytes result");
  }

  Py_XDECREF(returned);
  Py_XDECREF(payload);
  Py_XDECREF(function);
  PyGILState_Release(gil);
  active_log_callback = NULL;
  active_cancel_callback = NULL;
  active_context = NULL;
  pthread_mutex_unlock(&execution_lock);
  return result;
}

void ytdlpkit_python_result_free(ytdlpkit_python_result result) {
  free(result.bytes);
  free(result.error);
}

void ytdlpkit_python_string_free(char *value) { free(value); }
