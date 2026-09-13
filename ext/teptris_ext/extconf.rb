require "mkmf"
libdir = with_config("teptris-libdir") || ENV["TEPTRIS_LIBDIR"] ||
         File.dirname(ENV["TEPTRIS_LIB_PATH"].to_s)
abort "libteptris dylib directory not found (#{libdir})" unless Dir.glob("#{libdir}/libteptris*.{dylib,so,dll}").any?
inc = with_config("teptris-include") || ENV["TEPTRIS_INCLUDE"] ||
      File.expand_path("../../../teptris/src/include", __dir__)
abort "teptris headers not found (#{inc})" unless File.file?(File.join(inc, "teptris/teptris.h"))
$INCFLAGS << " -I#{inc}"
# The dylib's install name is @rpath/libteptris.0.dylib; the bundle sits
# beside it in the gem's lib/ → @loader_path resolves without env vars.
$LDFLAGS << " -L#{libdir} -lteptris -Wl,-rpath,@loader_path"
create_makefile "teptris_ext"
