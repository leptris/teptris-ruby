# frozen_string_literal: true

require "teptris"

RSpec.describe "Teptris::TOML.load_lazy" do
  let(:src) do
    <<~TOML
      title = "lazy"
      owner.name = "inherited"
      [database]
      enabled = true
      ports = [8001, 8001, 8002]
      [servers.alpha]
      ip = "10.0.0.1"
    TOML
  end

  it "materializes scalars on access without building the tree" do
    d = Teptris::TOML.load_lazy(src)
    expect(d.kind).to eq(:table)
    expect(d["title"].value).to eq("lazy")
    expect(d.dig("database", "enabled").value).to eq(true)
  end

  it "keeps containers lazy until flattened" do
    d = Teptris::TOML.load_lazy(src)
    expect(d["servers"].kind).to eq(:table)
    expect(d.dig("servers", "alpha", "ip").value).to eq("10.0.0.1")
    expect(d["servers"]["alpha"].to_h).to eq("ip" => "10.0.0.1")
  end

  it "flattens to the eager shape" do
    lazy = Teptris::TOML.load_lazy(src).to_h
    eager = Teptris::TOML.load(src)
    expect(lazy).to eq(eager)
  end

  it "survives GC between accesses (owner holds doc + input)" do
    d = Teptris::TOML.load_lazy(src)
    GC.start
    expect(d.dig("database", "ports", 2).value).to eq(8002)
  end

  it "answers nil for absent keys" do
    d = Teptris::TOML.load_lazy(src)
    expect(d["nope"]).to be_nil
    expect(d.dig("database", "nope")).to be_nil
  end

  it "raises ParseError like load on malformed input" do
    expect { Teptris::TOML.load_lazy("a = [1,") }
      .to raise_error(Teptris::ParseError)
  end
end
