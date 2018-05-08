defmodule Geolix.Database.Loader do
  @moduledoc """
  Takes care of (re-) loading databases.
  """

  use GenServer

  require Logger

  alias Geolix.Database.Supervisor, as: DatabaseSupervisor

  # GenServer lifecycle

  @doc """
  Starts the database loader.
  """
  @spec start_link(list) :: GenServer.on_start()
  def start_link(databases \\ []) do
    GenServer.start_link(__MODULE__, databases, name: __MODULE__)
  end

  def init(databases) do
    :ok = GenServer.cast(__MODULE__, :reload_databases)

    state =
      databases
      |> Enum.filter(&Map.has_key?(&1, :id))
      |> Enum.map(&{Map.fetch!(&1, :id), &1})

    {:ok, state}
  end

  # GenServer callbacks

  def handle_call({:get_database, which}, _, state) do
    {:reply, state[which], state}
  end

  def handle_call({:load_database, db}, _, state) do
    db =
      db
      |> load_database(:sync)
      |> register_state(db)

    case db[:state] do
      :loaded -> {:reply, :ok, Keyword.put(state, db[:id], db)}
      {:error, _} = err -> {:reply, err, state}
    end
  end

  def handle_call({:register_database, db, result}, _, state) do
    db =
      result
      |> register_state(db)
      |> maybe_log_error()

    {:reply, :ok, Keyword.put(state, db[:id], db)}
  end

  def handle_call({:unload_database, which}, _, state) do
    :ok =
      state
      |> Keyword.get(which)
      |> unload_database()

    {:reply, :ok, Keyword.delete(state, which)}
  end

  def handle_call(:loaded, _, state) do
    loaded =
      state
      |> Enum.filter(fn {_id, db} -> :loaded == Map.get(db, :state) end)
      |> Keyword.keys()

    {:reply, loaded, state}
  end

  def handle_call(:registered, _, state) do
    {:reply, Keyword.keys(state), state}
  end

  def handle_cast(:reload_databases, state) do
    state =
      Enum.map(state, fn {id, db} ->
        db =
          db
          |> load_database(:async)
          |> register_state(db)
          |> maybe_log_error()

        {id, db}
      end)

    {:noreply, state}
  end

  # Internal methods

  defp load_database(%{adapter: adapter} = database, sync_type) do
    case Code.ensure_loaded?(adapter) do
      true ->
        :ok = DatabaseSupervisor.start_adapter(adapter)

        cond do
          function_exported?(adapter, :load_database, 2) ->
            adapter.load_database(database, sync_type)

          function_exported?(adapter, :load_database, 1) ->
            adapter.load_database(database)

          true -> :ok
        end

      false ->
        {:error, {:config, :unknown_adapter}}
    end
  end

  defp load_database(%{id: _}, _), do: {:error, {:config, :missing_adapter}}
  defp load_database(_, _), do: {:error, {:config, :invalid}}

  defp load_error_message(:enoent), do: "file not found (:enoent)"
  defp load_error_message({:config, :missing_adapter}), do: "missing adapter configuration"
  defp load_error_message({:config, :unknown_adapter}), do: "unknown adapter configuration"
  defp load_error_message(reason), do: inspect(reason)

  defp maybe_log_error(%{state: :delayed} = db), do: db
  defp maybe_log_error(%{state: :loaded} = db), do: db

  defp maybe_log_error(%{state: {:error, reason}} = db) do
    Logger.error("Failed to load database #{inspect(db[:id])}: #{load_error_message(reason)}")

    db
  end

  defp register_state(:delayed, db), do: Map.put(db, :state, :delayed)
  defp register_state(:ok, db), do: Map.put(db, :state, :loaded)
  defp register_state({:error, _} = err, db), do: Map.put(db, :state, err)

  defp unload_database(nil), do: :ok

  defp unload_database(%{adapter: adapter} = database) do
    case function_exported?(adapter, :unload_database, 1) do
      true -> adapter.unload_database(database)
      false -> :ok
    end
  end
end
