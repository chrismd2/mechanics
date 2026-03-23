defmodule Mechanics.Disclaimers do
  @moduledoc """
  Stores and logs user acknowledgements for customer warranty and mechanic liability notices.
  """

  import Ecto.Query, warn: false

  alias Mechanics.Repo
  alias Mechanics.Disclaimers.DisclaimerText
  alias Mechanics.Disclaimers.UserDisclaimerAgreement

  @warranty_type "warranty"
  @liability_type "liability"

  @doc """
  Logs that `user_id` acknowledged a disclaimer.

  Finds the canonical disclaimer text row (by type + exact text); if missing, inserts it.
  Then inserts a `user_disclaimer_agreements` row referencing that text.
  """
  def log_user_agreement(user_id, disclaimer_type)

  def log_user_agreement(user_id, :warranty), do: log_user_agreement(user_id, @warranty_type)
  def log_user_agreement(user_id, :liability), do: log_user_agreement(user_id, @liability_type)

  def log_user_agreement(user_id, disclaimer_type)
      when is_binary(disclaimer_type) and disclaimer_type in [@warranty_type, @liability_type] do
    text = disclaimer_text(disclaimer_type)

    Repo.transaction(fn ->
      disclaimer_text_row = find_or_create_disclaimer_text!(disclaimer_type, text)

      agreement_attrs = %{
        user_id: user_id,
        disclaimer_text_id: disclaimer_text_row.id
      }

      case Repo.insert(UserDisclaimerAgreement.changeset(%UserDisclaimerAgreement{}, agreement_attrs)) do
        {:ok, agreement} -> agreement
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
    |> case do
      {:ok, %UserDisclaimerAgreement{} = agreement} -> {:ok, agreement}
      {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
      {:error, other} -> {:error, other}
    end
  end

  def log_user_agreement(_user_id, other), do: {:error, {:invalid_disclaimer_type, other}}

  def warranty_disclaimer_text, do: disclaimer_text(@warranty_type)
  def liability_disclaimer_text, do: disclaimer_text(@liability_type)

  defp disclaimer_text(disclaimer_type) do
    paragraphs =
      case disclaimer_type do
        @warranty_type -> customer_warranty_paragraphs()
        @liability_type -> mechanic_liability_paragraphs()
      end

    Enum.join(paragraphs, "\n\n")
  end

  defp customer_warranty_paragraphs do
    general_disclaimer = """
    The owner and any contributers to the Mechanics app are not responsible for indirect, incidental, special, consequential, or punitive damages arising from the work performed or use of the app.
    """

    [
      String.trim(general_disclaimer),
      "When you request work using the Mechanics app served by ElectricQuestLog, you understand that mechanics may provide services and/or parts without any specific warranty.",
      "Any implied warranties (including merchantability and fitness for a particular purpose) are disclaimed.",
      "Sometimes, repair and installation work can involve uncertainties (including condition of existing components) and agree to provide accurate information and access needed to perform the job.",
      "You are responsible for confirming scope of work, acceptable outcomes, pricing, and timing with the mechanic before and during the job.",
      "Mechanics may refuse or pause work where safety, authorization, or shop policies require it. Your acknowledgement helps ensure expectations are clear."
    ]
  end

  defp mechanic_liability_paragraphs do
    general_disclaimer = """
    The owner and any contributers to the Mechanics app are not responsible for indirect, incidental, special, consequential, or punitive damages arising from the work performed or use of the app.
    """

    [
      String.trim(general_disclaimer),
      "You, as the mechanic, are expected to use reasonable care, follow applicable safety practices, and communicate clearly with the customer about limitations, risks, and changes in scope.",
      "Customers acknowledge that repair and installation work can involve uncertainties (including condition of existing components) and agree to provide accurate information and access needed to perform the job.",
      "If additional work is required, you should obtain customer confirmation before proceeding."
    ]
  end

  defp find_or_create_disclaimer_text!(disclaimer_type, text) do
    case Repo.get_by(DisclaimerText, disclaimer_type: disclaimer_type, text: text) do
      %DisclaimerText{} = row ->
        row

      nil ->
        changeset = DisclaimerText.changeset(%DisclaimerText{}, %{disclaimer_type: disclaimer_type, text: text})

        case Repo.insert(changeset) do
          {:ok, %DisclaimerText{} = row} ->
            row

          {:error, _changeset} ->
            # If we lost a race, fetch the row and continue.
            case Repo.get_by(DisclaimerText, disclaimer_type: disclaimer_type, text: text) do
              %DisclaimerText{} = row -> row
              nil -> Repo.rollback(:could_not_create_disclaimer_text)
            end
        end
    end
  end
end

