defmodule HexHub.HTTPClient do
  @moduledoc """
  Buffered HTTP requests through `http_fetch`.

  Responses preserve encoded bytes unless `json: true` or `decode_body: true`
  enables content decoding. JSON parsing is opt-in with `json: true`.
  Retries are owned by the caller.
  """

  @type response :: %{status: pos_integer(), headers: [{String.t(), String.t()}], body: term()}

  @spec get(String.t(), keyword()) :: {:ok, response()} | {:error, term()}
  def get(url, opts \\ []), do: request(:get, url, opts)

  @spec request(atom(), String.t(), keyword()) :: {:ok, response()} | {:error, term()}
  def request(method, url, opts \\ []) do
    {json, opts} = Keyword.pop(opts, :json, false)

    opts =
      opts
      |> Keyword.put(:method, method)
      |> Keyword.put_new(:timeout, 30_000)
      |> Keyword.put_new(:decode_body, json)

    case url |> HTTP.fetch(opts) |> HTTP.Promise.await() do
      %HTTP.Response{} = response ->
        with {:ok, body} <- read_body(response, json) do
          {:ok,
           %{
             status: response.status,
             headers: HTTP.Headers.to_list(response.headers),
             body: body
           }}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp read_body(response, json) do
    body = HTTP.Response.read_all(response)
    {content_type, _params} = HTTP.Response.content_type(response)

    if json and
         (content_type == "application/json" or String.ends_with?(content_type, "+json")) do
      Jason.decode(body)
    else
      {:ok, body}
    end
  rescue
    error in RuntimeError -> {:error, error}
  end
end
