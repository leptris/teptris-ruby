# Round-trips a LOCAL, not-yet-published .gem (installed by the
# caller with gem install --local) and asserts the packaging
# doctrine's installed layout: the gem carries the compiled
# extension AND the vendored engine source with its rebuild README.
# Exit non-zero on any failure - this is the pre-publish gate.
# The source (ruby-platform) gem passes the ext check through its
# compiled-at-install extension in the gem's extension dir.
require_relative "roundtrip_assertions"

spec = Gem::Specification.find_by_name("teptris")
root = spec.full_gem_path
engine_src = Dir[File.join(root, "ext/teptris_ext/engine/src/teptris/*.{c,h}")]
raise "doctrine: only #{engine_src.size} engine sources in installed gem" if engine_src.size < 20
raise "doctrine: engine LICENSE missing" unless File.exist?(File.join(root, "ext/teptris_ext/engine/LICENSE.md"))
raise "doctrine: rebuild README missing" unless File.exist?(File.join(root, "ext/teptris_ext/engine/README.md"))
exts = Dir[File.join(root, "lib/teptris_ext.{so,bundle}")] +
       Dir[File.join(root, "lib/teptris/*/teptris_ext.{so,bundle}")] +
       Dir[File.join(spec.extension_dir.to_s, "teptris_ext.{so,bundle}")]
raise "doctrine: no compiled extension in installed gem" if exts.empty?
puts "DOCTRINE OK #{engine_src.size} engine sources + #{exts.size} ext"
