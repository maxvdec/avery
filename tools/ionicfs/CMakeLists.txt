cmake_minimum_required(VERSION 3.15)
project(ionicfs)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

file(GLOB_RECURSE SOURCES
    src/*.cpp
)

add_executable(ionicfs ${SOURCES})
target_include_directories(ionicfs PRIVATE include)

set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/build)