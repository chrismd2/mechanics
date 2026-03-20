defmodule Mechanics.Accounts.PasswordResetEmail do
  @moduledoc false

  alias Mechanics.Accounts.User
  alias Mechanics.Mailer

  def deliver(%User{email: email}, token) do
    email_struct = build(email, token)
    Mailer.deliver(email_struct)
  end

  def build(email, token) do
    reset_link = "/password/reset?token=#{token}"

    text_body =
      "If you have an account with us, then we'll send you a reset request.\n\n" <>
        "Reset link: #{reset_link}"

    html_body = """
    <p>If you have an account with us, then we'll send you a reset request.</p>
    <p><a href="#{reset_link}">Reset your password</a></p>
    """

    Swoosh.Email.new(
      to: email,
      from: {"Mechanics", "no-reply@mechanics.local"},
      subject: "Password reset request",
      text_body: text_body,
      html_body: html_body
    )
  end
end

