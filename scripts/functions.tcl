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
