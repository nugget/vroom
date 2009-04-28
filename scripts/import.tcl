#!/usr/local/bin/tclsh8.4

set ::debug 0

package require Pgtcl 
package require Tclx
source functions.tcl

proc main {} {
	global env

	source vroom.cfg

	global dbh
	set dbh [pg_connect -connlist [array get ::DB]]

	set data [read_file "rt.mail"]
	set live 0
	foreach line [split $data "\n"] {
		if {$line == "ROAD TRIP CSV"} {
			set live 1
		}
		if {[string match "---- End Copy and Paste ----" $line]} {
			set live 0
		}

		if {$live} {
			puts $line
		}
	}
}

if !$tcl_interactive main
