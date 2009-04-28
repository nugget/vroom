#!/usr/local/bin/tclsh8.4

set ::debug 0

package require Pgtcl 
package require Tclx
package require csv

source functions.tcl

proc main {} {
	global env

	source vroom.cfg

	global dbh
	set dbh [pg_connect -connlist [array get ::DB]]

	set vehicle_id NULL

	set data [read_file "rt.mail"]

	# First we need to pull out vehicle information (naturally at the bottom)
	set live 0
	foreach line [split $data "\n"] {
		if {$line == "VEHICLE"} {
			set live 1
			set vehicle 0
			set vbuf ""
		}
		if {[string match "---- End Copy and Paste ----" $line]} {
			set live 0
		}
		if {$live == 1} {
			# puts $line
			if {[string range $line 0 0] == "\""} {
				if {$line == "\""} {
					set vehicle 0
					append vbuf $line
					# set vbuf [string map {"\n" "\\n"} $vbuf]

					set vals [::csv::split $vbuf]
					set vehicle_id [add_vehicle [lindex $vals 0] [lindex $vals 1] [lindex $vals 2] [lindex $vals 3]]

				} else {
					set vehicle 1
				}
			}
			if {$vehicle == 1} {
				append vbuf "$line\n"
			}

		}
	}

	puts "Importing data for vehicle id $vehicle_id"

	# Now we can pull in our other data for the vehicles
	set live 0
	foreach line [split $data "\n"] {
		if {$line == "ROAD TRIP CSV"} {
			set live 1
			set section VERSIONS
		}
		if {[string match "---- End Copy and Paste ----" $line]} {
			set live 0
		}

		if {$live} {
			switch $section {
				VERSIONS {
				}
				FILLUPS {
				}
				SERVICES {
				}
				TRIPS {
				}
				VEHICLES {
				}
			}
		}
	}
}

if !$tcl_interactive main
