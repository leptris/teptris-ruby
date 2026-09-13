require_relative "lib/teptris/version"

Gem::Specification.new do |spec|
  spec.name = "teptris"
  spec.version = Teptris::VERSION
  spec.authors = ["teptris contributors"]
  spec.summary = "TOML for Ruby at libleptris speed (FFI, no C extension)"
  spec.description =
    "An FFI binding over libteptris, a C11 TOML 1.0 parser/emitter. " \
    "API shape mirrors the tomlib gem."
  spec.homepage = "https://github.com/leptris/teptris-ruby"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0"
  spec.files = Dir["lib/**/*.rb"]
  spec.bindir = "bin"
  spec.executables = []
  spec.add_dependency "ffi", "~> 1.15"
end
