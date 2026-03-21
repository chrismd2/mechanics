defmodule MechanicsWeb.NotificationBellComponents do
  @moduledoc """
  Shared UI for card-level chat bells: `<details>` with count and a peer list,
  mirroring the header inbox pattern (count = unread messages in scope).
  """

  use Phoenix.Component

  import MechanicsWeb.ChatTime, only: [datetime_html_attr: 1]

  use Phoenix.VerifiedRoutes,
    endpoint: MechanicsWeb.Endpoint,
    router: MechanicsWeb.Router,
    statics: MechanicsWeb.static_paths()

  attr :id, :string, required: true
  attr :count, :integer, required: true
  attr :peers, :list, required: true
  attr :data_test, :string, required: true
  attr :aria_label, :string, required: true

  @doc """
  Renders a bell control that expands to show counterparties (users) with unread
  messages in this card's context, each linking to the relevant chat.
  """
  def bell_card(assigns) do
    ~H"""
    <details
      id={@id}
      class="relative min-w-[3rem] border-l border-zinc-100"
      data-test={@data_test}
    >
      <summary
        class="flex cursor-pointer list-none flex-col items-center justify-center px-2 py-2 text-zinc-700 hover:bg-zinc-50 [&::-webkit-details-marker]:hidden"
        aria-label={@aria_label}
      >
        <svg
          xmlns="http://www.w3.org/2000/svg"
          class="h-5 w-5"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="1.5"
          stroke="currentColor"
          aria-hidden="true"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="M15 17h5l-1.405-1.405A2.032 2.032 0 0118 14.158V11a6.002 6.002 0 00-4-5.659V5a2 2 0 10-4 0v.341C7.67 6.165 6 8.388 6 11v3.159c0 .538-.214 1.055-.595 1.436L4 17h5m6 0v1a3 3 0 11-6 0v-1m6 0H9"
          />
        </svg>
        <span
          class="text-xs font-semibold"
          data-test={"#{@data_test}-count"}
        >
          <%= @count %>
        </span>
      </summary>
      <div
        id={"#{@id}-panel"}
        class="absolute right-0 top-full z-40 mt-1 w-64 rounded-lg border border-zinc-200 bg-white py-1 shadow-lg"
      >
        <ul id={"#{@id}-peer-list"} class="text-sm" role="list">
          <%= for peer <- @peers do %>
            <li class="card-notification-peer-row">
              <a
                href={~p"/chats/#{peer.chat_id}"}
                class="block px-3 py-2 hover:bg-zinc-50"
              >
                <div class="flex items-start justify-between gap-2">
                  <span class="min-w-0 font-medium text-zinc-900"><%= peer.display_name %></span>
                  <%= if peer[:last_message_at] do %>
                    <time
                      class="shrink-0 text-xs tabular-nums text-zinc-400"
                      datetime={datetime_html_attr(peer.last_message_at)}
                      data-local-chat-time
                    >
                      …
                    </time>
                  <% end %>
                </div>
                <div class="mt-0.5 text-xs text-zinc-500">
                  <%= peer.unread_count %> unread
                </div>
              </a>
            </li>
          <% end %>
        </ul>
      </div>
    </details>
    """
  end
end
