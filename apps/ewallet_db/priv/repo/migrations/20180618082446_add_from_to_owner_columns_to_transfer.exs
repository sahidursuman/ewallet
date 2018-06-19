defmodule EWalletDB.Repo.Migrations.AddFromToOwnerColumnsToTransfer do
  use Ecto.Migration

  def change do
    alter table(:transfer) do
      add :from_account_uuid, references(:account, column: :uuid, type: :uuid)
      add :from_user_uuid, references(:user, column: :uuid, type: :uuid)
      add :to_account_uuid, references(:account, column: :uuid, type: :uuid)
      add :to_user_uuid, references(:user, column: :uuid, type: :uuid)
    end

    create index(:transfer, [:from_account_uuid, :to_account_uuid])
    create index(:transfer, [:to_account_uuid])
    create index(:transfer, [:from_user_uuid, :to_user_uuid])
    create index(:transfer, [:to_user_uuid])
  end
end
