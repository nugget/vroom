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
	set partial 0
	set wrap_it_up 0

	foreach line [split $data "\n"] {
		if {$line == "ROAD TRIP CSV"} {
			set live 1
			set wbuf ""
			set section VERSIONS
			set partial 0
		}
		if {[string match "---- End Copy and Paste ----" $line]} {
			set live 0
		}


		if {$live} {
			switch $section {
				FILLUPS {
					puts $line
					if {![regexp {Trip Distance|Total Price|MPG,Note|FUEL RECORDS|MAINTENANCE RECORDS} $line] && $line != ""} {
						puts "  Looking at this line"
						if {$line == ""} {
							append wbuf "\n"
						} else {
							append wbuf "$line"
						}

						if {!$partial} {
							set partial [is_line_incomplete $line]
							puts "  Not in a partial buf, this line is $partial partiality"
							if {!$partial} {
								puts "  Stands alone, let's wrap it up"
								set wrap_it_up 1
							}
						} else {
							puts "  Building a buf from multiple lines"
							if {[is_line_incomplete $line]} {
								puts "  I think this is the last line in the block"
								set wrap_it_up 1
							}
						}
						if {$wrap_it_up} {
							# Clean out any double spaces
							set wbuf [string map {"  " " "} $wbuf]

							# Two partials make a whole!
							puts "--\n$wbuf\n--"

							unset -nocomplain data
							lassign [::csv::split $wbuf] data(odometer) data(trip_odometer) data(fillup_date) data(fill_amount) data(fill_units) data(unit_price) data(total_price) data(partial_fill) data(mpg) data(note) data(octane) data(location) data(payment) data(conditions) data(reset) data(categories) data(flags)

							# add_fillup $vehicle_id [array get data]

							set partial 0
							set wbuf ""
							set wrap_it_up 0
						}
					}
				}
			}
		}
		if {$line == "FUEL RECORDS"} {
			set section FILLUPS
			set wbuf ""
			set partial 0
		}
		if {$line == "MAINTENANCE RECORDS"} {
			set section FIXES
			set wbuf ""
			set partial 0
		}
	}
}

if !$tcl_interactive main
