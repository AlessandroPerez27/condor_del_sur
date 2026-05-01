defmodule CondorDelSur.RegistradorAuditoria do
  # Inicia el proceso y lo registra con nombre global
  def iniciar do
    pid = spawn(fn -> init() end)
    Process.register(pid, :registrador_auditoria)
    pid
  end

  # Abre el archivo de log en modo append y arranca el bucle
  defp init do
    {:ok, archivo} = File.open("auditoria.log", [:append, :utf8])
    bucle(archivo, nil)
  end

  # Loop recursivo, espera mensajes indefinidamente
  defp bucle(archivo, ref_monitor) do
    receive do
      # Configura el monitor sobre el servidor de vuelo
      {:configurar_monitor, pid} ->
        referencia = Process.monitor(pid)
        bucle(archivo, referencia)

      # Escribe el evento en disco y en consola
      {:registrar, mensaje} ->
        marca_tiempo = :os.system_time(:second)
        IO.write(archivo, "[#{marca_tiempo}] #{mensaje}\n")
        IO.puts("[AUDITORIA] #{mensaje}")
        bucle(archivo, ref_monitor)

      # Elixir manda esto automáticamente cuando el proceso monitoreado muere, ref_monitor significa "solo si es exactamente este monitor"
      {:DOWN, ^ref_monitor, :process, _pid, razon} ->
        IO.puts("[AUDITORIA] ⚠ ServidorVuelo terminó: #{inspect(razon)}")
        IO.write(archivo, "[SISTEMA] ServidorVuelo caído: #{inspect(razon)}\n")
        File.close(archivo)
        # El proceso termina naturalmente al no llamar a bucle/2
    end
  end
end
