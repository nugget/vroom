#!/usr/local/bin/tclsh8.5

set ::debug 0

package require Pgtcl
package require Tclx
package require csv
package require vroom

proc date_expand {date} {
	if {[regexp {(\d\d\d\d)/(\d+)/(\d+)} $date _ yyyy mm dd]} {
		return $date
	} else {
		return $date
	}
}

proc process_wbuf {section wbuf} {
	set id NULL

	global vehicle_id
	global records

	if {[regexp "^\$|$section|,Note,|,Start Date,|,Odometer," $wbuf]} {
		return
	}

	switch $section {
		"ROAD TRIP CSV" {
			# Ignoring version info for now
		}

		"FUEL RECORDS" {
			lassign [::csv::split $wbuf] data(odometer) data(trip_odometer) data(fillup_date) data(fill_amount) data(fill_units) data(unit_price) data(total_price) data(partial_fill) data(mpg) data(note) data(octane) data(location) data(payment) data(conditions) data(reset) data(categories) data(flags) data(currency_code) data(currency_rate)
			set data(vehicle_id) $vehicle_id

			set id [add_fillup [array get data]]
			incr records(fillups)
		}

		"MAINTENANCE RECORDS" {
			lassign [::csv::split $wbuf] data(name) data(service_date) data(odometer) data(cost) data(note) data(location) data(type) data(subtype) data(payment) data(categories) data(reminder_interval) data(reminder_distance) data(flags) data(currency_code) data(currency_rate)
			set data(vehicle_id) $vehicle_id
			set id [add_expense [array get data]]
			incr records(expenses)
		}

		"ROAD TRIPS" {
			lassign [::csv::split $wbuf] data(name) data(start_date) data(start_odometer) data(end_date) data(end_odometer) data(note) data(distance)
			set data(vehicle_id) $vehicle_id
			set id [add_trip [array get data]]
			incr records(trips)
		}

		"VEHICLE" {
			lassign [::csv::split $wbuf] data(name) data(odometer) data(units_odometer) data(units_economy) data(notes) data(tank_capacity) data(tank_units) data(home_currency)
			set id [add_vehicle [array get data]]
		}

		"TIRE LOG" {
			# puts "Ignoring tire log"
		}

		default {
			puts "wbuf $wbuf in unrecognized section $section"
		}

	}

	return $id
}

proc main {} {
	global env
	global vroomdb
	global records

	set records(fillups)  0
	set records(expenses) 0
	set records(trips)    0

	puts "Importing a Road Trip backup file ( http://darrensoft.ca/roadtrip/ )\n"

	::vroom::init

	global vehicle_id
	set vehicle_id NULL

	set data [read_file "/tmp/rt.mail"]

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
				if {[regexp {^",} $line]} {
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
		if {[string match "---- Begin Copy and Paste here" $line]} {
			set live 1
		}
		if {[regexp {^(ROAD TRIP CSV|FUEL RECORDS|MAINTENANCE RECORDS|ROAD TRIPS|VEHICLE|TIRE LOG)$} $line]} {
			set wbuf ""
			set section $line
		}
		if {[string match "---- End Copy and Paste ----" $line]} {
			set live 0
		}

		if {$live} {
			if {[regexp {[^ ]$} $line]} {
				regsub { $} $wbuf "" wbuf
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

	parray records
}

if !$tcl_interactive main
