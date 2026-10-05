require_relative "lib/teptris/version"

Gem::Specification.new do |spec|
  spec.name = "teptris"
  spec.version = Teptris::VERSION
  spec.authors = ["teptris contributors"]
  spec.summary = "TOML for Ruby at libteptris speed (native C extension)"
  spec.description =
    "A native C extension over libteptris, a C99 TOML 1.1 " \
    "parser/emitter. API shape mirrors the tomlib gem."
  spec.homepage = "https://github.com/leptris/teptris-ruby"
  spec.license = "MIT"
  # no homepage_uri in metadata: it duplicates spec.homepage and
  # rubygems.org shows only the first of identical URIs (build warning)
  spec.metadata = {
    "source_code_uri" => "https://github.com/leptris/teptris-ruby",
    "changelog_uri" =>
      "https://github.com/leptris/teptris-ruby/releases",
    "documentation_uri" =>
      "https://leptris.github.io/docs/teptris-ruby",
    "bug_tracker_uri" =>
      "https://github.com/leptris/teptris-ruby/issues",
    "rubygems_mfa_required" => "true"
  }
  spec.required_ruby_version = ">= 3.0"
  spec.files = Dir["lib/**/*.rb"] + Dir["lib/teptris_ext.*"] +
               Dir["sig/*.rbs"] + ["Steepfile"]
  spec.bindir = "bin"
  spec.executables = []
end
