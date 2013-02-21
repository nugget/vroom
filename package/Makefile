TARGET = /usr/local/lib/vroom

all:
	echo "pkg_mkIndex -verbose -- ." | tclsh8.6

install:
	install -m 0755 -o root -g wheel -d $(TARGET)
	install -C -m 0644 -o root -g wheel * $(TARGET)
