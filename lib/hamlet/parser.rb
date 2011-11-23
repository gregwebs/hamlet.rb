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
      if @lines.first and @lines.first =~ /\A<doctype\s+([^>]*)>?/i
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
    def parse_line
      if @line =~ /\A\s*\Z/
        @stacks.last << [:newline]
        return
      end

      indent = get_indent(@line)

      # Remove the indentation
      @line.lstrip!
      indent +=1 if @line[0] == '>'

      # If there's more stacks than indents, it means that the previous
      # line is expecting this line to be indented.
      expecting_indentation = @stacks.size > @indents.size

      if indent > @indents.last
        # This line was actually indented, so we'll have to check if it was
        # supposed to be indented or not.
        unless expecting_indentation
          syntax_error!('Unexpected indentation')
        end

        @indents << indent
      else
        # This line was *not* indented more than the line before,
        # so we'll just forget about the stack that the previous line pushed.
        @stacks.pop if expecting_indentation

        # This line was deindented.
        # Now we're have to go through the all the indents and figure out
        # how many levels we've deindented.
        while indent < @indents.last
          @indents.pop
          @stacks.pop
        end

        # This line's indentation happens lie "between" two other line's
        # indentation:
        #
        #   hello
        #       world
        #     this      # <- This should not be possible!
        syntax_error!('Malformed indentation') if indent != @indents.last
      end

      parse_line_indicators
    end

    def parse_line_indicators
      case @line[0]
      when '-' # code block.
        block = [:multi]
        @line.slice!(0)
        @stacks.last << [:slim, :control, parse_broken_line, block]
        @stacks << block
      when '=' # output block.
        @needs_space = true
        @line =~ /\A=(=?)('?)/
        @line = $'
        block = [:multi]
        @stacks.last << [:slim, :output, $1.empty?, parse_broken_line, block]
        @stacks.last << [:static, ' '] unless $2.empty?
        @stacks << block
      when '<'
        if @needs_space && !(@line[0] == '>')
          @stacks.last << [:slim, :interpolate, " " ]
        end
        @needs_space = false
        case @line
        when /\A<(\w+):\s*\Z/ # Embedded template. It is treated as block.
          @needs_space = false
          block = [:multi]
          @stacks.last << [:newline] << [:slim, :embedded, $1, block]
          @stacks << block
          parse_text_block(nil, :from_embedded)
          return # Don't append newline, this has already been done before
        when /\A<([#\.]|\w[:\w-]*)/ # HTML tag.
          @needs_space = false
          parse_tag($1)
        when /\A<!--( ?)(.*)\Z/ # HTML comment
          @needs_space = false
          block = [:multi]
          @stacks.last <<  [:html, :comment, block]
          @stacks << block
          @stacks.last << [:slim, :interpolate, $2] unless $2.empty?
          parse_text_block($2.empty? ? nil : @indents.last + $1.size + 2)
        else
          syntax_error! 'Unknown line indicator'
        end
      else
        if @line[0] == '#' and @line[1] != '{'
          @needs_space = false
          if @line =~ %r!\A#\[\s*(.*?)\s*\]\s*\Z! # HTML conditional comment
            block = [:multi]
            @stacks.last << [:slim, :condcomment, $1, block]
            @stacks << block
          else
            # otherwise the entire line is commented - ignore
          end
        else
          if @needs_space and not @line[0] == '>'
            @stacks.last << [:slim, :interpolate, " " ]
            @stacks.last << [:newline]
          end
          @needs_space = true
          push_text
        end
      end
      @stacks.last << [:newline]
    end

    def push_text
      if @line[0] == '>'
        @line.slice!(0)
      end
      if @line =~ /(\A|[^\\])#([^{]|\Z)/
        @line = $` + $1
      end
      @stacks.last << [:slim, :interpolate, @line]
    end

    # This is fundamentally broken
    # Can keep this for multi-lie html comment perhaps
    # But don't lookahead on text otherwise
    def parse_text_block(text_indent = nil, from = nil)
      empty_lines = 0
      first_line = true
      embedded = nil
      case from
      when :from_tag
        first_line = true
      when :from_embedded
        embedded = true
      end

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
          unless embedded
            @line = $' if @line =~ /\A>/
            # a code comment
            if @line =~ /(\A|[^\\])#([^{]|\Z)/
              @line = $` + $1
            end
          end
          @stacks.last << [:newline] if !first_line && !embedded
          @stacks.last << [:slim, :interpolate, (text_indent ? "\n" : '') + @line] << [:newline]

          # The indentation of first line of the text block
          # determines the text base indentation.
          text_indent ||= indent

          first_line = false
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
        @needs_space = true
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
        @needs_space = true
        content = [:multi, [:slim, :interpolate, @line]]
        tag << content
        @stacks << content
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
          value = $2
          if !value
            attributes << [:slim, :attr, name, false, 'true']
          elsif @line =~ /\A["']/
            # Value is quoted (static)
            @line = $'
            attributes << [:html, :attr, name, [:slim, :interpolate, parse_quoted_attribute($&)]]
          elsif @line =~ /\A(([^# >]+)|[^ >#]*#\{[^\}]+\}[^ >]*)/
            @line = $'
            attributes << [:html, :attr, name, [:slim, :interpolate, $&]]
          elsif value =~ /\A=\s*\Z/
            syntax_error!('Invalid empty attribute')
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
