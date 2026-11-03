cmake_minimum_required(VERSION 3.15)

find_package(bouffalo_sdk REQUIRED HINTS $ENV{BL_SDK_BASE})

sdk_add_include_directories(.)

# The SDK profile supplies the BL616 linker layout and drivers, but its board.c
# assumes a 40 MHz crystal and drives GPIO21/22 as a debug console. NEO 31005
# has a 26 MHz crystal; those GPIOs belong to other board functions.
set(neo_bsp "${BL_SDK_BASE}/bsp/board/bl616dk")
file(READ "${neo_bsp}/board.c" neo_board)
if(NOT neo_board MATCHES "GLB_XTAL_40M")
    message(FATAL_ERROR "Unsupported SDK BSP: review NEO crystal adaptation")
endif()
string(REPLACE "GLB_XTAL_40M" "GLB_XTAL_26M" neo_board "${neo_board}")
string(REPLACE "static void console_init()" "static void __attribute__((unused)) console_init()" neo_board "${neo_board}")
string(REPLACE "    console_init();" "    /* NEO: no UART0 console pinmux. */" neo_board "${neo_board}")
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/neo_board.c" "${neo_board}")

file(READ "${neo_bsp}/fw_header.c" neo_header)
if(NOT neo_header MATCHES "xtal_type = 0x07")
    message(FATAL_ERROR "Unsupported SDK firmware header: review crystal type")
endif()
string(REPLACE "xtal_type = 0x07" "xtal_type = 0x05" neo_header "${neo_header}")
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/neo_fw_header.c" "${neo_header}")

# Replace the two SDK translation units, without modifying the installed SDK.
get_target_property(neo_sources app SOURCES)
list(REMOVE_ITEM neo_sources "${neo_bsp}/board.c" "${neo_bsp}/fw_header.c")
set_property(TARGET app PROPERTY SOURCES "${neo_sources}")
target_sources(app PRIVATE
    "${CMAKE_CURRENT_BINARY_DIR}/neo_board.c"
    "${CMAKE_CURRENT_BINARY_DIR}/neo_fw_header.c"
)

sdk_set_main_file(main.c)
sdk_add_link_options(-Wl,--wrap=wl_init)
project(xinxian_ble_diagnostic)

