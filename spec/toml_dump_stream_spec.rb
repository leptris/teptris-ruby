require "spec_helper"

RSpec.describe "stream dump edge behaviors" do
  cases = {
    "empty table value" => [{ "k" => {} }, "[k]\n"],
    "empty array" => [{ "k" => [] }, "k = []\n"],
    "aot one" => [{ "k" => [{ "x" => 1 }] }, "[[k]]\nx = 1\n"],
    "aot empty element" => [{ "k" => [{}] }, "[[k]]\n"],
    "mixed array" => [{ "k" => [1, { "x" => 2 }] }, "k = [1, {x = 2}]\n"],
    "nested in aot" => [{ "k" => [{ "x" => 1, "s" => { "y" => 2 } }] },
                        "[[k]]\nx = 1\n[k.s]\ny = 2\n"],
    "scalar after section" => [{ "t" => { "b" => 2 }, "z" => 9 },
                               "z = 9\n[t]\nb = 2\n"],
    "nan inf" => [{ "n" => Float::NAN, "i" => Float::INFINITY },
                  "n = nan\ni = inf\n"],
    "floats" => [{ "f1" => 1.0, "f2" => -0.5, "f3" => 1e100, "f4" => 3.14 },
                 "f1 = 1.0\nf2 = -0.5\nf3 = 1e100\nf4 = 3.14\n"],
    "deep inline" => [{ "n" => [[1, 2], { "arr" => [false] }] },
                      "n = [[1, 2], {arr = [false]}]\n"],
    "quoted keys nested" => [{ "a b" => 1, "x.y" => 2, "" => 3,
                               "q\"q" => { "in'ner" => { "v" => 4 } } },
                             "'a b' = 1\n'x.y' = 2\n'' = 3\n" \
                             "['q\"q']\n['q\"q'.\"in'ner\"]\nv = 4\n"],
    # a Hash value under a table key is always a [section], never an
    # inline table — the shipped dump contract
    "hash inside inline table" =>
      [{ "t" => { "x" => { "y" => 2 }, "z" => 1 } },
       "[t]\nz = 1\n[t.x]\ny = 2\n"]
  }

  cases.each do |name, (obj, expected)|
    it "dumps #{name}" do
      expect(Teptris::TOML.dump(obj)).to eq(expected)
    end
  end

  it "roundtrips every corpus shape" do
    Dir[File.expand_path("../../teptris/bench-corpus/*.toml", __dir__)].sort.each do |path|
      obj = Teptris::TOML.load(File.read(path))
      once = Teptris::TOML.dump(obj)
      twice = Teptris::TOML.dump(Teptris::TOML.load(once))
      expect(twice).to eq(once)
    end
  end

  it "rejects non-hash roots and undumpable values" do
    expect { Teptris::TOML.dump([1]) }.to raise_error(ArgumentError)
    expect { Teptris::TOML.dump("k" => Object.new) }
      .to raise_error(Teptris::Error, /cannot dump Object/)
  end
end
