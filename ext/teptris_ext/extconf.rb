require "mkmf"
libdir = with_config("teptris-libdir") || ENV["TEPTRIS_LIBDIR"] ||
         File.dirname(ENV["TEPTRIS_LIB_PATH"].to_s)
dll = Dir.glob("#{libdir}/**/teptris.dll").first # MSVC: src/Release/teptris.dll
implib = Dir.glob("#{libdir}/**/teptris.lib").first
found = Dir.glob("#{libdir}/libteptris*.{dylib,so,dll}").any? || dll
abort "libteptris shared library not found under #{libdir}" unless found
inc = with_config("teptris-include") || ENV["TEPTRIS_INCLUDE"] ||
      File.expand_path("../../../teptris/src/include", __dir__)
abort "teptris headers not found (#{inc})" unless File.file?(File.join(inc, "teptris/teptris.h"))
$INCFLAGS << " -I#{inc}"
# On ELF/Mach-O, ruby symbols resolve from the running Ruby process
# (macOS: dynamic_lookup; ELF shared objects allow undefined syms).
# On Windows the .so MUST link the ruby DLL import lib — symbols do
# not resolve at load otherwise.
win = RUBY_PLATFORM =~ /mingw/
unless win
  $LIBS = $LIBS.sub("-lruby", "")
end
if RUBY_PLATFORM =~ /darwin/
  $DLDFLAGS << " -Wl,-undefined,dynamic_lookup"
end
# The dylib's install name is @rpath/libteptris.0.dylib; the bundle sits
# beside it in the gem's lib/ → @loader_path resolves without env vars.
if implib && Dir.glob("#{libdir}/libteptris*.dll").empty?
  $LDFLAGS << " #{implib}" # mingw ld links MSVC import libraries
elsif win
  $LDFLAGS << " -L#{libdir} -lteptris" # PE has no rpath; DLL sits beside the .so
else
  $LDFLAGS << " -L#{libdir} -lteptris -Wl,-rpath,@loader_path"
end
create_makefile "teptris_ext"

# mkmf buries the absolute builder libruby path in librubyarg_shared;
# blank the variable DEFINITIONS in the generated Makefile so any
# spelling dies — Ruby symbols come from the running process
# (dynamic_lookup on macOS, undefined-allowed on ELF). Not on Windows:
# the import-lib link binds the ruby DLL by name.
unless win
  makefile = File.read("Makefile")
  makefile.gsub!(/^LIBRUBYARG_SHARED = .*$/, "LIBRUBYARG_SHARED =")
  makefile.gsub!(/^LIBRUBYARG_STATIC = .*$/, "LIBRUBYARG_STATIC =")
  makefile.gsub!(/^LIBRUBY = .*$/, "LIBRUBY =")
  makefile.gsub!(/(^|\s)\S*libruby[\w.\/-]*/, "")
  File.write("Makefile", makefile)
end
