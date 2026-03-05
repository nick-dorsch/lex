defmodule LexWeb.ErrorView do
  use LexWeb, :html

  def render(template, assigns) do
    LexWeb.ErrorHTML.render(template, assigns)
  end
end
