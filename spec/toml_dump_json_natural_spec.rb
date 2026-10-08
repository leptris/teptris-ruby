require_relative "spec_helper"
require "date"
require "json"

# Natural-JSON dump (engine 0.3.0): the JSON a host actually wants —
# real numbers, booleans, RFC 3339 datetime strings. The two
# deliberate, documented lossy mappings: non-finite floats become
# null, and a datetime is indistinguishable from a same-shaped
# string (mirrors teptris.h's natural-JSON contract).
RSpec.describe "Teptris::TOML.dump_json_natural" do
  it "emits native JSON types for scalars" do
    obj = { "i" => 42, "f" => 3.5, "t" => true, "fa" => false,
            "s" => "hi" }
    expect(JSON.parse(Teptris::TOML.dump_json_natural(obj)))
      .to eq("i" => 42, "f" => 3.5, "t" => true, "fa" => false,
             "s" => "hi")
  end

  it "maps datetimes to RFC 3339 strings" do
    obj = { "at" => Time.utc(2026, 10, 9, 12, 34, 56),
            "d" => Date.new(2026, 10, 9) }
    json = JSON.parse(Teptris::TOML.dump_json_natural(obj))
    expect(json["at"]).to eq("2026-10-09T12:34:56Z")
    expect(json["d"]).to eq("2026-10-09")
  end

  it "maps non-finite floats to null (documented lossy mapping)" do
    obj = { "nan" => Float::NAN, "inf" => Float::INFINITY,
            "finite" => 1.0 }
    json = JSON.parse(Teptris::TOML.dump_json_natural(obj))
    expect(json["nan"]).to be_nil
    expect(json["inf"]).to be_nil
    expect(json["finite"]).to eq(1.0)
  end

  it "round-trips nested tables, arrays and arrays of tables" do
    obj = { "title" => "x",
            "nums" => [1, 2, 3],
            "nest" => { "deep" => { "v" => false } },
            "rows" => [{ "id" => 1 }, { "id" => 2 }] }
    expect(JSON.parse(Teptris::TOML.dump_json_natural(obj))).to eq(obj)
  end

  it "views a loaded document losslessly (except datetimes-as-strings)" do
    doc = <<~TOML
      title = "demo"
      [owner]
      name = "ron"
      dob = 2026-10-09T10:00:00Z
      [[items]]
      id = 1
      tags = ["a", "b"]
    TOML
    json = JSON.parse(Teptris::TOML.dump_json_natural(Teptris::TOML.load(doc)))
    expect(json).to eq("title" => "demo",
                       "owner" => { "name" => "ron",
                                    "dob" => "2026-10-09T10:00:00Z" },
                       "items" => [{ "id" => 1, "tags" => %w[a b] }])
  end

  it "rejects non-Hash roots like Teptris.dump" do
    expect { Teptris::TOML.dump_json_natural([1, 2]) }
      .to raise_error(ArgumentError, /root must be a Hash/)
  end
end
