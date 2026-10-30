/* turbo_gil.c: the GIL for turbo.c's lock, which waits without it (a thread inside qc may be calling into Python) */
#include <Python.h>

void *turbo_gil_release(void) { return Py_IsInitialized() && PyGILState_Check() ? (void *)PyEval_SaveThread() : 0; }
void turbo_gil_restore(void *ts) { if (ts) PyEval_RestoreThread((PyThreadState *)ts); }
