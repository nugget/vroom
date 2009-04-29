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

	set fields_varchar [list fillup_date fill_units unit_price total_price partial_fill note octane location payment conditions reset categories]
	set fields_numeric [list odometer trip_odometer fill_amount mpg flags]

	if {$data(partial_fill) == ""} {
		set data(partial_fill) "t"
	} else {
		set data(partial_fill) "f"
	}

	set fillup_id [simplesqlquery $dbh "SELECT fillup_id FROM fillups WHERE odometer = [sanitize_number $data(odometer)]"]
	if {$fillup_id == ""} {
		set sql "INSERT INTO fillups ("
		foreach field $fields_varchar {
			append sql "$field, "
		}
		foreach field $fields_numeric {
			append sql "$field, "
		}
		append sql "vehicle_id) VALUES ("
		foreach field $fields_varchar {
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

proc csv_version {} {
	global dbh

	set outbuf ""

	append outbuf "ROAD TRIP CSV"
	append outbuf "Version,Language"

	pg_select $dbh "SELECT version_id,language FROM versions ORDER BY version_id DESC LIMIT 1" buf {
		append outbuf "$buf(version_id),$buf(language)"
	}
	append outbuf ""

	return $outbuf
}

proc csv_fillups {vehicle_id} {
	global dbh

	set outbuf ""

	append outbuf "FUEL RECORDS\n"
	append outbuf "Odometer (mi.),Trip Distance,Date,Fill Amount,Fill Units,Price per\n"
	append outbuf "Unit,Total Price,Partial\n"
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

		append outbuf [::csv::join [list $buf(odometer) $buf(trip_odometer) $buf(fillup_date) $buf(fill_amount) $buf(fill_units) $buf(unit_price) $buf(total_price) $pf $buf(mpg) $buf(note) $buf(octane) $buf(location) $buf(payment) $buf(conditions) $reset $buf(flags)]]
		append outbuf "\n"
	}
	append outbuf "\n"

	return $outbuf
}

proc csv_expenses {vehicle_id} {
	global dbh

	set outbuf ""

	append outbuf "MAINTENANCE RECORDS"
	append outbuf "Description,Date,Odometer"
	append outbuf "(mi.),Cost,Note,Location,Type,Subtype,Payment,Categories,Reminder"
	append outbuf "Interval,Reminder Distance,Flags"

	pg_select $dbh "SELECT * FROM expenses WHERE vehicle_id = [sanitize_number $vehicle_id] ORDER BY service_date" buf {
		append outbuf [::csv::join $buf(name) $buf(service_date) $buf(odometer) $buf(cost) $buf(note) $buf(location) $buf(type) $buf(subtype) $buf(payment) $buf(categories) $buf(reminder_interval) $buf(reminder_distance) $buf(flags)]
	}
	append outbuf ""

	return $outbuf
}


proc csv_out {vehicle_id} {
	puts [csv_version]
	puts [csv_fillups $vehicle_id]
	puts [csv_expenses $vehicle_id]

}
