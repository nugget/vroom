#!/usr/local/bin/tclsh8.6

package require http
package require vroom
package require tls

proc logmsg {buf} {
	# return
	puts "$buf"
}

proc main {} {
	global vroomdb
	logmsg "Drobox Fetcher Thingey"
	::vroom::init

	# set ::tls::defaults {-ssl3 0 -tls1 1}
	::tls::init -ssl2 0 -ssl3 0 -tls1 1
	::http::register https 443 ::tls::socket

	set url [lindex $::argv 0]

	set dbpath /var/db/vroom

	unset -nocomplain urllist
	if {[regexp {^http} $url]} {
		lappend urllist $url
	} else {
		pg_select $vroomdb "SELECT tag,dropbox_url FROM vehicles WHERE dropbox_url IS NOT NULL" buf {
			lappend urllist $buf(dropbox_url)
			set tag($buf(dropbox_url)) $buf(tag)
		}
	}

	if {[info exists urllist]} {
		foreach u $urllist {
			logmsg "Fetching $u"

			if {[regexp {([^/]+$)} $u _ fn]} {
				set fn [file join $dbpath "$tag($u).roadtrip"]
				logmsg " -> $fn"

				if {[file exists $fn]} {
					set size [file size $fn]
				} else {
					set size -1
				}
				logmsg "Current copy: $size bytes"

				set rh [::http::geturl $u -validate 1 -headers {Accept-Encoding ""}]
				upvar #0 $rh state

				if {[info exists state(totalsize)]} {
					set dbsize $state(totalsize)
				} else {
					set dbsize 0
				}
				logmsg "Downloaded  : $size bytes ($state(http))"
				::http::cleanup $rh


				if {$dbsize > 0 && $size != $dbsize} {
					puts "Old file size ($size) != header totalsize ($dbsize)"
					set tempfile "/tmp/vroom.download"
					catch {file delete -force $tempfile} err
					set fh [open $tempfile "w"]
					set rh [::http::geturl $u -channel $fh]
					close $fh
					::http::cleanup $rh
					puts "Downloaded new copy to tempfile"

					set newsize [file size $tempfile]
					if {$size == $newsize} {
						# puts "Same Size, exiting"
						file delete -force $tempfile
						exit 0
					}
					file rename -force $tempfile $fn

					puts "New database from Dropbox is $newsize bytes and the old one was $size bytes"

					set fh [open "|[file join [file dirname [info script]] import_backup.tcl] \"$fn\"" "r"]
					while {1} {
						set line [gets $fh]
						puts $line
						if {[eof $fh]} {
							close $fh
							break
						}
					}
				}
			}
		}
	}
}

if !$tcl_interactive main
