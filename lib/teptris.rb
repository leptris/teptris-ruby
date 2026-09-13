require "date"

require_relative "teptris/version"
require_relative "teptris/error"
require_relative "teptris/toml"

# Windows ucrt rubies name their DLL per minor (x64-ucrt-ruby330.dll), so
# the mingw gems ship one extension per ruby minor beside a shared
# libteptris.dll (nokogiri's fat-gem layout). The native extension IS the
# binding — no fallback, ever.
begin
  if RUBY_PLATFORM =~ /mingw/
    require "teptris/#{RUBY_VERSION[/\A\d+\.\d+/]}/teptris_ext"
  else
    require "teptris_ext"
  end
rescue LoadError
  raise LoadError,
        "teptris native extension not available for #{RUBY_PLATFORM} " \
        "ruby #{RUBY_VERSION} (no fallback by design)"
end

module Teptris
  TEPTRIS_OK = 0
end
