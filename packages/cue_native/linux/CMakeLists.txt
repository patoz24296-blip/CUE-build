cmake_minimum_required(VERSION 3.22)
project(cue_native LANGUAGES C CXX)
add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../src" "${CMAKE_CURRENT_BINARY_DIR}/native")
set(cue_native_bundled_libraries $<TARGET_FILE:cue_native> PARENT_SCOPE)
