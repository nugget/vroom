#!/usr/local/bin/tclsh8.4

set ::debug 0

package require Pgtcl 
package require Tclx
package require csv

source functions.tcl

proc process_wbuf {section wbuf} {
	set id NULL

	global vehicle_id

	if {[regexp "^\$|$section|,Note,|,Start Date,|,Odometer," $wbuf]} {
		return
	}

	switch $section {
		"ROAD TRIP CSV" {
			# Ignoring version info for now
		}

		"FUEL RECORDS" {
			lassign [::csv::split $wbuf] data(odometer) data(trip_odometer) data(fillup_date) data(fill_amount) data(fill_units) data(unit_price) data(total_price) data(partial_fill) data(mpg) data(note) data(octane) data(location) data(payment) data(conditions) data(reset) data(categories) data(flags)
			set data(vehicle_id) $vehicle_id

			set id [add_fillup [array get data]]
		}

		"MAINTENANCE RECORDS" {
			lassign [::csv::split $wbuf] data(name) data(service_date) data(odometer) data(cost) data(note) data(location) data(type) data(subtype) data(payment) data(categories) data(reminder_interval) data(reminder_distance) data(flags)
			set data(vehicle_id) $vehicle_id
			# set id [add_expense [array get data]]
		}

		"ROAD TRIPS" {
			lassign [::csv::split $wbuf] data(name) data(start_date) data(start_odometer) data(end_date) data(end_odometer) data(note) data(distance)
			set data(vehicle_id) $vehicle_id
			# set id [add_trip [array get data]]
		}

		"VEHICLE" {
			lassign [::csv::split $wbuf] data(name) data(odometer) data(units_odometer) data(units_economy) data(notes)
			set id [add_vehicle [array get data]]
		}

		default {
			puts stderr "wbuf $wbuf in unrecognized section $section"
		}

	}

	return $id
}

proc main {} {
	global env

	source vroom.cfg

	global dbh
	set dbh [pg_connect -connlist [array get ::DB]]

	global vehicle_id
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
			if {[string range $line 0 0] == "\""} {
				if {$line == "\""} {
					set vehicle 0
					append vbuf $line

					set vehicle_id [process_wbuf VEHICLE $vbuf]
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

	set wbuf ""

	foreach line [split $data "\n"] {
		if {[regexp {^(ROAD TRIP CSV|FUEL RECORDS|MAINTENANCE RECORDS|ROAD TRIPS|VEHICLE)$} $line]} {
			set live 1
			set wbuf ""
			set section $line
		}
		if {[string match "---- End Copy and Paste ----" $line]} {
			set live 0
		}

		if {$live} {
			if {[regexp {[^ ]$} $line]} {
				append wbuf $line
				if {[::csv::iscomplete $wbuf]} {
					# We've got a valid CSV working buffer to deal with

					unset -nocomplain data

					process_wbuf $section $wbuf

					set wbuf ""
				} else {
					# We're in the middle of a quoted block, the CRLF was part of our string
					append wbuf "\n"
				}
			} else {
				regsub { $} $wbuf "" wbuf
				append wbuf $line
			}
		}

	}
}

if !$tcl_interactive main
