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

This Hamlet works on top of [slim](https://github.com/stonean/slim/). Please see [slim documentation](http://slim-lang.com). There is one important difference: hamlet always defers to HTML syntax. In slim you have:

    p data-attr=foo Text
      | More Text

In hamlet you have:

    <p data-attr=foo>Text
      More Text

## Whitespace

This is currently a bit of a Slim Frankenstein, but I added the same syntax that hamlet.js uses to indicate whitespace: a closing bracket

    <p>   White space to the left
      >   White space to the left again


## Limitations

I just hacked this up the other day - let me know if there are any issues. After some more experience using Slim's syntax I plan on trying to reduce the total available syntax.
