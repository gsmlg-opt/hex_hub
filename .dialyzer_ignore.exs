[
  # Ignore opaque type warnings in backup exporter (MapSet used in Mnesia transactions)
  ~r/lib\/hex_hub\/backup\/exporter\.ex.*call_without_opaque/,
  # Ignore pattern match warning in repositories.ex
  ~r/lib\/hex_hub\/mcp\/tools\/repositories\.ex.*pattern_match/,
  # Ignore pattern match warning in release_controller.ex (defensive clause for non-list terms)
  ~r/lib\/hex_hub_web\/controllers\/api\/release_controller\.ex.*pattern_match/,
  # Ignore pattern match warning in optional_authenticate.ex (defensive fallback for unknown IP format)
  ~r/lib\/hex_hub_web\/plugs\/optional_authenticate\.ex.*pattern_match/,
  # Ignore mix task callback warning (Mix.Task behaviour not available during dialyzer)
  ~r/lib\/mix\/tasks\/test\.e2e\.ex.*callback_info_missing/,
  # Ignore mix task no_return warning (expected for task that runs tests)
  ~r/lib\/mix\/tasks\/test\.e2e\.ex.*no_return/,
  # Ignore Mix.shell/0 and ExUnit functions in mix task
  # These are available at runtime but not during dialyzer analysis
  ~r/lib\/mix\/tasks\/test\.e2e\.ex.*unknown_function/,
  # Ignore pattern match coverage warning in packages.ex normalize_meta/1
  # This is a defensive clause for handling non-map meta values at runtime
  ~r/lib\/hex_hub\/mcp\/tools\/packages\.ex.*pattern_match_cov/,
  # Ignore contract_supertype in storage_config.ex config/0
  # The map() spec is intentionally broad for flexibility
  ~r/lib\/hex_hub\/storage_config\.ex.*contract_supertype/,
  # Ignore pattern match warning in package_controller.ex resolve_docs_version/2
  # Defensive clause for list_releases error (Mnesia transaction can fail at runtime)
  ~r/lib\/hex_hub_web\/controllers\/package_controller\.ex.*pattern_match/
]
