defmodule HexHub.HTTPClient.Swoosh do
  @moduledoc "HTTP fetch adapter for Swoosh email provider APIs."

  @behaviour Swoosh.ApiClient

  @impl true
  def post(url, headers, body, %Swoosh.Email{} = email) do
    {timeout, opts} = Keyword.pop(email.private[:client_options] || [], :receive_timeout, 30_000)

    redirect =
      case Keyword.get(opts, :redirect, :follow) do
        true -> :follow
        false -> :manual
        mode -> mode
      end

    opts =
      opts
      |> Keyword.put_new(:timeout, timeout)
      |> Keyword.merge(
        headers: [{"user-agent", "swoosh/#{Swoosh.version()}"} | headers],
        body: body,
        redirect: redirect,
        decode_body: true,
        json: false
      )

    case HexHub.HTTPClient.request(:post, IO.iodata_to_binary(url), opts) do
      {:ok, response} ->
        {:ok, response.status, response.headers, response.body}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
