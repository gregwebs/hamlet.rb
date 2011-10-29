require 'hamlet/forked_slim_parser'

# @api private
module Hamlet
  class Parser < ForkedSlim::Parser
    if RUBY_VERSION > '1.9'
      CLASS_ID_REGEX = /\A\s*(#|\.)([\w\u00c0-\uFFFF][\w:\u00c0-\uFFFF-]*)/
    else
      CLASS_ID_REGEX = /\A\s*(#|\.)(\w[\w:-]*)/
    end

    # Compile string to Temple expression
    #
    # @param [String] str Slim code
    # @return [Array] Temple expression representing the code]]
    def call(str)
      # Set string encoding if option is set
      if options[:encoding] && str.respond_to?(:encoding)
        old = str.encoding
        str = str.dup if str.frozen?
        str.force_encoding(options[:encoding])
        # Fall back to old encoding if new encoding is invalid
        str.force_encoding(old_enc) unless str.valid_encoding?
      end

      result = [:multi]
      reset(str.split($/), [result])

      while @lines.first && @lines.first =~ /\A\s*\Z/
        @stacks.last << [:newline]
        next_line 
      end
      if @lines.first and @lines.first =~ /\A<doctype\s+([^>]*)/i
        if !$'.empty? and $'[0] !~ /\s*#/
          fail("did not expect content after doctype")
        end
        @stacks.last << [:html, :doctype, $1]
        next_line
      end

      parse_line while next_line

      reset
      result
    end

  private

    def parse_line_indicators
      case @line
      when /\A-/ # code block.
        block = [:multi]
        @line.slice!(0)
        @stacks.last << [:slim, :control, parse_broken_line, block]
        @stacks << block
      when /\A=/ # output block.
        @line =~ /\A=(=?)('?)/
        @line = $'
        block = [:multi]
        @stacks.last << [:slim, :output, $1.empty?, parse_broken_line, block]
        @stacks.last << [:static, ' '] unless $2.empty?
        @stacks << block
      when /\A<(\w+):\s*\Z/ # Embedded template. It is treated as block.
        block = [:multi]
        @stacks.last << [:newline] << [:slim, :embedded, $1, block]
        @stacks << block
        parse_text_block(nil, true)
        return # Don't append newline, this has already been done before
      when /\A<([#\.]|\w[:\w-]*)/ # HTML tag.
        parse_tag($1)
      when /\A<!--( ?)(.*)\Z/ # HTML comment
        block = [:multi]
        @stacks.last <<  [:html, :comment, block]
        @stacks << block
        @stacks.last << [:slim, :interpolate, $2] unless $2.empty?
        parse_text_block($2.empty? ? nil : @indents.last + $1.size + 2)
      when %r{\A#\[\s*(.*?)\s*\]\s*\Z} # HTML conditional comment
        block = [:multi]
        @stacks.last << [:slim, :condcomment, $1, block]
        @stacks << block
      when /\A(?:\s*>( *))?/ # text block.
        @stacks.last << [:slim, :interpolate, $1 ? $1 << $' : $']
        parse_text_block($'.empty? ? nil : @indents.last + $1.to_s.size)
      else
        syntax_error! 'Unknown line indicator'
      end
      @stacks.last << [:newline]
    end

    def parse_text_block(text_indent = nil, special = nil)
      empty_lines = 0
      multi_line = false
      if special == :from_tag
        multi_line = true
        special = nil
      end

      first_line = true
      close_bracket = false
      until @lines.empty?
        if @lines.first =~ /\A\s*>?\s*\Z/
          next_line
          @stacks.last << [:newline]
          empty_lines += 1 if text_indent
        else
          indent = get_indent(@lines.first)
          break if indent <= @indents.last
          if @lines.first =~ /\A\s*>/
            indent += 1 #$1.size if $1
            close_bracket = true
          else
            close_bracket = false
          end

          if empty_lines > 0
            @stacks.last << [:slim, :interpolate, "\n" * empty_lines]
            empty_lines = 0
          end

          next_line

          # The text block lines must be at least indented
          # as deep as the first line.
          if text_indent && indent < text_indent
            # special case for a leading '>' being back 1 char
            unless first_line && close_bracket && (text_indent - indent == 1)
              @line.lstrip!
              syntax_error!('Unexpected text indentation')
            end
          end

          @line.slice!(0, text_indent || indent)
          @line = $' if @line =~ /\A>/
          # a code comment
          if @line =~ /(\A|[^\\])#([^{]|\Z)/
            @line = $` + $1
          end
          @stacks.last << [:newline] if multi_line && !special
          @stacks.last << [:slim, :interpolate, (text_indent ? "\n" : '') + @line] << [:newline]

          # The indentation of first line of the text block
          # determines the text base indentation.
          text_indent ||= indent

          first_line = false
          multi_line = true
        end
      end
    end

    def parse_tag(tag)
      @line.slice!(0,1) # get rid of leading '<'
      if tag == '#' || tag == '.'
        tag = options[:default_tag]
      else
        @line.slice!(0, tag.size)
      end

      tag = [:html, :tag, tag, parse_attributes]
      @stacks.last << tag

      case @line
      when /\A=(=?)('?)/ # Handle output code
        block = [:multi]
        @line = $'
        content = [:slim, :output, $1 != '=', parse_broken_line, block]
        tag << content
        @stacks.last << [:static, ' '] unless $2.empty?
        @stacks << block
      when /\A\s*\Z/
        # Empty content
        content = [:multi]
        tag << content
        @stacks << content
      when %r!\A/>!
        # Do nothing for closing tag
      else # Text content
        content = [:multi, [:slim, :interpolate, @line]]
        tag << content
        @stacks << content
        parse_text_block(@orig_line.size - @line.size, :from_tag)
      end
    end

    def parse_attributes
      attributes = [:html, :attrs]

      # Find any literal class/id attributes
      while @line =~ CLASS_ID_REGEX
        # The class/id attribute is :static instead of :slim :text,
        # because we don't want text interpolation in .class or #id shortcut
        attributes << [:html, :attr, ATTR_SHORTCUT[$1], [:static, $2]]
        @line = $'
      end

      # Check to see if there is a delimiter right after the tag name
      delimiter = '>'

      orig_line = @orig_line
      lineno = @lineno
      while true
        # Parse attributes
        while @line =~ /#{ATTR_NAME_REGEX}\s*(=\s*)?/
          name = $1
          @line = $'
          if !$2
            attributes << [:slim, :attr, name, false, 'true']
          elsif @line =~ /\A["']/
            # Value is quoted (static)
            @line = $'
            attributes << [:html, :attr, name, [:slim, :interpolate, parse_quoted_attribute($&)]]
          elsif @line =~ /\A[^ >]+/
            @line = $'
            attributes << [:html, :attr, name, [:slim, :interpolate, $&]]
          end
        end

        @line.lstrip!

        # Find ending delimiter
        if @line =~ /\A(>|\Z)/
          @line = $'
          break
        elsif @line =~ %r!\A/>!
          # Do nothing for closing tag
          # don't eat the line either, we check for it again
          if not $'.empty? and $' !~ /\s*#/
            syntax_error!("Did not expect any content after self closing tag",
                           :orig_line => orig_line,
                           :lineno => lineno,
                           :column => orig_line.size)
          end
          break
        end

        syntax_error!('Expected attribute') unless @line.empty?

        # Attributes span multiple lines
        @stacks.last << [:newline]
        next_line || syntax_error!("Expected closing delimiter #{delimiter}",
                                   :orig_line => orig_line,
                                   :lineno => lineno,
                                   :column => orig_line.size)
      end

      attributes
    end
  end
end
