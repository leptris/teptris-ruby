require "mkmf"
libdir = with_config("teptris-libdir") || ENV["TEPTRIS_LIBDIR"] ||
         File.dirname(ENV["TEPTRIS_LIB_PATH"].to_s)
found = Dir.glob("#{libdir}/libteptris*.{dylib,so,dll}").any? ||
       File.exist?("#{libdir}/teptris.dll") # MSVC names it without the lib prefix
abort "libteptris dylib directory not found (#{libdir})" unless found
inc = with_config("teptris-include") || ENV["TEPTRIS_INCLUDE"] ||
      File.expand_path("../../../teptris/src/include", __dir__)
abort "teptris headers not found (#{inc})" unless File.file?(File.join(inc, "teptris/teptris.h"))
$INCFLAGS << " -I#{inc}"
# The dylib's install name is @rpath/libteptris.0.dylib; the bundle sits
# beside it in the gem's lib/ → @loader_path resolves without env vars.
if File.exist?("#{libdir}/teptris.dll") && Dir.glob("#{libdir}/libteptris*.dll").empty?
  $LDFLAGS << " #{libdir}/teptris.dll" # mingw ld links the DLL directly
else
  $LDFLAGS << " -L#{libdir} -lteptris -Wl,-rpath,@loader_path"
end
create_makefile "teptris_ext"
