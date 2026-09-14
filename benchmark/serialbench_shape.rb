# serialbench-shaped comparison (teptris-ruby#28): parse/dump ips and
# GC allocation totals for small/medium/large documents vs tomlib.
#   ruby benchmark/serialbench_shape.rb
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "teptris"
require "tomlib"

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
    8.times { |i| out << "k#{i} = #{i * 7}\ns#{i} = \"value #{i}\"\nf#{i} = #{i}.25\n" }
  end
  out
end

def ips_of(call, arg)
  call.call(arg)
  best = Float::INFINITY
  batch = [1000, 100, 10].find { |b| b.times { call.call(arg) }; true } rescue 1000
  # calibrate batch so one batch lands well above clock resolution
  t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  1000.times { call.call(arg) }
  per = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) / 1000.0
  batch = per < 5e-5 ? 1000 : (per < 5e-4 ? 100 : 10)
  t_end = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 1.0
  loop do
    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    batch.times { call.call(arg) }
    dt = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) / batch
    best = dt if dt < best
    break if Process.clock_gettime(Process::CLOCK_MONOTONIC) > t_end
  end
  1.0 / best
end

def alloc_delta(call, arg)
  GC.disable
  GC.start
  before = GC.stat(:total_allocated_objects)
  10.times { call.call(arg) }
  after = GC.stat(:total_allocated_objects)
  GC.enable
  after - before
end

t_load = ->(s) { Teptris::TOML.load(s) }
l_load = ->(s) { Tomlib.load(s) }

[["small", small_doc], ["medium", medium_doc], ["large", large_doc]].each do |name, doc|
  t_dump = ->(o) { Teptris::TOML.dump(o) }
  l_dump = ->(o) { Tomlib.dump(o) }
  tp = ips_of(t_load, doc); lp = ips_of(l_load, doc)
  td = ips_of(t_dump, Teptris::TOML.load(doc)); ld = ips_of(l_dump, Tomlib.load(doc))
  ta = alloc_delta(t_load, doc); la = alloc_delta(l_load, doc)
  printf("%-6s doc=%4dkB | parse teptris=%8.0f tomlib=%8.0f (%5.2fx) | " \
         "dump teptris=%8.0f tomlib=%8.0f (%5.2fx) | objs/10 parse teptris=%6d tomlib=%6d (%4.2fx)\n",
         name, doc.bytesize / 1024, tp, lp, tp / lp, td, ld, td / ld, ta, la, ta.to_f / la)
end
