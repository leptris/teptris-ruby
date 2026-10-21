# The API-surface round-trip both gem lanes assert: load, datetime
# mapping, dump, load-what-you-dumped. Shared by gem_smoke.rb
# (published gem) and gem_verify.rb (pre-publish local gem).
require "teptris"

src = <<~TOML
  i = 1
  s = "x"
  d = 1979-05-27
  o = 1979-05-27T07:32:00-07:00
  [t]
  k = 1.5
  arr = [1, 2, {n = 3}]
TOML

doc = Teptris::TOML.load(src)
raise "int" unless doc["i"] == 1
raise "str" unless doc["s"] == "x"
raise "date" unless doc["d"] == Date.new(1979, 5, 27)
raise "tz" unless doc["o"].utc_offset == -25_200
raise "nested" unless doc["t"]["arr"].last["n"] == 3
raise "round" unless Teptris::TOML.load(Teptris::TOML.dump(doc)) == doc

# the error path: dumping an unsupported value raises Teptris::Error
# (rb_raise over the binding's own class). A broken ext binary crashes
# the process HERE instead of raising — the mingw-ucrt ruby-4.0 PGO
# miscompile shipped in 0.3.6.1 slipped through a smoke without this.
begin
  Teptris::TOML.dump("k" => Object.new)
  raise "err-path: dump of an unsupported value did not raise"
rescue Teptris::Error
  raise "err-path: wrong error class" unless $!.message.include?("cannot dump")
end

puts "OK #{RUBY_VERSION} #{RUBY_PLATFORM} engine=#{Teptris::TOML.engine_version}"
