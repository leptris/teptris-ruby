require "mkmf"

# Two modes:
# - archive mode (precompiled platform gems): --with-teptris-libdir
#   points at the cmake-built static archive; everything else links
#   from it. One self-contained teptris_ext artifact per platform, no
#   soname/rpath/dylib-chain distribution to get wrong (issue #38 —
#   0.2.17's linux/mingw gems shipped the ext without the
#   libteptris.so.0 soname it linked).
# - source mode (the ruby-platform gem): the engine tree is vendored
#   at engine/ and mkmf compiles it together with the ext — no cmake,
#   no archive. The ext is still mandatory: a platform without a C
#   toolchain fails the install instead of silently degrading.
eng = File.expand_path("engine", __dir__)
archive_mode = !File.file?(File.join(eng, "src/include/teptris/teptris.h"))
if archive_mode
  libdir = with_config("teptris-libdir") || ENV["TEPTRIS_LIBDIR"] ||
           File.dirname(ENV["TEPTRIS_LIB_PATH"].to_s)
  archive = Dir.glob("#{libdir}/libteptris*.a").first
  abort "libteptris static archive not found under #{libdir}" unless archive
  inc = with_config("teptris-include") || ENV["TEPTRIS_INCLUDE"] ||
        File.expand_path("../../../teptris/src/include", __dir__)
  abort "teptris headers not found (#{inc})" unless File.file?(File.join(inc, "teptris/teptris.h"))
  $INCFLAGS << " -I#{inc}"
else
  $INCFLAGS << " -I#{eng}/src -I#{eng}/src/include"
  $srcs = ["materialize.c"] + Dir["engine/src/teptris/**/*.c"].sort
  # link rule must carry the subdir paths (mkmf flattens $objs to
  # basenames, which breaks once sources live below the ext root)
  $objs = $srcs.map { |s| s.sub(/\.c\z/, ".o") }
end
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
if archive_mode
  # Link the whole archive: every teptris symbol lands inside the ext.
  $LDFLAGS << " #{archive}"
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
