# Hamlet

Hamlet is a template language whose goal is to reduce HTML syntax to the essential parts.

This Hamlet works on top of [slim](https://github.com/stonean/slim/). Please see [slim documentation](http://slim-lang.com). There is one important difference: hamlet always defers to HTML syntax. In slim you have:

    p data-attr=foo Text
      | More Text

In hamlet you have:

    <p data-attr=foo>Text
      More Text

see, it is just HTML! Closing tags are inferred from whitespace. Speaking of which, this is currently a bit of a slim frankenstein, but I added the same syntax that hamlet.js uses to indicate whitespace: a closing bracket

    <p>   White space to the left
      >   White space to the left again


You can see the [original hamlet templating langauge](http://www.yesodweb.com/book/templates) and the
[javascript port](hamlet: https://github.com/gregwebs/hamlet.js).
