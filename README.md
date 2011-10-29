Hamlet is a template language whose goal is to reduce HTML syntax to the essential parts.

# Syntax

``` html
<body>
    <p>Some paragraph.
    <ul data-attr=list>
        <li>Item 1
        <li>Item 2
```

That Hamlet snippet is equivalent to:

``` html
<body>
  <p>Some paragraph.</p>
  <ul data-attr="list">
    <li>Item 1</li>
    <li>Item 2</li>
  </ul>
</body>
```

see, it is just HTML! Designers love Hamlet because it is just HTML! Closing tags are inferred from whitespace.

## Details

You can see the [original hamlet templating langauge](http://www.yesodweb.com/book/templates) and the
[javascript port](hamlet: https://github.com/gregwebs/hamlet.js).

This Hamlet works on top of [slim](https://github.com/stonean/slim/). Please take a look at the [slim documentation](http://slim-lang.com) if you are looking to see if a more advanced feature is supported.

## Difference with Slim

The most important difference is that hamlet always uses angle brackets. Hamlet also does not require attributes to be quoted - unquoted is considered a normal html attribute value and quotes will be added. Hamlet also uses a '#' for code comments and the normal <!-- for HTML comments. Hamlet also uses different whitespace indicators - see the next section.

In Slim you have:

    /! HTML comment
    p data-attr="foo" Text
      | More Text
      / Comment

In hamlet you have:

    <!-- HTML comment
    <p data-attr=foo>Text
      More Text
      # Comment

## Whitespace

I added the same syntax that hamlet.js uses to indicate whitespace: a closing bracket to the left and a code comment to the right. I will probably take out some of the slim white space techniques.

    <p>   White space to the left        # and to the right
      >   White space to the left again# None to the right


## Limitations

I just hacked this up the other day - let me know if there are any issues. After some more experience using Slim's syntax I plan on trying to reduce the total available syntax.
