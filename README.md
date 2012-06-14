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

You can see the [original Haskell hamlet templating language](http://www.yesodweb.com/book/shakespearean-templates) and the
[javascript port](hamlet: https://github.com/gregwebs/hamlet.js).

This Hamlet (ruby) works on top of [slim](https://github.com/stonean/slim/). Please take a look at the [slim documentation](http://slim-lang.com) if you are looking to see if a more advanced feature is supported.

## Difference with Slim

The most important difference is that hamlet always uses angle brackets. Hamlet also does not require attributes to be quoted - unquoted is considered a normal html attribute value and quotes will automatically be added. Hamlet also uses a '#' for code comments and the normal <!-- for HTML comments. Hamlet also uses different whitespace indicators - see the next section.

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

Using indentation does have some consequences with respect to white space. This library is designed to do the right thing most of the time. This is a slightly different design from the original Haskell implementation of Hamlet and Slim, but the same design as hamlet.js

A closing tag is placed immediately after the tag contents. If you want to have a space before a closing tag, use a comment sign `#` on the line to indicate where the end of the line is.

``` html
<b>spaces  # 2 spaces are included

```

A new line is automatically added *after* tags with inner text. If you have multiple lines of inner text without tags (not a common use case) they will also get a new line added. If you do not want white space, you point it out with a `>` character, that you could think of as the end of the last tag, although you can still use it when separating content without tags onto different lines. You can also use a `>` if you want more than one space.

``` html
<b>spaces  # 2 spaces are included
```

``` html
<b>spaces  </b>
```

``` html
<b>no space
>none after bold.
>  Two spaces after a period is bad!
```

``` html
<b>no space</b>none after bold.  Two spaces after a period is bad!
```

## I18n support

You can hook up i18n support the same way you would for other templating lanugages.
[This rails plugin](https://github.com/grosser/gettext_i18n_rails) works out of the box.

## Limitations

A space is not automatically added after a tag when looping through an array
Double quotes in attributes will get messed up: `click=do('ok!')` not `click=do("whoops!")`

## Development

Run tests with

    rake test

or

    ruby -r ./test/slim/helper.rb TEST

