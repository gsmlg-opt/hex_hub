defmodule HexHubWeb.EndpointServerTest do
  use ExUnit.Case, async: false

  @timeout 10_000
  @endpoints [HexHubWeb.Endpoint, HexHubAdminWeb.Endpoint]

  setup_all do
    # Keep the application's server-disabled Endpoint supervisors and config intact.
    ports =
      Map.new(@endpoints, fn endpoint ->
        assert endpoint.config(:adapter) == Gaoxy.PhoenixAdapter

        http = Keyword.merge(endpoint.config(:http), ip: {127, 0, 0, 1}, port: 0)

        config =
          :hex_hub
          |> Application.fetch_env!(endpoint)
          |> Keyword.merge(server: true, http: http, https: false)

        [child] = Gaoxy.PhoenixAdapter.child_specs(endpoint, config)
        start_supervised!(child)
        assert {:ok, {{127, 0, 0, 1}, port}} = endpoint.server_info(:http)
        assert port in 1..65_535
        {endpoint, port}
      end)

    {:ok, ports: ports}
  end

  test "both endpoints serve their real routes through ephemeral Gaoxy listeners", %{ports: ports} do
    with_socket(ports[HexHubWeb.Endpoint], fn socket ->
      :ok = :gen_tcp.send(socket, request("GET", "/health/live"))
      assert {200, _headers, body} = recv_response(socket)
      assert %{"alive" => true} = Jason.decode!(body)
    end)

    with_socket(ports[HexHubAdminWeb.Endpoint], fn socket ->
      :ok = :gen_tcp.send(socket, request("GET", "/", [{"Accept", "text/html"}]))
      assert {200, _headers, body} = recv_response(socket)
      assert body =~ "HexHub"
      assert body =~ "Dashboard"
    end)
  end

  test "both LiveView sockets complete the WebSocket handshake", %{ports: ports} do
    for endpoint <- @endpoints do
      with_socket(ports[endpoint], fn socket ->
        key = Base.encode64(:crypto.strong_rand_bytes(16))

        :ok =
          :gen_tcp.send(socket, [
            "GET /live/websocket?vsn=2.0.0 HTTP/1.1\r\n",
            "Host: localhost\r\nConnection: Upgrade\r\nUpgrade: websocket\r\n",
            "Sec-WebSocket-Version: 13\r\nSec-WebSocket-Key: ",
            key,
            "\r\n\r\n"
          ])

        assert {101, headers, _rest} = recv_head(socket, "")

        expected_accept =
          :crypto.hash(:sha, key <> "258EAFA5-E914-47DA-95CA-C5AB0DC85B11")
          |> Base.encode64()

        assert headers["sec-websocket-accept"] == expected_accept
        assert String.downcase(headers["upgrade"]) == "websocket"
      end)
    end
  end

  test "publishing consumes a body above 8 MiB after 100 Continue before authenticating", %{
    ports: ports
  } do
    body = :binary.copy(<<0, 255, 10>>, 3_000_000)

    with_socket(ports[HexHubWeb.Endpoint], fn socket ->
      :ok =
        :gen_tcp.send(
          socket,
          request("POST", "/api/publish", [
            {"Accept", "application/json"},
            {"Content-Type", "application/octet-stream"},
            {"Content-Length", Integer.to_string(byte_size(body))},
            {"Expect", "100-continue"},
            {"Authorization", "Basic !!!"}
          ])
        )

      assert {100, _headers, rest} = recv_head(socket, "")
      :ok = :gen_tcp.send(socket, body)
      assert {401, _headers, response} = recv_response(socket, rest)
      assert %{"message" => "Invalid authorization format"} = Jason.decode!(response)
    end)
  end

  defp with_socket(port, callback) do
    assert {:ok, socket} =
             :gen_tcp.connect(
               ~c"127.0.0.1",
               port,
               [:binary, active: false, send_timeout: @timeout, send_timeout_close: true],
               @timeout
             )

    try do
      callback.(socket)
    after
      :gen_tcp.close(socket)
    end
  end

  defp request(method, path, headers \\ []) do
    [
      method,
      " ",
      path,
      " HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n",
      Enum.map(headers, fn {name, value} -> [name, ": ", value, "\r\n"] end),
      "\r\n"
    ]
  end

  defp recv_response(socket, buffer \\ "") do
    case recv_head(socket, buffer) do
      {status, _headers, rest} when status in 100..199 and status != 101 ->
        recv_response(socket, rest)

      {status, headers, rest} ->
        {status, headers, recv_body(socket, [rest])}
    end
  end

  defp recv_head(socket, buffer) do
    case :binary.split(buffer, "\r\n\r\n") do
      [head, rest] ->
        [status_line | fields] = String.split(head, "\r\n")
        ["HTTP/1.1", status | _reason] = String.split(status_line, " ", parts: 3)

        headers =
          Map.new(fields, fn field ->
            [name, value] = String.split(field, ":", parts: 2)
            {String.downcase(name), String.trim(value)}
          end)

        {String.to_integer(status), headers, rest}

      [_incomplete] ->
        assert {:ok, bytes} = :gen_tcp.recv(socket, 0, @timeout)
        recv_head(socket, buffer <> bytes)
    end
  end

  defp recv_body(socket, chunks) do
    case :gen_tcp.recv(socket, 0, @timeout) do
      {:ok, bytes} -> recv_body(socket, [bytes | chunks])
      {:error, :closed} -> chunks |> Enum.reverse() |> IO.iodata_to_binary()
      error -> flunk("Failed to receive endpoint response: #{inspect(error)}")
    end
  end
end
