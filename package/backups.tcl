namespace eval ::vroom {
	set expected_version(default) 190

	proc parse_backup_line {line} {
		set fields(RoadTrip)			{version}
		set fields(FuelRecords)			{version rowcount}
		set fields(MaintenanceRecords)	{version rowcount}
		set fields(RoadTripRecords)		{version rowcount}
		set fields(TireRecords)			{version rowcount}

		set fields(CarModel)	{name units_odometer units_economy _ notes tank_capacity tank_units home_currency _ _ fill_units _ uuid}
		set fields(f)			{odometer fillup_date fill_amount fill_units unit_price filled note octane location payment conditions reset categories _ _ _ lat lon _ _ _ uuid}
		set fields(m)			{odometer service_date name cost note location type subtype payment categories reminder_interval reminder_distance flags currency_code currency_rate lat lon uuid}
		set fields(r)			{name start_date start_odometer end_date end_odometer note flags categories uuid}
		set fields(t)			{_ _ _ _ _ _ _ _ _}

		set plist [split $line ","]
		set buf(rowtype) [lindex $plist 0]

		# set i 1
		# puts -nonewline "$buf(rowtype): "
		# foreach f $plist {
		# 	puts -nonewline "[format "%2d" $i]:[::vroom::urldecode [lindex $plist $i]] "
		# 	incr i
		# }
		# puts ""

		if {[info exists buf(rowtype)] && [info exists fields($buf(rowtype))]} {
			set i 1
			foreach f $fields($buf(rowtype)) {
				set buf($f) [::vroom::urldecode [lindex $plist $i]]
				incr i
			}
			return [array get buf]
		}
		return
	}

	proc check_version {arrayField} {
		upvar 1 $arrayField buf

		set ev $::vroom::expected_version(default)

		if {[info exists buf(version)]} {
			if {$buf(version) == $ev} {
				return 1
			}
		}

		logmsg "Version mismatch"
		exit -1
	}

	proc check_vehicle {arrayField} {
		upvar 1 $arrayField buf

		if {[info exists buf(vehicle_id)]} {
			return
		}

		if {![info exists ::vehicle_id]} {
			logmsg "No vehicle ID"
			exit -1
		}

		set buf(vehicle_id) $::vehicle_id
		return
	}

	proc import_row_RoadTrip {hash_data} {
		array set buf $hash_data
		check_version buf
		return 1
	}

	proc import_row_CarModel {hash_data} {
		global vroomdb

		unset -nocomplain ::vehicle_id
		array set buf $hash_data

		pg_select $vroomdb "SELECT vehicle_id FROM vehicles WHERE uuid = [pg_quote $buf(uuid)]" dbrow {
			set ::vehicle_id $dbrow(vehicle_id)
			logmsg "Matched data file to vehicle_id $::vehicle_id"
		}


		if {![info exists ::vehicle_id]} {
			if {1} {
				# Insert new vehicle

				set enum(fill_units)		{"Gal" "Liters" "kg" "kW-h"}
				set enum(units_odometer)	{"mi" "km" "hours" "none"}
				set enum(units_economy)		{"MPG" "MPG/i"}
				set enum(tank_units)		{"gal" "liters"}

				foreach e [array names enum] {
					set buf($e) [lindex $enum($e) $buf($e)]
				}

				add_vehicle [array get buf]
			} else {
				# Do not insert new vehicles
				logmsg "Could not find a matching vehicle for uuid $buf(uuid)"
				exit -1
			}
		}
	}

	proc import_row_recordcounts {hash_data} {
		array set buf $hash_data
		check_version buf

		set ::expected_count($buf(rowtype)) $buf(rowcount)
		debug "Expecting $::expected_count($buf(rowtype)) $buf(rowtype) in this file"
		return 1
	}

	proc import_row_f {hash_data} {
		array set buf $hash_data
		check_vehicle buf

		set enum(fill_units)		{"Gal" "Liters" "kg" "kW-h"}

		foreach e [array names enum] {
			set buf($e) [lindex $enum($e) $buf($e)]
		}

		set buf(currency_rate) 1.000000

		set id [add_fillup [array get buf]]
		incr ::count(FuelRecords)
	}

	proc import_row_m {hash_data} {
		array set buf $hash_data
		check_vehicle buf

		set enum(type)				{"Service" "Expense" "Other"}

		foreach e [array names enum] {
			set buf($e) [lindex $enum($e) $buf($e)]
		}

		set buf(currency_rate) 1.000000

		set id [add_expense [array get buf]]
		incr ::count(MaintenanceRecords)
	}

	proc import_row_r {hash_data} {
		array set buf $hash_data
		check_vehicle buf

		set id [add_trip [array get buf]]
		incr ::count(RoadTripRecords)
	}

	proc import_row_t {hash_data} {
		incr ::count(TireRecords)
	}

	proc urldecode {str} {
		set str [string map [list + { } "\\" "\\\\"] $str]
		regsub -all -- {%([A-Fa-f0-9][A-Fa-f0-9])} $str {\\u00\1} str
		return [subst -novar -nocommand $str]
	}

}

package provide vroom 1.0

