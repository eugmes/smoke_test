defmodule EchoServerTest do
  use ExUnit.Case
  alias SmokeTest.EchoServer

  doctest EchoServer

  @timeout 1000

  defp connect!() do
    port = EchoServer.port(EchoServer)
    {:ok, sock} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false])
    sock
  end

  setup do
    sock = connect!()
    on_exit(fn -> :gen_tcp.close(sock) end)
    [socket: sock]
  end

  test "it does not send data by itself", %{socket: socket} do
    {:error, :timeout} = :gen_tcp.recv(socket, 255, @timeout)
  end

  test "it echoes data", %{socket: socket} do
    data = "first line"
    :ok = :gen_tcp.send(socket, data)
    {:ok, ^data} = :gen_tcp.recv(socket, 0, @timeout)
    data =  "second line"
    :ok = :gen_tcp.send(socket, data)
    {:ok, ^data} = :gen_tcp.recv(socket, 0, @timeout)
  end

  test "has limit of 5 connections", %{socket: socket} do
    additional_sockets = 1..4 |> Enum.map(fn _ -> connect!() end)
    sockets = [socket | additional_sockets]

    assert length(sockets) === 5

    extra_socket = connect!()
    on_exit(fn -> :gen_tcp.close(extra_socket) end)

    # check that communication is possible on those sockets
    Enum.map(sockets, fn socket ->
      data = "#{inspect(socket)}"
      :ok = :gen_tcp.send(socket, data)
      {:ok, ^data} = :gen_tcp.recv(socket, 0, @timeout)
    end)

    # does not reply to an additional socket yet
    data = "#{inspect(extra_socket)}"
    :ok = :gen_tcp.send(extra_socket, data)
    {:error, :timeout} = :gen_tcp.recv(extra_socket, 0, @timeout)

    assert Enum.map(additional_sockets, &:gen_tcp.close/1) |> Enum.all?(&(&1 === :ok))

    {:ok, ^data} = :gen_tcp.recv(extra_socket, 0, @timeout)
  end
end
