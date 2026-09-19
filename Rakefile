# frozen_string_literal: true

require "bundler/gem_tasks"

begin
  require "rspec/core/rake_task"
  RSpec::Core::RakeTask.new(:spec)
rescue LoadError
end

# Lockstep with the C core; `rake compile` builds this tag from the
# release tarball (leptris-ruby pattern). Keep in step with
# .github/workflows/release.yml and the CHANGELOG.
LIBTEPTRIS_VERSION = "0.1.24"

# LTO off: bitcode in the static archive breaks mkmf's link step
# (llvm 'unsupported stack probing method' on the ext link)
CMAKE_FLAGS = %w[
  -DCMAKE_BUILD_TYPE=Release
  -DTEPTRIS_BUILD_SHARED=OFF
  -DTEPTRIS_BUILD_STATIC=ON
  -DBUILD_TESTING=OFF
  -DTEPTRIS_BUILD_CLI=OFF
  -DTEPTRIS_ENABLE_LTO=OFF
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON
].freeze

desc "Build libteptris + the native extension into lib/"
task :compile do
  version = ENV.fetch("LIBTEPTRIS_VERSION", LIBTEPTRIS_VERSION)
  src = ENV["TEPTRIS_SRC"] # local checkout overrides the tarball
  build = File.expand_path("tmp/libteptris-#{version}", __dir__)
  rm_rf(build)
  mkdir_p(build)
  # The C core links STATICALLY into the extension (issue #38): one
  # self-contained teptris_ext per platform — no soname, no rpath, no
  # dylib chain to distribute. On Windows the ext compiles under
  # Ruby's mingw toolchain; build the archive with the SAME toolchain.
  win = RUBY_PLATFORM =~ /mingw/
  toolchain = []
  if win
    cc = RbConfig::CONFIG["CC"].split(" ").first
    # Ninja: "MinGW Makefiles" emits cmd.exe recipes that MSYS path
    # mangling corrupts under CI bash ("cmTC_x.dir is not recognized")
    toolchain = ["-G Ninja", "-DCMAKE_C_COMPILER=#{cc}"]
  end
  if src
    cmake_src = File.expand_path(src)
  else
    url = "https://api.github.com/repos/leptris/teptris/tarball/v#{version}"
    sh "curl -sL #{url} | tar xz -C #{build} --strip-components=1"
    cmake_src = build
  end
  inc = File.join(cmake_src, "src/include")
  libdir = File.join(build, "src")

  # PGO two-stage (C core: scripts/build-pgo.sh): -fprofile-generate
  # build, train via `teptris format` over a generated corpus, then a
  # -fprofile-use rebuild. Measured +3-13% on the parse shapes
  # (benchmarks/LEDGER.md in the C repo). TEPTRIS_PGO=0 escapes to the
  # plain single-stage build (no python3, MSVC toolchains, debugging).
  if ENV["TEPTRIS_PGO"] != "0" && File.file?(File.join(cmake_src, "scripts/build-pgo.sh"))
    corpus = File.join(build, "bench-corpus")
    sh "python3 #{File.join(cmake_src, "scripts/gen_bench_corpus.py")} #{corpus}"
    sh ["bash", File.join(cmake_src, "scripts/build-pgo.sh"), cmake_src, build, corpus, toolchain].join(" ")
  else
    sh "cmake -B #{build} -S #{cmake_src} #{(CMAKE_FLAGS + toolchain).join(' ')}"
    sh "cmake --build #{build} --config Release -j"
  end

  extdir = File.expand_path("ext/teptris_ext", __dir__)
  Dir.chdir(extdir) do
    rm_f(["Makefile", "teptris_ext.bundle"] + Dir["*.o"])
    sh "ruby extconf.rb --with-teptris-libdir=#{libdir} --with-teptris-include=#{inc}"
    sh "make"
    ext = Dir["teptris_ext.{so,bundle,dll}"].first
    raise "extension build produced no bundle in #{extdir}" unless ext

    # fat gem on every platform: one extension per ruby minor under
    # lib/teptris/<minor>/ (a unix .so built for one minor fails
    # dlopen on another — ruby 4.0 could not load the 3.3-built ext)
    minor = RUBY_VERSION[/\A\d+\.\d+/]
    dest = File.expand_path("lib/teptris/#{minor}", __dir__)
    mkdir_p(dest)
    cp(ext, dest)
  end

  # nothing else to ship: libteptris lives inside teptris_ext
end

task spec: :compile unless ENV.key?("TEPTRIS_LIB_PATH")
task default: :spec

# Plain `gem build` on a generated gemspec: no rubygems/package_task
# dependency (it is not released as a standalone gem).
def build_gem(spec)
  mkdir_p "tmp"
  spec_path = "tmp/#{spec.full_name}.gemspec"
  File.write(spec_path, spec.to_ruby)
  sh "gem build #{spec_path}"
  mkdir_p "pkg"
  gem_file = "#{spec.full_name}.gem"
  mv(gem_file, "pkg/") if File.exist?(gem_file)
end

# Vendor the pinned-tag engine (clean tree) into the ext so the gem
# carries the C source beside any prebuilt ext — extconf's source mode
# compiles it with the installing ruby's own toolchain when a rebuild
# is wanted. Returns nothing; leaves ext/teptris_ext/engine populated.
def vendor_engine
  version = ENV.fetch("LIBTEPTRIS_VERSION", LIBTEPTRIS_VERSION)
  src = ENV["TEPTRIS_SRC"] # local checkout overrides the tarball
  build = File.expand_path("tmp/libteptris-#{version}", __dir__)
  rm_rf(build)
  mkdir_p(build)
  if src
    cmake_src = File.expand_path(src)
  else
    url = "https://api.github.com/repos/leptris/teptris/tarball/v#{version}"
    sh "curl -sL #{url} | tar xz -C #{build} --strip-components=1"
    cmake_src = build
  end
  eng = File.expand_path("ext/teptris_ext/engine", __dir__)
  rm_rf(eng)
  mkdir_p(File.join(eng, "src"))
  cp_r(File.join(cmake_src, "src/teptris"), File.join(eng, "src/teptris"))
  cp_r(File.join(cmake_src, "src/include"), File.join(eng, "src/include"))
  cp(File.join(cmake_src, "LICENSE.md"), File.join(eng, "LICENSE.md"))
end

# Engine source files a gem must carry (beside the prebuilt ext on
# platform gems, as the payload on the source gem).
ENGINE_SOURCE_FILES = ["ext/teptris_ext/extconf.rb",
                       "ext/teptris_ext/materialize.c",
                       "ext/teptris_ext/engine/LICENSE.md"] +
                      ["ext/teptris_ext/engine/src/**/*.{c,h}"].freeze

desc "Build the source (ruby-platform) gem: libteptris + ext compile at install"
task "gem:source" do
  vendor_engine
  spec = Gem::Specification.load("teptris.gemspec").dup
  spec.extensions = ["ext/teptris_ext/extconf.rb"]
  spec.files += ENGINE_SOURCE_FILES.flat_map { |g| Dir[g] }
  build_gem(spec)
end

platforms = [
  "x64-mingw32",
  "x64-mingw-ucrt",
  "aarch64-mingw-ucrt",
  "x86_64-linux",
  "x86_64-linux-musl",
  "aarch64-linux",
  "aarch64-linux-musl",
  "arm-linux",
  "arm-linux-musl",
  "powerpc64le-linux",
  "s390x-linux",
  "x86_64-darwin",
  "arm64-darwin",
].freeze

platforms.each do |platform|
  mingw = platform.include?("mingw")

  # Pack a pre-compiled gem from whatever native files already sit in
  # lib/ — used by CI's fat-gem assembly and never compiles. Every
  # platform gem also carries the engine SOURCE (recompile path:
  # untar, cd ext/teptris_ext, ruby extconf.rb && make).
  pack = task "gem:pack:#{platform}" do
    natives = Dir.glob("lib/teptris_ext.{so,bundle,dll}") +
              Dir.glob("lib/teptris/*/teptris_ext.{so,bundle,dll}")
    abort "no native extension under lib/ for #{platform} — run rake compile first" if natives.empty?
    vendor_engine
    spec = Gem::Specification.load("teptris.gemspec").dup
    spec.platform = Gem::Platform.new(platform)
    spec.files += natives + ENGINE_SOURCE_FILES.flat_map { |g| Dir[g] }
    build_gem(spec)
  end

  desc "Build pre-compiled gem for the #{platform} platform"
  task "gem:native:#{platform}" => ["compile", pack.name]
end

require "rake/clean"

CLOBBER.include("pkg")
CLEAN.include("tmp")
