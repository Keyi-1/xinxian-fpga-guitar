set project_dir [file dirname [file normalize [info script]]]
set project_file [file join $project_dir neo_guitar_touch_game.gprj]
open_project $project_file
run all
