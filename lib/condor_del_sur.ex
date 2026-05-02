defmodule CondorDelSur do
  alias CondorDelSur.{Vuelo, Asiento, Pasajero, ServidorVuelo, RegistradorAuditoria}

  # Levanta los procesos y ejecuta todos los escenarios
  def correr do
    IO.puts("\n========================================")
    IO.puts("   Condor del Sur - Sistema de Reservas")
    IO.puts("========================================\n")

    vuelo = Vuelo.nuevo("AR1234", "Buenos Aires", "Bariloche", "2026-07-15")

    asientos = [
      Asiento.nuevo("1A", 1, "A"),
      Asiento.nuevo("1B", 1, "B"),
      Asiento.nuevo("2A", 2, "A")
    ]

    pasajeros = [
      Pasajero.nuevo("P1", "Ana Garcia", "ana@gmail.com"),
      Pasajero.nuevo("P2", "Luis Perez", "luis@gmail.com"),
      Pasajero.nuevo("P3", "Maria Lopez", "maria@gmail.com")
    ]

    pid_logger = RegistradorAuditoria.iniciar()
    Process.sleep(100)
    pid_servidor = ServidorVuelo.iniciar(vuelo, asientos)
    Process.sleep(100)

    # Le avisamos al logger que monitoree al servidor
    send(pid_logger, {:configurar_monitor, pid_servidor})

    IO.puts("Vuelo #{vuelo.id}: #{vuelo.origen} -> #{vuelo.destino}")
    IO.puts("#{length(asientos)} asientos disponibles\n")

    # self() es el pid de este proceso, los hijos le mandan resultados aca
    yo = self()

    # ---- COMPETENCIA POR 1A ----

    IO.puts("--- Tres pasajeros compiten por el asiento 1A al mismo tiempo ---\n")

    Enum.each(pasajeros, fn pasajero ->
      spawn(fn ->
        send(:servidor_vuelo, {:reservar, "1A", pasajero.id, self()})

        receive do
          {:ok, id_reserva} ->
            IO.puts("OK #{pasajero.nombre} reservo 1A -> #{id_reserva}")
            send(yo, {:resultado_reserva, :ok, pasajero.id, id_reserva})

          {:error, razon} ->
            IO.puts("NO #{pasajero.nombre} no pudo reservar 1A (#{razon})")
            send(yo, {:resultado_reserva, :error, pasajero.id, nil})
        end
      end)
    end)

    reserva_ganadora = recolectar_resultados(length(pasajeros), nil)
    Process.sleep(300)

    # ---- CONFIRMACION ----

    IO.puts("\n--- Confirmacion del ganador ---\n")

    if reserva_ganadora do
      send(:servidor_vuelo, {:confirmar, reserva_ganadora, yo})

      receive do
        {:ok, :confirmed} -> IO.puts("OK Reserva #{reserva_ganadora} confirmada con pago")
        {:error, razon} -> IO.puts("NO Error al confirmar: #{razon}")
      after
        3000 -> IO.puts("NO Timeout esperando confirmacion")
      end
    end

    Process.sleep(300)

    # ---- CANCELACION ----

    IO.puts("\n--- Ana reserva 1B y cancela ---\n")

    send(:servidor_vuelo, {:reservar, "1B", "P1", yo})

    id_reserva_1b =
      receive do
        {:ok, id} ->
          IO.puts("OK Ana reservo 1B -> #{id}")
          id

        {:error, razon} ->
          IO.puts("NO Error: #{razon}")
          nil
      end

    if id_reserva_1b do
      Process.sleep(200)
      send(:servidor_vuelo, {:cancelar, id_reserva_1b, yo})

      receive do
        {:ok, :cancelled} ->
          IO.puts("OK Reserva #{id_reserva_1b} cancelada, 1B vuelve a estar available")

        {:error, razon} ->
          IO.puts("NO Error al cancelar: #{razon}")
      end
    end

    # ---- EXPIRACION ----

    IO.puts("\n--- Luis reserva 2A y no confirma (va a expirar) ---\n")

    send(:servidor_vuelo, {:reservar, "2A", "P2", yo})

    receive do
      {:ok, id} -> IO.puts("OK Luis reservo 2A -> #{id} (expira en 30s, no se confirma)")
      {:error, razon} -> IO.puts("NO Error: #{razon}")
    end

    IO.puts("(esperando 31 segundos para que expire...)\n")
    Process.sleep(31_000)

    # ---- ESTADO FINAL ----

    IO.puts("\n--- Estado final del sistema ---\n")

    send(:servidor_vuelo, {:obtener_estado, yo})

    receive do
      {:estado, estado} -> mostrar_estado(estado)
    end
  end

  # Toma N respuestas de procesos hijos y devuelve el primer id_reserva exitoso usa recursion con acumulador, cuando n llega a 0, retorna el ganador
  defp recolectar_resultados(0, ganador), do: ganador

  defp recolectar_resultados(n, ganador) do
    receive do
      {:resultado_reserva, :ok, _id, id_reserva} ->
        recolectar_resultados(n - 1, ganador || id_reserva)

      {:resultado_reserva, :error, _id, _} ->
        recolectar_resultados(n - 1, ganador)
    end
  end

  # Imprime el estado final del vuelo, asientos y reservas
  defp mostrar_estado(estado) do
    IO.puts("Vuelo: #{estado.vuelo.id} - #{estado.vuelo.origen} -> #{estado.vuelo.destino}\n")

    IO.puts("Asientos:")

    Enum.each(estado.asientos, fn {id, asiento} ->
      IO.puts("  [#{id}] #{asiento.estado}")
    end)

    IO.puts("\nReservas:")

    Enum.each(estado.reservas, fn {id, reserva} ->
      IO.puts(
        "  [#{id}] estado=#{reserva.estado} | asiento=#{reserva.id_asiento} | pasajero=#{reserva.id_pasajero}"
      )
    end)
  end
end
