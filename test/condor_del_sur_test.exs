defmodule CondorDelSurTest do
  use ExUnit.Case
  alias CondorDelSur.{Vuelo, Asiento, ServidorVuelo}

  # Levanta un servidor fresco antes de cada test con timeout corto para expiracion
  setup do
    vuelo = Vuelo.nuevo("AR1234", "Buenos Aires", "Bariloche", "2026-07-15")
    asientos = [Asiento.nuevo("1A", 1, "A"), Asiento.nuevo("1B", 1, "B")]
    pid = ServidorVuelo.iniciar(vuelo, asientos, 1_000)

    # Limpia el proceso registrado al terminar cada test
    on_exit(fn ->
      if Process.alive?(pid), do: Process.exit(pid, :kill)
      # Espera a que se limpie el registro antes del proximo test
      Process.sleep(50)
    end)

    %{pid: pid}
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

  # Usa timeout de 1 segundo configurado en setup, espera 2s para que expire
  test "reserva expirada libera el asiento" do
    send(:servidor_vuelo, {:reservar, "1A", "P1", self()})
    assert_receive {:ok, _id_reserva}, 1_000

    # Espera que expire (timeout configurado en 1s en setup)
    Process.sleep(2_000)

    send(:servidor_vuelo, {:obtener_estado, self()})
    assert_receive {:estado, estado}, 1_000

    reserva = estado.reservas |> Map.values() |> List.first()
    asiento = Map.get(estado.asientos, "1A")

    assert reserva.estado == :expired
    assert asiento.estado == :available
  end
end
