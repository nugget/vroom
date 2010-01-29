proc comma {num {sep ,}} {
	while {[regsub {^([-+]?\d+)(\d\d\d)} $num "\\1$sep\\2" num]} {}
	return $num
}

proc sanitize_number { value } {
        if {![info exists value]} {
                return "NULL"
        } else {
		set value [string map {"," "" " " ""} $value]
                if {[regexp {^[0-9.\+\-]+$} $value]} {
                        return $value
                }
        }
        return "NULL"
}

proc sql_boolean { value } {
	if {$value == ""} {
		return "f"
	} else {
		return "t"
	}
}

proc simplesqlquery {db sql} {
	set result [pg_exec $db $sql]
	set status [pg_result $result -status]

	if {[string match "PGRES_*_OK" $status]} {
		set success 1
	} else {
		set success 0
		puts [pg_result $result -error]
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
	# if there's a trailing space it's a partial line
	if {[regexp { $} $line]} {
		return 1
	} else {
		return 0
	}

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
		puts $sql
		puts [pg_result $result -error]
	}

	pg_result $result -clear
	return $success
}

proc sql_field_list { field_list } {
	set outbuf ""

	if {$field_list == ""} {
		return
	}
	foreach field $field_list {
		append outbuf "$field, "
	}
	regsub {, $} $outbuf "" outbuf

	return $outbuf
}

proc sql_value_list { type field_list hash_data } {

	if {$field_list == ""} {
		return
	}

	array set data $hash_data

	foreach field $field_list {
		if {$type == "numeric"} {
			append outbuf "[sanitize_number $data($field)], "
		} else {
			if {$data($field) == ""} {
				append outbuf "NULL, "
			} else {
				append outbuf "[pg_quote $data($field)], "
			}
		}
	}
	regsub {, $} $outbuf "" outbuf

	return $outbuf
}

proc add_vehicle { hash_data } {
	global vroomdb

	array set data $hash_data

	set fields_varchar [list name units_odometer units_economy notes tank_units home_currency]
	set fields_numeric [list tank_capacity]

	set id [simplesqlquery $vroomdb "SELECT vehicle_id FROM vehicles WHERE name = [pg_quote $data(name)]"]

	if {$id == ""} {
		set sql "INSERT INTO vehicles ([sql_field_list $fields_varchar]) "
		append sql "VALUES ([sql_value_list varchar $fields_varchar [array get data]]);"

		if {[pg_exec_or_exception $vroomdb $sql]} {
			set id [simplesqlquery $vroomdb "SELECT vehicle_id FROM vehicles WHERE name = [pg_quote $data(name)]"]
			puts "Added new vehicle id $id ($data(name))"
		}
	}
	if {$id != ""} {
		return $id
	}

	return 0
}

proc add_fillup { hash_data } {
	global vroomdb

	array set data $hash_data

	set fields_varchar [list fillup_date fill_units partial_fill note octane location payment conditions reset categories currency_code]
	set fields_numeric [list odometer trip_odometer total_price unit_price fill_amount mpg flags vehicle_id currency_rate]

	set data(partial_fill) [sql_boolean $data(partial_fill)]
	set data(reset)        [sql_boolean $data(reset)]

	set id [simplesqlquery $vroomdb "SELECT fillup_id FROM fillups WHERE odometer = [sanitize_number $data(odometer)]"]

	if {$id == ""} {
		set sql "INSERT INTO fillups ([sql_field_list $fields_varchar], [sql_field_list $fields_numeric]) "
		append sql "VALUES ([sql_value_list varchar $fields_varchar [array get data]], [sql_value_list numeric $fields_numeric [array get data]]);"

		if {[pg_exec_or_exception $vroomdb $sql]} {
			set id [simplesqlquery $vroomdb "SELECT fillup_id FROM fillups WHERE odometer = [sanitize_number $data(odometer)]"]
			puts "Added new fillup id $id ($data(fillup_date) $data(note))"
		}
	}
	if {$id != ""} {
		return $id
	}

	return 0
}

proc add_expense { hash_data } {
	global vroomdb

	array set data $hash_data

	set fields_varchar [list name service_date note location type subtype payment categories reminder_interval currency_code]
	set fields_numeric [list odometer cost reminder_distance flags vehicle_id currency_rate]

	set id [simplesqlquery $vroomdb "SELECT expense_id FROM expenses WHERE name = [pg_quote $data(name)] AND odometer = [sanitize_number $data(odometer)]"]

	if {$id == ""} {
		set sql "INSERT INTO expenses ([sql_field_list $fields_varchar], [sql_field_list $fields_numeric]) "
		append sql "VALUES ([sql_value_list varchar $fields_varchar [array get data]], [sql_value_list numeric $fields_numeric [array get data]]);"

		if {[pg_exec_or_exception $vroomdb $sql]} {
			set id [simplesqlquery $vroomdb "SELECT expense_id FROM expenses WHERE name = [pg_quote $data(name)] AND odometer = [sanitize_number $data(odometer)]"]
			puts "Added new expense id $id ($data(name) on $data(service_date))"
		}
	}
	if {$id != ""} {
		return $id
	}

	return 0
}

proc add_trip { hash_data } {
	global vroomdb

	array set data $hash_data

	set fields_varchar [list name start_date end_date note]
	set fields_numeric [list start_odometer end_odometer distance vehicle_id]

	set id [simplesqlquery $vroomdb "SELECT trip_id FROM trips WHERE name = [pg_quote $data(name)] AND start_odometer = [sanitize_number $data(start_odometer)]"]

	if {$id == ""} {
		set sql "INSERT INTO trips ([sql_field_list $fields_varchar], [sql_field_list $fields_numeric]) "
		append sql "VALUES ([sql_value_list varchar $fields_varchar [array get data]], [sql_value_list numeric $fields_numeric [array get data]]);"

		if {[pg_exec_or_exception $vroomdb $sql]} {
			set id [simplesqlquery $vroomdb "SELECT trip_id FROM trips WHERE name = [pg_quote $data(name)] AND start_odometer = [sanitize_number $data(start_odometer)]"]
			puts "Added new trip id $id ($data(name) on $data(start_date))"
		}
	} else {
		set sql "UPDATE trips SET end_date = [pg_quote $data(end_date)], end_odometer = [sanitize_number $data(end_odometer)], note = [pg_quote $data(note)], distance = [sanitize_number $data(distance)]
				 WHERE trip_id = $id AND (end_date != [pg_quote $data(end_date)] OR end_odometer != [sanitize_number $data(end_odometer)] OR note != [pg_quote $data(note)] OR distance != [sanitize_number $data(distance)])"
		if {[pg_exec_or_exception $vroomdb $sql]} {
			puts "Updated existing trip id $id ($data(name) on $data(start_date))"
		}

	}
	if {$id != ""} {
		return $id
	}

	return 0
}

proc csv_quote {buf} {
	if {$buf == ""} {
		return ""
	}

	set buf [string map {{"} {""}} $buf]
	return "\"$buf\""
}

proc csv_version {} {
	global vroomdb

	set outbuf ""

	append outbuf "ROAD TRIP CSV\n"
	append outbuf "Version,Language\n"

	pg_select $vroomdb "SELECT version_id,language FROM versions ORDER BY version_id DESC LIMIT 1" buf {
		append outbuf "$buf(version_id),$buf(language)\n"
	}
	append outbuf "\n"

	return $outbuf
}

proc csv_fillups {vehicle_id} {
	global vroomdb

	set outbuf ""

	append outbuf "FUEL RECORDS\n"
	append outbuf "Odometer (mi.),Trip Distance,Date,Fill Amount,Fill Units,Price per "
	append outbuf "Unit,Total Price,Partial "
	append outbuf "Fill,MPG,Note,Octane,Location,Payment,Conditions,Reset,Categories,Flags\n"

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
	global vroomdb

	set outbuf ""

	append outbuf "MAINTENANCE RECORDS\n"
	append outbuf "Description,Date,Odometer "
	append outbuf "(mi.),Cost,Note,Location,Type,Subtype,Payment,Categories,Reminder "
	append outbuf "Interval,Reminder Distance,Flags\n"

	pg_select $vroomdb "SELECT * FROM expenses WHERE vehicle_id = [sanitize_number $vehicle_id] ORDER BY service_date" buf {
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
	global vroomdb

	set outbuf ""

	append outbuf "ROAD TRIPS\n"
	append outbuf "Name,Start Date,Start Odometer (mi.),End Date,End Odometer,Note,Distance\n"

	pg_select $vroomdb "SELECT * FROM trips WHERE vehicle_id = [sanitize_number $vehicle_id] ORDER BY start_date" buf {
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
	global vroomdb

	set outbuf ""

	append outbuf "VEHICLE\n"
	append outbuf "Name,Odometer,Units,Notes\n"

	pg_select $vroomdb "SELECT * FROM vehicles WHERE vehicle_id = [sanitize_number $vehicle_id]" buf {
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

package provide vroom 1.0

