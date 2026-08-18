defmodule Mechanics.Pricing.Sources.Craigslist do
  @moduledoc false

  @behaviour Mechanics.Pricing.Sources

  alias Mechanics.Pricing.AuctionSource

  @impl true
  def search(%AuctionSource{}, _query, _opts), do: {:error, :not_implemented}

  @impl true
  def fetch_detail(_url_or_id, _opts), do: {:error, :not_implemented}
end
