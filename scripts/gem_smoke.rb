# Round-trips the PUBLISHED gem (installed from rubygems by the caller)
# across the API surface users touch first: load, datetime mapping,
# dump, load-what-you-dumped.
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
puts "PUBLISHED GEM OK #{RUBY_VERSION} #{RUBY_PLATFORM} engine=#{Teptris::TOML.engine_version}"
