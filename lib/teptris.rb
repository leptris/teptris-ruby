require "date"

require_relative "teptris/version"
require_relative "teptris/error"
require_relative "teptris/descriptor"
require_relative "teptris/toml"

# Fat-gem layout on EVERY platform (nokogiri's shape): one extension
# per ruby minor under lib/teptris/<minor>/ — ucrt rubies bind a
# minor-named DLL, and a unix .so built for one minor fails dlopen on
# another (a 3.3-built ext hard-failed under ruby 4.0 with the gem
# already installed). The native extension IS the binding — no
# fallback, ever; minors without a prebuilt cell ship via the source
# gem, which compiles at install.
minor = RUBY_VERSION[/\A\d+\.\d+/]
begin
  # fat prebuilt gems: lib/teptris/<minor>/teptris_ext
  require "teptris/#{minor}/teptris_ext"
rescue LoadError
  begin
    # source-built installs: rubygems puts the compiled ext on the
    # load path under its bare name (no <minor> dir exists)
    require "teptris_ext"
  rescue LoadError
    raise LoadError,
          "teptris native extension for ruby #{RUBY_VERSION} not found " \
          "(#{RUBY_PLATFORM}; no fallback by design — install the source " \
          "gem: gem install teptris --platform ruby)"
  end
end

module Teptris
  TEPTRIS_OK = 0
end
