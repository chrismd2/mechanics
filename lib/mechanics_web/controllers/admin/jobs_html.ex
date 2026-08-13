defmodule MechanicsWeb.Admin.JobsHTML do
  use MechanicsWeb, :html

  embed_templates "jobs_html/*"

  def short_worker(worker) when is_binary(worker) do
    worker
    |> String.split(".")
    |> List.last()
  end

  def short_worker(_), do: "—"

  def format_dt(nil), do: "—"

  def format_dt(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S UTC")
  end

  def format_dt(_), do: "—"

  def pretty_json(value) do
    value
    |> Jason.encode!(pretty: true)
  rescue
    _ -> inspect(value, pretty: true, limit: :infinity)
  end

  def job_results(%{meta: meta}) when is_map(meta) do
    case Map.get(meta, "results") do
      list when is_list(list) -> list
      _ -> nil
    end
  end

  def job_results(_), do: nil
end
