# Dump tier: Teptris::TOML.dump vs Tomlib.dump over materialized corpus
# documents. Run:
#   ruby benchmark/dump_tier.rb [corpus-dir] [reps]
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "teptris"
require "tomlib"

corpus = ARGV[0] || File.expand_path("../../teptris/bench-corpus", __dir__)
reps = (ARGV[1] || 12).to_i

def bench(call, obj, reps)
  2.times { call.call(obj) }
  best = Float::INFINITY
  reps.times do
    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    call.call(obj)
    dt = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
    best = dt if dt < best
  end
  best * 1000.0
end

Dir[File.join(corpus, "*.toml")].sort.each do |path|
  src = File.read(path)
  obj_t = Teptris::TOML.load(src)
  obj_l = Tomlib.load(src)
  bytes = obj_t.inspect.bytesize
  row = {}
  { "teptris" => [->(o) { Teptris::TOML.dump(o) }, obj_t],
    "tomlib"  => [->(o) { Tomlib.dump(o) }, obj_l] }.each do |name, (call, obj)|
    begin
      ms = bench(call, obj, reps)
      row[name] = format("%7.2f ms", ms)
    rescue StandardError => e
      row[name] = "ERROR: #{e.message[0, 40]}"
    end
  end
  ratio = (row["teptris"] =~ /ms/ && row["tomlib"] =~ /ms/) ? nil : nil
  puts format("%-20s obj~%dkB teptris %s | tomlib %s", File.basename(path),
              bytes / 1024, row["teptris"], row["tomlib"])
end
