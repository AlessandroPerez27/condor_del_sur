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

## Estructura del proyecto

```
condor_del_sur/
├── lib/
│   ├── condor_del_sur/
│   │   ├── asiento.ex           # struct Asiento y transiciones de estado
│   │   ├── pasajero.ex          # struct Pasajero
│   │   ├── reserva.ex           # struct Reserva y transiciones de estado
│   │   ├── vuelo.ex             # struct Vuelo
│   │   ├── servidor_vuelo.ex    # proceso principal, dueño del estado
│   │   └── registrador_auditoria.ex  # proceso auxiliar, log y monitor
│   └── condor_del_sur.ex        # punto de entrada, demo con correr/0
└── test/
    ├── condor_del_sur/
    │   ├── asiento_test.exs     # tests unitarios del struct Asiento
    │   └── reserva_test.exs     # tests unitarios del struct Reserva
    └── condor_del_sur_test.exs  # tests de integración con el servidor
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

## Decisiones de diseño

**ServidorVuelo como único dueño del estado**
Todo el estado vive en un solo proceso. Esto garantiza que no haya
condiciones de carrera: si dos pasajeros mandan `{:reservar, "1A"}` al
mismo tiempo, el servidor los atiende en orden y solo uno gana. No hacen
falta locks ni mutexes porque no hay memoria compartida.

**Confirmación asincrónica con pagos_pendientes**
`manejar_confirmacion` no responde inmediatamente al pasajero: guarda su
pid en `pagos_pendientes` y responde recién cuando llega `{:resultado_pago}`.
Esto permite que la tarea de pago corra en paralelo sin bloquear el servidor.

**Tarea de expiración verifica estado antes de expirar**
La tarea spawneada puede llegar tarde si el pasajero ya confirmó o canceló
mientras tanto. Por eso `manejar_expiracion` verifica que la reserva siga
`:pending` antes de aplicar el cambio, evitando transiciones inválidas.

**timeout_expiracion configurable**
El timeout se pasa como parámetro a `iniciar/3` con valor por defecto
`30_000ms`. Esto permite que los tests usen `1_000ms` sin esperar 30
segundos reales, sin tocar nada de la lógica de negocio.

**RegistradorAuditoria con monitor sobre ServidorVuelo**
Se usa `^ref_monitor` para matchear exactamente el monitor configurado y
no mensajes de otros procesos. Si el servidor cae, el auditor cierra el
archivo de log limpiamente antes de terminar.

## Restricciones del TP

No se usa ningún módulo de OTP. Solo:

- `spawn` / `send` / `receive`
- loops recursivos manuales
- `Process.register`
- `Process.monitor`
