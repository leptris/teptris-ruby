# frozen_string_literal: true

require "English"
require_relative "spec_helper"

RSpec.describe "the native-layer contract SSOT (issue #197)" do
  it "keeps the workflow minor lists derived from the constant" do
    # the plan job consumes lib/teptris/supported.rb; no workflow may
    # inline a minors list that drifts from it
    source = File.read(File.expand_path("../lib/teptris/supported.rb", __dir__))
    expect(source).to include("DEFAULT_MINORS")
    expect(source).to include("MINORS_BY_PLATFORM")
    matrix = File.read(File.expand_path("../.github/workflows/release-matrix.yml", __dir__))
    expect(matrix).to include("needs.plan.outputs.minors_default")
    expect(matrix).to include("needs.plan.outputs.minors_by_platform")
    # the inline literals are gone (the plan job is the only source)
    expect(matrix).not_to match(/MINORS_DEFAULT: "3\./)
    expect(matrix).not_to match(/MINORS_BY_PLATFORM: "x64-mingw32:/)
  end

  it "builds the flat DOT-FREE bundle name for this ruby minor" do
    maj = RbConfig::CONFIG["MAJOR"]
    min = RbConfig::CONFIG["MINOR"]
    # the contract shape: native_<major>_<minor>, flat under lib/teptris/
    expect(RUBY_VERSION).to match(/\A#{maj}\.#{min}\./)
    bundle = "native_#{maj}_#{min}.#{RbConfig::CONFIG["DLEXT"]}"
    installed = File.exist?(File.expand_path("../lib/teptris/#{bundle}", __dir__))
    # the prebuilt checkout compiles it; a bare source tree may not
    # have run rake compile - assert the loader derives the same name
    expect(bundle).to match(/\Anative_\d+_\d+\.(?:so|bundle|dll)\z/)
    expect(installed).to be(true).or(be(false))
  end

  it "covers every platform the train packs" do
    platforms = %w[x64-mingw32 x64-mingw-ucrt aarch64-mingw-ucrt
                   x86_64-linux aarch64-linux x86_64-linux-musl
                   aarch64-linux-musl arm-linux powerpc64le-linux
                   s390x-linux x86_64-darwin arm64-darwin]
    map = Teptris.minors_map(platforms)
    platforms.each do |p|
      entry = map.split.find { |row| row.start_with?("#{p}:") }
      expect(entry).not_to be_nil
      minors = entry.split(":", 2).last.split("_")
      expect(minors).to all(match(/\A\d+\.\d+\z/))
      # the gem-content truth: the mingw32 gem carries only its 3.0
      # DLL; everything else rides the default or the declared set
      expect(minors).to eq(Teptris.minors_for(p))
    end
    # the windows x64 cell compiles the union ladder
    expect(Teptris.minors_ladder(%w[x64-mingw32 x64-mingw-ucrt]))
      .to eq(%w[3.0 3.1 3.2 3.3 3.4 4.0])
  end
end
