defmodule SmokeTest.EchoServer do
  use GenServer

  require Logger

  defstruct [:max_active_clients, :listen_socket, :accept_ref, clients: %{}]

  @type server_option :: {:port, :inet.port_number()} | {:max_active_clients, non_neg_integer()}
  @type option :: server_option() | GenServer.option()
  @type options :: [option()]

  @spec start_link(options()) :: GenServer.on_start()
  def start_link(opts) do
    {server_opts, gen_opts} = Keyword.split(opts, [:port, :max_active_clients])
    GenServer.start_link(__MODULE__, server_opts, gen_opts)
  end

  @doc """
  Return the port number on which this server is listening.
  """
  @spec port(GenServer.server()) :: :inet.port_number()
  def port(pid) do
    GenServer.call(pid, :port)
  end

  @impl GenServer
  def init(opts) do
    Logger.debug("Starting echo server")

    port = Keyword.get(opts, :port, 0)
    {:ok, listen_socket} = :gen_tcp.listen(port, [:binary, active: false, reuseaddr: true])

    Logger.debug(fn ->
      {:ok, port} = :inet.port(listen_socket)
      "Listening at port #{port}"
    end)

    {:ok, accept_ref} = :prim_inet.async_accept(listen_socket, -1)
    max_active_clients = Keyword.get(opts, :max_active_clients, 0)

    state = %__MODULE__{
      listen_socket: listen_socket,
      accept_ref: accept_ref,
      max_active_clients: max_active_clients
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_info(
        {:inet_async, listen_socket, accept_ref, {:ok, sock}},
        %__MODULE__{
          listen_socket: listen_socket,
          accept_ref: accept_ref,
          clients: clients,
          max_active_clients: max_active_clients
        } =
          state
      ) do
    {:ok, peer_name} = :inet.peername(sock)
    Logger.debug("New connection from #{inspect(peer_name)}")

    :ok = :inet.setopts(sock, active: :once)

    clients = Map.put(clients, sock, peer_name)

    accept_ref =
      if max_active_clients == 0 || map_size(clients) < max_active_clients do
        {:ok, accept_ref} = :prim_inet.async_accept(listen_socket, -1)
        accept_ref
      else
        Logger.debug("Suspending accept")
        nil
      end

    state = %{state | accept_ref: accept_ref, clients: clients}

    {:noreply, state}
  end

  def handle_info({:tcp, sock, data}, state) do
    :ok = :inet.send(sock, data)
    :inet.setopts(sock, active: :once)
    {:noreply, state}
  end

  def handle_info(
        {:tcp_closed, sock},
        %__MODULE__{listen_socket: listen_socket, accept_ref: accept_ref, clients: clients} =
          state
      ) do
    Logger.debug(fn ->
      peer_name = Map.fetch!(clients, sock)
      "Disconnected from #{inspect(peer_name)}"
    end)

    clients = Map.delete(clients, sock)

    accept_ref =
      case accept_ref do
        nil ->
          Logger.debug("Resuming accept")
          {:ok, accept_ref} = :prim_inet.async_accept(listen_socket, -1)
          accept_ref

        ref ->
          ref
      end

    state = %{state | clients: clients, accept_ref: accept_ref}
    {:noreply, state}
  end

  @impl GenServer
  def handle_call(:port, _from, %__MODULE__{listen_socket: listen_socket} = state) do
    {:ok, port} = :inet.port(listen_socket)
    {:reply, port, state}
  end
end
