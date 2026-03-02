defmodule LexWeb.Router do
  use LexWeb, :router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {LexWeb.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope "/", LexWeb do
    pipe_through(:browser)

    live("/", LibraryLive.Index)
    live("/library", LibraryLive.Index)
    live("/read/:document_id", ReaderLive.Show)
  end

  scope "/api", LexWeb do
    pipe_through(:api)

    # API routes will be added here
  end
end
