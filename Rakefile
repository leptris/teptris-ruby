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
  sh "cmake --build #{build} --config Release -j"

  # Pick the produced shared library for this platform into lib/.
  # MSVC multi-config puts it in src/Release/ and names it teptris.dll
  # (no lib prefix); single-config generators emit src/libteptris.*.
  lib = Dir.glob("#{build}/src/**/libteptris.{dylib,so,dll}").first ||
        Dir.glob("#{build}/src/**/teptris.dll").first
  raise "libteptris shared library not found under #{build}/src" unless lib

  cp(lib, "lib/")
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
    spec.files += Dir.glob("lib/{libteptris,teptris}.{dll,so,dylib}")
    build_gem(spec)
  end
end

require "rake/clean"

CLOBBER.include("pkg")
CLEAN.include("tmp")
