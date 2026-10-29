defmodule HexHub.Database.Schema do
  @moduledoc """
  Shared record definitions for the metadata database backends.
  """

  def definitions do
    [
      {:users,
       [
         attributes: [
           :username,
           :email,
           :password_hash,
           :totp_secret,
           :totp_enabled,
           :recovery_codes,
           :service_account,
           :deactivated_at,
           :inserted_at,
           :updated_at
         ],
         type: :set,
         index: [:email, :service_account]
       ]},
      {:repositories,
       [
         attributes: [:name, :public, :active, :billing_active, :inserted_at, :updated_at],
         type: :set
       ]},
      {:packages,
       [
         attributes: [
           :name,
           :repository_name,
           :meta,
           :private,
           :downloads,
           :inserted_at,
           :updated_at,
           :html_url,
           :docs_html_url,
           :source
         ],
         type: :set
       ]},
      {:package_releases,
       [
         attributes: [
           :package_name,
           :version,
           :has_docs,
           :meta,
           :requirements,
           :retired,
           :downloads,
           :inserted_at,
           :updated_at,
           :url,
           :package_url,
           :html_url,
           :docs_html_url
         ],
         type: :bag
       ]},
      {:package_owners,
       [
         attributes: [:package_name, :username, :level, :inserted_at],
         type: :bag
       ]},
      {:api_keys,
       [
         attributes: [
           :name,
           :username,
           :secret,
           :secret_hash,
           :permissions,
           :revoked_at,
           :last_accessed_at,
           :inserted_at,
           :updated_at
         ],
         type: :set
       ]},
      {:package_downloads,
       [
         attributes: [:package_name, :version, :day_count, :week_count, :all_count],
         type: :set
       ]},
      # Rate limit is always ephemeral - no need to persist across restarts
      {:rate_limit,
       [
         attributes: [:key, :type, :identifier, :count, :window_start, :updated_at],
         type: :set,
         ram_copies: [node()]
       ]},
      {:audit_logs,
       [
         attributes: [
           :id,
           :timestamp,
           :user_id,
           :action,
           :resource_type,
           :resource_id,
           :details,
           :ip_address,
           :user_agent
         ],
         type: :ordered_set,
         index: [:user_id, :resource_type, :timestamp]
       ]},
      {:upstream_configs,
       [
         attributes: [
           :id,
           :enabled,
           :api_url,
           :repo_url,
           :api_key,
           :timeout,
           :retry_attempts,
           :retry_delay,
           :inserted_at,
           :updated_at
         ],
         type: :set
       ]},
      {:publish_configs,
       [
         attributes: [
           :id,
           :enabled,
           :inserted_at,
           :updated_at
         ],
         type: :set
       ]},
      {:storage_configs,
       [
         attributes: [
           :id,
           :storage_type,
           :storage_path,
           :s3_bucket,
           :s3_bucket_path,
           :s3_region,
           :s3_host,
           :s3_port,
           :s3_scheme,
           :s3_path_style,
           :s3_access_key_id,
           :s3_secret_access_key,
           :inserted_at,
           :updated_at
         ],
         type: :set
       ]},
      {:blocked_addresses,
       [
         attributes: [:ip_address, :type, :reason, :blocked_at, :blocked_until, :created_by],
         type: :set,
         index: [:type, :blocked_until]
       ]},
      {:retired_releases,
       [
         attributes: [:key, :package_name, :version, :reason, :message, :retired_at, :retired_by],
         type: :set,
         index: [:package_name]
       ]},
      {:system_metadata,
       [
         attributes: [:key, :value],
         type: :set
       ]},
      {:backups,
       [
         attributes: [
           :id,
           :filename,
           :file_path,
           :size_bytes,
           :user_count,
           :package_count,
           :release_count,
           :created_by,
           :status,
           :error_message,
           :created_at,
           :completed_at,
           :expires_at
         ],
         type: :set,
         index: [:created_at, :expires_at]
       ]},
      # Registry response cache - stores proxied registry data for offline fallback
      {:registry_cache,
       [
         attributes: [:path, :data, :headers, :cached_at],
         type: :set
       ]}
    ]
  end

  def tables, do: Enum.map(definitions(), &elem(&1, 0))
end
