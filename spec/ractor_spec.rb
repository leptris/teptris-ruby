require "spec_helper"

RSpec.describe "Ractor", if: defined?(Ractor) && Ractor.instance_methods.include?(:take) do
  it "loads TOML inside a non-main Ractor" do
    r = Ractor.new do
      Teptris::TOML.load("a = 1\n[x]\nb = 2\n")
    end
    expect(r.take).to eq({ "a" => 1, "x" => { "b" => 2 } })
  end

  it "dumps inside a non-main Ractor" do
    r = Ractor.new do
      Teptris::TOML.dump({ "k" => [1, 2], "t" => { "s" => "v" } })
    end
    expect(r.take).to eq("k = [1, 2]\n[t]\ns = 'v'\n")
  end
end
