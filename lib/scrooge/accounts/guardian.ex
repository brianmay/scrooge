defmodule Scrooge.Accounts.Guardian do
  @moduledoc "Guardian support functions"
  use Guardian, otp_app: :scrooge

  alias Scrooge.Accounts

  def subject_for_token(user, _claims) do
    {:ok, to_string(user.id)}
  end

  def resource_from_claims(%{"sub" => id}) do
    case Accounts.get_user!(id) do
      nil -> {:error, :resource_not_found}
      user -> {:ok, user}
    end
  end
end
