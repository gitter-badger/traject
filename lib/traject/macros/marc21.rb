require 'traject/marc_extractor'
require 'traject/translation_map'
require 'base64'
require 'json'

module Traject::Macros
  # Some of these may be generic for any MARC, but we haven't done
  # the analytical work to think it through, some of this is
  # def specific to Marc21.
  module Marc21

    # A combo function macro that will extract data from marc according to a string
    # field/substring specification, then apply various optional post-processing to it too.
    #
    # First argument is a string spec suitable for the MarcExtractor, see
    # MarcExtractor::parse_string_spec.
    #
    # Second arg is optional options, including options valid on MarcExtractor.new,
    # and others. (TODO)
    #
    # Examples:
    #
    # to_field("title"), extract_marc("245abcd", :trim_punctuation => true)
    # to_field("id"),    extract_marc("001", :first => true)
    # to_field("geo"),   extract_marc("040a", :seperator => nil, :translation_map => "marc040")
    def extract_marc(spec, options = {})
      only_first              = options.delete(:first)
      trim_punctuation        = options.delete(:trim_punctuation)
      if translation_map_arg  = options.delete(:translation_map)
        translation_map = Traject::TranslationMap.new(translation_map_arg)
      end

      lambda do |record, accumulator, context|
        accumulator.concat Traject::MarcExtractor.extract_by_spec(record, spec, options)

        if only_first
          Marc21.first! accumulator
        end

        if translation_map
          translation_map.translate! accumulator
        end

        if trim_punctuation
          accumulator.collect! {|s| Marc21.trim_punctuation(s)}
        end
      end
    end

    # Serializes complete marc record to a serialization format.
    # required param :format,
    # serialize_marc(:format => :binary)
    #
    # formats:
    # [xml] MarcXML
    # [json] marc-in-json (http://dilettantes.code4lib.org/blog/2010/09/a-proposal-to-serialize-marc-in-json/)
    # [binary] Standard ISO 2709 binary marc. By default WILL be base64-encoded,
    #          assumed destination a solr 'binary' field.
    #          add option `:binary_escape => false` to do straight binary -- unclear
    #          what Solr's documented behavior is when you do this, and add a string
    #          with binary control chars to solr. May do different things in diff
    #          Solr versions, including raising exceptions.
    def serialized_marc(options)
      options[:format] = options[:format].to_s
      raise ArgumentError.new("Need :format => [binary|xml|json] arg") unless %w{binary xml json}.include?(options[:format])

      lambda do |record, accumulator, context|
        case options[:format]
        when "binary"
          binary = record.to_marc
          binary = Base64.encode64(binary) unless options[:binary_escape] == false
          accumulator << binary
        when "xml"
          # ruby-marc #to_xml returns a REXML object at time of this writing, bah!@
          # call #to_s on it. Hopefully that'll be forward compatible. 
          accumulator << record.to_xml.to_s
        when "json"
          accumulator << JSON.dump(record.to_hash)
        end
      end
    end


    # Trims punctuation mostly from end, and occasionally from beginning
    # of string. Not nearly as complex logic as SolrMarc's version, just
    # pretty simple.
    #
    # Removes
    # * trailing: comma, slash, semicolon, colon (possibly followed by whitespace)
    # * trailing period if it is preceded by at least three letters (possibly followed by whitespace)
    # * single square bracket characters if they are the start and/or end
    #   chars and there are no internal square brackets.
    #
    # Returns altered string, doesn't change original arg.
    def self.trim_punctuation(str)
      str = str.sub(/[ ,\/;:] *\Z/, '')
      str = str.sub(/(\w\w\w)\. *\Z/, '\1')
      str = str.sub(/\A\[?([^\[\]]+)\]?\Z/, '\1')
      return str
    end

    def self.first!(arr)
      # kind of esoteric, but slice used this way does mutating first, yep
      arr.slice!(1, arr.length)
    end

  end
end