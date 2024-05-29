defmodule SmokeTest.Application do
  use Application

  @impl Application
  def start(_type, _args) do
    children = [
      {SmokeTest.EchoServer, port: 4000, max_active_clients: 5, name: SmokeTest.EchoServer}
    ]

    opts = [strategy: :one_for_one, name: SmokeTest.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
