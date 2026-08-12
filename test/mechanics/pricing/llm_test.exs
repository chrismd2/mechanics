defmodule Mechanics.Pricing.LLMTest do
  use ExUnit.Case, async: true

  alias Mechanics.Pricing.LLM

  test "returns missing_api_key when api_key is nil" do
    assert {:error, :missing_api_key} =
             LLM.chat_completion([%{"role" => "user", "content" => "hi"}], [], api_key: nil)
  end

  test "returns http_error when provider responds with non-2xx (e.g. invalid key)" do
    http =
      fn _url, _headers, _body ->
        {:ok, %{status: 401, body: ~s({"error":{"message":"Invalid API Key"}})}}
      end

    assert {:error, {:http_error, 401}} =
             LLM.chat_completion([%{"role" => "user", "content" => "hi"}], [],
               api_key: "invalid-key",
               http_client: http
             )
  end

  test "returns error when http_client raises instead of returning a tuple" do
    http = fn _url, _headers, _body -> raise "boom" end

    assert {:error, {:exception, message}} =
             LLM.chat_completion([%{"role" => "user", "content" => "hi"}], [],
               api_key: "any-key",
               http_client: http
             )

    assert message =~ "boom"
  end
end
