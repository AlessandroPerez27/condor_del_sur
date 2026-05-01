defmodule CondorDelSur.ServidorVuelo do
  alias CondorDelSur.{Asiento, Reserva}

  # Inicia el proceso del servidor y lo registra con nombre global Process.register devuelve :ok, por eso retornamos pid explicitamente
  def iniciar(vuelo, asientos) do
    pid = spawn(fn -> init(vuelo, asientos) end)
    Process.register(pid, :servidor_vuelo)
    pid
  end

  # Arma el estado inicial y arranca el bucle
  defp init(vuelo, asientos) do
    estado = %{
      vuelo: vuelo,
      # Convierte la lista en un mapa id => asiento para acceso rapido
      asientos: Map.new(asientos, fn a -> {a.id, a} end),
      reservas: %{},
      proximo_id: 1,
      # Guarda que proceso espera el resultado del pago: id_reserva => pid
      pagos_pendientes: %{}
    }

    bucle(estado)
  end

  # Bucle principal, atiende 1 mensaje a la vez, esto garantiza que no haya condicion de carrera sobre el estado, el servidor los atiende en orden - solo uno gana
  defp bucle(estado) do
    receive do
      {:reservar, id_asiento, id_pasajero, desde} ->
        {respuesta, nuevo_estado} = manejar_reserva(estado, id_asiento, id_pasajero)
        send(desde, respuesta)
        bucle(nuevo_estado)

      # Espera el resultado del pago
      {:confirmar, id_reserva, desde} ->
        nuevo_estado = manejar_confirmacion(estado, id_reserva, desde)
        bucle(nuevo_estado)

      # El proceso de pago manda esto cuando termina
      {:resultado_pago, id_reserva, resultado} ->
        nuevo_estado = manejar_resultado_pago(estado, id_reserva, resultado)
        bucle(nuevo_estado)

      {:cancelar, id_reserva, desde} ->
        {respuesta, nuevo_estado} = manejar_cancelacion(estado, id_reserva)
        send(desde, respuesta)
        bucle(nuevo_estado)

      # La tarea de expiracion manda esto despues de 30 segundos
      {:expirar, id_reserva} ->
        nuevo_estado = manejar_expiracion(estado, id_reserva)
        bucle(nuevo_estado)

      {:obtener_estado, desde} ->
        send(desde, {:estado, estado})
        bucle(estado)
    end
  end

  # ---- Manejadores privados ----

  # Intenta reservar un asiento, si esta available crea la reserva y lanza la tarea de expiracion
  # si no, retorna error sin cambiar el estado
  defp manejar_reserva(estado, id_asiento, id_pasajero) do
    asiento = Map.get(estado.asientos, id_asiento)

    cond do
      asiento == nil ->
        {{:error, :asiento_no_encontrado}, estado}

      not Asiento.disponible?(asiento) ->
        {{:error, :asiento_no_disponible}, estado}

      true ->
        id_reserva = "R#{estado.proximo_id}"
        reserva = Reserva.nueva(id_reserva, id_pasajero, id_asiento)
        {:ok, asiento_reservado} = Asiento.transicion(asiento, :reserved)

        nuevo_estado = %{
          estado
          | asientos: Map.put(estado.asientos, id_asiento, asiento_reservado),
            reservas: Map.put(estado.reservas, id_reserva, reserva),
            proximo_id: estado.proximo_id + 1
        }

        lanzar_expiracion(id_reserva)

        send(
          :registrador_auditoria,
          {:registrar,
           "RESERVA asiento=#{id_asiento} pasajero=#{id_pasajero} reserva=#{id_reserva}"}
        )

        {{:ok, id_reserva}, nuevo_estado}
    end
  end

  # Valida que la reserva exista y este pending, luego lanza el pago guarda el pid del pasajero y responde cuando llegue el resultado del pago
  defp manejar_confirmacion(estado, id_reserva, desde) do
    reserva = Map.get(estado.reservas, id_reserva)

    cond do
      reserva == nil ->
        send(desde, {:error, :reserva_no_encontrada})
        estado

      not Reserva.pendiente?(reserva) ->
        send(desde, {:error, :no_pendiente})
        estado

      true ->
        # Guarda quien espera para responderle cuando llegue el resultado del pago
        nuevo_estado = %{
          estado
          | pagos_pendientes: Map.put(estado.pagos_pendientes, id_reserva, desde)
        }

        lanzar_pago(id_reserva)
        nuevo_estado
    end
  end

  # Pago exitoso, confirma la reserva y el asiento y notifica al pasajero
  defp manejar_resultado_pago(estado, id_reserva, :ok) do
    reserva = Map.get(estado.reservas, id_reserva)
    desde = Map.get(estado.pagos_pendientes, id_reserva)

    case Reserva.confirmar(reserva) do
      {:ok, reserva_confirmada} ->
        asiento = Map.get(estado.asientos, reserva.id_asiento)
        {:ok, asiento_confirmado} = Asiento.transicion(asiento, :confirmed)

        send(:registrador_auditoria, {:registrar, "CONFIRMACION reserva=#{id_reserva}"})
        if desde, do: send(desde, {:ok, :confirmed})

        %{
          estado
          | reservas: Map.put(estado.reservas, id_reserva, reserva_confirmada),
            asientos: Map.put(estado.asientos, reserva.id_asiento, asiento_confirmado),
            pagos_pendientes: Map.delete(estado.pagos_pendientes, id_reserva)
        }

      {:error, razon} ->
        if desde, do: send(desde, {:error, razon})
        %{estado | pagos_pendientes: Map.delete(estado.pagos_pendientes, id_reserva)}
    end
  end

  # Pago fallido, notifica al pasajero y la reserva sigue pending
  defp manejar_resultado_pago(estado, id_reserva, :error) do
    desde = Map.get(estado.pagos_pendientes, id_reserva)
    if desde, do: send(desde, {:error, :pago_fallido})
    %{estado | pagos_pendientes: Map.delete(estado.pagos_pendientes, id_reserva)}
  end

  # Cancela una reserva pending y libera el asiento
  defp manejar_cancelacion(estado, id_reserva) do
    reserva = Map.get(estado.reservas, id_reserva)

    cond do
      reserva == nil ->
        {{:error, :reserva_no_encontrada}, estado}

      not Reserva.pendiente?(reserva) ->
        {{:error, :no_pendiente}, estado}

      true ->
        {:ok, reserva_cancelada} = Reserva.cancelar(reserva)
        asiento = Map.get(estado.asientos, reserva.id_asiento)
        {:ok, asiento_libre} = Asiento.transicion(asiento, :available)

        send(
          :registrador_auditoria,
          {:registrar, "CANCELACION reserva=#{id_reserva} asiento=#{reserva.id_asiento}"}
        )

        nuevo_estado = %{
          estado
          | reservas: Map.put(estado.reservas, id_reserva, reserva_cancelada),
            asientos: Map.put(estado.asientos, reserva.id_asiento, asiento_libre)
        }

        {{:ok, :cancelled}, nuevo_estado}
    end
  end

  # Expira la reserva solo si sigue pending
  # puede haber sido confirmed o cancelled antes de que llegue este mensaje
  defp manejar_expiracion(estado, id_reserva) do
    reserva = Map.get(estado.reservas, id_reserva)

    if reserva != nil and Reserva.pendiente?(reserva) do
      {:ok, reserva_expirada} = Reserva.expirar(reserva)
      asiento = Map.get(estado.asientos, reserva.id_asiento)
      {:ok, asiento_libre} = Asiento.transicion(asiento, :available)

      send(
        :registrador_auditoria,
        {:registrar, "EXPIRACION reserva=#{id_reserva} asiento=#{reserva.id_asiento}"}
      )

      %{
        estado
        | reservas: Map.put(estado.reservas, id_reserva, reserva_expirada),
          asientos: Map.put(estado.asientos, reserva.id_asiento, asiento_libre)
      }
    else
      estado
    end
  end

  # ---- Tareas puntuales (procesos que nacen, hacen algo y mueren) ----

  # Espera 30 segundos y avisa al servidor que la reserva vencio
  defp lanzar_expiracion(id_reserva) do
    spawn(fn ->
      Process.sleep(30_000)
      send(:servidor_vuelo, {:expirar, id_reserva})
    end)
  end

  # Simula latencia de pago y notifica el resultado al servidor
  defp lanzar_pago(id_reserva) do
    spawn(fn ->
      Process.sleep(500)
      send(:servidor_vuelo, {:resultado_pago, id_reserva, :ok})
    end)
  end
end
