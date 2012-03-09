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

  def initialize options = nil
    options ||= {}
    reset(nil, [])
  end

  def self.runtime; @instance ||= new(nil) end

  rule('-')
  rule('<')
  rule(:output_code => /\A=(=?)('?)/)

  rule(:line) do |r|
    r[:s]
    r['-', :rest].as { |s,_,rest| runtime.code s, rest }

    r[:output_code, :rest].as {|s,indicator,rest|
      runtime.output s, indicator, rest
    }

    r['<', :rest].as {|s,_,rest| runtime.tag s, rest }

    r[:starting_comment].as {|s,rest|
      runtime.starting_comment s, rest
    }
    r[:not_close_tag, :rest].as {|s,_,rest|
      runtime.not_close_tag s, rest
    }
    #  @stacks.last << [:newline]
  end

  rule(:comment => /[^\\]#([^{]?.*)\Z/).as {|_| $1 }

  comment = "#([^{]?.*)"
  rule(:starting_comment => /\A#{comment}\Z/).as { $1 }
  rule(:comment => /\A[^\\]#{comment}\Z/)

  rule(:broken_line => /\\\n.+/)

  rule(:rest) do |r|
    r[:broken_line]
    r[:not_comment]
    r[:comment]
  end

  rule("\n")

  rule(:end_space => /\A.*\Z/)
  rule(:s => /\A\s*/).as {|s| runtime.indent(s) }

  rule(:not_comment) do |r|
    r[:escaped_pound]
    r[:not_pound]
    r[:begin_code]
  end
  rule(:escaped_pound => '\\#')
  rule(:not_pound => /[^#\n]/)
  rule(:begin_code => '#{')
  rule(:not_close_tag => /[^>]/)

  rule(:html) do |r|
    r[:html, "\n", :line].as { |list, _, id| list << id }
    r[:line].as        { |line| line }
  end

  rule(:doctype => /\A<doctype\s+([^>]*)>?\s*(#.*)?\Z/i).as { append [:html, :doctype, $1] }
  rule(:blank => /\A\s*\Z/).as { append([:newline]) }

  rule(:document) do |r|
    r[:blank]
    r[:doctype, :html]
    r[:html]
  end

  start(:document)

  def indent s; @indents << s end

  def self.append *args; runtime.append *args end
  def append temple
    @stacks.last << temple
  end

  def code space, rest
    block = [:multi]
    @stacks.last << [:slim, :control, s + rest, block]
    @stacks << block
  end

  def output space, indicator, rest
    indicator =~ /\A=(=?)('?)/
    @needs_space = true
    block = [:multi]
    @stacks.last << [:slim, :output, $1.empty?, rest, block]
    @stacks.last << [:static, ' '] unless $2.empty?
    @stacks << block
  end

  def tag s, rest
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
  end

  def starting_comment s, rest
    @needs_space = false
    if rest =~ %r!\A#\[\s*(.*?)\s*\]\s*\Z! # HTML conditional comment
      block = [:multi]
      @stacks.last << [:slim, :condcomment, $1, block]
      @stacks << block
    else
      # otherwise the entire line is commented - ignore
    end
  end

  def not_close_tag
    if @needs_space
      @stacks.last << [:slim, :interpolate, " " ]
      @stacks.last << [:newline]
    end
    @needs_space = true
    push_text(rest || "")
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

  def syntax_error!(message, args = {})
    args[:orig_line] ||= @orig_line
    args[:line] ||= @line
    args[:lineno] ||= @lineno
    args[:column] ||= args[:orig_line] && args[:line] ?
                      args[:orig_line].size - args[:line].size : 0
    raise SyntaxError.new(message, options[:file],
                          args[:orig_line], args[:lineno], args[:column])
  end

    include Temple::Mixins::Options

    set_default_options :tabsize  => 4,
                        :encoding => 'utf-8',
                        :default_tag => 'div'

    class SyntaxError < StandardError
      attr_reader :error, :file, :line, :lineno, :column

      def initialize(error, file, line, lineno, column)
        @error = error
        @file = file || '(__TEMPLATE__)'
        @line = line.to_s
        @lineno = lineno
        @column = column
      end

      def to_s
        line = @line.strip
        column = @column + line.size - @line.size
        %{#{error}
  #{file}, Line #{lineno}
    #{line}
    #{' ' * column}^
}
      end
    end

  def push_text rest
    if rest[0] == '>'
      rest.slice!(0)
    end
    if rest =~ /(\A|[^\\])#([^{]|\Z)/
      rest = $` + $1
    end
    @stacks.last << [:slim, :interpolate, rest]
  end

  def reset(lines = nil, stacks = nil)
    # Since you can indent however you like in Slim, we need to keep a list
    # of how deeply indented you are. For instance, in a template like this:
    #
    #   doctype       # 0 spaces
    #   html          # 0 spaces
    #    head         # 1 space
    #       title     # 4 spaces
    #
    # indents will then contain [0, 1, 4] (when it's processing the last line.)
    #
    # We uses this information to figure out how many steps we must "jump"
    # out when we see an de-indented line.
    @indents = [0]

    # Whenever we want to output something, we'll *always* output it to the
    # last stack in this array. So when there's a line that expects
    # indentation, we simply push a new stack onto this array. When it
    # processes the next line, the content will then be outputted into that
    # stack.
    @stacks = stacks

    @lineno = 0
    @lines = lines
    @line = @orig_line = nil
  end
end
