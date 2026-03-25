defmodule MechanicsWeb.AltchaController do
  use MechanicsWeb, :controller

  alias Mechanics.Altcha

  def challenge(conn, _params) do
    case Altcha.create_challenge() do
      {:ok, challenge} ->
        json(conn, challenge)

      {:error, :disabled} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "ALTCHA is disabled"})
    end
  end
end
