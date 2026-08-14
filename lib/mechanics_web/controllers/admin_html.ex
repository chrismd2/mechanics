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

  def search_row_id(row) when is_map(row) do
    Map.get(row, :id) || Map.get(row, "id")
  end

  def search_row_source(row) when is_map(row) do
    Map.get(row, :source) || Map.get(row, "source")
  end

  def search_row_url(row) when is_map(row) do
    Map.get(row, :source_url) || Map.get(row, "source_url")
  end

  def search_row_label(row) when is_map(row) do
    title = Map.get(row, :title) || Map.get(row, "title")

    if is_binary(title) and title != "" do
      title
    else
      [Map.get(row, :year) || Map.get(row, "year"), Map.get(row, :make) || Map.get(row, "make"), Map.get(row, :model) || Map.get(row, "model")]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" ")
      |> case do
        "" -> to_string(search_row_id(row))
        label -> label
      end
    end
  end

  def search_row_candidate_id(row) when is_map(row) do
    case Mechanics.Pricing.ListingSearch.parse_candidate_tool_id(to_string(search_row_id(row) || "")) do
      {:ok, uuid} -> uuid
      :error -> nil
    end
  end

  def admin_path(opts \\ []) do
    tab = Keyword.get(opts, :tab, "sources")

    extras =
      opts
      |> Keyword.drop([:tab])
      |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
      |> Map.new(fn {k, v} -> {to_string(k), to_string(v)} end)

    query = Map.put(extras, "tab", tab)
    "/admin?" <> URI.encode_query(query)
  end

  attr :source, :map, required: true
  attr :report, :any, default: nil
  attr :linked?, :boolean, default: false

  def auction_source_summary(assigns) do
    ~H"""
    <div class="min-w-0">
      <div class="font-medium text-zinc-900">
        <%= @source.label %>
        <%= if @linked? do %>
          <span class="ml-1 text-xs font-normal text-zinc-500">View last crawl job →</span>
        <% end %>
      </div>
      <div class="break-words text-zinc-600">
        <%= @source.base_url %> · <%= @source.kind %> ·
        <%= if @source.enabled, do: "enabled", else: "disabled" %>
        <%= if @source.last_crawled_at do %>
          · crawled <%= Calendar.strftime(@source.last_crawled_at, "%Y-%m-%d %H:%M") %>
        <% end %>
      </div>
      <%= if @report do %>
        <pre class="mt-2 max-h-32 max-w-full overflow-auto whitespace-pre-wrap break-words rounded bg-zinc-50 p-2 text-xs text-zinc-700"><%= Jason.encode!(@report) %></pre>
      <% end %>
    </div>
    """
  end
end
