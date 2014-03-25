package require Tclx
package require Pgtcl


namespace eval ::vroom {

	proc init {} {
		set ::vroomdb [::vroom::dbconnect ::vroom::DB]
	}

	proc dbconnect {DB} {
		if {[catch {set db [pg_connect -connlist [array get ::$DB]]} result] == 1} {
			puts "Unable to connect to database: $result"

		} else {
			return $db
		}
	}

	proc vehicle_id_from_tag {tag} {
		pg_select $::vroomdb "SELECT vehicle_id FROM vehicles WHERE tag ilike [pg_quote $tag]" buf {
			return $buf(vehicle_id)
		}
		return
	}

	proc vehicle_array {id} {
		array set vehicle {}

		lappend min_odo "SELECT purchase_odometer FROM vehicles WHERE vehicle_id = $id"
		lappend min_odo "SELECT min(odometer) FROM fillups WHERE vehicle_id = $id"
		lappend min_odo "SELECT min(odometer) FROM expenses WHERE vehicle_id = $id"
		lappend min_odo "SELECT min(start_odometer) FROM trips WHERE vehicle_id = $id AND start_odometer > 0"
		lappend stats_sql "COALESCE(([join $min_odo "),("]),0) AS min_odometer"

		lappend max_odo "SELECT sold_odometer FROM vehicles WHERE vehicle_id = $id"
		lappend max_odo "SELECT max(odometer) FROM fillups WHERE vehicle_id = $id"
		lappend max_odo "SELECT max(odometer) FROM expenses WHERE vehicle_id = $id"
		lappend max_odo "SELECT max(end_odometer) FROM trips WHERE vehicle_id = $id AND end_odometer > 0"
		lappend stats_sql "COALESCE(([join $max_odo "),("]),0) AS max_odometer"

		lappend min_date "SELECT purchase_date FROM vehicles WHERE vehicle_id = $id"
		lappend min_date "SELECT min(fillup_date) FROM fillups WHERE vehicle_id = $id"
		lappend stats_sql "COALESCE(([join $min_date "),("])) AS min_date"

		lappend max_date "SELECT sold_date FROM vehicles WHERE vehicle_id = $id"
		lappend max_date "SELECT max(fillup_date) FROM fillups WHERE vehicle_id = $id"
		lappend stats_sql "COALESCE(([join $max_date "),("])) AS max_date"

		pg_select $::vroomdb "SELECT * FROM vehicles WHERE vehicle_id = $id" buf {
			array set vehicle [array get buf]
		}
		pg_select $::vroomdb "SELECT [join $stats_sql ", "]" buf {
			array set vehicle [concat [array get vehicle] [array get buf]]
		}
		pg_select $::vroomdb "SELECT [pg_quote $vehicle(max_date)]::date - [pg_quote $vehicle(min_date)]::date as days" buf {
			set vehicle(days) $buf(days)
			set vehicle(months) [expr round($buf(days)/30)]
		}

		set vehicle(miles)  [expr $vehicle(max_odometer) - $vehicle(min_odometer)]

		return [array get vehicle]
	}

}

package provide vroom 1.0
