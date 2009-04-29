proc comma {num {sep ,}} {
	while {[regsub {^([-+]?\d+)(\d\d\d)} $num "\\1$sep\\2" num]} {}
	return $num
}

proc sanitize_number { value } {
        if {![info exists value]} {
                return "NULL"
        } else {
		set value [string map {"," ""} $value]
                if {[regexp {^[0-9.\+\-]+$} $value]} {
                        return $value
                }
        }
        return "NULL"
}

proc simplesqlquery {db sql} {
	set result [pg_exec $db $sql]
	set status [pg_result $result -status]

	if {[string match "PGRES_*_OK" $status]} {
		set success 1
	} else {
		set success 0
		puts stderr [pg_result $result -error]
	}
	
	if {$success && [pg_result $result -numTuples] > 0} {
		set return [pg_result $result -getTuple 0]
	} else {
		set return ""
	}

	pg_result $result -clear
	return $return
}


proc is_line_incomplete {line} {
	# If line ends with a comma, it's incomplete
	if {[regexp {, ?$} $line]} {
		return 1
	}

	set trimmed [regsub -all {[^\"]} $line ""]
	set quotes [string length $trimmed]

	if {$quotes == 0} {
		return 0
	}
	return [expr $quotes % 2]
}


proc pg_exec_or_exception {db sql} {
	set result [pg_exec $db $sql]
	set status [pg_result $result -status]

	if {[string match "PGRES_*_OK" $status]} {
		set success 1
	} else {
		set success 0
		puts stderr [pg_result $result -error]
	}

	pg_result $result -clear
	return $success
}

proc add_vehicle { name units_odometer units_economy notes } {
	global dbh

	set vehicle_id [simplesqlquery $dbh "SELECT vehicle_id FROM vehicles WHERE name = [pg_quote $name]"]
	if {$vehicle_id == ""} {
		pg_exec_or_exception $dbh "INSERT INTO vehicles (name,units_odometer,units_economy,notes) VALUES ([pg_quote $name],[pg_quote $units_odometer],[pg_quote $units_economy],[pg_quote $notes])"
		set vehicle_id [simplesqlquery $dbh "SELECT vehicle_id FROM vehicles WHERE name = [pg_quote $name]"]
		puts "Added new vehicle id $vehicle_id ($name) to database"
	}
	if {$vehicle_id != ""} {
		return $vehicle_id
	}
	return -1
}

proc add_fillup { vehicle_id hash_data } {
	global dbh

	array set data $hash_data

	set fields_varchar [list fillup_date fill_units partial_fill note octane location payment conditions reset categories]
	set fields_numeric [list odometer trip_odometer total_price unit_price fill_amount mpg flags]

	if {$data(partial_fill) == ""} {
		set data(partial_fill) "t"
	} else {
		set data(partial_fill) "f"
	}

	set fillup_id [simplesqlquery $dbh "SELECT fillup_id FROM fillups WHERE odometer = [sanitize_number $data(odometer)]"]
		parray data

	if {$fillup_id == ""} {
		parray data
		set sql "INSERT INTO fillups ("
		foreach field $fields_varchar {
			append sql "$field, "
		}
		foreach field $fields_numeric {
			append sql "$field, "
		}
		append sql "vehicle_id) VALUES ("
		foreach field $fields_varchar {
			puts "$field -> $data($field) "
			append sql "[pg_quote $data($field)], "
		}
		foreach field $fields_numeric {
			append sql "[sanitize_number $data($field)], "
		}
		append sql "$vehicle_id);"

		puts $sql


		if {[pg_exec_or_exception $dbh $sql]} {
			set fillup_id [simplesqlquery $dbh "SELECT fillup_id FROM fillups WHERE odometer = [sanitize_number $data(odometer)]"]
			puts "Added new fillup id $fillup_id ($data(fillup_date) $data(note))"
		} 
	}
	if {$fillup_id != ""} {
		return $fillup_id
	}

	return -1
}

proc csv_quote {buf} {
	if {$buf == ""} {
		return ""
	}

	set buf [string map {{"} {""}} $buf]
	return "\"$buf\""
}

proc csv_version {} {
	global dbh

	set outbuf ""

	append outbuf "ROAD TRIP CSV\n"
	append outbuf "Version,Language\n"

	pg_select $dbh "SELECT version_id,language FROM versions ORDER BY version_id DESC LIMIT 1" buf {
		append outbuf "$buf(version_id),$buf(language)\n"
	}
	append outbuf "\n"

	return $outbuf
}

proc csv_fillups {vehicle_id} {
	global dbh

	set outbuf ""

	append outbuf "FUEL RECORDS\n"
	append outbuf "Odometer (mi.),Trip Distance,Date,Fill Amount,Fill Units,Price per "
	append outbuf "Unit,Total Price,Partial "
	append outbuf "Fill,MPG,Note,Octane,Location,Payment,Conditions,Reset,Categories,Flags\n"

	pg_select $dbh "SELECT * FROM fillups WHERE vehicle_id = [sanitize_number $vehicle_id] ORDER BY odometer" buf {
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

		append outbuf "$buf(odometer),"
		append outbuf "$buf(trip_odometer),"
		append outbuf "[csv_quote $buf(fillup_date)],"
		append outbuf "$buf(fill_amount),"
		append outbuf "$buf(fill_units),"
		append outbuf "$buf(unit_price),"
		append outbuf "$buf(total_price),"
		append outbuf "$pf,"
		append outbuf "$buf(mpg),"
		append outbuf "[csv_quote $buf(note)],"
		append outbuf "[csv_quote $buf(octane)],"
		append outbuf "[csv_quote $buf(location)],"
		append outbuf "[csv_quote $buf(payment)],"
		append outbuf "[csv_quote $buf(conditions)],"
		append outbuf "$reset,"
		append outbuf "[csv_quote $buf(categories)],"
		append outbuf "$buf(flags)"
		append outbuf "\n"
	}
	append outbuf "\n"

	return $outbuf
}

proc csv_expenses {vehicle_id} {
	global dbh

	set outbuf ""

	append outbuf "MAINTENANCE RECORDS\n"
	append outbuf "Description,Date,Odometer "
	append outbuf "(mi.),Cost,Note,Location,Type,Subtype,Payment,Categories,Reminder "
	append outbuf "Interval,Reminder Distance,Flags\n"

	pg_select $dbh "SELECT * FROM expenses WHERE vehicle_id = [sanitize_number $vehicle_id] ORDER BY service_date" buf {
		append outbuf "[csv_quote $buf(name)],"
		append outbuf "[csv_quote $buf(service_date)],"
		append outbuf "$buf(odometer),"
		append outbuf "$buf(cost),"
		append outbuf "[csv_quote $buf(note)],"
		append outbuf "[csv_quote $buf(location)],"
		append outbuf "[csv_quote $buf(type)],"
		append outbuf "[csv_quote $buf(subtype)],"
		append outbuf "[csv_quote $buf(payment)],"
		append outbuf "[csv_quote $buf(categories)],"
		append outbuf "[csv_quote $buf(reminder_interval)],"
		append outbuf "$buf(reminder_distance),"
		append outbuf "$buf(flags)"
		append outbuf "\n"
	}
	append outbuf "\n"

	return $outbuf
}

proc csv_trips {vehicle_id} {
	global dbh

	set outbuf ""

	append outbuf "ROAD TRIPS\n"
	append outbuf "Name,Start Date,Start Odometer (mi.),End Date,End Odometer,Note,Distance\n"

	pg_select $dbh "SELECT * FROM trips WHERE vehicle_id = [sanitize_number $vehicle_id] ORDER BY start_date" buf {
		append outbuf "[csv_quote $buf(name)],"
		append outbuf "[csv_quote $buf(start_date)],"
		append outbuf "$buf(start_odometer),"
		append outbuf "[csv_quote $buf(end_date)],"
		append outbuf "$buf(end_odometer),"
		append outbuf "[csv_quote $buf(note)],"
		append outbuf "$buf(distance)"
		append outbuf "\n"
	}
	append outbuf "\n"

	return $outbuf
}

proc csv_vehicle {vehicle_id} {
	global dbh

	set outbuf ""

	append outbuf "VEHICLE\n"
	append outbuf "Name,Odometer,Units,Notes\n"

	pg_select $dbh "SELECT * FROM vehicles WHERE vehicle_id = [sanitize_number $vehicle_id]" buf {
		append outbuf "[csv_quote $buf(name)],"
		append outbuf "[csv_quote $buf(units_odometer)],"
		append outbuf "[csv_quote $buf(units_economy)],"
		append outbuf "[csv_quote $buf(notes)]"
		append outbuf "\n"
	}
	append outbuf "\n"

	return $outbuf
}

proc csv_out {vehicle_id} {
	puts [csv_version]
	puts [csv_fillups $vehicle_id]
	puts [csv_expenses $vehicle_id]
	puts [csv_trips $vehicle_id]
	puts [csv_vehicle $vehicle_id]

}
