# End-to-end Ruby tier (TODO.impl/09): Teptris::TOML.load vs tomlib vs
# tomlrb over the teptris bench corpus. Run:
#   TEPTRIS_LIB_PATH=../teptris/build-shared/src/libteptris.dylib \
#     ruby benchmark/lang_tier.rb [corpus-dir] [reps]
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "teptris"
require "tomlib"
require "tomlrb"

corpus = ARGV[0] || File.expand_path("../../teptris/bench-corpus", __dir__)
reps = (ARGV[1] || 12).to_i

LIBS = {
  "teptris" => ->(s) { Teptris::TOML.load(s) },
  "tomlib" => ->(s) { Tomlib.load(s) },
  "tomlrb" => ->(s) { Tomlrb.parse(s) }
}.freeze

def bench(call, src, reps)
  2.times { call.call(src) }
  best = Float::INFINITY
  reps.times do
    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    call.call(src)
    dt = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
    best = dt if dt < best
  end
  best * 1000.0
end

Dir[File.join(corpus, "*.toml")].sort.each do |path|
  src = File.read(path)
  row = {}
  LIBS.each do |name, call|
    begin
      ms = bench(call, src, reps)
      row[name] = format("%7.2f ms %7.1f MB/s", ms,
                         src.bytesize / 1024.0 / 1024.0 / (ms / 1000.0))
    rescue StandardError => e
      row[name] = "ERROR: #{e.message[0, 50]}"
    end
  end
  puts format("%-20s teptris %s | tomlib %s | tomlrb %s",
              File.basename(path), row["teptris"], row["tomlib"], row["tomlrb"])
end
