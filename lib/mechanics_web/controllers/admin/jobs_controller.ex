defmodule MechanicsWeb.Admin.JobsController do
  use MechanicsWeb, :controller

  alias Mechanics.Pricing.ListingSearch

  def index(conn, params) do
    query =
      %{"tab" => "jobs"}
      |> maybe_put("queue", params["queue"])
      |> URI.encode_query()

    redirect(conn, to: "/admin?#{query}")
  end

  def show(conn, %{"id" => id}) do
    case admin_user(conn) do
      {:ok, _user} ->
        job = ListingSearch.get_oban_job!(id)
        results = ListingSearch.results_for_oban_job(job)

        conn
        |> assign(:wide_layout, true)
        |> render(:show, job: job, results: results)

      :error ->
        redirect(conn, to: ~p"/")
    end
  end

  def retry(conn, %{"id" => id}) do
    case admin_user(conn) do
      {:ok, _user} ->
        case ListingSearch.retry_oban_job(id) do
          {:ok, job} ->
            conn
            |> put_flash(:info, "Job ##{job.id} requeued (state: #{job.state}).")
            |> redirect(to: ~p"/admin/jobs/#{job.id}")

          {:error, {:not_retryable, state}} ->
            conn
            |> put_flash(:error, "Job is not retryable (state: #{state}).")
            |> redirect(to: ~p"/admin/jobs/#{id}")

          {:error, reason} ->
            conn
            |> put_flash(:error, "Could not retry job: #{inspect(reason)}")
            |> redirect(to: ~p"/admin/jobs/#{id}")
        end

      :error ->
        redirect(conn, to: ~p"/")
    end
  end

  def run_now(conn, %{"id" => id}) do
    case admin_user(conn) do
      {:ok, _user} ->
        case ListingSearch.run_oban_job_now(id) do
          {:ok, job} ->
            conn
            |> put_flash(:info, "Job ##{job.id} set to run now (state: #{job.state}).")
            |> redirect(to: ~p"/admin/jobs/#{job.id}")

          {:error, {:not_runnable_now, state}} ->
            conn
            |> put_flash(:error, "Job cannot run now (state: #{state}). Use Retry if it failed.")
            |> redirect(to: ~p"/admin/jobs/#{id}")

          {:error, reason} ->
            conn
            |> put_flash(:error, "Could not run job now: #{inspect(reason)}")
            |> redirect(to: ~p"/admin/jobs/#{id}")
        end

      :error ->
        redirect(conn, to: ~p"/")
    end
  end

  defp admin_user(conn) do
    current_user = conn.assigns[:current_user]

    if current_user && "admin" in (current_user.roles || []) do
      {:ok, current_user}
    else
      :error
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
