# CodSpeed benchmarks: Google Benchmark (CodSpeed's compatibility layer) over turbo against SQLite's interpreter.
#   cmake -S bench -B build/bench -DCMAKE_BUILD_TYPE=Release -DCODSPEED_MODE=simulation
#   cmake --build build/bench -j
#   build/bench/turbo_bench            (or: codspeed run -m simulation -- build/bench/turbo_bench)
# The build runs the repository's `make all` (fetches SQLite, pinned; writes build/gen) and scripts/gen-db.py (the
# benchmarks' database, build/bench/turbo_bench.db). CODSPEED_MODE unset: a plain Google Benchmark binary.
cmake_minimum_required(VERSION 3.16)
project(turbo_bench LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE RelWithDebInfo)
endif()

get_filename_component(TURBO_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/.." ABSOLUTE)
set(TURBO_GEN "${TURBO_ROOT}/build/gen")
find_program(MAKE_EXE NAMES gmake make REQUIRED)
find_package(Python3 COMPONENTS Interpreter REQUIRED)

include(FetchContent)
FetchContent_Declare(
  google_benchmark
  GIT_REPOSITORY https://github.com/CodSpeedHQ/codspeed-cpp
  GIT_TAG v2.4.0
  SOURCE_SUBDIR google_benchmark
)
set(BENCHMARK_ENABLE_TESTING OFF CACHE BOOL "" FORCE)
set(BENCHMARK_ENABLE_GTEST_TESTS OFF CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(google_benchmark)

# turbo's patched amalgamation and generated decoders (the Makefile's `all`)
add_custom_command(
  OUTPUT "${TURBO_GEN}/sqlite3.c" "${TURBO_GEN}/sqlite3.h" "${TURBO_GEN}/qc_dec.h"
  COMMAND "${MAKE_EXE}" -C "${TURBO_ROOT}" all "PYTHON=${Python3_EXECUTABLE}"
  DEPENDS "${TURBO_ROOT}/qc/patch.py" "${TURBO_ROOT}/qc/gen_decoders.py" "${TURBO_ROOT}/scripts/fetch-sqlite.sh"
  COMMENT "make all (the patched amalgamation and qc's decoders)"
  VERBATIM
)

# the benchmarks' database: 5k users, 20k posts, 80k likes (CI's test size)
set(TURBO_BENCH_DB "${CMAKE_CURRENT_BINARY_DIR}/turbo_bench.db")
add_custom_command(
  OUTPUT "${TURBO_BENCH_DB}"
  COMMAND "${Python3_EXECUTABLE}" "${TURBO_ROOT}/scripts/gen-db.py" "${TURBO_BENCH_DB}" 5000 20000 80000
  DEPENDS "${TURBO_ROOT}/scripts/gen-db.py"
  COMMENT "scripts/gen-db.py (the benchmarks' database)"
  VERBATIM
)
add_custom_target(turbo_bench_db DEPENDS "${TURBO_BENCH_DB}")

# SQLite and qc in one C translation unit, with the options of the Makefile's benchmark build (no -march=native: the
# binary must run on any machine, and under CodSpeed's CPU simulation)
add_library(turbo_sqlite STATIC
  turbo_lib.c
  "${TURBO_GEN}/sqlite3.c"
  "${TURBO_GEN}/qc_dec.h"
)
set_source_files_properties("${TURBO_GEN}/sqlite3.c" "${TURBO_GEN}/qc_dec.h" PROPERTIES HEADER_FILE_ONLY ON GENERATED ON)
target_include_directories(turbo_sqlite PUBLIC "${TURBO_GEN}" PRIVATE "${TURBO_ROOT}/qc")
target_compile_definitions(turbo_sqlite PRIVATE
  SQLITE_THREADSAFE=0 SQLITE_DEFAULT_MEMSTATUS=0 SQLITE_DEFAULT_WAL_SYNCHRONOUS=1 SQLITE_DQS=0
  SQLITE_LIKE_DOESNT_MATCH_BLOBS SQLITE_USE_ALLOCA SQLITE_OMIT_LOAD_EXTENSION SQLITE_OMIT_DEPRECATED
  SQLITE_OMIT_SHARED_CACHE SQLITE_OMIT_DECLTYPE
)
target_compile_options(turbo_sqlite PRIVATE -O2 -w)
find_package(Threads REQUIRED)
target_link_libraries(turbo_sqlite PUBLIC m Threads::Threads)

add_executable(turbo_bench turbo_bench.cpp)
target_compile_definitions(turbo_bench PRIVATE TURBO_BENCH_DB="${TURBO_BENCH_DB}")
target_link_libraries(turbo_bench PRIVATE turbo_sqlite benchmark::benchmark)
add_dependencies(turbo_bench turbo_bench_db)
