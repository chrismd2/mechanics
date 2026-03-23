defmodule MechanicsWeb.ChatTime do
  @moduledoc """
  ISO `datetime` attributes for `<time>` elements. Visible labels use the viewer’s local
  timezone in the browser (`assets/js/chat_transcript_time.mjs` + `data-local-chat-time`).
  """

  @doc """
  Human-readable UTC time (e.g. emails or non-HTML diagnostics). Prefer `datetime_html_attr/1`
  plus client-side formatting for page UI.
  """
  def format_message_time(nil), do: ""

  def format_message_time(%DateTime{} = dt) do
    dt
    |> DateTime.truncate(:second)
    |> DateTime.to_naive()
    |> Calendar.strftime("%Y-%m-%d %H:%M UTC")
  end

  @doc "Value for HTML `datetime` on `<time>` elements."
  def datetime_html_attr(nil), do: ""

  def datetime_html_attr(%DateTime{} = dt) do
    dt |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  end
end
