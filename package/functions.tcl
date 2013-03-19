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
	if {[string is false -strict $value]} {
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

proc update_if_changed {db table key id data_hash} {
	set changed 0
	array set new_data $data_hash

	set ignore_fields {reset}

	set sql "UPDATE $table SET "
	pg_select $db "SELECT * FROM $table WHERE $key = $id" old_data {
		foreach field [array names new_data] {
			if {$field != "rowtype" && [lsearch -exact $ignore_fields $field] == -1} {
				if {[regexp {_date$} $field] && $new_data($field) != ""} {
					set new_data($field) [simplesqlquery $db "SELECT [pg_quote $new_data($field)]::date"]
				}
				if {[info exists old_data($field)]} {
					if {$new_data($field) != $old_data($field)} {
						set changed 1
						append sql "$field = [pg_quote $new_data($field)], "
					}
				}
			}
		}
	}
	if {$changed} {
		set sql [regsub {, $} $sql ""]
		append sql " WHERE $key = $id;"

		puts $sql
		pg_exec_or_exception $db $sql
	}

	return $changed
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
		if {![info exists data($field)]} {
			append outbuf "NULL, "
		} elseif {$type == "numeric"} {
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

proc lookup_by_uuid_with_fallback {idfield tablename uuidVar where} {
	upvar 1 $uuidVar uuid

	set id ""
	if {[info exists uuid] && $uuid ne ""} {
		#
		# Try to find our trip from the uuid if we can
		#
		set id [simplesqlquery $::vroomdb "SELECT $idfield FROM $tablename WHERE uuid = [pg_quote $uuid]"]
	}
	if {![info exists id] || $id == ""} {
		#
		# uuid lookup failed, try the fallback where clause
		#
		set id [simplesqlquery $::vroomdb "SELECT $idfield FROM $tablename WHERE $where"]
	}

	return $id
}

proc add_vehicle { hash_data } {
	global vroomdb

	array set data $hash_data

	set fields_varchar [list name units_odometer units_economy notes tank_units home_currency uuid]
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

proc old_add_fillup {hash_data} {
	array set data $hash_data

	set diff_varchar [list ]
	set diff_numeric [list lat lon]

	set fields_varchar [list fillup_date fill_units partial_fill note octane location payment conditions reset categories currency_code]
	set fields_numeric [list odometer trip_odometer total_price unit_price fill_amount mpg flags vehicle_id currency_rate lat lon]

	if {![info exists data(flags)]} {
		set data(flags) 0
	}

	if {[info exists data(filled)]} {
		if {$data(filled) == 1} {
			set data(partial_fill) 0
		} else {
			set data(partial_fill) 1
		}
	}

	set data(partial_fill) [sql_boolean $data(partial_fill)]
	set data(reset)        [sql_boolean $data(reset)]

	unset -nocomplain oldrow
	pg_select $::vroomdb "SELECT * FROM fillups WHERE vehicle_id = [sanitize_number $data(vehicle_id)] AND odometer = [sanitize_number $data(odometer)]" buf {
		array set oldrow [array get buf]
	}

	if {[info exists oldrow(fillup_id)]} {
		unset -nocomplain changes
		foreach f $diff_numeric {
			if {$oldrow($f) ne ""} {
				set oldrow($f) [format "%f" $oldrow($f)]
			}
			if {$data($f) ne ""} {
				set data($f) [format "%f" $data($f)]
			}
			if {$oldrow($f) ne $data($f)} {
				# puts "$f $oldrow($f) -> $data($f)"
				lappend changes "$f = [sanitize_number $data($f)]"
			}
		}
		foreach f $diff_varchar {
			if {$oldrow($f) ne $data($f)} {
				puts "$f $oldrow($f) -> $data($f)"
				lappend changes "$f = [pg_quote $data($f)]"
			}
		}
		if {[info exists changes]} {
			set sql "UPDATE fillups SET [join $changes ", "] WHERE fillup_id = $oldrow(fillup_id)"

			if {[pg_exec_or_exception $::vroomdb $sql]} {
				puts "Updated fillup $oldrow(fillup_id): [join $changes ", "]"
			}
		}
	} else {
		set sql "INSERT INTO fillups ([sql_field_list $fields_varchar], [sql_field_list $fields_numeric]) "
		append sql " SELECT [sql_value_list varchar $fields_varchar [array get data]], [sql_value_list numeric $fields_numeric [array get data]] RETURNING fillup_id"

		pg_select $::vroomdb $sql ins {
			puts "Added new fillup id $ins(fillup_id) ($data(fillup_date) $data(note))"
		}
	}

	if {[info exists ins(fillup_id)]} {
		return $ins(fillup_id)
	}

	return 0
}

proc add_fillup { hash_data } {
	array set data $hash_data

	set fields_varchar [list fillup_date fill_units partial_fill note octane location payment conditions reset categories currency_code uuid]
	set fields_numeric [list odometer trip_odometer total_price unit_price fill_amount mpg flags vehicle_id currency_rate lat lon]

	if {![info exists data(flags)]} {
		set data(flags) 0
	}

	if {[info exists data(filled)]} {
		if {$data(filled) == 1} {
			set data(partial_fill) f
		} else {
			set data(partial_fill) t
		}
	}

	set data(partial_fill) [sql_boolean $data(partial_fill)]
	set data(reset)        [sql_boolean $data(reset)]

	set id [lookup_by_uuid_with_fallback fillup_id fillups data(uuid) "vehicle_id = [sanitize_number $data(vehicle_id)] AND odometer = [sanitize_number $data(odometer)]"]

	if {$id == ""} {
		if {![info exists data(total_price)]} {
			set data(total_price) [format "%.02f" [expr $data(unit_price) * $data(fill_amount)]]
		}
		set sql "INSERT INTO fillups ([sql_field_list $fields_varchar], [sql_field_list $fields_numeric]) "
		append sql "VALUES ([sql_value_list varchar $fields_varchar [array get data]], [sql_value_list numeric $fields_numeric [array get data]]);"

		if {[pg_exec_or_exception $::vroomdb $sql]} {
			set id [simplesqlquery $::vroomdb "SELECT expense_id FROM expenses WHERE name = [pg_quote $data(name)] AND odometer = [sanitize_number $data(odometer)]"]
			puts "Added new fillup id $id ($data(name) on $data(service_date))"
		}
	} else {
		if {[update_if_changed $::vroomdb fillups fillup_id $id [array get data]]} {
			puts "Updated fillup id $id"
		}
	}

	if {$id != ""} {
		return $id
	}

	return 0
}

proc add_expense { hash_data } {
	array set data $hash_data

	set fields_varchar [list name service_date note location type subtype payment categories reminder_interval currency_code uuid]
	set fields_numeric [list odometer cost reminder_distance flags vehicle_id currency_rate lat lon]

	set id [lookup_by_uuid_with_fallback expense_id expenses data(uuid) "name = [pg_quote $data(name)] AND odometer = [sanitize_number $data(odometer)]"]

	if {$id == ""} {
		if {$data(cost) == ""} {
			set data(cost) 0.00
		}
		set sql "INSERT INTO expenses ([sql_field_list $fields_varchar], [sql_field_list $fields_numeric]) "
		append sql "VALUES ([sql_value_list varchar $fields_varchar [array get data]], [sql_value_list numeric $fields_numeric [array get data]]);"

		if {[pg_exec_or_exception $::vroomdb $sql]} {
			set id [simplesqlquery $::vroomdb "SELECT expense_id FROM expenses WHERE name = [pg_quote $data(name)] AND odometer = [sanitize_number $data(odometer)]"]
			puts "Added new expense id $id ($data(name) on $data(service_date))"
		}
	} else {
		if {[update_if_changed $::vroomdb expenses expense_id $id [array get data]]} {
			puts "Updated expense id $id"
		}
	}

	if {$id != ""} {
		return $id
	}

	return 0
}

proc add_trip { hash_data } {
	array set data $hash_data

	set fields_varchar [list name start_date end_date note categories uuid]
	set fields_numeric [list start_odometer end_odometer distance vehicle_id flags]

	unset -nocomplain id
	set id [lookup_by_uuid_with_fallback trip_id trips data(uuid) "name = [pg_quote $data(name)] AND start_odometer = [sanitize_number $data(start_odometer)]"]

	if {$id == ""} {
		set sql "INSERT INTO trips ([sql_field_list $fields_varchar], [sql_field_list $fields_numeric]) "
		append sql "VALUES ([sql_value_list varchar $fields_varchar [array get data]], [sql_value_list numeric $fields_numeric [array get data]]);"

		if {[pg_exec_or_exception $::vroomdb $sql]} {
			set id [simplesqlquery $::vroomdb "SELECT trip_id FROM trips WHERE name = [pg_quote $data(name)] AND start_odometer = [sanitize_number $data(start_odometer)]"]
			puts "Added new trip id $id ($data(name) on $data(start_date))"
		}
	} else {
		if {[update_if_changed $::vroomdb trips trip_id $id [array get data]]} {
			puts "Updated trip id $id"
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

