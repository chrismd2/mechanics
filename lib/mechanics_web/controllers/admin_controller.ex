defmodule MechanicsWeb.AdminController do
  use MechanicsWeb, :controller

  alias Mechanics.Pricing.ListingSearch
  alias Mechanics.Pricing.AuctionSource

  @tabs ~w(sources jobs candidates)

  def index(conn, params) do
    case admin_user(conn) do
      {:ok, _user} ->
        render_admin(conn, params)

      :error ->
        redirect(conn, to: ~p"/")
    end
  end

  def create_source(conn, %{"auction_source" => params}) do
    case admin_user(conn) do
      {:ok, _user} ->
        case ListingSearch.create_auction_source(params) do
          {:ok, _source} ->
            conn
            |> put_flash(:info, "Auction source added.")
            |> redirect(to: admin_path(tab: "sources"))

          {:error, changeset} ->
            conn
            |> put_flash(:error, "Could not add auction source.")
            |> render_admin(%{"tab" => "sources"}, changeset: changeset)
        end

      :error ->
        redirect(conn, to: ~p"/")
    end
  end

  def update_source(conn, %{"id" => id, "auction_source" => params}) do
    case admin_user(conn) do
      {:ok, _user} ->
        source = ListingSearch.get_auction_source!(id)

        case ListingSearch.update_auction_source(source, params) do
          {:ok, _source} ->
            conn
            |> put_flash(:info, "Auction source updated.")
            |> redirect(to: admin_path(tab: "sources"))

          {:error, _changeset} ->
            conn
            |> put_flash(:error, "Could not update auction source.")
            |> redirect(to: admin_path(tab: "sources"))
        end

      :error ->
        redirect(conn, to: ~p"/")
    end
  end

  def create_source_from_suggestion(conn, %{"base_url" => base_url, "kind" => kind, "label" => label}) do
    case admin_user(conn) do
      {:ok, _user} ->
        attrs = %{
          "base_url" => base_url,
          "kind" => kind,
          "label" => label,
          "enabled" => true
        }

        case ListingSearch.create_auction_source(attrs) do
          {:ok, _} ->
            conn
            |> put_flash(:info, "Suggested source added.")
            |> redirect(to: admin_path(tab: "sources"))

          {:error, _} ->
            conn
            |> put_flash(:error, "Could not add suggested source.")
            |> redirect(to: admin_path(tab: "sources"))
        end

      :error ->
        redirect(conn, to: ~p"/")
    end
  end

  def enqueue_crawl(conn, params) do
    case admin_user(conn) do
      {:ok, _user} ->
        opts =
          case blank_to_nil(params["source_id"]) do
            nil -> []
            source_id -> [source_id: source_id]
          end

        case ListingSearch.enqueue_crawl(opts) do
          {:ok, job} ->
            conn
            |> put_flash(:info, "Crawl job ##{job.id} enqueued (queue: #{job.queue}).")
            |> redirect(to: ~p"/admin/jobs/#{job.id}")

          {:error, reason} ->
            conn
            |> put_flash(:error, "Could not enqueue crawl: #{inspect(reason)}")
            |> redirect(to: admin_path(tab: "jobs"))
        end

      :error ->
        redirect(conn, to: ~p"/")
    end
  end

  def trial_search(conn, params) do
    case admin_user(conn) do
      {:ok, user} ->
        vehicle = normalize_vehicle(params["vehicle"] || %{})
        make = vehicle["make"]
        model = vehicle["model"]

        {flash_conn, results} =
          cond do
            blank?(make) or blank?(model) ->
              {put_flash(conn, :error, "Enter make and model (same as the pricing form)."), []}

            true ->
              case ListingSearch.search_for_vehicle(make, model, user_id: user.id) do
                {:ok, candidates} ->
                  {put_flash(
                     conn,
                     :info,
                     "search_for_vehicle(#{make}, #{model}) returned #{length(candidates)} candidate(s)."
                   ), candidates}

                {:error, :blank_query} ->
                  {put_flash(conn, :error, "Enter make and model."), []}

                {:error, reason} ->
                  {put_flash(conn, :error, "Search failed: #{inspect(reason)}"), []}
              end
          end

        render_admin(flash_conn, %{"tab" => "jobs"},
          vehicle: vehicle,
          search_results: results
        )

      :error ->
        redirect(conn, to: ~p"/")
    end
  end

  def enqueue_digest(conn, %{"id" => id}) do
    case admin_user(conn) do
      {:ok, user} ->
        _candidate = ListingSearch.get_candidate!(id)

        case ListingSearch.enqueue_digest(id, user.id) do
          {:ok, job} ->
            conn
            |> put_flash(:info, "Digest job ##{job.id} enqueued.")
            |> redirect(to: ~p"/admin/jobs/#{job.id}")

          {:error, reason} ->
            conn
            |> put_flash(:error, "Could not enqueue digest: #{inspect(reason)}")
            |> redirect(to: admin_path(tab: "candidates"))
        end

      :error ->
        redirect(conn, to: ~p"/")
    end
  end

  def dismiss_candidate(conn, %{"id" => id}) do
    case admin_user(conn) do
      {:ok, _user} ->
        candidate = ListingSearch.get_candidate!(id)

        case ListingSearch.dismiss_candidate(candidate) do
          {:ok, _} ->
            conn
            |> put_flash(:info, "Candidate dismissed.")
            |> redirect(to: admin_path(tab: "candidates"))

          {:error, _} ->
            conn
            |> put_flash(:error, "Could not dismiss candidate.")
            |> redirect(to: ~p"/admin/candidates/#{id}")
        end

      :error ->
        redirect(conn, to: ~p"/")
    end
  end

  defp render_admin(conn, params, overrides \\ []) do
    tab = normalize_tab(Map.get(params, "tab"))
    queue = blank_to_nil(Map.get(params, "queue"))
    status = blank_to_nil(Map.get(params, "status"))

    assigns =
      [
        admin_tab: tab,
        sources: ListingSearch.list_auction_sources(),
        suggestions: ListingSearch.suggest_auction_sources(limit: 15),
        changeset: Keyword.get(overrides, :changeset) || ListingSearch.change_auction_source(%AuctionSource{}),
        jobs: ListingSearch.list_oban_jobs(limit: 50, queue: queue),
        enabled_sources: ListingSearch.list_auction_sources(enabled: true),
        queue: queue,
        vehicle: Keyword.get(overrides, :vehicle) || empty_vehicle(),
        search_results: Keyword.get(overrides, :search_results),
        candidates: ListingSearch.list_candidates(limit: 100, status: status),
        status: status,
        wide_layout: true
      ]
      |> Keyword.merge(Keyword.take(overrides, [:changeset, :vehicle, :search_results]))

    conn
    |> assign(:wide_layout, true)
    |> render(:index, assigns)
  end

  defp admin_path(opts) do
    tab = Keyword.get(opts, :tab, "sources")
    extras =
      opts
      |> Keyword.drop([:tab])
      |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
      |> Map.new(fn {k, v} -> {to_string(k), v} end)

    query = Map.put(extras, "tab", tab)
    "/admin?" <> URI.encode_query(query)
  end

  defp normalize_tab(tab) when tab in @tabs, do: tab
  defp normalize_tab(_), do: "sources"

  defp admin_user(conn) do
    current_user = conn.assigns[:current_user]

    if current_user && "admin" in (current_user.roles || []) do
      {:ok, current_user}
    else
      :error
    end
  end

  defp empty_vehicle do
    %{"make" => "", "model" => "", "year" => "", "miles" => "", "zipcode" => "00000"}
  end

  defp normalize_vehicle(params) when is_map(params) do
    %{
      "make" => params |> Map.get("make") |> to_string() |> String.trim(),
      "model" => params |> Map.get("model") |> to_string() |> String.trim(),
      "year" => params |> Map.get("year") |> to_string() |> String.trim(),
      "miles" => params |> Map.get("miles") |> to_string() |> String.trim(),
      "zipcode" =>
        case params |> Map.get("zipcode") |> to_string() |> String.trim() do
          "" -> "00000"
          zip -> zip
        end
    }
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_), do: false

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
