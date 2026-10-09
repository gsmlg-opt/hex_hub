defmodule HexHub.HTTPClient.ExAws do
  @moduledoc "HTTP fetch adapter for S3 and other ExAws requests."

  @behaviour ExAws.Request.HttpClient

  @impl true
  def request(method, url, body, headers, http_opts) do
    {timeout, opts} = Keyword.pop(http_opts, :recv_timeout, 30_000)
    {follow_redirect, opts} = Keyword.pop(opts, :follow_redirect, false)

    opts =
      opts
      |> Keyword.put_new(:timeout, timeout)
      |> Keyword.put_new(:redirect, if(follow_redirect, do: :follow, else: :manual))
      |> Keyword.put_new(:decode_body, true)
      |> Keyword.merge(headers: headers, body: body, json: false)

    case HexHub.HTTPClient.request(method, url, opts) do
      {:ok, response} ->
        {:ok, %{status_code: response.status, headers: response.headers, body: response.body}}

      {:error, reason} ->
        {:error, %{reason: reason}}
    end
  end
end
