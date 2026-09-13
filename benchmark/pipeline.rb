# Consumer-pipeline benchmark leg + GC.stat allocation deltas +
# fresh-process one-shot medians (launch checklist item 5).
#
#   TEPTRIS_LIB_PATH=../teptris/build-shared/src/libteptris.dylib \
#     ruby benchmark/pipeline.rb [corpus-file]
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "teptris"
require "tomlib"

path = ARGV[0] || File.expand_path("../../teptris/bench-corpus/mixed.toml", __dir__)
src = File.read(path)

Item = Struct.new(:id, :name, :price, :tags, :available, :weight)

def pipeline(hash) # nested doc -> typed objects (the consumer walk)
  hash.fetch("items", []).map do |it|
    Item.new(it["id"], it["name"], it["price"], it["tags"], it["available"],
             it.dig("meta", "weight"))
  end
end

def bench(n = 10)
  yield # warmup
  best = nil
  n.times do
    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    dt = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
    best = dt if best.nil? || dt < best
  end
  best
end

def alloc_delta
  GC.disable
  before = GC.stat(:total_allocated_objects)
  out = yield
  [GC.stat(:total_allocated_objects) - before, out]
ensure
  GC.enable
end

teptris_best = bench { pipeline(Teptris::TOML.load(src)) }
tomlib_best = begin
  bench { pipeline(Tomlib.load(src)) }
rescue StandardError
  Float::NAN
end
t_alloc, items = alloc_delta { pipeline(Teptris::TOML.load(src)) }

one_shot = []
10.times do
  t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  out = IO.popen([RbConfig.ruby, "-I#{File.expand_path('../lib', __dir__)}", "-e",
    'require "teptris"; require "tomlib"; ' \
    'src = File.read(ARGV[0]); ' \
    'Struct.new(:id, :name).new(Teptris::TOML.load(src).size, "x")',
    "--", path], &:read)
  one_shot << Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0 if $?.success?
end
one_shot.sort!

puts format("%-22s pipeline teptris %8.2f ms | tomlib %10.2f ms", File.basename(path),
            teptris_best * 1000, tomlib_best * 1000)
puts format("typed objects: %d; allocation delta: %d objects", items.size, t_alloc)
puts format("fresh-process one-shot median: %d ms (min %d, max %d)",
            (one_shot[one_shot.size / 2] * 1000).round,
            (one_shot.min * 1000).round, (one_shot.max * 1000).round)
