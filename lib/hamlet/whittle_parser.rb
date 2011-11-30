class WhittleParser < Whittle::Parser
  DELIMITERS = {
    '(' => ')',
    '[' => ']',
    '{' => '}',
  }.freeze

  ATTR_SHORTCUT = {
    '#' => 'id',
    '.' => 'class',
  }.freeze

  DELIMITER_REGEX = /\A[\(\[\{]/
  ATTR_NAME_REGEX = '\A\s*(\w[:\w-]*)'

  def initialize stacks
    @stacks = stacks
    @indents = []
  end

  @indents = []

  rule(:blank => /\A\s*\Z/).as { @stacks.last << [:newline] }

  rule(:doctype) do |r|
    r[/\A<doctype\s+([^>]*)>?\s*(#.*)?\Z/i].as { @stacks.last << [:html, :doctype, $1] }
  end

  rule(:s => /\A\s*/).as {|s| @indents << s}
  rule(:end_space => /\A.*\Z/)
  rule(:comment => /[^\\]#([^{]?.*)\Z/).as {|_| $1 }
  rule(:starting_comment => /\A#([^{]?.*)\Z/).as { $1 }
  rule(:no_escape => /[^\\]/)
  rule(:comment) do |r|
    r[:no_escape, :starting_comment].as {""}
  end

  rule(:escaped_pound => '\\#')
  rule(:not_pound => /[^#\n]/)
  rule(:begin_code => '#{')

  rule(:not_comment) do |r|
    r[:escaped_pound]
    r[:not_pound]
    r[:begin_code]
  end

  rule(:broken_line) do |r|
    r[/\\\n.+/]
  end

  rule(:rest) do |r|
    r[:broken_line]
    r[:not_comment]
    r[:comment]
  end

  rule('-')
  rule('<')
  rule(:output_code => /\A=(=?)('?)/)
  rule(:not_close_tag => /[^>]/)

  rule(:line) do |r|
    # code block.
    r[:s, '-', :rest].as { |s,_,rest|
        block = [:multi]
        @stacks.last << [:slim, :control, s + rest, block]
        @stacks << block
    }
    # output block.
    r[:s, :output_code, :rest].as {|s,indicator,rest|
        indicator =~ /\A=(=?)('?)/
        @needs_space = true
        block = [:multi]
        @stacks.last << [:slim, :output, $1.empty?, rest, block]
        @stacks.last << [:static, ' '] unless $2.empty?
        @stacks << block
    }

    r[:s, '<', :rest].as {|s,_,rest|
        if @needs_space && !(@line[0] == '>')
          @stacks.last << [:slim, :interpolate, " " ]
        end
        @needs_space = false
        case rest
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

    }
    r[:s, :starting_comment].as {|s,rest|
          @needs_space = false
          if rest =~ %r!\A#\[\s*(.*?)\s*\]\s*\Z! # HTML conditional comment
            block = [:multi]
            @stacks.last << [:slim, :condcomment, $1, block]
            @stacks << block
          else
            # otherwise the entire line is commented - ignore
          end
    }
    r[:s, :not_close_tag, :rest].as {|s,_,rest|
          if @needs_space
            @stacks.last << [:slim, :interpolate, " " ]
            @stacks.last << [:newline]
          end
          @needs_space = true
          push_text(rest)
    }
    #  @stacks.last << [:newline]
  end

  rule("\n")

  rule(:html) do |r|
    r[:html, "\n", :line].as { |list, _, id| list << id }
    r[:line].as        { |line| line }
  end

  rule(:document) do |r|
    r[:blank]
    r[:doctype, :html]
    r[:html]
  end

  start(:document)
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

end
