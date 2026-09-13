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
LIBTEPTRIS_VERSION = "0.1.0"

CMAKE_FLAGS = %w[
  -DCMAKE_BUILD_TYPE=Release
  -DTEPTRIS_BUILD_SHARED=ON
  -DTEPTRIS_BUILD_STATIC=OFF
  -DBUILD_TESTING=OFF
  -DTEPTRIS_BUILD_CLI=OFF
].freeze

desc "Build libteptris #{LIBTEPTRIS_VERSION} from the release tarball into lib/"
task :compile do
  version = ENV.fetch("LIBTEPTRIS_VERSION", LIBTEPTRIS_VERSION)
  src = ENV["TEPTRIS_SRC"] # local checkout overrides the tarball
  build = File.expand_path("tmp/libteptris-#{version}", __dir__)
  rm_rf(build)
  mkdir_p(build)
  if src
    sh "cmake -B #{build} -S #{src} #{CMAKE_FLAGS.join(' ')}"
  else
    url = "https://api.github.com/repos/leptris/teptris/tarball/v#{version}"
    sh "curl -sL #{url} | tar xz -C #{build} --strip-components=1"
    sh "cmake -B #{build} -S #{build} #{CMAKE_FLAGS.join(' ')}"
  end
  sh "cmake --build #{build} -j"

  # Pick the produced shared library for this platform into lib/.
  lib = Dir.glob("#{build}/src/libteptris.{dylib,so,dll}").first
  raise "libteptris shared library not found in #{build}/src" unless lib

  cp(lib, "lib/")
end

task spec: :compile unless ENV.key?("TEPTRIS_LIB_PATH")
task default: :spec

desc "Build the pure-Ruby gem"
task "gem:native:any" do
  sh "rake platform:any gem"
end

desc "Define the gem task to build the pure-Ruby gem"
task "platform:any" do
  spec = Gem::Specification.load("teptris.gemspec").dup
  task = Gem::PackageTask.new(spec)
  task.define
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
    sh "rake compile platform:#{platform} gem"
  end

  desc "Define the gem task to build on the #{platform} platform (binary gem)"
  task "platform:#{platform}" do
    spec = Gem::Specification.load("teptris.gemspec").dup
    spec.platform = Gem::Platform.new(platform)
    spec.files += Dir.glob("lib/libteptris.{dll,so,dylib}")
    task = Gem::PackageTask.new(spec)
    task.define
  end
end

begin
  require "rubygems/package_task"
rescue LoadError
end

require "rake/clean"

CLOBBER.include("pkg")
CLEAN.include("tmp")
