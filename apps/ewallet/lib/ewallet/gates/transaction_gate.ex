defmodule EWallet.TransactionGate do
  @moduledoc """
  Handles the logic for a transfer of value from an account to a user. Delegates the
  actual transfer to EWallet.TransferGate once the wallets have been loaded.
  """
  alias EWallet.{
    TransactionSourceFetcher,
    TransferGate
  }

  alias EWalletDB.{Transfer, Token}

  def create(%{"token_id" => token_id} = attrs) do
    with from = TransactionSourceFetcher.fetch_from(attrs),
         to = TransactionSourceFetcher.fetch_to(attrs),
         %Token{} = token <- Token.get(token_id) || :token_not_found,
         {:ok, transfer} <- get_or_insert_transfer(from, to, token, attrs) do
      process_with_transfer(transfer)
    else
      error -> error
    end
  end

  def create(_), do: {:error, :invalid_parameter}

  defp get_or_insert_transfer(
         from,
         to,
         token,
         %{
           "amount" => amount,
           "idempotency_token" => idempotency_token
         } = attrs
       ) do
    TransferGate.get_or_insert(%{
      idempotency_token: idempotency_token,
      from_account: from[:from_account],
      from_user: from[:from_user],
      from_wallet: from.from_wallet,
      to_account: to[:to_account],
      to_user: to[:to_user],
      to_wallet: to.to_wallet,
      token: token,
      amount: amount,
      metadata: attrs["metadata"] || %{},
      encrypted_metadata: attrs["encrypted_metadata"] || %{},
      payload: attrs
    })
  end

  defp process_with_transfer(%Transfer{status: "pending"} = transfer) do
    transfer
    |> TransferGate.process()
    |> process_with_transfer()
  end

  defp process_with_transfer(%Transfer{status: "confirmed"} = transfer) do
    {:ok, transfer}
  end

  defp process_with_transfer(%Transfer{status: "failed"} = transfer) do
    {:error, transfer, transfer.error_code, transfer.error_description || transfer.error_data}
  end
end
