defmodule HexHubWeb.API.ReleaseController do
  use HexHubWeb, :controller
  alias HexHub.Packages

  action_fallback HexHubWeb.FallbackController

  def show(conn, %{"name" => name, "version" => version}) do
    start_time = System.monotonic_time()

    case Packages.get_release(name, version) do
      {:ok, release} ->
        response = %{
          name: release.package_name,
          version: release.version,
          checksum: generate_checksum(release),
          inner_checksum: generate_inner_checksum(release),
          has_docs: release.has_docs,
          meta: release.meta,
          requirements: release.requirements,
          retired: if(release.retired, do: %{}, else: nil),
          downloads: release.downloads,
          inserted_at: release.inserted_at,
          updated_at: release.updated_at,
          url: release.url,
          package_url: "/api/packages/#{name}/releases/#{version}/download",
          html_url: release.html_url,
          docs_html_url: release.docs_html_url,
          docs_url: "/api/packages/#{name}/releases/#{version}/docs/download"
        }

        duration_ms =
          (System.monotonic_time() - start_time)
          |> System.convert_time_unit(:native, :millisecond)

        HexHub.Telemetry.track_api_request("releases.show", duration_ms, 200)

        json(conn, response)

      {:error, :not_found} ->
        duration_ms =
          (System.monotonic_time() - start_time)
          |> System.convert_time_unit(:native, :millisecond)

        HexHub.Telemetry.track_api_request("releases.show", duration_ms, 404, "not_found")

        conn
        |> put_status(:not_found)
        |> json(%{message: "Package not found"})
    end
  end

  def publish(conn, _params) do
    start_time = System.monotonic_time()

    # Get the raw body from the tarball parser (stored in conn.private[:raw_body])
    body = conn.private[:raw_body]

    with {:ok, body} <- ensure_body(body, conn),
         {:ok, package_name, version} <- extract_package_info_from_tarball(body),
         {:ok, meta} <- parse_meta_from_tarball(body),
         {:ok, requirements} <- parse_requirements_from_tarball(body),
         :ok <- ensure_package_exists(package_name, meta, conn),
         {:ok, release} <-
           Packages.create_release(package_name, version, meta, requirements, body) do
      response = %{
        version: release.version,
        has_docs: release.has_docs,
        meta: release.meta,
        requirements: release.requirements,
        retired: if(release.retired, do: %{}, else: nil),
        downloads: release.downloads,
        inserted_at: release.inserted_at,
        updated_at: release.updated_at,
        url: release.url,
        package_url: release.package_url,
        html_url: release.html_url,
        docs_html_url: release.docs_html_url
      }

      duration_ms =
        (System.monotonic_time() - start_time) |> System.convert_time_unit(:native, :millisecond)

      HexHub.Telemetry.track_api_request("releases.publish", duration_ms, 201)
      HexHub.Telemetry.track_package_published("hexpm")

      conn
      |> put_status(:created)
      |> json(response)
    else
      {:error, "Package not found"} ->
        duration_ms =
          (System.monotonic_time() - start_time)
          |> System.convert_time_unit(:native, :millisecond)

        HexHub.Telemetry.track_api_request("releases.publish", duration_ms, 404, "not_found")

        conn
        |> put_status(:not_found)
        |> json(%{message: "Package not found"})

      {:error, reason} ->
        duration_ms =
          (System.monotonic_time() - start_time)
          |> System.convert_time_unit(:native, :millisecond)

        HexHub.Telemetry.track_api_request("releases.publish", duration_ms, 422, "error")

        conn
        |> put_status(:unprocessable_entity)
        |> json(%{message: reason})
    end
  end

  def retire(conn, %{"name" => name, "version" => version}) do
    start_time = System.monotonic_time()

    with {:ok, _release} <- Packages.get_release(name, version),
         {:ok, _} <- Packages.retire_release(name, version) do
      duration_ms =
        (System.monotonic_time() - start_time) |> System.convert_time_unit(:native, :millisecond)

      HexHub.Telemetry.track_api_request("releases.retire", duration_ms, 204)

      send_resp(conn, 204, "")
    else
      {:error, :not_found} ->
        duration_ms =
          (System.monotonic_time() - start_time)
          |> System.convert_time_unit(:native, :millisecond)

        HexHub.Telemetry.track_api_request("releases.retire", duration_ms, 404, "not_found")

        conn
        |> put_status(:not_found)
        |> json(%{message: "Package not found"})

      {:error, reason} ->
        duration_ms =
          (System.monotonic_time() - start_time)
          |> System.convert_time_unit(:native, :millisecond)

        HexHub.Telemetry.track_api_request("releases.retire", duration_ms, 422, "error")

        conn
        |> put_status(:unprocessable_entity)
        |> json(%{message: reason})
    end
  end

  def unretire(conn, %{"name" => name, "version" => version}) do
    start_time = System.monotonic_time()

    with {:ok, _release} <- Packages.get_release(name, version),
         {:ok, _} <- Packages.unretire_release(name, version) do
      duration_ms =
        (System.monotonic_time() - start_time) |> System.convert_time_unit(:native, :millisecond)

      HexHub.Telemetry.track_api_request("releases.unretire", duration_ms, 204)

      send_resp(conn, 204, "")
    else
      {:error, :not_found} ->
        duration_ms =
          (System.monotonic_time() - start_time)
          |> System.convert_time_unit(:native, :millisecond)

        HexHub.Telemetry.track_api_request("releases.unretire", duration_ms, 404, "not_found")

        conn
        |> put_status(:not_found)
        |> json(%{message: "Package not found"})

      {:error, reason} ->
        duration_ms =
          (System.monotonic_time() - start_time)
          |> System.convert_time_unit(:native, :millisecond)

        HexHub.Telemetry.track_api_request("releases.unretire", duration_ms, 422, "error")

        conn
        |> put_status(:unprocessable_entity)
        |> json(%{message: reason})
    end
  end

  defp generate_checksum(release) do
    # Generate a mock checksum for now
    # In real implementation, this would be the SHA256 of the package contents
    :crypto.hash(:sha256, "#{release.package_name}-#{release.version}")
    |> Base.encode16()
    |> String.downcase()
  end

  defp generate_inner_checksum(release) do
    # Generate a mock inner checksum for now
    # In real implementation, this would be the SHA256 of the inner package contents
    :crypto.hash(:sha256, "inner-#{release.package_name}-#{release.version}")
    |> Base.encode16()
    |> String.downcase()
  end

  defp extract_package_info_from_tarball(tarball) do
    # Hex tarballs are gzipped, containing a VERSION file, metadata.config, and contents.tar.gz
    # The metadata.config contains the package name and version
    with {:ok, files} <- :erl_tar.extract({:binary, tarball}, [:memory, :compressed]) do
      # Find metadata.config in the tarball
      case Enum.find(files, fn {name, _content} -> name == ~c"metadata.config" end) do
        {_name, metadata_content} ->
          parse_metadata_config(metadata_content)

        nil ->
          {:error, "Invalid tarball: missing metadata.config"}
      end
    else
      {:error, reason} ->
        {:error, "Failed to extract tarball: #{inspect(reason)}"}
    end
  end

  defp parse_metadata_config(content) do
    # metadata.config is an Erlang term file
    # Format: [{<<"name">>, <<"package_name">>}, {<<"version">>, <<"0.1.0">>}, ...]
    with {:ok, terms} <- safe_consult_string(content) do
      name = find_term_value(terms, "name")
      version = find_term_value(terms, "version")

      if name && version do
        {:ok, name, version}
      else
        {:error, "Invalid metadata.config: missing name or version"}
      end
    end
  end

  defp safe_consult_string(content) do
    try do
      # metadata.config is formatted like file:consult/1 - multiple Erlang terms
      # Each term ends with a dot: {<<"key">>, <<"value">>}.
      # We need to parse all terms and collect them into a list
      content_str = to_string(content)

      case parse_consult_format(content_str) do
        {:ok, terms} ->
          {:ok, terms}

        {:error, reason} ->
          {:error, "Failed to parse metadata.config: #{inspect(reason)}"}
      end
    rescue
      e ->
        {:error, "Failed to parse metadata.config: #{inspect(e)}"}
    catch
      _kind, reason ->
        {:error, "Failed to parse metadata.config: #{inspect(reason)}"}
    end
  end

  # Parse file:consult/1 format - multiple terms separated by dots
  defp parse_consult_format(content) do
    case :erl_scan.string(String.to_charlist(content)) do
      {:ok, tokens, _} ->
        parse_all_terms(tokens, [])

      {:error, reason, _} ->
        {:error, {:scan_error, reason}}
    end
  end

  defp parse_all_terms([], acc), do: {:ok, Enum.reverse(acc)}

  defp parse_all_terms(tokens, acc) do
    case :erl_parse.parse_term(tokens) do
      {:ok, term} ->
        # All tokens consumed
        {:ok, Enum.reverse([term | acc])}

      {:error, {_, :erl_parse, _}} ->
        # Try to find the next dot and parse up to it
        case split_at_dot(tokens) do
          {term_tokens, rest} when term_tokens != [] ->
            case :erl_parse.parse_term(term_tokens ++ [{:dot, 1}]) do
              {:ok, term} ->
                parse_all_terms(rest, [term | acc])

              {:error, reason} ->
                {:error, {:parse_term_error, reason}}
            end

          _ ->
            {:error, :no_dot_found}
        end
    end
  end

  defp split_at_dot(tokens) do
    case Enum.split_while(tokens, fn
           {:dot, _} -> false
           _ -> true
         end) do
      {before, [{:dot, _} | rest]} -> {before, rest}
      {before, []} -> {before, []}
    end
  end

  defp find_term_value(terms, key) when is_list(terms) do
    key_binary = key

    case Enum.find(terms, fn
           {k, _v} when is_binary(k) -> k == key_binary
           {k, _v} when is_list(k) -> to_string(k) == key_binary
           _ -> false
         end) do
      {_, value} when is_binary(value) ->
        value

      {_, value} when is_list(value) ->
        # Only convert charlists (lists of integers) to string.
        # Leave structured lists (e.g. requirements proplists) as-is.
        if value != [] and is_integer(hd(value)) do
          to_string(value)
        else
          value
        end

      {_, value} ->
        value

      _ ->
        nil
    end
  end

  # Fall-through for non-list terms (defensive)
  defp find_term_value(_non_list, _key), do: nil

  defp parse_meta_from_tarball(tarball) do
    # Extract build_tools and other metadata from the tarball
    with {:ok, files} <- :erl_tar.extract({:binary, tarball}, [:memory, :compressed]) do
      case Enum.find(files, fn {name, _content} -> name == ~c"metadata.config" end) do
        {_name, metadata_content} ->
          parse_meta_fields(metadata_content)

        nil ->
          {:ok, %{build_tools: ["mix"]}}
      end
    else
      _ -> {:ok, %{build_tools: ["mix"]}}
    end
  end

  defp parse_meta_fields(content) do
    with {:ok, terms} <- safe_consult_string(content) do
      build_tools = find_term_value(terms, "build_tools") || ["mix"]

      build_tools =
        if is_binary(build_tools), do: [build_tools], else: build_tools

      {:ok, %{build_tools: build_tools}}
    else
      _ -> {:ok, %{build_tools: ["mix"]}}
    end
  end

  defp parse_requirements_from_tarball(tarball) do
    # Extract requirements from metadata.config
    with {:ok, files} <- :erl_tar.extract({:binary, tarball}, [:memory, :compressed]) do
      case Enum.find(files, fn {name, _content} -> name == ~c"metadata.config" end) do
        {_name, metadata_content} ->
          parse_requirements_fields(metadata_content)

        nil ->
          {:ok, %{}}
      end
    else
      _ -> {:ok, %{}}
    end
  end

  defp parse_requirements_fields(content) do
    with {:ok, terms} <- safe_consult_string(content) do
      requirements = find_term_value(terms, "requirements") || []

      req_map =
        if is_list(requirements) do
          Enum.reduce(requirements, %{}, fn
            # Hex client format: list of proplists with string keys
            # e.g. [{"name", "telemetry"}, {"requirement", "~> 1.0"}, ...]
            opts, acc when is_list(opts) and is_tuple(hd(opts)) ->
              name = proplist_get(opts, "name")

              if name do
                Map.put(acc, to_string(name), parse_requirement_proplist(opts))
              else
                acc
              end

            # Legacy format: {name, keyword_list}
            {name, opts}, acc when is_list(opts) ->
              Map.put(acc, to_string(name), parse_requirement_opts(opts))

            _, acc ->
              acc
          end)
        else
          %{}
        end

      {:ok, req_map}
    else
      _ -> {:ok, %{}}
    end
  end

  defp parse_requirement_proplist(opts) do
    %{
      "requirement" => to_string(proplist_get(opts, "requirement") || ""),
      "optional" => proplist_get(opts, "optional") || false,
      "app" => case proplist_get(opts, "app") do
        nil -> nil
        app -> to_string(app)
      end
    }
  end

  defp parse_requirement_opts(opts) do
    %{
      "requirement" => Keyword.get(opts, :requirement, ""),
      "optional" => Keyword.get(opts, :optional, false),
      "app" => Keyword.get(opts, :app)
    }
  end

  defp proplist_get(list, key) do
    case List.keyfind(list, key, 0) do
      {_, value} -> value
      nil -> nil
    end
  end

  defp ensure_body(nil, conn) do
    # Fallback: try to read the body directly (may fail if already read)
    # Use larger length and timeout for package tarballs
    case Plug.Conn.read_body(conn,
           length: 100_000_000,
           read_length: 1_000_000,
           read_timeout: 120_000
         ) do
      {:ok, body, _conn} ->
        {:ok, body}

      {:more, _partial, _conn} ->
        {:error, "Body too large"}

      {:error, reason} ->
        {:error, "Failed to read body: #{inspect(reason)}"}
    end
  end

  defp ensure_body(body, _conn) when is_binary(body) and byte_size(body) > 0 do
    {:ok, body}
  end

  defp ensure_body(_body, _conn) do
    {:error, "Empty or invalid body"}
  end

  defp ensure_package_exists(package_name, meta, conn) do
    case Packages.get_package(package_name) do
      {:ok, package} ->
        # If previously cached from upstream, update source to local
        # since we're now publishing it directly
        if package[:source] == :cached do
          Packages.update_package_source(package_name, :local)
        end

        :ok

      {:error, :not_found} ->
        # Create new package with metadata from tarball
        description = Map.get(meta, "description") || Map.get(meta, :description, "")

        package_meta = %{
          "description" => description,
          "licenses" => Map.get(meta, "licenses") || Map.get(meta, :licenses, []),
          "links" => Map.get(meta, "links") || Map.get(meta, :links, %{}),
          "maintainers" => Map.get(meta, "maintainers") || Map.get(meta, :maintainers, [])
        }

        case Packages.create_package(package_name, "hexpm", package_meta, false) do
          {:ok, _package} ->
            # Add the publishing user as owner if authenticated
            maybe_add_owner(package_name, conn)
            :ok

          {:error, reason} ->
            {:error, "Failed to create package: #{reason}"}
        end
    end
  end

  defp maybe_add_owner(package_name, conn) do
    case conn.assigns[:current_user] do
      %{username: "anonymous", is_anonymous: true, ip_address: ip_address} ->
        # Anonymous user - add as owner and log telemetry
        Packages.add_package_owner(package_name, "anonymous", "full")

        HexHub.Telemetry.log(:info, :package, "Anonymous package published", %{
          package_name: package_name,
          ip_address: ip_address
        })

      %{username: username} ->
        Packages.add_package_owner(package_name, username, "full")

      _ ->
        :ok
    end
  end
end
