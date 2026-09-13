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
LIBTEPTRIS_VERSION = "0.1.1"

CMAKE_FLAGS = %w[
  -DCMAKE_BUILD_TYPE=Release
  -DTEPTRIS_BUILD_SHARED=ON
  -DTEPTRIS_BUILD_STATIC=OFF
  -DBUILD_TESTING=OFF
  -DTEPTRIS_BUILD_CLI=OFF
].freeze

desc "Build libteptris + the native extension into lib/"
task :compile do
  version = ENV.fetch("LIBTEPTRIS_VERSION", LIBTEPTRIS_VERSION)
  src = ENV["TEPTRIS_SRC"] # local checkout overrides the tarball
  build = File.expand_path("tmp/libteptris-#{version}", __dir__)
  rm_rf(build)
  mkdir_p(build)
  # On Windows the ext compiles under Ruby's mingw toolchain; build the
  # C core with the SAME toolchain so -L/-l links natively (MSVC-built
  # DLLs need import-lib gymnastics — issue #15).
  win = RUBY_PLATFORM =~ /mingw/
  toolchain = []
  if win
    cc = RbConfig::CONFIG["CC"].split(" ").first
    toolchain = ["-G", "MinGW Makefiles", "-DCMAKE_C_COMPILER=#{cc}"]
  end
  if src
    sh "cmake -B #{build} -S #{src} #{(CMAKE_FLAGS + toolchain).join(' ')}"
    inc = File.expand_path("src/include", src)
  else
    url = "https://api.github.com/repos/leptris/teptris/tarball/v#{version}"
    sh "curl -sL #{url} | tar xz -C #{build} --strip-components=1"
    sh "cmake -B #{build} -S #{build} #{(CMAKE_FLAGS + toolchain).join(' ')}"
    inc = File.join(build, "src/include")
  end
  sh "cmake --build #{build} --config Release -j"
  libdir = File.join(build, "src")

  extdir = File.expand_path("ext/teptris_ext", __dir__)
  Dir.chdir(extdir) do
    rm_f(["Makefile", "teptris_ext.bundle"] + Dir["*.o"])
    sh "ruby extconf.rb --with-teptris-libdir=#{libdir} --with-teptris-include=#{inc}"
    sh "make"
    ext = Dir["teptris_ext.{so,bundle,dll}"].first
    raise "extension build produced no bundle in #{extdir}" unless ext

    cp(ext, File.expand_path("lib", __dir__))
  end

  # the dylib chain the bundle links (@loader_path rpath)
  Dir.glob("#{libdir}/libteptris*").each { |f| cp(f, "lib/") unless f.end_with?(".a") || f.end_with?(".dll.a") }
  Dir.glob("#{libdir}/**/teptris.dll").each { |f| cp(f, "lib/") }
  Dir.glob("#{libdir}/libteptris.dll").each { |f| cp(f, "lib/") }
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

desc "Build the pure-Ruby gem"
task "gem:native:any" do
  build_gem(Gem::Specification.load("teptris.gemspec").dup)
end

platforms = [
  "x64-mingw32",
  "x64-mingw-ucrt",
  "aarch64-mingw-ucrt",
  "x86_64-linux",
  "x86_64-linux-musl",
  "aarch64-linux",
  "aarch64-linux-musl",
  "x86_64-darwin",
  "arm64-darwin",
].freeze

platforms.each do |platform|
  desc "Build pre-compiled gem for the #{platform} platform"
  task "gem:native:#{platform}" do
    Rake::Task["compile"].invoke
    spec = Gem::Specification.load("teptris.gemspec").dup
    spec.platform = Gem::Platform.new(platform)
    spec.files += Dir.glob("lib/teptris_ext.*") +
                  Dir.glob("lib/libteptris*.{dylib,so,dll}") +
                  Dir.glob("lib/*.dll")
    build_gem(spec)
  end
end

require "rake/clean"

CLOBBER.include("pkg")
CLEAN.include("tmp")
