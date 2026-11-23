# frozen_string_literal: true

require "date"

require_relative "teptris/version"
require_relative "teptris/supported"
require_relative "teptris/error"
require_relative "teptris/descriptor"
require_relative "teptris/toml"
require_relative "teptris/schema"

# The native-layer contract (issue #197): one DOT-FREE bundle per
# ruby minor, FLAT under lib/teptris/ — native_<major>_<minor> — so
# coexistence across minors is exact and a wrong-minor load is
# structurally impossible (the compiled-in RString layout changed in
# 3.2 — the 3.1 segfault class; no unversioned fallback, ever). The
# native extension IS the binding — minors without a prebuilt cell
# ship via the source gem, which compiles AT INSTALL under the same
# name (extconf targets teptris/native_<maj>_<min>, so the installed
# bundle lands on the load path under the identical require string).
maj = RbConfig::CONFIG["MAJOR"]
min = RbConfig::CONFIG["MINOR"]
begin
  require "teptris/native_#{maj}_#{min}"
rescue LoadError
  raise LoadError,
        "teptris native extension for ruby #{RUBY_VERSION} not found " \
        "(#{RUBY_PLATFORM}; no fallback by design — install the source " \
        "gem: gem install teptris --platform ruby)"
end

module Teptris
  TEPTRIS_OK = 0
end
