require 'time'
require 'uri'
require 'multi_json'

module FFMPEG
  # read movie metadata
  class Movie
    attr_reader :metadata
    attr_reader :path, :duration, :time, :bitrate, :rotation, :creation_time
    attr_reader :format, :container
    attr_reader :video_stream, :video_codec, :video_bitrate, :video_profile, :colorspace, :width, :height, :sar, :dar, :frame_rate
    attr_reader :audio_stream, :audio_codec, :audio_bitrate, :audio_sample_rate, :audio_channels

    def initialize(path)
      if path =~ URI.regexp
        URI.parse(path)
      else
        raise Errno::ENOENT, "the file '#{path}' does not exist" unless File.exist?(path)
      end

      @path = path

      # ffmpeg will output to stderr
      command = "#{FFMPEG.ffprobe_binary} -i #{Shellwords.escape(path)} -print_format json -show_format -show_streams -show_error -hide_banner"
      std_output = ''
      std_error = ''

      Open3.popen3(command) do |_stdin, stdout, stderr|
        std_output = stdout.read unless stdout.nil?
        std_error = stderr.read  unless stderr.nil?
      end

      fix_encoding(std_output)

      @metadata = parse_metadata(std_output)

      if @metadata.key?(:error)
        @duration = 0
      else
        video_streams = @metadata[:streams].select { |stream| stream.key?(:codec_type) && stream[:codec_type] == 'video' }
        audio_streams = @metadata[:streams].select { |stream| stream.key?(:codec_type) && stream[:codec_type] == 'audio' }

        @format        = @metadata[:format]

        @container     = @format[:format_name]
        @duration      = @format[:duration].to_f
        @time          = @format[:start_time].to_f
        @bitrate       = @format[:bit_rate].to_i
        @creation_time = Time.parse(@format[:tags][:creation_time]) if @format.key?(:tags) && @format[:tags].key?(:creation_time)

        unless video_streams.empty?
          # TODO: Handle multiple video codecs (is that possible?)
          video_stream = video_streams.first
          @video_codec   = video_stream[:codec_name]
          @video_profile = video_stream[:profile] if video_stream[:profile]
          @colorspace    = video_stream[:pix_fmt]
          @width         = video_stream[:width]
          @height        = video_stream[:height]
          @video_bitrate = video_stream[:bit_rate].to_i
          @sar           = video_stream[:sample_aspect_ratio]
          @dar           = video_stream[:display_aspect_ratio]
          @frame_rate    = Rational(video_stream[:avg_frame_rate]) unless video_stream[:avg_frame_rate] == '0/0'

          @video_stream = [
            video_stream[:codec_name],
            "(#{video_stream[:profile]})",
            "(#{video_stream[:codec_tag_string]} / #{video_stream[:codec_tag]})",
            colorspace,
            resolution,
            "[SAR #{sar} DAR #{dar}]"
          ].join(' ')

          @rotation = video_stream[:tags][:rotate].to_i if video_stream.key?(:tags) && video_stream[:tags].key?(:rotate)
        end

        unless audio_streams.empty?
          # TODO: Handle multiple audio codecs
          audio_stream = audio_streams.first
          @audio_channels       = audio_stream[:channels].to_i
          @audio_codec          = audio_stream[:codec_name]
          @audio_sample_rate    = audio_stream[:sample_rate].to_i
          @audio_bitrate        = audio_stream[:bit_rate].to_i
          @audio_channel_layout = audio_stream[:channel_layout]

          @audio_stream = [
            audio_codec,
            "(#{audio_stream[:codec_tag_string]} / #{audio_stream[:codec_tag]})",
            audio_sample_rate, 'Hz',
            audio_channel_layout,
            audio_stream[:sample_fmt],
            audio_bitrate, 'bit/s'
          ].join(' ')
        end

      end
      @invalid = true if @metadata.key?(:error)
      @invalid = true if std_error.include?('Unsupported codec') && !audio_stream && !video_stream
      @invalid = true if std_error.include?('is not supported')
      @invalid = true if std_error.include?('could not find codec parameters')
    end

    def valid?
      !@invalid
    end

    def resolution
      return if width.nil? || height.nil?
      "#{width}x#{height}"
    end

    def calculated_aspect_ratio
      aspect_from_dar || aspect_from_dimensions
    end

    def calculated_pixel_aspect_ratio
      aspect_from_sar || 1
    end

    def size
      File.size(@path)
    end

    def audio_channel_layout
      @audio_channel_layout ||= audio_channels_string
    end

    def transcode(output_file, options = EncodingOptions.new, transcoder_options = {}, &block)
      Transcoder.new(self, output_file, options, transcoder_options).run(&block)
    end

    def screenshot(output_file, options = EncodingOptions.new, transcoder_options = {}, &block)
      Transcoder.new(self, output_file, options.merge(screenshot: true), transcoder_options).run(&block)
    end

    protected ##################################################################

    def aspect_from_dar
      return nil unless dar
      w, h = dar.split(':')
      aspect = w.to_f / h.to_f
      aspect.zero? ? nil : aspect
    end

    def aspect_from_sar
      return nil unless sar
      w, h = sar.split(':')
      aspect = w.to_f / h.to_f
      aspect.zero? ? nil : aspect
    end

    def aspect_from_dimensions
      aspect = width.to_f / height.to_f
      aspect.nan? ? nil : aspect
    end

    def fix_encoding(output)
      output[/test/] # Running a regexp on the string throws error if it's not UTF-8
    rescue ArgumentError
      output.force_encoding(Encoding::ISO_8859_1)
    end

    private ####################################################################

    def parse_metadata(string)
      FFMPEG::JSON.parse(MultiJson.load(string, symbolize_keys: true))
    end

    def audio_channels_string
      case audio_channels
      when 1
        'mono'
      when 2
        'stereo'
      when 6
        '5.1'
      else
        'unknown'
      end
    end
  end
end
