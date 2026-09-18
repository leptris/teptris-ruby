require_relative "lib/teptris/version"

Gem::Specification.new do |spec|
  spec.name = "teptris"
  spec.version = Teptris::VERSION
  spec.authors = ["teptris contributors"]
  spec.summary = "TOML for Ruby at libteptris speed (native C extension)"
  spec.description =
    "A native C extension over libteptris, a C11 TOML 1.1 " \
    "parser/emitter. API shape mirrors the tomlib gem."
  spec.homepage = "https://github.com/leptris/teptris-ruby"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0"
  spec.files = Dir["lib/**/*.rb"] + Dir["lib/teptris_ext.*"]
  spec.bindir = "bin"
  spec.executables = []
end
