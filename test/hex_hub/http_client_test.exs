defmodule HexHub.HTTPClientTest do
  use ExUnit.Case, async: true

  import Plug.Conn

  alias HexHub.{HTTPClient, TestHTTPServer}

  test "raw responses preserve gzip bytes, headers, and repeated headers" do
    body = :zlib.gzip(<<0, 255, 1, 2, 3>>)

    url =
      start_server(fn conn ->
        conn
        |> put_resp_header("content-encoding", "gzip")
        |> put_resp_header("etag", "original-checksum")
        |> put_resp_cookie("first", "1")
        |> put_resp_cookie("second", "2")
        |> send_resp(200, body)
      end)

    assert {:ok, %{status: 200, body: ^body, headers: headers}} = HTTPClient.get(url)
    assert {"content-encoding", "gzip"} in headers
    assert {"etag", "original-checksum"} in headers

    assert [{"set-cookie", _}, {"set-cookie", _}] =
             Enum.filter(headers, fn {name, _value} -> name == "set-cookie" end)
  end

  test "chunked responses preserve compressed binary data" do
    body = :zlib.gzip(:binary.copy(<<0, 255, 10>>, 1000))
    <<first::binary-size(10), rest::binary>> = body

    url =
      start_server(fn conn ->
        conn = conn |> put_resp_header("content-encoding", "gzip") |> send_chunked(200)
        {:ok, conn} = chunk(conn, first)
        {:ok, conn} = chunk(conn, rest)
        conn
      end)

    assert {:ok, %{body: ^body, headers: headers}} = HTTPClient.get(url)
    assert {"content-encoding", "gzip"} in headers
  end

  test "large fixed-length responses are buffered without losing bytes" do
    body = :binary.copy(<<0, 255, 10>>, 2_000_000)
    url = start_server(&send_resp(&1, 200, body))

    assert {:ok, %{status: 200, body: ^body}} = HTTPClient.get(url)
  end

  test "JSON decoding is opt-in and decodes compressed JSON responses" do
    body = ~s({"name":"sample","releases":[{"version":"1.0.0"}]})
    encoded = :zlib.gzip(body)

    url =
      start_server(fn conn ->
        conn
        |> put_resp_content_type("application/json")
        |> put_resp_header("content-encoding", "gzip")
        |> send_resp(200, encoded)
      end)

    assert {:ok, %{body: ^encoded}} = HTTPClient.get(url)

    assert {:ok, %{body: %{"name" => "sample", "releases" => [%{"version" => "1.0.0"}]}}} =
             HTTPClient.get(url, json: true)
  end

  test "invalid JSON returns an error" do
    url =
      start_server(fn conn ->
        conn |> put_resp_content_type("application/json") |> send_resp(200, "invalid")
      end)

    assert {:error, %Jason.DecodeError{}} = HTTPClient.get(url, json: true)
  end

  test "requests follow redirects by default and allow manual handling" do
    url =
      start_server(fn conn ->
        case conn.request_path do
          "/" -> conn |> put_resp_header("location", "/destination") |> send_resp(302, "")
          "/destination" -> send_resp(conn, 200, "download")
        end
      end)

    assert {:ok, %{status: 200, body: "download"}} = HTTPClient.get(url)
    assert {:ok, %{status: 302, body: ""}} = HTTPClient.get(url, redirect: :manual)
  end

  test "transport failures respect the request timeout" do
    url =
      start_server(fn conn ->
        Process.sleep(100)
        send_resp(conn, 200, "too late")
      end)

    assert {:error, :request_timeout} = HTTPClient.get(url, timeout: 20)
  end

  test "a stalled response stream returns an error instead of partial data" do
    url =
      start_server(fn conn ->
        conn = send_chunked(conn, 200)
        {:ok, conn} = chunk(conn, "partial")
        Process.sleep(100)
        conn
      end)

    assert {:error, %RuntimeError{message: message}} = HTTPClient.get(url, timeout: 20)
    assert message =~ "request_timeout"
  end

  test "ExAws adapter forwards signed upload bytes and returns the required response shape" do
    parent = self()
    body = <<0, 255, 10>>

    url =
      start_server(fn conn ->
        {:ok, received, conn} = read_body(conn)
        send(parent, {:upload, conn.method, received, get_req_header(conn, "authorization")})
        conn |> put_resp_header("etag", "checksum") |> send_resp(200, "<Result/>")
      end)

    assert {:ok, %{status_code: 200, body: "<Result/>", headers: headers}} =
             HTTPClient.ExAws.request(:put, url, body, [{"authorization", "signed-header"}], [])

    assert {"etag", "checksum"} in headers
    assert_receive {:upload, "PUT", ^body, ["signed-header"]}
  end

  test "configured ExAws client downloads an S3 object without decoding its content" do
    parent = self()
    body = :zlib.gzip(<<0, 255, 10>>)

    url =
      start_server(fn conn ->
        send(parent, {:s3, conn.request_path, get_req_header(conn, "authorization")})
        conn |> put_resp_header("content-encoding", "gzip") |> send_resp(200, body)
      end)

    %{port: port} = URI.parse(url)

    assert {:ok, %{status_code: 200, body: ^body}} =
             "packages"
             |> ExAws.S3.get_object("sample.tar")
             |> ExAws.request(
               host: "127.0.0.1",
               scheme: "http://",
               port: port,
               region: "us-east-1",
               access_key_id: "test-access-key",
               secret_access_key: "test-secret-key",
               http_opts: [decode_body: false]
             )

    assert_receive {:s3, "/packages/sample.tar", [authorization]}
    assert String.starts_with?(authorization, "AWS4-HMAC-SHA256 ")
  end

  test "configured ExAws client decodes compressed XML before parsing S3 listings" do
    parent = self()

    xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <ListBucketResult>
      <Name>packages</Name>
      <IsTruncated>false</IsTruncated>
      <MaxKeys>2</MaxKeys>
      <Contents><Key>sample.tar</Key><Size>123</Size></Contents>
      <Contents><Key>docs.tar</Key><Size>456</Size></Contents>
    </ListBucketResult>
    """

    url =
      start_server(fn conn ->
        send(
          parent,
          {:listing, conn.method, conn.request_path, get_req_header(conn, "authorization")}
        )

        conn
        |> put_resp_content_type("application/xml")
        |> put_resp_header("content-encoding", "gzip")
        |> send_resp(200, :zlib.gzip(xml))
      end)

    %{port: port} = URI.parse(url)

    assert {:ok,
            %{
              status_code: 200,
              body: %{
                name: "packages",
                is_truncated: "false",
                contents: [%{key: "sample.tar", size: "123"}, %{key: "docs.tar", size: "456"}]
              }
            }} =
             "packages"
             |> ExAws.S3.list_objects(max_keys: 2)
             |> ExAws.request(
               host: "127.0.0.1",
               scheme: "http://",
               port: port,
               region: "us-east-1",
               access_key_id: "test-access-key",
               secret_access_key: "test-secret-key"
             )

    assert_receive {:listing, "GET", "/packages/", [authorization]}
    assert String.starts_with?(authorization, "AWS4-HMAC-SHA256 ")
  end

  test "ExAws adapter maps timeouts to its error contract" do
    url =
      start_server(fn conn ->
        Process.sleep(100)
        send_resp(conn, 200, "too late")
      end)

    opts = [
      http_version: :http1,
      http1_reuse: true,
      http1_scope: "timeout-#{System.unique_integer([:positive])}",
      redirect: :manual
    ]

    # Keep connection establishment outside the response timeout assertion.
    promise = HTTP.fetch(url, opts)
    assert %HTTP.Response{status: 200} = response = HTTP.Promise.await(promise)
    assert HTTP.Response.read_all(response) == "too late"
    assert :ok = HTTP.RequestCompletion.await(HTTP.Promise.completion(promise))

    assert {:error, %{reason: :request_timeout}} =
             HTTPClient.ExAws.request(:get, url, "", [], Keyword.put(opts, :recv_timeout, 20))
  end

  test "ExAws adapter preserves manual redirects unless following is requested" do
    url =
      start_server(fn conn ->
        case conn.request_path do
          "/" -> conn |> put_resp_header("location", "/object") |> send_resp(307, "")
          "/object" -> send_resp(conn, 200, "object")
        end
      end)

    assert {:ok, %{status_code: 307}} = HTTPClient.ExAws.request(:get, url, "", [], [])

    assert {:ok, %{status_code: 200, body: "object"}} =
             HTTPClient.ExAws.request(:get, url, "", [], follow_redirect: true)
  end

  test "Swoosh adapter forwards email body and headers and keeps provider JSON binary" do
    parent = self()

    url =
      start_server(fn conn ->
        {:ok, body, conn} = read_body(conn)

        send(
          parent,
          {:email, conn.method, conn.request_path, body, get_req_header(conn, "authorization"),
           get_req_header(conn, "user-agent")}
        )

        conn
        |> put_resp_content_type("application/json")
        |> put_resp_header("content-encoding", "gzip")
        |> send_resp(202, :zlib.gzip(~s({"id":"mail-1"})))
      end)

    email = %Swoosh.Email{private: %{client_options: [body: "ignored", json: true]}}

    assert {:ok, 202, headers, ~s({"id":"mail-1"})} =
             HTTPClient.Swoosh.post(
               [url, "/messages"],
               [{"authorization", "Bearer mail-token"}],
               ["email", "-body"],
               email
             )

    assert {"content-type", "application/json; charset=utf-8"} in headers

    assert_receive {:email, "POST", "/messages", "email-body", ["Bearer mail-token"],
                    [user_agent]}

    assert user_agent == "swoosh/#{Swoosh.version()}"
  end

  test "Swoosh adapter forwards transport errors and client timeout options" do
    url =
      start_server(fn conn ->
        Process.sleep(100)
        send_resp(conn, 202, "too late")
      end)

    email = %Swoosh.Email{private: %{client_options: [receive_timeout: 20]}}

    assert {:error, :request_timeout} = HTTPClient.Swoosh.post(url, [], "email", email)
  end

  test "Swoosh adapter preserves boolean redirect client options" do
    url =
      start_server(fn conn ->
        case conn.request_path do
          "/" -> conn |> put_resp_header("location", "/provider") |> send_resp(307, "")
          "/provider" -> send_resp(conn, 202, "accepted")
        end
      end)

    manual = %Swoosh.Email{private: %{client_options: [redirect: false]}}
    follow = %Swoosh.Email{private: %{client_options: [redirect: true]}}

    assert {:ok, 307, _, ""} = HTTPClient.Swoosh.post(url, [], "email", manual)
    assert {:ok, 202, _, "accepted"} = HTTPClient.Swoosh.post(url, [], "email", follow)
  end

  defp start_server(handler) do
    {TestHTTPServer, handler}
    |> start_supervised!()
    |> TestHTTPServer.url()
  end
end
