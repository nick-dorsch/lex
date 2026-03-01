defmodule LexWeb.ErrorHTML do
  use LexWeb, :html

  def render("404.html", _assigns) do
    "Page not found"
  end

  def render("500.html", _assigns) do
    "Internal server error"
  end

  def render(_template, _assigns) do
    "Something went wrong"
  end
end
