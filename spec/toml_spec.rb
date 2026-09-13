require_relative "spec_helper"

RSpec.describe Teptris::TOML do
  it "loads scalars" do
    expect(described_class.load("a = 1\nb = 1.5\nc = 'x'\nd = true\ne = [1, 2]"))
      .to eq("a" => 1, "b" => 1.5, "c" => "x", "d" => true, "e" => [1, 2])
  end

  it "loads nested tables and arrays of tables in order" do
    doc = described_class.load(<<~TOML)
      root = true
      [a]
      x = 1
      [[aot]]
      n = "first"
      [[aot]]
      n = "second"
    TOML
    expect(doc).to eq("root" => true, "a" => {"x" => 1},
                      "aot" => [{"n" => "first"}, {"n" => "second"}])
  end

  it "maps datetimes per the tomlib contract" do
    doc = described_class.load(<<~TOML)
      o = 1979-05-27T07:32:00Z
      l = 1979-05-27T07:32:00
      d = 1979-05-27
      t = 07:32:00
    TOML
    expect(doc["o"]).to be_a(Time)
    expect(doc["o"].utc).to eq(Time.utc(1979, 5, 27, 7, 32, 0))
    expect(doc["l"]).to be_a(Time)
    expect(doc["d"]).to eq(Date.new(1979, 5, 27))
    expect(doc["t"]).to eq("07:32:00")
  end

  it "keeps utf-8 and escape handling intact" do
    expect(described_class.load(%(s = "\\u00e9\\n"))).to eq("s" => "é\n")
  end

  it "raises ParseError with line and column" do
    expect { described_class.load("a = 1\nb = ?\n") }
      .to raise_error(Teptris::ParseError) do |e|
        expect(e.line).to eq(2)
        expect(e.column).to eq(5)
      end
  end

  it "dumps and roundtrips" do
    obj = {"title" => "teptris", "nested" => {"x" => 1},
           "aot" => [{"n" => 1}, {"n" => 2}], "f" => 1.5}
    expect(described_class.load(described_class.dump(obj))).to eq(obj)
  end

  it "dumps times and dates" do
    obj = {"at" => Time.utc(2026, 9, 13, 8, 0, 0), "on" => Date.new(2026, 9, 13)}
    expect(described_class.dump(obj))
      .to eq("at = 2026-09-13T08:00:00Z\non = 2026-09-13\n")
  end

  describe "parity with tomlib", if: defined?(Tomlib) do
    cases = [
      "a = 1\nb = -2\nc = 0xFF\n",
      "s = 'lit'\nt = \"esc\\t\"\n",
      "f = 3.14\ng = 1e6\n",
      "[t]\nx = 1\n[t.u]\ny = [1, 2]\n",
      "[[a]]\nn = 1\n[[a]]\nn = 2\n",
      "d = 1979-05-27\no = 1979-05-27T07:32:00Z\nl = 1979-05-27T07:32:00\nt = 07:32:00\n",
      "k.'quoted key' = 1\n",
    ]
    cases.each_with_index do |toml, i|
      it "matches tomlib on case #{i}" do
        require "tomlib"
        expect(described_class.load(toml)).to eq(Tomlib.load(toml))
      end
    end
  end
end
