require "date"

require_relative "error"

require_relative "version"

module Teptris
  # API shape mirrors the tomlib gem: load/dump, String keys, and the
  # tomlib datetime contract (Time with zone for offset datetimes, local
  # Time for local datetimes, Date for dates, String "HH:MM:SS" for
  # local times).
  module TOML
    class << self
      def load(toml)
        raise ArgumentError, "input must be a String" unless toml.is_a?(String)

        TeptrisExt.load(toml)
      end

      # Safe-load shaped entry point for frameworks: permitted_classes
      # restricts datetime materialization (raise when a value would
      # materialize an unpermitted class); datetime_policy :string keeps
      # every datetime kind as its canonical ISO string instead.
      def safe_load(toml, permitted_classes: nil, datetime_policy: :native)
        unless %i[native string].include?(datetime_policy)
          raise ArgumentError, "datetime_policy must be :native or :string"
        end
        opts = {}
        opts[:string_datetimes] = true if datetime_policy == :string
        if permitted_classes && datetime_policy == :native
          permitted = permitted_classes + [:__scalar]
          opts[:forbid_time] = true unless permitted.include?(Time)
          opts[:forbid_date] = true unless permitted.include?(Date)
        end
        load(toml) if opts.empty?
        TeptrisExt.load(toml, opts)
      end

      # One-pass schema materialization over a compiled
      # Teptris::Descriptor: unplanned keys are never materialized
      # (teptris#46).
      def load_schema(toml, descriptor)
        unless descriptor.is_a?(Teptris::Descriptor)
          raise ArgumentError,
                "descriptor must be a Teptris::Descriptor (use " \
                "Teptris::Descriptor.build), got #{descriptor.class}"
        end
        descriptor.walk(toml)
      end

      def engine_version
        TeptrisExt.engine_version
      end

      public

      def load_file(path)
        load(File.read(path))
      end

      def dump(obj)
        TeptrisExt.dump(obj)
      end
    end
  end
end
