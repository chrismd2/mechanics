defmodule Mechanics.Accounts.PasswordResetEmail do
  @moduledoc false

  alias Mechanics.Accounts.User
  alias Mechanics.Mailer
  alias Mechanics.ZeptoMail

  def deliver(%User{email: email}, token, opts \\ []) do
    case Application.get_env(:mechanics, :transactional_email_backend) do
      :zepto ->
        {_name, from_email} = default_from()
        msg = build(email, token, Keyword.merge(opts, full_urls: true))
        ZeptoMail.send_email(
          email,
          msg.subject,
          msg.html_body,
          msg.text_body,
          from_email
        )

      _ ->
        Mailer.deliver(build(email, token, opts))
    end
  end

  def build(email, token, opts \\ []) do
    reset_link =
      if Keyword.get(opts, :full_urls, false) do
        public_reset_url(token, Keyword.get(opts, :base_url))
      else
        "/password/reset?token=#{token}"
      end

    text_body =
      "If you have an account with us, then we'll send you a reset request.\n\n" <>
        "Reset link: #{reset_link}"

    html_body = """
    <p>If you have an account with us, then we'll send you a reset request.</p>
    <p><a href="#{reset_link}">Reset your password</a></p>
    """

    Swoosh.Email.new(
      to: email,
      from: default_from(),
      subject: "Password reset request",
      text_body: text_body,
      html_body: html_body
    )
  end

  defp public_reset_url(token, base_url) do
    base_url =
      cond do
        is_binary(base_url) and base_url != "" ->
          String.trim_trailing(base_url, "/")

        true ->
          endpoint_url =
            try do
              MechanicsWeb.Endpoint.url()
            rescue
              _ -> nil
            end

          endpoint_url || "https://#{System.get_env("PHX_HOST") || "localhost"}"
      end

    "#{base_url}/password/reset?token=#{token}"
  end

  defp default_from do
    Application.get_env(:mechanics, :mailer_default_from) || default_from_env()
  end

  defp default_from_env do
    name = System.get_env("MAIL_FROM_NAME") || "Mechanics"

    case System.get_env("MAIL_FROM_EMAIL") || System.get_env("ZEPTO_FROM_ADDRESS") do
      addr when is_binary(addr) and addr != "" -> {name, addr}
      _ -> {name, "no-reply@electricquestlog.com"}
    end
  end
end
