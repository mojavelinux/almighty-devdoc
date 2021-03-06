require 'asciidoctor'
require 'asciidoctor-diagram'

module Jekyll
  module AsciiDoc
    VERSION = '1.1.1'
  end
end

JEKYLL_MIN_VERSION_3 = Gem::Version.new(Jekyll::VERSION) >= Gem::Version.new('3.0.0') unless defined? JEKYLL_MIN_VERSION_3

module Jekyll
  module Converters
    class AsciiDocConverter < Converter
      IMPLICIT_ATTRIBUTES = %W(
        env=site env-site site-gen=jekyll site-gen-jekyll builder=jekyll builder-jekyll jekyll-version=#{Jekyll::VERSION}
      )

      safe true

      highlighter_prefix "\n"
      highlighter_suffix "\n"

      def initialize(config)
        # Hack to get the output path of the current rendered doc
        Jekyll::Hooks.register(:pages, :pre_render) do |page, payload|
          @curr_page_output = page.dir
          @dest = page.site.dest
        end
        Jekyll::Hooks.register(:documents, :pre_render) do |page, payload|
          @curr_page_output = page.collection.label
          @dest = page.site.dest
        end
        @config = config
        config['asciidoc'] ||= 'asciidoctor'
        asciidoc_ext = (config['asciidoc_ext'] ||= 'asciidoc,adoc,ad')
        config['asciidoc_ext_re'] = Regexp.new("\.(#{asciidoc_ext.tr ',', '|'})$", Regexp::IGNORECASE)
        config['asciidoc_page_attribute_prefix'] ||= 'page'
        unless (asciidoctor_config = (config['asciidoctor'] ||= {})).frozen?
          # NOTE convert keys to symbols
          asciidoctor_config.keys.each do |key|
            asciidoctor_config[key.to_sym] = asciidoctor_config.delete(key)
          end
          asciidoctor_config[:safe] ||= 'safe'
          (asciidoctor_config[:attributes] ||= []).tap do |attributes|
            attributes.unshift('notitle', 'hardbreaks', 'idprefix', 'idseparator=-', 'linkattrs')
            attributes.concat(IMPLICIT_ATTRIBUTES)
          end
          asciidoctor_config.freeze
        end
      end

      def setup
        return if @setup
        @setup = true
        case @config['asciidoc']
        when 'asciidoctor'
          begin
            require 'asciidoctor' unless defined? ::Asciidoctor
          rescue LoadError
            STDERR.puts 'You are missing a library required to convert AsciiDoc files. Please run:'
            STDERR.puts '  $ [sudo] gem install asciidoctor'
            raise FatalException.new('Missing dependency: asciidoctor')
          end
        else
          STDERR.puts "Invalid AsciiDoc processor: #{@config['asciidoc']}"
          STDERR.puts '  Valid options are [ asciidoctor ]'
          raise FatalException.new("Invalid AsciiDoc processor: #{@config['asciidoc']}")
        end
      end
      
      def matches(ext)
        ext =~ @config['asciidoc_ext_re']
      end

      def output_ext(ext)
        '.html'
      end

      def convert(content)
        setup
        case @config['asciidoc']
        when 'asciidoctor'
          config = @config['asciidoctor'].dup
          config[:attributes] = hashify(config[:attributes])
          config[:attributes]["outdir"] = "#{@dest}/#{@curr_page_output}"
          config[:attributes]["imagesdir"] = ""

          Asciidoctor.convert(content, config)
        else
          warn 'Unknown AsciiDoc converter. Passing through raw content.'
          content
        end
      end

      def load_header(content)
        setup
        case @config['asciidoc']
        when 'asciidoctor'
          Asciidoctor.load(content, parse_header_only: true)
        else
          warn 'Unknown AsciiDoc converter. Cannot load document header.'
          nil
        end
      end

      def hashify(list)
        def key(x)
          return x if x.index("=").nil?
          return x.slice(0, x.index("=")||-1)
        end
        def value(x)
          index = x.index("=")
          return "" if index.nil?
          return x.slice(x.index("=")+1, x.length)
        end
        return Hash[list.map {|x| [key(x), value(x)]}]
      end
    end
  end

  module Generators
    # Promotes select AsciiDoc attributes to Jekyll front matter
    class AsciiDocPreprocessor < Generator
      def generate(site)
        asciidoc_converter = JEKYLL_MIN_VERSION_3 ?
            site.find_converter_instance(Jekyll::Converters::AsciiDocConverter) :
            site.getConverterImpl(Jekyll::Converters::AsciiDocConverter)
        asciidoc_converter.setup
        unless (page_attr_prefix = site.config['asciidoc_page_attribute_prefix']).empty?
          page_attr_prefix = %(#{page_attr_prefix}-)
        end
        page_attr_prefix_l = page_attr_prefix.length

        site.pages.each do |page|
          if asciidoc_converter.matches(page.ext)
            next unless (doc = asciidoc_converter.load_header(page.content))

            page.data['title'] = doc.doctitle if doc.header?
            page.data['author'] = doc.author if doc.author

            page.data['layout'] = 'default' unless page.data.key? 'layout'
          end
        end

        (JEKYLL_MIN_VERSION_3 ? site.posts.docs : site.posts).each do |post|
          if asciidoc_converter.matches(JEKYLL_MIN_VERSION_3 ? post.data['ext'] : post.ext)
            next unless (doc = asciidoc_converter.load_header(post.content))

            post.data['title'] = doc.doctitle if doc.header?
            post.data['author'] = doc.author if doc.author
            post.data['date'] = DateTime.parse(doc.revdate).to_time if doc.attr? 'revdate'

            unless (additional_page_data = SafeYAML.load(doc.attributes
                .select {|name| name.start_with?(page_attr_prefix) }
                .map {|name, val| %(#{name[page_attr_prefix_l..-1]}: #{val}) }
                .join("\n"))).empty?
              post.data.update(additional_page_data)
            end

            post.data['layout'] = 'post' unless post.data.key? 'layout'
          end
        end
      end
    end
  end

  module Filters
    # Convert an AsciiDoc string into HTML output.
    #
    # input - The AsciiDoc String to convert.
    #
    # Returns the HTML formatted String.
    def asciidocify(input)
      site = @context.registers[:site]
      converter = JEKYLL_MIN_VERSION_3 ?
          site.find_converter_instance(Jekyll::Converters::AsciiDocConverter) :
          site.getConverterImpl(Jekyll::Converters::AsciiDocConverter)
      converter.convert(input)
    end
  end
end
