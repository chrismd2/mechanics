defmodule MechanicsWeb.AdminHTML do
  use MechanicsWeb, :html

  embed_templates "admin_html/*"

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

  @doc """
  Best available timestamp for an Oban job row (no `updated_at` on Oban.Job).
  """
  def job_timestamp(%Oban.Job{} = job) do
    job.completed_at || job.discarded_at || job.cancelled_at || job.attempted_at ||
      job.scheduled_at || job.inserted_at
  end

  def pretty_json(value) do
    value
    |> Jason.encode!(pretty: true)
  rescue
    _ -> inspect(value, pretty: true, limit: :infinity)
  end

  def admin_path(opts \\ []) do
    tab = Keyword.get(opts, :tab, "sources")

    extras =
      opts
      |> Keyword.drop([:tab])
      |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
      |> Map.new(fn {k, v} -> {to_string(k), v} end)

    query = Map.put(extras, "tab", tab)
    "/admin?" <> URI.encode_query(query)
  end
end
