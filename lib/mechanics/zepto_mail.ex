defmodule Mechanics.ZeptoMail do
  @moduledoc """
  Sends email via the [ZeptoMail](https://www.zoho.com/zeptomail/) HTTP API.

  Environment variables:

  - `ZEPTO_SEND_MAIL_TOKEN` — API token (required for each request)
  - `ZEPTO_FROM_ADDRESS` — default sender if `from` argument is omitted
  - `ZEPTO_BOUNCE_ADDRESS` — optional bounce return path
  """
  require Logger

  @api_url "https://api.zeptomail.com/v1.1/email"

  @doc """
  Sends a transactional email. `from` defaults to `ZEPTO_FROM_ADDRESS` when nil.
  """
  def send_email(to, subject, html_body, text_body \\ nil, from \\ nil) do
    api_token =
      System.get_env("ZEPTO_SEND_MAIL_TOKEN") ||
        raise "ZEPTO_SEND_MAIL_TOKEN environment variable is not set"

    if api_token == "" do
      raise "ZEPTO_SEND_MAIL_TOKEN environment variable is empty"
    end

    from_address = from || System.get_env("ZEPTO_FROM_ADDRESS") ||
      raise "Set ZEPTO_FROM_ADDRESS or pass `from` when sending ZeptoMail email"

    bounce_address = System.get_env("ZEPTO_BOUNCE_ADDRESS")

    case validate_email(to) do
      :ok ->
        body =
          build_request_body(to, subject, html_body, text_body, from_address, bounce_address)

        headers = [
          {"Accept", "application/json"},
          {"Content-Type", "application/json"},
          {"Authorization", zepto_authorization_header(api_token)}
        ]

        Logger.debug("Sending email to #{to} via ZeptoMail API")

        case Finch.build(:post, @api_url, headers, body) |> Finch.request(Mechanics.Finch) do
          {:ok, %{status: status, body: response_body} = response} when status in 200..299 ->
            case Jason.decode(response_body) do
              {:ok, decoded} ->
                Logger.info("Email sent successfully to #{to}")
                Logger.debug("ZeptoMail response: #{inspect(decoded)}")

                if Map.get(decoded, "object") == "email" do
                  Enum.each(Map.get(decoded, "data", []), fn item ->
                    code = Map.get(item, "code", "")
                    message = Map.get(item, "message", "")
                    Logger.debug("ZeptoMail code: #{code}, message: #{message}")

                    if code in ["EM_104", "EM_105"] do
                      Logger.warning(
                        "Email accepted but may be in sandbox/test mode. Check ZeptoMail dashboard for delivery status."
                      )
                    end
                  end)
                end

              {:error, _} ->
                Logger.info("Email sent successfully to #{to} (response not JSON)")
            end

            {:ok, response}

          {:ok, %{status: status, body: response_body, headers: response_headers}} ->
            response_str =
              if is_binary(response_body), do: response_body, else: inspect(response_body)

            error_message =
              case Jason.decode(response_str) do
                {:ok, decoded} -> inspect(decoded)
                {:error, _} ->
                  if String.trim(response_str) == "", do: "(empty response body)", else: response_str
              end

            Logger.error("Failed to send email to #{to}: HTTP #{status}")
            Logger.error("Error message: #{error_message}")

            content_type = List.keyfind(response_headers, "content-type", 0)

            if content_type && String.contains?(elem(content_type, 1), "text/html") do
              Logger.error("ZeptoMail returned HTML — check token, domain verification, and permissions")
            end

            {:error, {:http_error, status, response_str}}

          {:error, reason} ->
            Logger.error("Failed to send email to #{to}: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} ->
        Logger.warning("Email not sent to #{to}: #{reason}")
        {:error, reason}
    end
  end

  defp build_request_body(to, subject, html_body, text_body, from_address, bounce_address) do
    base_body = %{
      from: %{address: from_address},
      to: [%{email_address: %{address: to}}],
      subject: subject,
      htmlbody: html_body
    }

    body = if text_body, do: Map.put(base_body, :textbody, text_body), else: base_body

    body =
      if bounce_address not in [nil, ""] and String.trim(bounce_address) != "",
        do: Map.put(body, :bounce_address, bounce_address),
        else: body

    Jason.encode!(body)
  end

  # ZeptoMail expects: Authorization: Zoho-enczapikey <token> (see API / curl examples).
  defp zepto_authorization_header(token) do
    t = String.trim(token)

    if String.starts_with?(t, "Zoho-enczapikey") do
      t
    else
      "Zoho-enczapikey " <> t
    end
  end

  defp validate_email(email) do
    case String.split(email, "@") do
      [_local, domain] ->
        if domain == "not-a.pg" do
          {:error, "Cannot send email to test domain: #{domain}"}
        else
          :ok
        end

      _ ->
        {:error, "Invalid email format"}
    end
  end
end
