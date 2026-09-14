cmake_minimum_required(VERSION 3.16)

project(gemu_input LANGUAGES CXX)

set(CMAKE_CONFIGURATION_TYPES Release Debug CACHE STRING "" FORCE)
set(CMAKE_CXX_STANDARD 11)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Pass -DGMOD_HEADERS_DIR=... to use a local checkout. When it is omitted,
# FetchContent obtains the official x86-64 development headers at configure
# time. The headers are a build dependency and are never put in the addon GMA.
set(GMOD_HEADERS_DIR "" CACHE PATH "Path to gmod-module-base development checkout")
if(NOT GMOD_HEADERS_DIR)
    include(FetchContent)
    if(POLICY CMP0169)
        cmake_policy(SET CMP0169 OLD)
    endif()
    FetchContent_Declare(
        gmod_headers
        GIT_REPOSITORY https://github.com/Facepunch/gmod-module-base.git
        GIT_TAG development
        GIT_SHALLOW TRUE
    )
    FetchContent_GetProperties(gmod_headers)
    if(NOT gmod_headers_POPULATED)
        FetchContent_Populate(gmod_headers)
    endif()
    set(GMOD_HEADERS_DIR "${gmod_headers_SOURCE_DIR}")
endif()

if(NOT EXISTS "${GMOD_HEADERS_DIR}/include/CMakeLists.txt")
    message(FATAL_ERROR "GMOD_HEADERS_DIR must point to the development gmod-module-base checkout")
endif()

add_subdirectory("${GMOD_HEADERS_DIR}/include" "${CMAKE_CURRENT_BINARY_DIR}/gmod-module-base")

add_library(gemu_input SHARED src/gemu_input.cpp)
target_compile_definitions(gemu_input PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX _AMD64_ _WIN64 _M_X64)
target_link_libraries(gemu_input PRIVATE gmod-module-base Xinput dinput8 dxguid)
set_gmod_suffix_prefix(gemu_input)

# gmod-module-base defaults to the server prefix. This module intentionally
# exposes a client-only polling API and must be loaded as gmcl_gemu_input.
set_target_properties(gemu_input PROPERTIES PREFIX "gmcl_")

add_executable(gemu_input_probe src/probe.cpp)
target_compile_definitions(gemu_input_probe PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
target_link_libraries(gemu_input_probe PRIVATE dinput8 dxguid)

if(MSVC)
    target_compile_options(gemu_input PRIVATE /W4 /permissive-)
else()
    target_compile_options(gemu_input PRIVATE -Wall -Wextra -Wpedantic)
endif()
