#!/bin/env ruby

# tiny-slidedown: All-in-one SlideDown Fork
#
# original slidedown:
#   http://github.com/nakajima/slidedown
# tiny-slidedown fork:
#   http://github.com/rpl/tiny-slidedown

require 'rubygems'
require 'open4'
require 'bluecloth'
require 'nokogiri'
require 'optparse'
require 'nokogiri'
require 'erb'

class Albino
  @@bin = ENV['PYGMENTIZE_BIN'] || '/usr/local/bin/pygmentize'

  def self.bin=(path)
    @@bin = path
  end

  def self.colorize(*args)
    new(*args).colorize
  end

  def initialize(target, lexer = :ruby, format = :html)
    @target  = File.exists?(target) ? File.read(target) : target rescue target.chomp
    @options = { :l => lexer, :f => format }
  end

  def execute(command)
    pid, stdin, stdout, stderr = Open4.popen4(command)
    stdin.puts @target
    stdin.close
    stdout.read.strip
  end

  def colorize(options = {})
    execute @@bin + convert_options(options)
  end
  alias_method :to_s, :colorize

  def convert_options(options = {})
    @options.merge(options).inject('') do |string, (flag, value)|
      string += " -#{flag} #{value}"
      string
    end
  end
end
$LOAD_PATH << File.dirname(__FILE__)

module MakersMark
  def self.generate(markdown)
    Generator.new(markdown).to_html
  end
end
module MakersMark
  class Generator
    def initialize(markdown)
      @markdown = markdown
    end

    def to_html
      highlight!
      doc.search('body > *').to_html
    end

    private

    def doc
      @doc ||= Nokogiri::HTML(markup)
    end

    def highlight!
      doc.search('div.code').each do |div|
        lexer = div['rel'] || :ruby

        lexted_text = Albino.new(div.text, lexer).to_s

        highlighted = Nokogiri::HTML(lexted_text).at('div')

        klasses = highlighted['class'].split(/\s+/)
        klasses << lexer
        klasses << 'code'
        klasses << 'highlight'
        highlighted['class'] = klasses.join(' ')

        div.replace(highlighted)
      end
    end

    def markup
      @markup ||= begin
        logger.info "WRITING!"
        text = @markdown.dup
        ### NOTE: preserve code snippets
        text.gsub!(/^(?:<p>)?@@@(?:<\/p>)?$/, '</div>')
        text.gsub!(/^(?:<p>)?@@@\s*([\w\+]+)(?:<\/p>)?$/, '<div class="code" rel="\1">')
        ### NOTE: convert to html and return
        BlueCloth.new(text).to_html
      end
    end

    def logger
      @logger ||= Class.new {
        def info(msg)
          say msg
        end

        private

        def say(msg)
          $stdout.puts msg if $VERBOSE
        end
      }.new
    end
  end
end
class Slide
  attr_accessor :text, :classes, :notes

  def initialize(text, *classes)
    @text    = text
    @classes = classes
    @notes   = nil
    
    extract_notes!
  end

  def html
    MakersMark::Generator.new(@text).to_html
  end
  
  private
  
  def extract_notes!
    @text.gsub!(/^!NOTES\s*(.*\n)$/m) do |note|
      @notes = note.to_s.chomp.gsub('!NOTES', '')
      ''
    end
  end
end

$SILENT = true

class SlideDown
  USAGE = "The SlideDown command line interface takes a .md (Markdown) file as its only required argument. It will convert the file to HTML in standard out. Options:
  -t, --template [TEMPLATE] the .erb files in /templates directory. Default is -t default, which prints stylesheets and javascripts inline. The import template uses link and script tags. This can also accept an absolute path for templates outside the /templates directory."

  attr_accessor :stylesheets, :title
  attr_reader :classes

  def self.run!(argv = ARGV)
    args = argv.dup
    @@local_template = false
    @@output_text = ""

    if args.empty?
      puts USAGE
    else
      source = args[0]
      if args.length == 1
        render(source)
      else
        option_parser(source).parse!(args)
      end
    end

    return @@output_text
  end

  def self.option_parser(source)
    OptionParser.new do |opts|
      opts.on('-h', '--help') { puts USAGE }
      opts.on('-l', '--local') { @@local_template = true }
      opts.on('-t', '--template TEMPLATE') do |template|
        @@output_text = render(source, template)
      end
    end
  end

  def self.render(source_path, template = "default")
    if source_path
      slideshow = new(File.read(source_path))
      slideshow.render(template)
    end
  end

  # Ensures that the first slide has proper !SLIDE declaration
  def initialize(raw, opts = {})
    @raw = raw =~ /\A!SLIDE/ ? raw : "!SLIDE\n#{raw}"
    extract_classes!

    self.stylesheets = opts[:stylesheets] || local_stylesheets
    self.title =       opts[:title]       || "Slides"
  end

  def slides
    @slides ||= lines.map { |text| Slide.new(text, *@classes.shift) }
  end

  def read(path)
    if @@local_template
      File.read(File.join(Dir.pwd, File.dirname(@local_template_name), path))
    else
      File.read(File.join(File.dirname(__FILE__), '..', "templates", path))
    end
  end

  def render(name)
    if is_absolute_path?(name)
      template = File.read("#{name}.erb")
    elsif @@local_template
      @local_template_name = name
      template = File.read("#{Dir.pwd}/#{name}.erb")
    else
      directory = File.join(File.dirname(__FILE__), "..", "templates")
      path      = File.join(directory, "#{name}.erb")
      template  = File.read(path)
    end
    ERB.new(template).result(binding)
  end

  private

  def lines
    @lines ||= @raw.split(/^!SLIDE\s*([a-z\s]*)$/).reject { |line| line.empty? }
  end

  def local_stylesheets
    Dir[Dir.pwd + '/*.stylesheets']
  end

  def javascripts
    Dir[Dir.pwd + '/*.javascripts'].map { |path| File.read(path) }
  end

  def extract_classes!
    @classes = []
    @raw.gsub!(/^!SLIDE\s*([a-z\s]*)$/) do |klass|
      @classes << klass.to_s.chomp.gsub('!SLIDE', '')
      "!SLIDE"
    end
    @classes
  end

  def extract_notes!
    @raw.gsub!(/^!NOTES\s*(.*)!SLIDE$/m) do |note|
      '!SLIDE'
    end
    @raw.gsub!(/^!NOTES\s*(.*\n)$/m) do |note|
      ''
    end
  end

  def is_absolute_path?(path)
    path == File.expand_path(path)
  end
end

if __FILE__ == $PROGRAM_NAME
  puts SlideDown.run!
end
