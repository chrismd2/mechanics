defmodule MechanicsWeb.RequestURL do
  @moduledoc """
  Builds absolute public URLs from the incoming request host.

  Prefer this over `url(~p"...")` when the link will be shared outside the app
  (emails, invite share links). Behind nginx, Endpoint `url` config often stays
  on localhost while `Host` / `X-Forwarded-Host` carry the public hostname.
  """

  @doc """
  Returns `https://<public-host>` using `X-Forwarded-Host` when present.
  """
  def base_url(%Plug.Conn{} = conn) do
    host =
      case Plug.Conn.get_req_header(conn, "x-forwarded-host") do
        [h | _] when is_binary(h) and h != "" -> h
        _ -> conn.host
      end

    "https://#{host}"
  end

  @doc """
  Absolute invite accept URL for `token`.
  """
  def invite_url(%Plug.Conn{} = conn, token) when is_binary(token) do
    base_url(conn) <> "/invites/" <> token
  end
end
