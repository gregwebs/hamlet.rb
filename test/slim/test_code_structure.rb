require 'helper'

class TestSlimCodeStructure < TestSlim
  def test_render_with_conditional
    source = %q{
<div
  - if show_first?
      <p>The first paragraph
  - else
      <p>The second paragraph
}

    assert_html '<div><p>The second paragraph</p></div>', source
  end

  def test_render_with_consecutive_conditionals
    source = %q{
<div>
  - if show_first? true
      <p>The first paragraph
  - if show_first? true
      <p>The second paragraph
}

    assert_html '<div><p>The first paragraph</p><p>The second paragraph</p></div>', source
  end

  def test_render_with_parameterized_conditional
    source = %q{
<div
  - if show_first? false
      <p>The first paragraph
  - else
      <p>The second paragraph
}

    assert_html '<div><p>The second paragraph</p></div>', source
  end

  def test_render_with_conditional_and_following_nonconditonal
    source = %q{
<div
  - if true
      <p>The first paragraph
  - var = 42
  = var
}

    assert_html '<div><p>The first paragraph</p>42</div>', source
  end

  def test_render_with_inline_condition
    source = %q{
<p>= hello_world if true
}

    assert_html '<p>Hello World from @env</p>', source
  end

  def test_render_with_case
    source = %q{
<p>
  - case 42
  - when 41
    1
  - when 42
    42
  > is the answer
}

    assert_html '<p>42 is the answer</p>', source
  end

  def test_render_with_slim_comments
    source = %q{
<p>Hello
# This is a comment
# Another comment
<p>World
}

    assert_html '<p>Hello</p><p>World</p>', source
  end

  def test_render_with_yield
    source = %q{
<div
  == yield :menu
}

    assert_html '<div>This is the menu</div>', source do
      'This is the menu'
    end
  end
end
