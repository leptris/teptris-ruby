require "date"

require_relative "teptris/version"
require_relative "teptris/error"
require_relative "teptris/toml"
require "teptris_ext" # the native extension IS the binding (no fallback)

module Teptris
  TEPTRIS_OK = 0
end
