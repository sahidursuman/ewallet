defmodule EWalletDB.Wallet do
  @moduledoc """
  Ecto Schema representing wallet.
  """
  use Ecto.Schema
  use EWalletDB.Types.WalletAddress
  import Ecto.{Changeset, Query}
  import EWalletDB.Validator
  alias Ecto.UUID
  alias ExULID.ULID
  alias EWalletDB.Types.WalletAddress
  alias EWalletDB.{Repo, Account, Wallet, User}

  @genesis "genesis"
  @burn "burn"
  @primary "primary"
  @secondary "secondary"

  @genesis_address "gnis000000000000"

  def genesis, do: @genesis
  def burn, do: @burn
  def primary, do: @primary
  def secondary, do: @secondary

  def genesis_address, do: @genesis_address

  @primary_key {:uuid, UUID, autogenerate: true}
  @cast_attrs [
    :address,
    :account_uuid,
    :user_uuid,
    :metadata,
    :encrypted_metadata,
    :name,
    :identifier
  ]

  schema "wallet" do
    # Wallet does not have an external ID. Use `address` instead.

    wallet_address(:address)
    field(:name, :string)
    field(:identifier, :string)
    field(:metadata, :map, default: %{})
    field(:encrypted_metadata, EWalletDB.Encrypted.Map, default: %{})

    belongs_to(
      :user,
      User,
      foreign_key: :user_uuid,
      references: :uuid,
      type: UUID
    )

    belongs_to(
      :account,
      Account,
      foreign_key: :account_uuid,
      references: :uuid,
      type: UUID
    )

    timestamps()
  end

  defp changeset(%Wallet{} = wallet, attrs) do
    wallet
    |> cast(attrs, @cast_attrs)
    |> validate_required([:name, :identifier])
    |> validate_format(
      :identifier,
      ~r/#{@genesis}|#{@burn}|#{@burn}_.|#{@primary}|#{@secondary}_.*/
    )
    |> validate_required_exclusive(%{account_uuid: nil, user_uuid: nil, identifier: @genesis})
    |> shared_changeset()
  end

  defp secondary_changeset(%Wallet{} = wallet, attrs) do
    wallet
    |> cast(attrs, @cast_attrs)
    |> validate_required([:name, :identifier])
    |> validate_format(:identifier, ~r/#{@secondary}_.*/)
    |> validate_required_exclusive([:account_uuid, :user_uuid])
    |> shared_changeset()
  end

  defp burn_changeset(%Wallet{} = wallet, attrs) do
    wallet
    |> cast(attrs, @cast_attrs)
    |> validate_required([:name, :identifier, :account_uuid])
    |> validate_format(:identifier, ~r/#{@burn}|#{@burn}_.*/)
    |> validate_required_exclusive([:account_uuid, :user_uuid])
    |> shared_changeset()
  end

  defp shared_changeset(changeset) do
    changeset
    |> validate_immutable(:address)
    |> unique_constraint(:address)
    |> assoc_constraint(:account)
    |> assoc_constraint(:user)
    |> unique_constraint(:unique_account_name, name: :wallet_account_uuid_name_index)
    |> unique_constraint(:unique_user_name, name: :wallet_user_uuid_name_index)
    |> unique_constraint(:unique_account_identifier, name: :wallet_account_uuid_identifier_index)
    |> unique_constraint(:unique_user_identifier, name: :wallet_user_uuid_identifier_index)
  end

  def all_for(%Account{} = account) do
    from(t in Wallet, where: t.account_uuid == ^account.uuid, preload: [:user, :account])
  end

  def all_for(%User{} = user) do
    from(t in Wallet, where: t.user_uuid == ^user.uuid, preload: [:user, :account])
  end

  def all_for(_), do: nil

  def query_all_for_account_uuids_and_user(query, account_uuids) do
    where(query, [w], w.account_uuid in ^account_uuids or not is_nil(w.user_uuid))
  end

  def query_all_for_account_uuids(query, account_uuids) do
    where(query, [w], w.account_uuid in ^account_uuids)
  end

  @doc """
  Retrieve a wallet using the specified address.
  """
  def get(nil), do: nil

  def get(address) do
    case WalletAddress.cast(address) do
      {:ok, address} ->
        Repo.get_by(Wallet, address: address)

      :error ->
        nil
    end
  end

  @doc """
  Create a new wallet with the passed attributes.
  A UUID is generated as the address if address is not specified.
  """
  def insert(attrs) do
    %Wallet{}
    |> changeset(attrs)
    |> Repo.insert()
  end

  def insert_secondary_or_burn(%{"identifier" => identifier} = attrs) do
    attrs
    |> Map.put("identifier", build_identifier(identifier))
    |> insert_secondary_or_burn(identifier)
  end

  # This will always fail but will return the errors in the expected Ecto format
  # Without us having to do anything about it.
  def insert_secondary_or_burn(attrs), do: insert_secondary_or_burn(attrs, nil)

  def insert_secondary_or_burn(attrs, "burn") do
    %Wallet{} |> burn_changeset(attrs) |> Repo.insert()
  end

  # "secondary" and anything else will go in there.
  def insert_secondary_or_burn(attrs, _) do
    %Wallet{} |> secondary_changeset(attrs) |> Repo.insert()
  end

  defp build_identifier("genesis"), do: @genesis
  defp build_identifier("primary"), do: @primary
  defp build_identifier("secondary"), do: "#{@secondary}_#{ULID.generate()}"
  defp build_identifier("burn"), do: "#{@burn}_#{ULID.generate()}"
  defp build_identifier(_), do: ""

  @doc """
  Returns the genesis wallet.
  """
  def get_genesis do
    case get(@genesis_address) do
      nil ->
        {:ok, genesis} = insert_genesis()
        genesis

      wallet ->
        wallet
    end
  end

  @doc """
  Inserts a genesis.
  """
  def insert_genesis do
    changeset =
      changeset(%Wallet{}, %{address: @genesis_address, name: @genesis, identifier: @genesis})

    opts = [on_conflict: :nothing, conflict_target: :address]

    case Repo.insert(changeset, opts) do
      {:ok, _wallet} ->
        {:ok, get(@genesis_address)}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Check if a wallet is a burn wallet.
  """
  @spec burn_wallet?(%Wallet{} | nil) :: true | false
  def burn_wallet?(nil), do: false
  def burn_wallet?(wallet), do: String.match?(wallet.identifier, ~r/^#{@burn}|#{@burn}:.*/)
end
