require "date"

require_relative "error"
require_relative "lib"
require_relative "version"

module Teptris
  # API shape mirrors the tomlib gem: load/dump, String keys, and the
  # tomlib datetime contract (Time with zone for offset datetimes, local
  # Time for local datetimes, Date for dates, String "HH:MM:SS" for
  # local times).
  module TOML
    class << self
      def load(toml)
        parse_and_materialize(toml, 0, nil)
      end

      # Safe-load shaped entry point for frameworks: permitted_classes
      # restricts datetime materialization (raise when a value would
      # materialize an unpermitted class); datetime_policy :string keeps
      # every datetime kind as its canonical ISO string instead.
      def safe_load(toml, permitted_classes: nil, datetime_policy: :native)
        unless %i[native string].include?(datetime_policy)
          raise ArgumentError, "datetime_policy must be :native or :string"
        end
        mode = datetime_policy == :string ? 1 : 0
        permitted = permitted_classes && Set.new(permitted_classes)
        if permitted && mode.zero?
          permitted << String # TOML scalars are always materialized
        end
        parse_and_materialize(toml, mode, permitted)
      end

      # Reserved: fused descriptor materialization, the same descriptor
      # shape as leptris/yeptris#238 — see docs/DESCRIPTOR_ABI.md. The
      # entry point exists so frameworks can code against it today; the
      # fused native pass lands with the co-designed ABI.
      def load_schema(toml, descriptor)
        raise Error,
              "descriptor materialization lands with the co-designed " \
              "ABI (leptris/yeptris#238); entry point is reserved — " \
              "see docs/DESCRIPTOR_ABI.md (descriptor #{descriptor.class})"
      end

      private

      def parse_and_materialize(toml, mode, permitted)
        raise ArgumentError, "input must be a String" unless toml.is_a?(String)

        data = FFI::MemoryPointer.from_string(toml)
        docp = FFI::MemoryPointer.new(:pointer)
        st = Lib.teptris_parse(data, toml.bytesize, nil, docp)
        handle = docp.read_pointer
        if st != Teptris::TEPTRIS_OK
          raise build_parse_error(handle)
        end
        begin
          @mode = mode
          @permitted = permitted
          load_flat(handle)
        ensure
          @mode = nil
          @permitted = nil
          Lib.teptris_document_free(handle)
        end
      end

      public

      def load_file(path)
        load(File.read(path))
      end

      def dump(obj)
        raise ArgumentError, "cannot dump #{obj.class}" unless obj.is_a?(Hash)

        out = +""
        emit_table(obj, out, nil)
        out
      end

      private

      def build_parse_error(handle)
        line = 0
        column = 0
        msg = "parse failed"
        unless handle.null?
          es = Lib::ErrorStruct.new(Lib.teptris_document_error(handle))
          line = es[:line]
          column = es[:column]
          msg = es[:message]
        end
        ParseError.new(msg, line, column)
      end

      # One-bulk-drain load: the C side flattens the whole tree in a
      # single crossing; this decoder walks the typed flat buffer.
      FLAT_TABLE = 0x01
      FLAT_ARRAY = 0x02
      FLAT_STRING = 0x03
      FLAT_INT = 0x04
      FLAT_FLOAT = 0x05
      FLAT_FALSE = 0x06
      FLAT_TRUE = 0x07
      FLAT_DT = 0x08 # ..0x0B: offset, local-datetime, date, local-time

      def load_flat(handle)
        bufp = FFI::MemoryPointer.new(:pointer)
        lenp = FFI::MemoryPointer.new(:size_t)
        st = Lib.teptris_document_flatten(handle, bufp, lenp)
        raise Error, "flatten failed" unless st == Teptris::TEPTRIS_OK

        buf = bufp.read_pointer
        begin
          data = buf.get_bytes(0, lenp.read_uint64)
          value, = decode_flat(data, 0)
          value
        ensure
          Lib.teptris_flatten_free(buf)
        end
      end

      def decode_flat(d, pos)
        case d.getbyte(pos)
        when FLAT_TABLE
          n = d.unpack1("L<", offset: pos + 1)
          pos += 5
          h = {}
          n.times do
            kl = d.unpack1("L<", offset: pos)
            pos += 4
            k = d.byteslice(pos, kl).force_encoding(Encoding::UTF_8)
            pos += kl
            v, pos = decode_flat(d, pos)
            h[k] = v
          end
          [h, pos]
        when FLAT_ARRAY
          n = d.unpack1("L<", offset: pos + 1)
          pos += 5
          a = Array.new(n)
          n.times do |i|
            a[i], pos = decode_flat(d, pos)
          end
          [a, pos]
        when FLAT_STRING
          l = d.unpack1("L<", offset: pos + 1)
          pos += 5
          [d.byteslice(pos, l).force_encoding(Encoding::UTF_8), pos + l]
        when FLAT_INT
          [d.unpack1("q<", offset: pos + 1), pos + 9]
        when FLAT_FLOAT
          [d.unpack1("E", offset: pos + 1), pos + 9]
        when FLAT_FALSE then [false, pos + 1]
        when FLAT_TRUE then [true, pos + 1]
        when FLAT_DT, FLAT_DT + 1, FLAT_DT + 2, FLAT_DT + 3
          kind = d.getbyte(pos)
          year = d.unpack1("q<", offset: pos + 1)
          mon = d.getbyte(pos + 9)
          day = d.getbyte(pos + 10)
          hour = d.getbyte(pos + 11)
          min = d.getbyte(pos + 12)
          sec = d.getbyte(pos + 13)
          nsec = d.unpack1("L<", offset: pos + 14)
          off = d.unpack1("q<", offset: pos + 18)
          [flat_datetime(kind, year, mon, day, hour, min, sec, nsec, off),
           pos + 26]
        else
          raise Error, "corrupt flat buffer at #{pos}"
        end
      end

      def flat_datetime(kind, y, mon, day, hour, min, sec, nsec, off)
        return flat_datetime_string(kind, y, mon, day, hour, min, sec, nsec, off) if @mode == 1

        rational = Rational(sec * 1_000_000_000 + nsec, 1_000_000_000)
        case kind
        when FLAT_DT
          check_permitted!(Time)
          Time.new(y, mon, day, hour, min, rational, off)
        when FLAT_DT + 1
          check_permitted!(Time)
          Time.local(y, mon, day, hour, min, rational)
        when FLAT_DT + 2
          check_permitted!(Date)
          Date.new(y, mon, day)
        else
          s = format("%02d:%02d:%02d", hour, min, sec)
          s << "." << format("%09d", nsec).sub(/0+\z/, "") if nsec.positive?
          s
        end
      end

      def check_permitted!(klass)
        permitted = @permitted
        return if permitted.nil? || permitted.include?(klass)

        raise Error,
              "value materializes #{klass}, which is not in " \
              "permitted_classes (use datetime_policy: :string to keep " \
              "datetimes as strings)"
      end

      def flat_datetime_string(kind, y, mon, day, hour, min, sec, nsec, off)
        case kind
        when FLAT_DT + 2 then return format("%04d-%02d-%02d", y, mon, day)
        when FLAT_DT + 3 then s = +""
        else s = +(format("%04d-%02d-%02dT", y, mon, day))
        end
        s << format("%02d:%02d:%02d", hour, min, sec)
        if nsec.positive?
          s << "." << format("%09d", nsec).sub(/0+\z/, "")
        end
        case kind
        when FLAT_DT
          off.zero? ? s << "Z" : s << format("%+03d:%02d", off / 3600, (off % 3600).abs / 60)
        end
        s
      end

      # ---- dump -----------------------------------------------------------

      def emit_table(hash, out, prefix)
        hash.each do |k, v|
          next if table?(v) || aot?(v)

          out << emit_key(k) << " = " << emit_value(v) << "\n"
        end
        hash.each do |k, v|
          next unless table?(v) || aot?(v)

          path = prefix ? "#{prefix}.#{emit_key(k)}" : emit_key(k)
          if aot?(v)
            v.each do |item|
              out << "[[" << path << "]]\n"
              emit_table(item, out, path)
            end
          else
            out << "[" << path << "]\n"
            emit_table(v, out, path)
          end
        end
      end

      def table?(v)
        v.is_a?(Hash)
      end

      def aot?(v)
        v.is_a?(Array) && !v.empty? && v.all? { |e| e.is_a?(Hash) }
      end

      def emit_key(k)
        k = k.to_s
        if /\A[A-Za-z0-9_-]+\z/.match?(k)
          k
        elsif !k.include?("'") && !k.each_char.any? { |c| c.ord < 0x20 }
          "'#{k}'"
        else
          "\"#{escape_basic(k)}\""
        end
      end

      BASIC_ESCAPES = {
        "\\" => "\\\\\\\\", # \ -> \\
        "\"" => "\\\"", "\b" => "\\b", "\f" => "\\f",
        "\n" => "\\n", "\r" => "\\r", "\t" => "\\t"
      }.freeze

      def escape_basic(s)
        s.gsub(/[\\\"\b\f\n\r\t]/) { |c| BASIC_ESCAPES[c] }
      end

      def emit_value(v)
        case v
        when String
          if !v.include?("'") && !v.each_char.any? { |c| c.ord < 0x20 }
            "'#{v}'"
          else
            "\"#{escape_basic(v)}\""
          end
        when Integer then v.to_s
        when Float
          return v.to_s if v.finite?

          v.nan? ? "nan" : (v.positive? ? "inf" : "-inf")
        when TrueClass then "true"
        when FalseClass then "false"
        when Time
          base = v.strftime("%Y-%m-%dT%H:%M:%S")
          frac = v.strftime("%N").sub(/0+\z/, "")
          base << "." << frac unless frac.empty?
          base << tz(v)
        when Date then v.iso8601
        when Array then "[#{v.map { |e| emit_value(e) }.join(', ')}]"
        when Hash
          "{#{v.map { |k, e| "#{emit_key(k)} = #{emit_value(e)}" }.join(', ')}}"
        else raise Error, "cannot dump #{v.class}"
        end
      end

      def tz(time)
        off = time.utc_offset
        return "Z" if off.zero?

        sign = off.negative? ? "-" : "+"
        off = -off if off.negative?
        format("%s%02d:%02d", sign, off / 3600, (off % 3600) / 60)
      end
    end
  end
end
