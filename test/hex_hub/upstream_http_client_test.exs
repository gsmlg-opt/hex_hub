defmodule HexHub.UpstreamHTTPClientTest do
  use ExUnit.Case, async: false

  import Plug.Conn

  alias HexHub.{CachedPackages, TestHTTPServer, Upstream, UpstreamConfig}
  alias HexHubAdminWeb.UpstreamController
  alias HexHubWeb.API.RegistryController

  setup do
    original_config = :mnesia.dirty_read(:upstream_configs, "default")
    original_cache = :mnesia.dirty_match_object({:registry_cache, :_, :_, :_, :_})
    {:atomic, :ok} = :mnesia.clear_table(:registry_cache)

    on_exit(fn ->
      :mnesia.dirty_delete(:upstream_configs, "default")
      Enum.each(original_config, &:mnesia.dirty_write/1)
      {:atomic, :ok} = :mnesia.clear_table(:registry_cache)
      Enum.each(original_cache, &:mnesia.dirty_write/1)
    end)

    :ok =
      UpstreamConfig.update_config(%{
        enabled: true,
        api_key: nil,
        timeout: 1000,
        retry_attempts: 1,
        retry_delay: 1
      })

    :ok
  end

  test "fetches JSON package metadata and releases with the configured API key" do
    parent = self()

    start_upstream(fn conn ->
      send(parent, {:request, conn.request_path, get_req_header(conn, "authorization")})

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, Jason.encode!(%{name: "sample", releases: [%{version: "1.2.3"}]}))
    end)

    :ok = UpstreamConfig.update_config(%{api_key: "upstream-key"})

    assert {:ok, %{"name" => "sample", "releases" => [%{"version" => "1.2.3"}]}} =
             Upstream.fetch_package("sample")

    assert {:ok, [%{"version" => "1.2.3"}]} = Upstream.fetch_releases("sample")
    assert_receive {:request, "/api/packages/sample", ["Bearer upstream-key"]}
    assert_receive {:request, "/api/packages/sample", ["Bearer upstream-key"]}
  end

  test "search decodes JSON lists and preserves query options and pagination" do
    parent = self()

    start_upstream(fn conn ->
      conn = fetch_query_params(conn)
      send(parent, {:search, conn.query_params})

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, Jason.encode!([%{name: "sample"}]))
    end)

    assert {:ok, [%{"name" => "sample"}], 3} =
             Upstream.search_packages("sample & other", page: 2, per_page: 2, sort: :name)

    assert_receive {:search,
                    %{
                      "search" => "sample & other",
                      "page" => "2",
                      "per_page" => "2",
                      "sort" => "name"
                    }}
  end

  test "metadata requests preserve non-JSON binary responses" do
    start_upstream(fn conn ->
      conn |> put_resp_content_type("text/plain") |> send_resp(200, "plain response")
    end)

    assert {:ok, "plain response"} = Upstream.fetch_package("sample")
  end

  test "upstream retry loop retries failed requests before returning JSON metadata" do
    attempts = start_supervised!({Agent, fn -> 0 end})

    start_upstream(fn conn ->
      attempt = Agent.get_and_update(attempts, fn count -> {count + 1, count + 1} end)

      if attempt < 3 do
        send_resp(conn, 503, "temporarily unavailable")
      else
        conn |> put_resp_content_type("application/json") |> send_resp(200, ~s({"name":"sample"}))
      end
    end)

    :ok = UpstreamConfig.update_config(%{retry_attempts: 3})

    assert {:ok, %{"name" => "sample"}} = Upstream.fetch_package("sample")
    assert Agent.get(attempts, & &1) == 3
  end

  test "failed metadata requests keep the public exhausted-retry error" do
    attempts = start_supervised!({Agent, fn -> 0 end})

    start_upstream(fn conn ->
      Agent.update(attempts, &(&1 + 1))
      send_resp(conn, 404, "missing")
    end)

    :ok = UpstreamConfig.update_config(%{retry_attempts: 2})

    assert {:error, "Request failed after multiple attempts"} = Upstream.fetch_package("missing")
    assert Agent.get(attempts, & &1) == 2
  end

  test "metadata requests respect the configured timeout" do
    start_upstream(fn conn ->
      Process.sleep(100)
      conn |> put_resp_content_type("application/json") |> send_resp(200, ~s({"name":"sample"}))
    end)

    :ok = UpstreamConfig.update_config(%{timeout: 20})

    assert {:error, "Request failed after multiple attempts"} = Upstream.fetch_package("sample")
  end

  test "tarball and documentation downloads preserve gzip bytes and authorization" do
    body = :zlib.gzip(<<0, 255, 128, "tarball contents">>)
    parent = self()

    start_upstream(fn conn ->
      send(parent, {:download, conn.request_path, get_req_header(conn, "authorization")})

      conn
      |> put_resp_content_type("application/octet-stream")
      |> put_resp_header("content-encoding", "gzip")
      |> send_resp(200, body)
    end)

    :ok = UpstreamConfig.update_config(%{api_key: "download-key"})

    assert {:ok, ^body} = Upstream.fetch_release_tarball("sample", "1.2.3")
    assert {:ok, ^body} = Upstream.fetch_docs_tarball("sample", "1.2.3")
    assert_receive {:download, "/tarballs/sample-1.2.3.tar", ["Bearer download-key"]}
    assert_receive {:download, "/docs/sample-1.2.3.tar", ["Bearer download-key"]}
  end

  test "tarball downloads follow redirects without changing binary contents" do
    body = <<0, 255, 128, "redirected tarball">>

    start_upstream(fn conn ->
      case conn.request_path do
        "/tarballs/sample-1.2.3.tar" ->
          conn |> put_resp_header("location", "/download") |> send_resp(302, "")

        "/download" ->
          conn |> put_resp_content_type("application/octet-stream") |> send_resp(200, body)
      end
    end)

    assert {:ok, ^body} = Upstream.fetch_release_tarball("sample", "1.2.3")
  end

  test "failed tarball requests preserve the final upstream status error" do
    attempts = start_supervised!({Agent, fn -> 0 end})

    start_upstream(fn conn ->
      Agent.update(attempts, &(&1 + 1))
      send_resp(conn, 404, "missing")
    end)

    :ok = UpstreamConfig.update_config(%{retry_attempts: 2})

    assert {:error, "Not found upstream"} = Upstream.fetch_release_tarball("missing", "1.0.0")
    assert Agent.get(attempts, & &1) == 2
  end

  test "registry proxy preserves gzip wire bytes and headers and caches its response" do
    body = :zlib.gzip("protobuf registry bytes")

    start_upstream(fn conn ->
      conn
      |> put_resp_content_type("application/octet-stream")
      |> put_resp_header("content-encoding", "gzip")
      |> put_resp_header("etag", "registry-etag")
      |> put_resp_header("cache-control", "public, max-age=60")
      |> send_resp(200, body)
    end)

    conn = RegistryController.names(Phoenix.ConnTest.build_conn(), %{})

    assert conn.status == 200
    assert conn.resp_body == body
    assert get_resp_header(conn, "content-encoding") == ["gzip"]
    assert get_resp_header(conn, "etag") == ["registry-etag"]
    assert get_resp_header(conn, "cache-control") == ["public, max-age=60"]

    assert [{:registry_cache, "/names", ^body, headers, _cached_at}] = wait_for_cache("/names")
    assert {"content-encoding", "gzip"} in headers
    assert {"etag", "registry-etag"} in headers
  end

  test "registry proxy falls back to cached bytes and legacy header lists" do
    body = :zlib.gzip("cached protobuf")
    path = "/packages/http-client-test"
    headers = [{"content-encoding", ["gzip"]}, {"etag", ["cached-etag"]}]
    :mnesia.dirty_write({:registry_cache, path, body, headers, System.system_time(:second)})
    start_upstream(&send_resp(&1, 503, "unavailable"))

    conn =
      RegistryController.package(Phoenix.ConnTest.build_conn(), %{"name" => "http-client-test"})

    assert conn.status == 200
    assert conn.resp_body == body
    assert get_resp_header(conn, "content-encoding") == ["gzip"]
    assert get_resp_header(conn, "etag") == ["cached-etag"]
  end

  test "registry proxy returns bad gateway when upstream fails without a cached response" do
    :mnesia.dirty_delete(:registry_cache, "/packages/http-client-test")
    start_upstream(&send_resp(&1, 503, "unavailable"))

    conn =
      RegistryController.package(Phoenix.ConnTest.build_conn(), %{"name" => "http-client-test"})

    assert conn.status == 502

    assert %{"message" => "Failed to fetch registry data from upstream"} =
             Jason.decode!(conn.resp_body)
  end

  test "registry refresh stores gzip wire bytes and selected headers" do
    body = :zlib.gzip("refreshed protobuf")

    start_upstream(fn conn ->
      conn
      |> put_resp_content_type("application/octet-stream")
      |> put_resp_header("content-encoding", "gzip")
      |> put_resp_header("etag", "refresh-etag")
      |> put_resp_header("x-upstream-only", "discard")
      |> send_resp(200, body)
    end)

    assert {:ok, %{names: true, versions: true, errors: []}} =
             CachedPackages.refresh_registry_cache()

    for path <- ["/names", "/versions"] do
      assert [{:registry_cache, ^path, ^body, headers, _cached_at}] =
               :mnesia.dirty_read(:registry_cache, path)

      assert {"content-encoding", "gzip"} in headers
      assert {"etag", "refresh-etag"} in headers
      refute Enum.any?(headers, fn {name, _value} -> name == "x-upstream-only" end)
    end
  end

  test "registry refresh reports failed endpoints while refreshing available ones" do
    start_upstream(fn conn ->
      case conn.request_path do
        "/names" -> send_resp(conn, 503, "unavailable")
        _path -> send_resp(conn, 200, "registry bytes")
      end
    end)

    assert {:ok,
            %{
              names: false,
              versions: true,
              errors: [%{path: "/names", reason: "Upstream returned status 503"}]
            }} = CachedPackages.refresh_registry_cache()
  end

  test "admin connection test sends the API key and reports success" do
    parent = self()

    start_upstream(fn conn ->
      send(
        parent,
        {:request, conn.request_path, conn.query_string, get_req_header(conn, "authorization")}
      )

      send_resp(conn, 200, "[]")
    end)

    :ok = UpstreamConfig.update_config(%{api_key: "admin-key"})

    assert %{"status" => "success", "message" => "Connection successful!"} = connection_result()
    assert_receive {:request, "/api/packages", "per_page=1", ["Bearer admin-key"]}
  end

  test "admin connection test reports required authentication without an API key" do
    start_upstream(&send_resp(&1, 401, "authentication required"))

    assert %{
             "status" => "error",
             "message" => "Connection failed: Authentication required - API key needed"
           } = connection_result()
  end

  test "admin connection test reports rejected authentication with an API key" do
    start_upstream(&send_resp(&1, 403, "forbidden"))
    :ok = UpstreamConfig.update_config(%{api_key: "invalid-key"})

    assert %{
             "status" => "error",
             "message" => "Connection failed: Authentication failed - check API key"
           } = connection_result()
  end

  test "admin connection test reports other HTTP failures" do
    start_upstream(&send_resp(&1, 503, "unavailable"))

    assert %{"status" => "error", "message" => "Connection failed: HTTP 503"} =
             connection_result()
  end

  test "disabled upstream prevents metadata and admin connection requests" do
    parent = self()

    start_upstream(fn conn ->
      send(parent, :unexpected_request)
      send_resp(conn, 200, "{}")
    end)

    :ok = UpstreamConfig.update_config(%{enabled: false})

    assert {:error, "Upstream is disabled"} = Upstream.fetch_package("sample")
    assert %{"status" => "warning", "message" => "Upstream is disabled"} = connection_result()
    refute_receive :unexpected_request
  end

  defp start_upstream(handler) do
    server = start_supervised!({TestHTTPServer, handler})
    url = TestHTTPServer.url(server)
    :ok = UpstreamConfig.update_config(%{api_url: url, repo_url: url})
    server
  end

  defp connection_result do
    Phoenix.ConnTest.build_conn()
    |> UpstreamController.test_connection(%{})
    |> Map.fetch!(:resp_body)
    |> Jason.decode!()
  end

  defp wait_for_cache(path, remaining \\ 100)

  defp wait_for_cache(path, 0), do: :mnesia.dirty_read(:registry_cache, path)

  defp wait_for_cache(path, remaining) do
    case :mnesia.dirty_read(:registry_cache, path) do
      [] ->
        Process.sleep(5)
        wait_for_cache(path, remaining - 1)

      records ->
        records
    end
  end
end
