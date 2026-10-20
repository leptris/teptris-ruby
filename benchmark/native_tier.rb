# Native tier: the retained-document roundtrip (load_doc + dump_doc -
# zero Ruby objects materialized) vs tomlib's dict roundtrip (its
# loads + its dumps; tomlrb has no serializer). The native-doc API's
# home cell.
#
# Run: ruby benchmark/native_tier.rb [corpus-dir] [reps]
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "teptris"
require "tomlib"

corpus = ARGV[0] || File.expand_path("../../teptris/bench-corpus", __dir__)
reps = (ARGV[1] || 40).to_i

def bench(call, src, reps)
  call.call(src)
  best = Float::INFINITY
  reps.times do
    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    call.call(src)
    dt = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
    best = dt if dt < best
  end
  best * 1000.0
end

native = ->(s) { Teptris::TOML.dump_doc(Teptris::TOML.load_doc(s)) }
dict = ->(s) { Tomlib.dump(Tomlib.load(s)) }

Dir.glob(File.join(corpus, "*.toml")).sort.each do |f|
  src = File.read(f)
  mn = bench(native, src, reps)
  md = bench(dict, src, reps)
  puts format("%-20s teptris native %8.2f ms %6.1f MB/s | tomlib dict %8.2f ms %6.1f MB/s",
              File.basename(f), mn, src.size / 1_048_576.0 / (mn / 1000.0),
              md, src.size / 1_048_576.0 / (md / 1000.0))
end
