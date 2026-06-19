set_global_assignment -entity "pll_5" -library "lib_pll_5" -name IP_TOOL_NAME "altera_pll"
set_global_assignment -entity "pll_5" -library "lib_pll_5" -name IP_TOOL_VERSION "25.1"
set_global_assignment -entity "pll_5" -library "lib_pll_5" -name IP_TOOL_ENV "mwpim"
set_global_assignment -library "lib_pll_5" -name SPD_FILE [file join $::quartus(sip_path) "pll_5.spd"]

set_global_assignment -library "lib_pll_5" -name MISC_FILE [file join $::quartus(sip_path) "pll_5_sim/pll_5.vo"]
