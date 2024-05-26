include(cmake/SystemLink.cmake)
include(cmake/LibFuzzer.cmake)
include(CMakeDependentOption)
include(CheckCXXCompilerFlag)


macro(template_testing_supports_sanitizers)
  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND NOT WIN32)
    set(SUPPORTS_UBSAN ON)
  else()
    set(SUPPORTS_UBSAN OFF)
  endif()

  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND WIN32)
    set(SUPPORTS_ASAN OFF)
  else()
    set(SUPPORTS_ASAN ON)
  endif()
endmacro()

macro(template_testing_setup_options)
  option(template_testing_ENABLE_HARDENING "Enable hardening" ON)
  option(template_testing_ENABLE_COVERAGE "Enable coverage reporting" OFF)
  cmake_dependent_option(
    template_testing_ENABLE_GLOBAL_HARDENING
    "Attempt to push hardening options to built dependencies"
    ON
    template_testing_ENABLE_HARDENING
    OFF)

  template_testing_supports_sanitizers()

  if(NOT PROJECT_IS_TOP_LEVEL OR template_testing_PACKAGING_MAINTAINER_MODE)
    option(template_testing_ENABLE_IPO "Enable IPO/LTO" OFF)
    option(template_testing_WARNINGS_AS_ERRORS "Treat Warnings As Errors" OFF)
    option(template_testing_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(template_testing_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" OFF)
    option(template_testing_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(template_testing_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" OFF)
    option(template_testing_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(template_testing_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(template_testing_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(template_testing_ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)
    option(template_testing_ENABLE_CPPCHECK "Enable cpp-check analysis" OFF)
    option(template_testing_ENABLE_PCH "Enable precompiled headers" OFF)
    option(template_testing_ENABLE_CACHE "Enable ccache" OFF)
  else()
    option(template_testing_ENABLE_IPO "Enable IPO/LTO" ON)
    option(template_testing_WARNINGS_AS_ERRORS "Treat Warnings As Errors" ON)
    option(template_testing_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(template_testing_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" ${SUPPORTS_ASAN})
    option(template_testing_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(template_testing_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" ${SUPPORTS_UBSAN})
    option(template_testing_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(template_testing_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(template_testing_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(template_testing_ENABLE_CLANG_TIDY "Enable clang-tidy" ON)
    option(template_testing_ENABLE_CPPCHECK "Enable cpp-check analysis" ON)
    option(template_testing_ENABLE_PCH "Enable precompiled headers" OFF)
    option(template_testing_ENABLE_CACHE "Enable ccache" ON)
  endif()

  if(NOT PROJECT_IS_TOP_LEVEL)
    mark_as_advanced(
      template_testing_ENABLE_IPO
      template_testing_WARNINGS_AS_ERRORS
      template_testing_ENABLE_USER_LINKER
      template_testing_ENABLE_SANITIZER_ADDRESS
      template_testing_ENABLE_SANITIZER_LEAK
      template_testing_ENABLE_SANITIZER_UNDEFINED
      template_testing_ENABLE_SANITIZER_THREAD
      template_testing_ENABLE_SANITIZER_MEMORY
      template_testing_ENABLE_UNITY_BUILD
      template_testing_ENABLE_CLANG_TIDY
      template_testing_ENABLE_CPPCHECK
      template_testing_ENABLE_COVERAGE
      template_testing_ENABLE_PCH
      template_testing_ENABLE_CACHE)
  endif()

  template_testing_check_libfuzzer_support(LIBFUZZER_SUPPORTED)
  if(LIBFUZZER_SUPPORTED AND (template_testing_ENABLE_SANITIZER_ADDRESS OR template_testing_ENABLE_SANITIZER_THREAD OR template_testing_ENABLE_SANITIZER_UNDEFINED))
    set(DEFAULT_FUZZER ON)
  else()
    set(DEFAULT_FUZZER OFF)
  endif()

  option(template_testing_BUILD_FUZZ_TESTS "Enable fuzz testing executable" ${DEFAULT_FUZZER})

endmacro()

macro(template_testing_global_options)
  if(template_testing_ENABLE_IPO)
    include(cmake/InterproceduralOptimization.cmake)
    template_testing_enable_ipo()
  endif()

  template_testing_supports_sanitizers()

  if(template_testing_ENABLE_HARDENING AND template_testing_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR template_testing_ENABLE_SANITIZER_UNDEFINED
       OR template_testing_ENABLE_SANITIZER_ADDRESS
       OR template_testing_ENABLE_SANITIZER_THREAD
       OR template_testing_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    message("${template_testing_ENABLE_HARDENING} ${ENABLE_UBSAN_MINIMAL_RUNTIME} ${template_testing_ENABLE_SANITIZER_UNDEFINED}")
    template_testing_enable_hardening(template_testing_options ON ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()
endmacro()

macro(template_testing_local_options)
  if(PROJECT_IS_TOP_LEVEL)
    include(cmake/StandardProjectSettings.cmake)
  endif()

  add_library(template_testing_warnings INTERFACE)
  add_library(template_testing_options INTERFACE)

  include(cmake/CompilerWarnings.cmake)
  template_testing_set_project_warnings(
    template_testing_warnings
    ${template_testing_WARNINGS_AS_ERRORS}
    ""
    ""
    ""
    "")

  if(template_testing_ENABLE_USER_LINKER)
    include(cmake/Linker.cmake)
    template_testing_configure_linker(template_testing_options)
  endif()

  include(cmake/Sanitizers.cmake)
  template_testing_enable_sanitizers(
    template_testing_options
    ${template_testing_ENABLE_SANITIZER_ADDRESS}
    ${template_testing_ENABLE_SANITIZER_LEAK}
    ${template_testing_ENABLE_SANITIZER_UNDEFINED}
    ${template_testing_ENABLE_SANITIZER_THREAD}
    ${template_testing_ENABLE_SANITIZER_MEMORY})

  set_target_properties(template_testing_options PROPERTIES UNITY_BUILD ${template_testing_ENABLE_UNITY_BUILD})

  if(template_testing_ENABLE_PCH)
    target_precompile_headers(
      template_testing_options
      INTERFACE
      <vector>
      <string>
      <utility>)
  endif()

  if(template_testing_ENABLE_CACHE)
    include(cmake/Cache.cmake)
    template_testing_enable_cache()
  endif()

  include(cmake/StaticAnalyzers.cmake)
  if(template_testing_ENABLE_CLANG_TIDY)
    template_testing_enable_clang_tidy(template_testing_options ${template_testing_WARNINGS_AS_ERRORS})
  endif()

  if(template_testing_ENABLE_CPPCHECK)
    template_testing_enable_cppcheck(${template_testing_WARNINGS_AS_ERRORS} "" # override cppcheck options
    )
  endif()

  if(template_testing_ENABLE_COVERAGE)
    include(cmake/Tests.cmake)
    template_testing_enable_coverage(template_testing_options)
  endif()

  if(template_testing_WARNINGS_AS_ERRORS)
    check_cxx_compiler_flag("-Wl,--fatal-warnings" LINKER_FATAL_WARNINGS)
    if(LINKER_FATAL_WARNINGS)
      # This is not working consistently, so disabling for now
      # target_link_options(template_testing_options INTERFACE -Wl,--fatal-warnings)
    endif()
  endif()

  if(template_testing_ENABLE_HARDENING AND NOT template_testing_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR template_testing_ENABLE_SANITIZER_UNDEFINED
       OR template_testing_ENABLE_SANITIZER_ADDRESS
       OR template_testing_ENABLE_SANITIZER_THREAD
       OR template_testing_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    template_testing_enable_hardening(template_testing_options OFF ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()

endmacro()
