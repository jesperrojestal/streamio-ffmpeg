module FFMPEG
  # parse FFmpeg JSON output and ensure types where value migbt be string
  module JSON
    module_function ############################################################

    def parse(obj)
      case obj
      when Hash
        hash(obj)
      when Array
        array(obj)
      when String
        string(obj)
      else
        obj
      end
    end

    def string(obj)
      case obj
      when /^\s*(true)\s*$/
        true
      when /^\s*(false)\s*$/
        false
      when /^\s*[+-]?((\d+_?)*\d+\s*)$/ # Integer
        Integer(obj)
      when /^\s*[+-]?((\d+_?)*\d+(\.(\d+_?)*\d+)?|\.(\d+_?)*\d+)(\s*|([eE][+-]?(\d+_?)*\d+)\s*)$/ # Float
        Float(obj)
      when %r{^\s*([+-]?(\d+_?)*\d+\/[+-]?(\d+_?)*\d+\s*)$} # Rational
        begin
          Rational(obj)
        rescue ZeroDivisionError
          0
        end
      else
        obj
      end
    end

    def hash(obj)
      Hash[obj.map { |key, value| [key, parse(value)] }]
    end

    def array(obj)
      obj.map { |value| parse(value) }
    end
  end
end
