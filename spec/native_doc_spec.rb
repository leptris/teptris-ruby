# frozen_string_literal: true

require "date"
require_relative "spec_helper"

RSpec.describe "native-doc API" do
  let(:src) do
    %(a = 1
[t]
k = 07:32
[[fruit]]
name = "apple"
)
  end

  it "roundtrips doc -> TOML -> hash at C speed" do
    out = Teptris::TOML.dump_doc(Teptris::TOML.load_doc(src))
    expect(Teptris::TOML.load(out)).to eq(
      "a" => 1,
      "t" => { "k" => "07:32:00" }, # canonical time form on reparse
      "fruit" => [{ "name" => "apple" }]
    )
  end

  it "re-emits canonically (byte-stable)" do
    doc = Teptris::TOML.load_doc(src)
    once = Teptris::TOML.dump_doc(doc)
    twice = Teptris::TOML.dump_doc(Teptris::TOML.load_doc(once))
    expect(twice).to eq(once)
  end

  it "keeps the doc alive across GC (values are views into its input)" do
    doc = Teptris::TOML.load_doc(src)
    GC.start
    GC.start
    dumped = Teptris::TOML.dump_doc(doc)
    expect(Teptris::TOML.load(dumped)["fruit"][0]["name"]).to eq("apple")
  end

  it "raises ParseError with line/column on bad input" do
    raised = nil
    begin
      Teptris::TOML.load_doc("a = ")
    rescue Teptris::ParseError => e
      raised = e
    end
    expect(raised).to be_a(Teptris::ParseError)
    expect(raised.line).to eq(1)
    expect(raised.column).to eq(5)
  end

  it "rejects non-string input" do
    expect { Teptris::TOML.load_doc(42) }.to raise_error(ArgumentError)
  end

  it "rejects a non-doc in dump_doc" do
    expect { Teptris::TOML.dump_doc("not a doc") }.to raise_error(TypeError)
  end
end
