# Cóndor del Sur

Sistema de reservas de asientos para la aerolínea regional Cóndor del Sur,
implementado con procesos manuales en Elixir sin OTP.

## Requisitos

- Elixir 1.19 o superior
- Mix (viene incluido con Elixir)

## Instalación

```bash
git clone https://github.com/AlessandroPerez27/condor_del_sur
cd condor_del_sur
mix deps.get
```

## Correr la demo

La demo levanta todos los procesos y ejecuta 4 escenarios: competencia
concurrente por un asiento, confirmación por pago, cancelación y expiración.

```bash
mix run -e "CondorDelSur.correr()"
```

O desde la consola interactiva:

```bash
iex -S mix
iex> CondorDelSur.correr()
```

La demo tarda ~31 segundos porque espera que la reserva de 2A expire naturalmente.
Al terminar genera un archivo `auditoria.log` con todos los eventos del sistema.

## Correr los tests

```bash
mix test                  # todos los tests
mix test --trace          # con detalle de cada test por nombre
mix test test/condor_del_sur/asiento_test.exs   # solo tests de Asiento
mix test test/condor_del_sur/reserva_test.exs   # solo tests de Reserva
mix test test/condor_del_sur_test.exs           # solo tests de integracion
```

En total hay 20 tests:

- 5 en `asiento_test.exs` — estados y transiciones del struct Asiento
- 9 en `reserva_test.exs` — estados y transiciones del struct Reserva
- 6 en `condor_del_sur_test.exs` — integración con el ServidorVuelo real

## Procesos principales

### ServidorVuelo (registrado como `:servidor_vuelo`)

Proceso central del sistema. Mantiene todo el estado: vuelo, asientos,
reservas y pagos pendientes. Atiende un mensaje a la vez, lo que garantiza
que no haya condiciones de carrera: si dos pasajeros intentan reservar el
mismo asiento simultáneamente, el servidor los atiende en orden y solo uno
gana.

Mensajes que acepta:

- `{:reservar, id_asiento, id_pasajero, desde}`
- `{:confirmar, id_reserva, desde}`
- `{:cancelar, id_reserva, desde}`
- `{:expirar, id_reserva}` — enviado por la tarea de expiración
- `{:resultado_pago, id_reserva, :ok | :error}` — enviado por la tarea de pago
- `{:obtener_estado, desde}`

### RegistradorAuditoria (registrado como `:registrador_auditoria`)

Proceso auxiliar que escribe eventos a `auditoria.log` y los imprime en
consola con prefijo `[AUDITORIA]`. Monitorea al ServidorVuelo y cierra
el archivo limpiamente si el servidor cae.

### Procesos cliente

Un proceso spawneado por pasajero. Envían mensajes al ServidorVuelo y
esperan respuesta. Varios compiten concurrentemente por el mismo asiento.

### Tareas puntuales

- **Tarea de expiración**: spawneada al crear cada reserva. Duerme 30
  segundos y manda `{:expirar, id_reserva}` al servidor. El servidor
  verifica que la reserva siga `:pending` antes de expirar.
- **Tarea de pago**: spawneada al confirmar. Imprime `[PAGO] procesando...`,
  simula latencia de red (500ms) y manda el resultado al servidor.

## Uso de `register` y `monitor`

### Process.register

```elixir
Process.register(pid, :servidor_vuelo)
Process.register(pid, :registrador_auditoria)
```

Permite que cualquier proceso mande mensajes por nombre sin necesitar
el PID directamente. Se usa en los dos procesos principales del sistema.

### Process.monitor

```elixir
referencia = Process.monitor(pid_servidor)
```

El `RegistradorAuditoria` monitorea al `ServidorVuelo`. Cuando el servidor
termina, la VM manda automáticamente `{:DOWN, ref, :process, pid, razon}`
a la mailbox del auditor. Se usa `^ref_monitor` para matchear exactamente
ese monitor y no mensajes de otros procesos, y al recibirlo cierra el
archivo de log limpiamente.

## Estados

**Reserva**: `:pending` → `:confirmed` | `:cancelled` | `:expired`

**Asiento**: `:available` → `:reserved` → `:confirmed` | `:available`

## Restricciones de diseño

No se usa ningún módulo de OTP. Solo:

- `spawn` / `send` / `receive`
- loops recursivos manuales
- `Process.register`
- `Process.monitor`
