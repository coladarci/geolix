defmodule Geolix.Adapter.MMDB2.Loader do
  @moduledoc """
  Loader module to load an MMDB2 database into Geolix.
  """

  alias Geolix.Adapter.MMDB2.Reader
  alias Geolix.Adapter.MMDB2.Storage

  @doc """
  Implementation of `Geolix.Adapter.MMDB2.load_database/1`.

  Requires the parameter `:source` as the location of the database. Can access
  the system environment by receiving a `{ :system, "env_var_name" }` tuple.

  Using `{ :system, "env_var_name", "/path/to/default.mmdb2" }` you can define
  a fallback value to be used if the environment variable is not set.
  """
  @spec load_database(map, atom) :: :ok | :delayed | {:error, term}
  def load_database(%{source: {:system, var, default}} = database, sync_type) do
    database
    |> Map.put(:source, System.get_env(var) || default)
    |> load_database(sync_type)
  end

  def load_database(%{source: {:system, var}} = database, sync_type) do
    database
    |> Map.put(:source, System.get_env(var))
    |> load_database(sync_type)
  end

  def load_database(%{id: id, source: "http" <> _ = source} = database, :async) do
    _ = Task.start(fn ->
      result =
        source
        |> Reader.read_database()
        |> store_data(id)

      call = {:register_database, database, result}

      :ok = GenServer.call(Geolix.Database.Loader, call)
    end)

    :delayed
  end

  def load_database(%{id: id, source: source}, _) do
    source
    |> Reader.read_database()
    |> store_data(id)
  end

  @doc """
  Implementation of `Geolix.Adapter.MMDB2.unload_database/1`.
  """
  def unload_database(%{id: id}), do: store_data({nil, nil, nil}, id)

  defp store_data({:error, _reason} = error, _), do: error

  defp store_data({meta, tree, data}, id) do
    Storage.Data.set(id, data)
    Storage.Metadata.set(id, meta)
    Storage.Tree.set(id, tree)

    :ok
  end
end
