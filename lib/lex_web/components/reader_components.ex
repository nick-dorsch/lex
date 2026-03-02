defmodule LexWeb.ReaderComponents do
  @moduledoc """
  Components for the reader interface.
  """

  use Phoenix.Component

  @doc """
  Renders a token with color-coded status box.

  ## Examples

      <.token token={token} status={:new} focused={false} />
      <.token token={token} status={:learning} focused={true} />
  """
  attr(:token, :map, required: true)
  attr(:status, :atom, values: [:new, :seen, :learning, :known], required: true)
  attr(:focused, :boolean, default: false)

  def token(assigns) do
    ~H"""
    <span
      class={[
        status_class(@status),
        @focused && "ring-2 ring-indigo-500"
      ]}
      data-token-id={@token.id}
    >
      <%= @token.surface %>
    </span>
    """
  end

  defp status_class(:new), do: "bg-amber-200 px-1 rounded cursor-pointer"
  defp status_class(:seen), do: "border border-gray-400 border-dashed px-1 rounded cursor-pointer"
  defp status_class(:learning), do: "bg-blue-200 px-1 rounded cursor-pointer"
  defp status_class(:known), do: "cursor-pointer"
end
