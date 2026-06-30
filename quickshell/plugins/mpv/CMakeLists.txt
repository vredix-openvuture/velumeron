cmake_minimum_required(VERSION 3.21)
project(VelumeronMpv LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 REQUIRED COMPONENTS Quick Gui OpenGL)
qt_standard_project_setup(REQUIRES 6.5)

find_package(PkgConfig REQUIRED)
pkg_check_modules(MPV REQUIRED IMPORTED_TARGET mpv)

# Emit the compiled QML module to <repo>/quickshell/plugins/Velumeron/Mpv so that
# `import Velumeron.Mpv` resolves when QML_IMPORT_PATH includes <repo>/quickshell/plugins.
qt_add_qml_module(velumeronmpv
    URI Velumeron.Mpv
    VERSION 1.0
    PLUGIN_TARGET velumeronmpvplugin
    OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/../Velumeron/Mpv"
    SOURCES
        MpvVideo.h
        MpvVideo.cpp
)

target_link_libraries(velumeronmpv PRIVATE Qt6::Quick Qt6::Gui Qt6::OpenGL PkgConfig::MPV)

# qt_add_qml_module emits TWO artifacts: the loadable plugin (velumeronmpvplugin) and its backing
# library (velumeronmpv), and the plugin links against the backing lib. OUTPUT_DIRECTORY above only
# relocates the plugin + qmldir/typeinfo into Velumeron/Mpv; the backing lib otherwise stays in the
# build tree. Once that build tree is cleaned, loading the plugin fails with
#   "libvelumeronmpv.so: cannot open shared object file"
# and live wallpapers fall back to a black surface. Fix: emit the backing lib next to the plugin and
# give the plugin an $ORIGIN rpath so it resolves libvelumeronmpv.so from its own folder.
set(_qml_out "${CMAKE_CURRENT_SOURCE_DIR}/../Velumeron/Mpv")
set_target_properties(velumeronmpv PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY "${_qml_out}")
set_target_properties(velumeronmpvplugin PROPERTIES
    BUILD_WITH_INSTALL_RPATH ON
    INSTALL_RPATH "$ORIGIN")
