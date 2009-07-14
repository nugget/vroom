TARGET = /usr/local/lib/vroom

all:
	echo "pkg_mkIndex -verbose -- ." | tclsh8.5

install:
	mkdir -p $(TARGET)
	install -C -m 644 -o root -g wheel * $(TARGET)
