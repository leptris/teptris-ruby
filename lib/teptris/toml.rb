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

      # Lazy load: returns a wrapper that parses eagerly (one pass)
      # but materializes host objects only along the paths actually
      # accessed. Same datetime contract as load; to_h/to_a flatten to
      # the eager shape.
      def load_lazy(toml)
        raise ArgumentError, "input must be a String" unless toml.is_a?(String)

        TeptrisExt.load_lazy(toml)
      end

      # Many-small batch path (teptris-ruby#108 ask 3): parse N inputs
      # in one C call, share the safe_load/datetime_policy options
      # struct across the batch, return one eager Hash per document.
      # Same datetime contract as load. A failing document raises
      # Teptris::ParseError carrying the first failure's line/column.
      def load_batch(tomls, safe_load: nil, datetime_policy: :native)
        _validate_batch!(tomls, safe_load, datetime_policy)
        TeptrisExt.load_batch(tomls, _safe_load_opts(safe_load, datetime_policy))
      end

      # Lazy twin of load_batch: parse N inputs eagerly, hand back an
      # Array of Lazy wrappers — materialization happens only on access.
      # Same per-doc error semantics as load_lazy (first failure raises).
      def load_lazy_batch(tomls)
        _validate_batch!(tomls, nil, :native)
        TeptrisExt.load_lazy_batch(tomls)
      end

      # Many-small path with file paths: read each file, then call
      # load_batch. Symmetric with load_file's single-doc shape.
      def load_files(paths, safe_load: nil, datetime_policy: :native)
        _validate_batch!(paths, safe_load, datetime_policy, kind: :paths)
        load_batch(paths.map { |p| File.read(p) },
                   safe_load: safe_load, datetime_policy: datetime_policy)
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

      private

      def _validate_batch!(input, safe_load, datetime_policy, kind: :strings)
        unless input.is_a?(Array)
          raise ArgumentError, "expected Array of #{kind}, got #{input.class}"
        end
        if !safe_load.nil? && !safe_load.is_a?(Array) && !safe_load.is_a?(Symbol)
          raise ArgumentError, "safe_load must be nil, an Array, or a Symbol"
        end
        unless %i[native string].include?(datetime_policy)
          raise ArgumentError, "datetime_policy must be :native or :string"
        end
      end

      def _safe_load_opts(safe_load, datetime_policy)
        opts = {}
        opts[:string_datetimes] = true if datetime_policy == :string
        if safe_load && datetime_policy == :native
          permitted = Array(safe_load) + [:__scalar]
          opts[:forbid_time] = true unless permitted.include?(Time)
          opts[:forbid_date] = true unless permitted.include?(Date)
        end
        opts.empty? ? nil : opts
      end
    end
  end
end
