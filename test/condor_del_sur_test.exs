defmodule CondorDelSurTest do
  use ExUnit.Case
  alias CondorDelSur.{Vuelo, Asiento, ServidorVuelo, RegistradorAuditoria}

  # Helpers para no repetir la inicializacion
  defp iniciar_sistema(timeout_expiracion) do
    # Mata cualquier proceso registrado previo antes de levantar uno nuevo
    if pid = Process.whereis(:registrador_auditoria) do
      Process.exit(pid, :kill)
      Process.sleep(20)
    end

    if pid = Process.whereis(:servidor_vuelo) do
      Process.exit(pid, :kill)
      Process.sleep(20)
    end

    vuelo = Vuelo.nuevo("AR1234", "Buenos Aires", "Bariloche", "2026-07-15")
    asientos = [Asiento.nuevo("1A", 1, "A"), Asiento.nuevo("1B", 1, "B")]
    pid_logger = RegistradorAuditoria.iniciar()
    Process.sleep(50)
    pid_servidor = ServidorVuelo.iniciar(vuelo, asientos, timeout_expiracion)
    {pid_servidor, pid_logger}
  end

  defp detener_sistema(pid_servidor, pid_logger) do
    if Process.alive?(pid_servidor), do: Process.exit(pid_servidor, :kill)
    if Process.alive?(pid_logger), do: Process.exit(pid_logger, :kill)
    Process.sleep(50)
  end

  # Setup con 5 segundos de expiracion, suficiente para que el pago (500ms) llegue antes
  setup do
    {pid_servidor, pid_logger} = iniciar_sistema(5_000)
    on_exit(fn -> detener_sistema(pid_servidor, pid_logger) end)
    %{pid_servidor: pid_servidor, pid_logger: pid_logger}
  end

  test "reservar asiento disponible retorna ok con id de reserva" do
    send(:servidor_vuelo, {:reservar, "1A", "P1", self()})
    assert_receive {:ok, id_reserva}, 1_000
    assert String.starts_with?(id_reserva, "R")
  end

  test "reservar asiento ocupado retorna error" do
    send(:servidor_vuelo, {:reservar, "1A", "P1", self()})
    assert_receive {:ok, _}, 1_000

    send(:servidor_vuelo, {:reservar, "1A", "P2", self()})
    assert_receive {:error, :asiento_no_disponible}, 1_000
  end

  test "confirmar reserva pending la confirma y responde ok" do
    send(:servidor_vuelo, {:reservar, "1A", "P1", self()})
    assert_receive {:ok, id_reserva}, 1_000

    send(:servidor_vuelo, {:confirmar, id_reserva, self()})
    assert_receive {:ok, :confirmed}, 2_000
  end

  test "cancelar reserva pending la cancela y libera el asiento" do
    send(:servidor_vuelo, {:reservar, "1A", "P1", self()})
    assert_receive {:ok, id_reserva}, 1_000

    send(:servidor_vuelo, {:cancelar, id_reserva, self()})
    assert_receive {:ok, :cancelled}, 1_000

    # El asiento vuelve a estar disponible
    send(:servidor_vuelo, {:reservar, "1A", "P2", self()})
    assert_receive {:ok, _}, 1_000
  end

  test "no se puede cancelar una reserva confirmed" do
    send(:servidor_vuelo, {:reservar, "1A", "P1", self()})
    assert_receive {:ok, id_reserva}, 1_000

    send(:servidor_vuelo, {:confirmar, id_reserva, self()})
    assert_receive {:ok, :confirmed}, 2_000

    send(:servidor_vuelo, {:cancelar, id_reserva, self()})
    assert_receive {:error, :no_pendiente}, 1_000
  end

  # Este test levanta su propio sistema con timeout corto, independiente del setup
  test "reserva expirada libera el asiento" do
    {pid_servidor, pid_logger} = iniciar_sistema(1_000)

    send(pid_servidor, {:reservar, "1A", "P1", self()})
    assert_receive {:ok, _id_reserva}, 1_000

    # Espera que expire (timeout 1s + margen)
    Process.sleep(1_500)

    send(pid_servidor, {:obtener_estado, self()})
    assert_receive {:estado, estado}, 1_000

    reserva = estado.reservas |> Map.values() |> List.first()
    asiento = Map.get(estado.asientos, "1A")

    assert reserva.estado == :expired
    assert asiento.estado == :available

    detener_sistema(pid_servidor, pid_logger)
  end
end
