require "mkmf"
lib = with_config("teptris-lib") ||
      ENV["TEPTRIS_LIB_PATH"] ||
      File.expand_path("../../lib/libteptris.#{RbConfig::CONFIG["DLEXT"]}", __dir__)
abort "libteptris not found (#{lib}) — build it or pass --with-teptris-lib" unless File.file?(lib)
$LDFLAGS << " #{lib}"
create_makefile "teptris_ext"
