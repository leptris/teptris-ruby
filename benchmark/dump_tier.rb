# Dump tier: TOML dumps (Teptris::TOML.dump vs Tomlib.dump) and the
# natural-JSON view (Teptris::TOML.dump_json_natural vs stdlib
# JSON.generate) over materialized corpus documents. The JSON
# comparison runs on EQUALIZED content: stdlib JSON cannot serialize
# Time/Date, so both columns receive a copy whose datetimes were
# pre-converted to RFC 3339 strings (outside the timed region) —
# teptris does that conversion inline, so its column is the honest
# end-to-end number. Run:
#   ruby benchmark/dump_tier.rb [corpus-dir] [reps]
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "teptris"
require "tomlib"
require "json"

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

def jsonize(obj)
  case obj
  when Time then obj.strftime("%Y-%m-%dT%H:%M:%S") + obj.utc_offset.to_s
  when DateTime, Date then obj.iso8601
  when Hash then obj.each_with_object({}) { |(k, v), h| h[k] = jsonize(v) }
  when Array then obj.map { |v| jsonize(v) }
  else obj
  end
end

Dir[File.join(corpus, "*.toml")].sort.each do |path|
  src = File.read(path)
  obj_t = Teptris::TOML.load(src)
  obj_l = Tomlib.load(src)
  obj_j = jsonize(obj_t)
  bytes = obj_t.inspect.bytesize
  row = {}
  { "teptris" => [->(o) { Teptris::TOML.dump(o) }, obj_t],
    "tomlib" => [->(o) { Tomlib.dump(o) }, obj_l],
    "tep-json" => [->(o) { Teptris::TOML.dump_json_natural(o) }, obj_t],
    "json" => [->(o) { JSON.generate(o) }, obj_j] }.each do |name, (call, obj)|
    ms = bench(call, obj, reps)
    row[name] = format("%7.2f ms", ms)
  rescue StandardError => e
    row[name] = "ERROR: #{e.message[0, 40]}"
  end
  puts format(
    "%-20s obj~%dkB teptris %s | tomlib %s | tep-json %s | json %s",
    File.basename(path), bytes / 1024, row["teptris"], row["tomlib"],
    row["tep-json"], row["json"])
end
