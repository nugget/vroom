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
