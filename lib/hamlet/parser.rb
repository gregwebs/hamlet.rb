require 'hamlet/forked_slim_parser'

# @api private
module Hamlet
  class Parser < ForkedSlim::Parser
    private

    def parse_line_indicators
      case @line
      when /\A\//
        # Found a comment block.
        if @line =~ %r{\A/!( ?)(.*)\Z}
          # HTML comment
          block = [:multi]
          @stacks.last <<  [:html, :comment, block]
          @stacks << block
          @stacks.last << [:slim, :interpolate, $2] unless $2.empty?
          parse_text_block($2.empty? ? nil : @indents.last + $1.size + 2)
        elsif @line =~ %r{\A/\[\s*(.*?)\s*\]\s*\Z}
          # HTML conditional comment
          block = [:multi]
          @stacks.last << [:slim, :condcomment, $1, block]
          @stacks << block
        else
          # Slim comment
          parse_comment_block
        end
      when /\A-/
        # Found a code block.
        # We expect the line to be broken or the next line to be indented.
        block = [:multi]
        @line.slice!(0)
        @stacks.last << [:slim, :control, parse_broken_line, block]
        @stacks << block
      when /\A=/
        # Found an output block.
        # We expect the line to be broken or the next line to be indented.
        @line =~ /\A=(=?)('?)/
        @line = $'
        block = [:multi]
        @stacks.last << [:slim, :output, $1.empty?, parse_broken_line, block]
        @stacks.last << [:static, ' '] unless $2.empty?
        @stacks << block
      when /\A<(\w+):\s*\Z/
        # Embedded template detected. It is treated as block.
        block = [:multi]
        @stacks.last << [:newline] << [:slim, :embedded, $1, block]
        @stacks << block
        parse_text_block
        return # Don't append newline, this has already been done before
      when /\Adoctype\s+/i
        # Found doctype declaration
        @stacks.last << [:html, :doctype, $'.strip]
      when /\A<([#\.]|\w[:\w-]*)/
        # Found a HTML tag.
        parse_tag($1)
      when /\A(?:>( *))?(.*)?\Z/
        # Found a text block.
        @stacks.last << [:slim, :interpolate, $1 ? $1 << $2 : $2] unless $2.empty?
        parse_text_block($2.empty? ? nil : @indents.last + $1.to_s.size)
      else
        syntax_error! 'Unknown line indicator'
      end
      @stacks.last << [:newline]
    end

    def parse_text_block(text_indent = nil)
      empty_lines = 0
      until @lines.empty?
        if @lines.first =~ /\A\s*\Z/
          next_line
          @stacks.last << [:newline]
          empty_lines += 1 if text_indent
        else
          indent = get_indent(@lines.first)
          break if indent <= @indents.last

          if empty_lines > 0
            @stacks.last << [:slim, :interpolate, "\n" * empty_lines]
            empty_lines = 0
          end

          next_line

          # The text block lines must be at least indented
          # as deep as the first line.
          if text_indent && indent < text_indent
            @line.lstrip!
            syntax_error!('Unexpected text indentation')
          end

          @line.slice!(0, text_indent || indent)
          @stacks.last << [:slim, :interpolate, (text_indent ? "\n" : '') + @line] << [:newline]

          # The indentation of first line of the text block
          # determines the text base indentation.
          text_indent ||= indent
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
      when /\A\s*>?=(=?)('?)/
        # Handle output code
        block = [:multi]
        @line = $'
        content = [:slim, :output, $1 != '=', parse_broken_line, block]
        tag << content
        @stacks.last << [:static, ' '] unless $2.empty?
        @stacks << block
      when /\A\s*\//
        # Closed tag. Do nothing
      when /\A\s*>?\s*\Z/
        # Empty content
        content = [:multi]
        tag << content
        @stacks << content
      when /\A( ?)>?(.*)\Z/
        # Text content
        content = [:multi, [:slim, :interpolate, $2]]
        tag << content
        @stacks << content
        parse_text_block(@orig_line.size - @line.size + $1.size)
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
      delimiter = nil
      if @line =~ DELIMITER_REGEX
        delimiter = DELIMITERS[$&]
        @line.slice!(0)
      end

      orig_line = @orig_line
      lineno = @lineno
      while true
        # Parse attributes
        attr_regex = delimiter ? /#{ATTR_NAME_REGEX}(=|\s|(?=#{Regexp.escape delimiter}))/ : /#{ATTR_NAME_REGEX}=/
        while @line =~ attr_regex
          @line = $'
          name = $1
          if delimiter && $2 != '='
            attributes << [:slim, :attr, name, false, 'true']
          elsif @line =~ /\A["']/
            # Value is quoted (static)
            @line = $'
            attributes << [:html, :attr, name, [:slim, :interpolate, parse_quoted_attribute($&)]]
          else
            @line =~ /[^ >]+/
            @line = $'
            attributes << [:html, :attr, name, [:slim, :interpolate, $&]]
          end
        end

        # No ending delimiter, attribute end
        break unless delimiter

        # Find ending delimiter
        if @line =~ /\A\s*#{Regexp.escape delimiter}/
          @line = $'
          break
        end

        # Found something where an attribute should be
        @line.lstrip!
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
