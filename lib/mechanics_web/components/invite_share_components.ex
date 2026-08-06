defmodule MechanicsWeb.InviteShareComponents do
  @moduledoc """
  Shared UI for displaying an invite share URL and QR code.
  """
  use Phoenix.Component

  attr :url, :string, required: true
  attr :wrapper_id, :string, required: true
  attr :url_input_id, :string, required: true
  attr :qr_id, :string, required: true

  def invite_share_panel(assigns) do
    ~H"""
    <div id={@wrapper_id} class="rounded-lg border border-zinc-200 bg-white p-3">
      <div class="flex items-center gap-3">
        <div class="min-w-0 flex-1">
          <label for={@url_input_id} class="block text-xs font-semibold text-zinc-700">
            Share link
          </label>
          <input
            type="text"
            readonly
            id={@url_input_id}
            value={@url}
            onclick="this.select()"
            class="mt-1 w-full rounded-md border border-zinc-300 bg-white px-2 py-1.5 text-xs text-zinc-800"
          />
        </div>
        <div
          id={@qr_id}
          class="h-28 w-28 shrink-0 overflow-hidden rounded-md border border-zinc-200 bg-white p-1 [&>svg]:h-full [&>svg]:w-full"
          aria-label="QR code for invite link"
        >
          <%= qr_svg(@url) %>
        </div>
      </div>
    </div>
    """
  end

  defp qr_svg(url) when is_binary(url) do
    url
    |> EQRCode.encode()
    |> EQRCode.svg(width: 112, viewbox: true)
    |> Phoenix.HTML.raw()
  end
end
