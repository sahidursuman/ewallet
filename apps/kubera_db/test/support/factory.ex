defmodule KuberaDB.Factory do
  @moduledoc """
  Factories used for testing.
  """
  use ExMachina.Ecto, repo: KuberaDB.Repo
  alias KuberaDB.{Balance, MintedToken, User}

  def balance_factory do
    %Balance{
      address: sequence("address"),
      user: insert(:user),
      minted_token: nil,
      metadata: %{}
    }
  end

  def minted_token_factory do
    %MintedToken{
      symbol: sequence("jon"),
      iso_code: sequence("JON"),
      name: sequence("John Currency"),
      description: sequence("Official currency of Johndoeland"),
      short_symbol: sequence("J"),
      subunit: "Doe",
      subunit_to_unit: 100,
      symbol_first: true,
      html_entity: "&curren;",
      iso_numeric: sequence("990"),
      smallest_denomination: 1,
      locked: false,
    }
  end

  def user_factory do
    %User{
      username: sequence("johndoe"),
      provider_user_id: sequence("provider_id"),
      metadata: %{
        "first_name" => sequence("John"),
        "last_name" => sequence("Doe")
      }
    }
  end
end