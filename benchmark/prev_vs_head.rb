# HEAD-vs-previous binding regression check: measures load/dump
# throughput + GC allocations on the serialbench documents with
# $LOAD_PATH pointed at a gem tree (previous release) or a repo
# lib/ tree (HEAD). Usage:
#   ruby benchmark/prev_vs_head.rb /tmp/prev-gem-dir prev
#   ruby benchmark/prev_vs_head.rb lib head
# The workflow compares the two "head"/"prev" outputs and fails on a
# >10% throughput regression (allocations are reported, not gated).
lib = ARGV[0] or abort "usage: prev_vs_head.rb <lib-or-gem-dir> <label>"
label = ARGV[1] || lib
$LOAD_PATH.unshift File.expand_path(lib)
require "teptris"

def small_doc
  <<~TOML
    title = "bench"
    [owner]
    name = "a"
    active = true
    ratio = 1.5
  TOML
end

def medium_doc
  out = +""
  120.times do |t|
    out << "[table.#{t}]\n"
    8.times { |i| out << "k#{i} = #{i * 7}\ns#{i} = \"v#{i}\"\nf#{i} = #{i}.25\n" }
  end
  out
end

def large_doc
  out = +""
  800.times do |t|
    out << "[table.#{t}]\n"
    4.times { |i| out << "k#{i} = #{i * 7}\n" }
  end
  out
end

SMALL = small_doc
MEDIUM = medium_doc
LARGE = large_doc

# parse each document once for warmup/shape, then measure fixed work
def throughput(seconds: 0.6)
  t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  ops = 0
  while Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0 < seconds
    yield
    ops += 1
  end
  ops / (Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0)
end

def allocations
  before = GC.stat(:total_allocated_objects)
  yield
  GC.stat(:total_allocated_objects) - before
end

# medians of 3 rounds per metric: single short samples swing too
# widely to gate on (the engine lane's lesson, applied here)
def median3
  xs = 3.times.map { yield }.sort
  xs[1]
end

results = {}
{
  "load_small" => -> { Teptris::TOML.load(SMALL) },
  "load_medium" => -> { Teptris::TOML.load(MEDIUM) },
  "load_large" => -> { Teptris::TOML.load(LARGE) },
  "dump_medium" => -> { Teptris::TOML.dump(Teptris::TOML.load(MEDIUM)) },
}.each do |name, blk|
  blk.call # warmup
  results[name] = median3 { throughput(&blk) }.round(1)
end
results["alloc_load_large"] = allocations { Teptris::TOML.load(LARGE) }

results.each { |k, v| puts "#{label} #{k} #{v}" }
