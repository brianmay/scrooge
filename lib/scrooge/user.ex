defmodule Scrooge.User do
  @moduledoc "Authentication support"

  @type t :: %__MODULE__{
          name: String.t(),
          sub: String.t(),
          groups: list(String.t())
        }
  @enforce_keys [:name, :sub, :groups]
  defstruct [:name, :sub, :groups]

  @type any_user_t :: t() | :anonymous

  @spec claims_to_user(map() | nil) :: any_user_t()
  def claims_to_user(nil) do
    :anonymous
  end

  def claims_to_user(claims) do
    %__MODULE__{
      name: claims["name"] || "",
      sub: claims["sub"] || "",
      groups: claims["groups"] || {}
    }
  end

  @spec user_signed_in?(any_user_t()) :: bool
  def user_signed_in?(:anonymous), do: false
  def user_signed_in?(%__MODULE__{}), do: true

  @spec user_is_admin?(any_user_t()) :: boolean()
  def user_is_admin?(:anonymous) do
    false
  end

  def user_is_admin?(%__MODULE__{} = user) do
    Enum.member?(user.groups, "admin")
  end
end
