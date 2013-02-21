#!/usr/local/bin/tclsh8.6

set ::debug 0

package require Pgtcl
package require Tclx
package require csv
package require vroom

proc csv_quote {buf} {
	if {$buf == ""} {
		return ""
	}

	set buf [string map {{"} {""}} $buf]
	return "\"$buf\""
}

proc euro_date {buf} {
	regexp {(\d\d\d\d)-(\d\d)-(\d\d)} $buf _ year month day

	return "$day.$month.$year"
}

proc euro_num {buf} {
	set buf [string map {{,} {}} $buf]
	set buf [string map {{.} {,}} $buf]
	return $buf
}

proc gal_to_l {gallons} {
	set liters [expr $gallons * 3.78541178]

	return $liters
}

proc sprit_fillups {vehicle_id} {
	global vroomdb

	set outbuf ""

	append outbuf "Date;Odometer;Trip-Odom.;Quanitity;Price;Currency;Type;Tires;Routes;Driving-style;Fuel;Note;Consumption\n"

	pg_select $vroomdb "SELECT * FROM fillups WHERE vehicle_id = [sanitize_number $vehicle_id] ORDER BY odometer" buf {
		if {$buf(partial_fill) == "f"} {
			set pf ""
		} else {
			set pf "Partial"
		}

		if {$buf(reset) == "f"} {
			set reset ""
		} else {
			set reset "Reset"
		}

		append outbuf "[euro_date $buf(fillup_date)];"
		append outbuf "[euro_num $buf(odometer)];"
		append outbuf "[euro_num $buf(trip_odometer)];"
		append outbuf "[euro_num [gal_to_l $buf(fill_amount)]];"
		append outbuf "[euro_num $buf(total_price)];"
		append outbuf "\"USD\";1;1;14;2;7;"
		append outbuf "[csv_quote $buf(conditions)];"
		append outbuf "[euro_num $buf(mpg)]"
		append outbuf "\n"
	}
	append outbuf "\n"

	return $outbuf
}

proc sprit_out {vehicle_id} {
	puts [sprit_fillups $vehicle_id]
}


proc main {} {
	global env

	::vroom::init

	set vehicle_id 1

	sprit_out $vehicle_id

}

if !$tcl_interactive main
