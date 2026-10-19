cmake_minimum_required(VERSION 3.22)
project(cue_native LANGUAGES C CXX)
include(FetchContent)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(LLAMA_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_SERVER OFF CACHE BOOL "" FORCE)
set(LLAMA_CURL OFF CACHE BOOL "" FORCE)
set(GGML_METAL OFF CACHE BOOL "" FORCE)
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
set(GGML_NATIVE OFF CACHE BOOL "" FORCE)
set(GGML_ACCELERATE OFF CACHE BOOL "" FORCE)
# The optimized llamafile kernels require ARMv8 half-float instructions.
# Keep the portable CPU implementation for Flutter's ARMv7 Android target.
if(ANDROID AND ANDROID_ABI STREQUAL "armeabi-v7a")
  set(GGML_LLAMAFILE OFF CACHE BOOL "" FORCE)
endif()
FetchContent_Declare(llama URL https://github.com/ggml-org/llama.cpp/archive/refs/tags/b5046.tar.gz
  URL_HASH SHA256=694c69e7975a5950797e068d896c1fbafc45269c03164a64ae49754273eb5e4d)
FetchContent_MakeAvailable(llama)
# Only CUE's shared bridge belongs in the app bundle. llama/ggml are linked
# statically; their standalone install rules cannot use Flutter's bundle prefix.
set_property(DIRECTORY "${llama_SOURCE_DIR}" PROPERTY EXCLUDE_FROM_ALL TRUE)
add_library(cue_native SHARED cue_bridge.cpp)
target_link_libraries(cue_native PRIVATE llama)
target_compile_features(cue_native PRIVATE cxx_std_17)
if(APPLE)
  set_target_properties(cue_native PROPERTIES FRAMEWORK TRUE FRAMEWORK_VERSION A
    MACOSX_FRAMEWORK_IDENTIFIER studio.cue.native MACOSX_FRAMEWORK_SHORT_VERSION_STRING 1.0
    MACOSX_FRAMEWORK_BUNDLE_VERSION 1 INSTALL_NAME_DIR "@rpath")
endif()
