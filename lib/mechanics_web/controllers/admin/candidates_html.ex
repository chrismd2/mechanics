defmodule MechanicsWeb.Admin.CandidatesHTML do
  use MechanicsWeb, :html

  embed_templates "candidates_html/*"

  def pretty_json(value) do
    value
    |> Jason.encode!(pretty: true)
  rescue
    _ -> inspect(value, pretty: true, limit: :infinity)
  end

  def format_dt(nil), do: "—"

  def format_dt(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S UTC")
  end

  def format_dt(_), do: "—"
end
