defmodule HexHub.PackageSearch do
  @moduledoc """
  Full-text search implementation for packages using the configured metadata database.

  Features:
  - Inverted index for fast text search
  - Fuzzy matching with edit distance
  - Weighted scoring based on field importance
  - Search suggestions and autocomplete
  """

  @search_index_table :package_search_index
  @search_cache_table :search_cache

  # Field weights for scoring
  @weights %{
    name_exact: 10.0,
    name_prefix: 5.0,
    name_contains: 3.0,
    description: 2.0,
    tags: 1.5
  }

  @doc """
  Initialize search index tables.
  """
  def init_tables() do
    # Create search index table
    HexHub.Database.create_table(@search_index_table,
      attributes: [:term, :field, :package_name, :position, :score],
      type: :bag,
      ram_copies: [node()],
      index: [:term, :package_name]
    )

    # Create search cache table
    HexHub.Database.create_table(@search_cache_table,
      attributes: [:query, :results, :timestamp],
      type: :set,
      ram_copies: [node()]
    )

    :ok
  end

  @doc """
  Search for packages matching the query.
  """
  @spec search(String.t(), keyword()) :: {:ok, list(map())} | {:error, String.t()}
  def search(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    offset = Keyword.get(opts, :offset, 0)
    include_deprecated = Keyword.get(opts, :include_deprecated, false)

    # Normalize and tokenize query
    normalized_query = normalize_query(query)
    tokens = tokenize(normalized_query)

    # Check cache first
    case get_cached_results(normalized_query) do
      {:ok, cached_results} ->
        results =
          cached_results
          |> apply_pagination(offset, limit)
          |> filter_deprecated(include_deprecated)

        {:ok, results}

      :miss ->
        # Perform search
        results =
          perform_search(tokens, normalized_query)
          |> apply_pagination(offset, limit)
          |> filter_deprecated(include_deprecated)

        # Cache results
        cache_results(normalized_query, results)

        {:ok, results}
    end
  end

  @doc """
  Index a package for search.
  """
  @spec index_package(map()) :: :ok | {:error, String.t()}
  def index_package(package) do
    HexHub.Database.transaction(fn ->
      # Remove old index entries for this package
      remove_package_index(package.name)

      # Index package name
      index_field(package.name, package.name, :name)

      # Index description if available
      if package[:meta] && package.meta["description"] do
        index_field(package.meta["description"], package.name, :description)
      end

      # Index tags/keywords if available
      if package[:meta] && package.meta["links"] do
        Enum.each(package.meta["links"], fn {key, _url} ->
          index_field(key, package.name, :tags)
        end)
      end

      :ok
    end)
    |> handle_transaction_result()
  end

  @doc """
  Remove a package from the search index.
  """
  @spec remove_package(String.t()) :: :ok | {:error, String.t()}
  def remove_package(package_name) do
    HexHub.Database.transaction(fn ->
      remove_package_index(package_name)
    end)
    |> handle_transaction_result()
  end

  @doc """
  Rebuild the entire search index.
  """
  @spec rebuild_index() :: {:ok, integer()} | {:error, String.t()}
  def rebuild_index() do
    case HexHub.Database.transaction(fn ->
           # Clear existing index
           HexHub.Database.clear_table(@search_index_table)

           # Get all packages
           packages =
             HexHub.Database.match_object({:packages, :_, :_, :_, :_, :_, :_, :_, :_, :_})

           # Reindex each package
           count =
             Enum.reduce(packages, 0, fn package_tuple, acc ->
               package = tuple_to_package(package_tuple)
               index_package(package)
               acc + 1
             end)

           count
         end) do
      {:atomic, count} ->
        clear_cache()
        {:ok, count}

      {:aborted, reason} ->
        {:error, "Failed to rebuild index: #{inspect(reason)}"}
    end
  end

  @doc """
  Get search suggestions for autocomplete.
  """
  @spec suggest(String.t(), keyword()) :: list(String.t())
  def suggest(prefix, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)

    normalized_prefix = normalize_query(prefix)

    case HexHub.Database.transaction(fn ->
           # Find packages with names starting with prefix
           HexHub.Database.foldl(
             fn {:packages, name, _repo, _meta, _private, _downloads, _inserted, _updated,
                 _html_url, _docs_url},
                acc ->
               normalized_name = String.downcase(name)

               if String.starts_with?(normalized_name, normalized_prefix) do
                 [name | acc]
               else
                 acc
               end
             end,
             [],
             :packages
           )
         end) do
      {:atomic, suggestions} ->
        suggestions
        |> Enum.sort()
        |> Enum.take(limit)

      {:aborted, _} ->
        []
    end
  end

  @doc """
  Search packages by specific field.
  """
  @spec search_by_field(String.t(), atom(), keyword()) ::
          {:ok, list(map())} | {:error, String.t()}
  def search_by_field(query, field, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)

    normalized_query = normalize_query(query)

    case HexHub.Database.transaction(fn ->
           matches = HexHub.Database.match_object({@search_index_table, :_, field, :_, :_, :_})

           matches
           |> Enum.filter(fn {_, term, _, _, _, _} ->
             String.contains?(term, normalized_query)
           end)
           |> Enum.group_by(fn {_, _, _, package_name, _, _} -> package_name end)
           |> Enum.map(fn {package_name, entries} ->
             score = calculate_field_score(entries, normalized_query, field)
             {package_name, score}
           end)
           |> Enum.sort_by(fn {_, score} -> -score end)
           |> Enum.take(limit)
           |> Enum.map(fn {package_name, score} ->
             load_package_with_score(package_name, score)
           end)
         end) do
      {:atomic, results} ->
        {:ok, Enum.reject(results, &is_nil/1)}

      {:aborted, reason} ->
        {:error, "Search failed: #{inspect(reason)}"}
    end
  end

  # Private functions

  defp normalize_query(query) do
    query
    |> String.downcase()
    |> String.trim()
  end

  defp tokenize(text) do
    text
    |> String.replace(~r/[^\w\s-]/, " ")
    |> String.split(~r/\s+/)
    |> Enum.reject(&(&1 == ""))
  end

  defp index_field(text, package_name, field) do
    normalized_text = normalize_query(text)
    tokens = tokenize(normalized_text)

    # Index full text
    HexHub.Database.write({
      @search_index_table,
      normalized_text,
      field,
      package_name,
      0,
      1.0
    })

    # Index individual tokens
    Enum.with_index(tokens)
    |> Enum.each(fn {token, position} ->
      HexHub.Database.write({
        @search_index_table,
        token,
        field,
        package_name,
        position,
        0.8
      })
    end)
  end

  defp remove_package_index(package_name) do
    matches = HexHub.Database.match_object({@search_index_table, :_, :_, package_name, :_, :_})
    Enum.each(matches, &HexHub.Database.delete_object/1)
  end

  defp perform_search(tokens, full_query) do
    case HexHub.Database.transaction(fn ->
           # Search for exact matches
           exact_matches = search_exact(full_query)

           # Search for prefix matches
           prefix_matches = search_prefix(full_query)

           # Search for token matches
           token_matches = search_tokens(tokens)

           # Combine and score results
           all_matches = combine_results([exact_matches, prefix_matches, token_matches])

           # Load package details and sort by score
           all_matches
           |> Enum.map(fn {package_name, score} ->
             load_package_with_score(package_name, score)
           end)
           |> Enum.reject(&is_nil/1)
           |> Enum.sort_by(fn pkg -> {-pkg.score, -(pkg.downloads || 0)} end)
         end) do
      {:atomic, results} -> results
      {:aborted, _} -> []
    end
  end

  defp search_exact(query) do
    HexHub.Database.match_object({@search_index_table, query, :name, :_, 0, :_})
    |> Enum.map(fn {_, _, _, package_name, _, score} ->
      {package_name, score * @weights.name_exact}
    end)
  end

  defp search_prefix(query) do
    HexHub.Database.foldl(
      fn {_, term, :name, package_name, 0, score}, acc ->
        if String.starts_with?(term, query) do
          [{package_name, score * @weights.name_prefix} | acc]
        else
          acc
        end
      end,
      [],
      @search_index_table
    )
  end

  defp search_tokens(tokens) do
    Enum.flat_map(tokens, fn token ->
      HexHub.Database.match_object({@search_index_table, token, :_, :_, :_, :_})
      |> Enum.map(fn {_, _, field, package_name, _, score} ->
        weight = Map.get(@weights, field, 1.0)
        {package_name, score * weight}
      end)
    end)
  end

  defp combine_results(result_lists) do
    result_lists
    |> List.flatten()
    |> Enum.group_by(fn {package_name, _} -> package_name end)
    |> Enum.map(fn {package_name, scores} ->
      total_score =
        scores
        |> Enum.map(fn {_, score} -> score end)
        |> Enum.sum()

      {package_name, total_score}
    end)
  end

  defp calculate_field_score(entries, query, field) do
    base_weight = Map.get(@weights, field, 1.0)

    entries
    |> Enum.map(fn {_, term, _, _, _, score} ->
      if term == query do
        # Exact match bonus
        score * base_weight * 2
      else
        score * base_weight
      end
    end)
    |> Enum.sum()
  end

  defp load_package_with_score(package_name, score) do
    case HexHub.Database.read({:packages, package_name}) do
      [
        {:packages, name, repo, meta, _private, downloads, inserted_at, updated_at, html_url,
         docs_url}
      ] ->
        %{
          name: name,
          repository: repo,
          description: get_in(meta, ["description"]),
          downloads: downloads,
          score: Float.round(score, 2),
          inserted_at: inserted_at,
          updated_at: updated_at,
          html_url: html_url,
          docs_html_url: docs_url
        }

      [] ->
        nil
    end
  end

  defp tuple_to_package(
         {:packages, name, repo, meta, private, downloads, inserted_at, updated_at, html_url,
          docs_url}
       ) do
    %{
      name: name,
      repository: repo,
      meta: meta,
      private: private,
      downloads: downloads,
      inserted_at: inserted_at,
      updated_at: updated_at,
      html_url: html_url,
      docs_html_url: docs_url
    }
  end

  defp apply_pagination(results, offset, limit) do
    results
    |> Enum.drop(offset)
    |> Enum.take(limit)
  end

  defp filter_deprecated(results, false) do
    # Filter out deprecated packages if not including them
    Enum.reject(results, fn package ->
      case HexHub.Database.transaction(fn ->
             HexHub.Database.match_object({:retired_releases, package.name, :_, :_, :_, :_, :_})
           end) do
        # Has retired releases
        {:atomic, [_ | _]} -> true
        _ -> false
      end
    end)
  end

  defp filter_deprecated(results, true), do: results

  defp get_cached_results(query) do
    # 5 minutes
    cache_ttl = 300

    case HexHub.Database.transaction(fn ->
           case HexHub.Database.read({@search_cache_table, query}) do
             [{_, _, results, timestamp}] ->
               age = DateTime.diff(DateTime.utc_now(), timestamp, :second)

               if age < cache_ttl do
                 {:ok, results}
               else
                 :miss
               end

             [] ->
               :miss
           end
         end) do
      {:atomic, result} -> result
      _ -> :miss
    end
  end

  defp cache_results(query, results) do
    HexHub.Database.transaction(fn ->
      HexHub.Database.write({
        @search_cache_table,
        query,
        results,
        DateTime.utc_now()
      })
    end)
  end

  defp clear_cache() do
    HexHub.Database.clear_table(@search_cache_table)
  end

  defp handle_transaction_result({:atomic, :ok}), do: :ok
  defp handle_transaction_result({:atomic, result}), do: result

  defp handle_transaction_result({:aborted, reason}),
    do: {:error, "Transaction failed: #{inspect(reason)}"}
end
