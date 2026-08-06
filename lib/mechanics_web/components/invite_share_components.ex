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
    modal_id = assigns.qr_id <> "-modal"
    open_id = assigns.qr_id <> "-open"
    assigns = assign(assigns, modal_id: modal_id, open_id: open_id)

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
        <button
          type="button"
          id={@open_id}
          class="h-28 w-28 shrink-0 overflow-hidden rounded-md border border-zinc-200 bg-white p-1 transition hover:border-zinc-400 hover:shadow-sm focus:outline-none focus:ring-2 focus:ring-zinc-400 [&>svg]:h-full [&>svg]:w-full"
          aria-label="Open larger QR code"
          aria-haspopup="dialog"
          aria-controls={@modal_id}
        >
          <span id={@qr_id} class="block h-full w-full [&>svg]:h-full [&>svg]:w-full">
            <%= qr_svg(@url, 112) %>
          </span>
        </button>
      </div>

      <div
        id={@modal_id}
        hidden
        class="fixed inset-0 z-50"
        role="dialog"
        aria-modal="true"
        aria-labelledby={"#{@modal_id}-title"}
      >
        <div class="absolute inset-0 bg-zinc-900/60" data-invite-qr-overlay></div>
        <div class="relative mx-auto mt-16 w-[95%] max-w-sm rounded-xl bg-white p-6 shadow-xl">
          <div class="flex items-start justify-between gap-4">
            <h2 id={"#{@modal_id}-title"} class="text-lg font-semibold text-zinc-900">
              Invite QR code
            </h2>
            <button
              type="button"
              class="text-zinc-500 hover:text-zinc-700"
              aria-label="Close"
              data-invite-qr-close
            >
              &times;
            </button>
          </div>
          <div
            id={"#{@qr_id}-large"}
            class="mx-auto mt-4 h-72 w-72 overflow-hidden rounded-md border border-zinc-200 bg-white p-3 [&>svg]:h-full [&>svg]:w-full"
          >
            <%= qr_svg(@url, 288) %>
          </div>
          <p class="mt-3 break-all text-center text-xs text-zinc-500"><%= @url %></p>
        </div>
      </div>

      <script>
        (function () {
          var openBtn = document.getElementById("<%= @open_id %>");
          var modal = document.getElementById("<%= @modal_id %>");
          if (!openBtn || !modal) return;

          function openModal() {
            modal.hidden = false;
            document.body.style.overflow = "hidden";
          }

          function closeModal() {
            modal.hidden = true;
            document.body.style.overflow = "";
          }

          openBtn.addEventListener("click", openModal);

          modal.querySelectorAll("[data-invite-qr-close]").forEach(function (btn) {
            btn.addEventListener("click", closeModal);
          });

          var overlay = modal.querySelector("[data-invite-qr-overlay]");
          if (overlay) overlay.addEventListener("click", closeModal);

          document.addEventListener("keydown", function (e) {
            if (e.key === "Escape" && !modal.hidden) closeModal();
          });
        })();
      </script>
    </div>
    """
  end

  defp qr_svg(url, width) when is_binary(url) and is_integer(width) do
    url
    |> EQRCode.encode()
    |> EQRCode.svg(width: width, viewbox: true)
    |> Phoenix.HTML.raw()
  end
end
