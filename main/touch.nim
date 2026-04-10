import std/options

const
  GT911_ADDR_PRIMARY = 0x5_d'u8
  GT911_ADDR_SECONDARY = 0x14'u8
  GT911_TOUCH_STATUS_REG = 0x814E'u16
  GT911_POINT1_REG = 0x814_f'u16

type
  TouchPhase* = enum
    Started, Moved, Ended

  TouchEvent* = object
    x*: int32
    y*: int32
    phase*: TouchPhase

  TouchController* = object
    i2cPort: cint
    address: uint8
    lastTouch: bool
    lastX: int32
    lastY: int32
    width: uint32
    height: uint32

# --- I2C C API bindings (legacy driver) ---

type
  I2cMode {.size: sizeof(cint).} = enum
    I2C_MODE_SLAVE = 0
    I2C_MODE_MASTER = 1

  I2cConfig {.importc: "i2c_config_t", header: "driver/i2c.h", bycopy.} = object
    mode {.importc: "mode".}: I2cMode
    sda_io_num {.importc: "sda_io_num".}: cint
    scl_io_num {.importc: "scl_io_num".}: cint
    sda_pullup_en {.importc: "sda_pullup_en".}: bool
    scl_pullup_en {.importc: "scl_pullup_en".}: bool
    master_clk_speed {.importc: "master.clk_speed".}: uint32

  I2cCmdHandle = pointer

const
  I2C_NUM_0 = 0.cint
  I2C_MASTER_WRITE = 0'u8
  I2C_MASTER_READ = 1'u8
  I2C_MASTER_ACK = 0.cint
  I2C_MASTER_NACK = 1.cint

proc i2c_param_config(i2c_num: cint, i2c_conf: ptr I2cConfig): cint {.
  importc: "i2c_param_config", header: "driver/i2c.h".}

proc i2c_driver_install(i2c_num: cint, mode: I2cMode,
                         slv_rx_buf: csize_t, slv_tx_buf: csize_t,
                         intr_alloc_flags: cint): cint {.
  importc: "i2c_driver_install", header: "driver/i2c.h".}

proc i2c_cmd_link_create(): I2cCmdHandle {.
  importc: "i2c_cmd_link_create", header: "driver/i2c.h".}

proc i2c_cmd_link_delete(cmd: I2cCmdHandle) {.
  importc: "i2c_cmd_link_delete", header: "driver/i2c.h".}

proc i2c_master_start(cmd: I2cCmdHandle): cint {.
  importc: "i2c_master_start", header: "driver/i2c.h".}

proc i2c_master_stop(cmd: I2cCmdHandle): cint {.
  importc: "i2c_master_stop", header: "driver/i2c.h".}

proc i2c_master_write_byte(cmd: I2cCmdHandle, data: uint8, ack_en: bool): cint {.
  importc: "i2c_master_write_byte", header: "driver/i2c.h".}

proc i2c_master_read_byte(cmd: I2cCmdHandle, data: ptr uint8, ack: cint): cint {.
  importc: "i2c_master_read_byte", header: "driver/i2c.h".}

proc i2c_master_read(cmd: I2cCmdHandle, data: ptr uint8, len: csize_t, ack: cint): cint {.
  importc: "i2c_master_read", header: "driver/i2c.h".}

proc i2c_master_cmd_begin(i2c_num: cint, cmd: I2cCmdHandle,
                           ticks_to_wait: uint32): cint {.
  importc: "i2c_master_cmd_begin", header: "driver/i2c.h".}

proc gpio_set_direction(gpio_num: cint, mode: cint): cint {.
  importc: "gpio_set_direction", header: "driver/gpio.h".}

proc gpio_set_level(gpio_num: cint, level: uint32): cint {.
  importc: "gpio_set_level", header: "driver/gpio.h".}

proc vTaskDelay(ticks: uint32) {.importc: "vTaskDelay", header: "freertos/FreeRTOS.h".}

const
  GPIO_MODE_OUTPUT = 2
  GPIO_MODE_INPUT = 1

proc pdMS_TO_TICKS(ms: uint32): uint32 {.importc: "pdMS_TO_TICKS",
  header: "freertos/FreeRTOS.h".}

# --- I2C helpers ---

proc i2cWrite(tc: TouchController, reg: uint16, data: openarray[uint8]): bool =
  let cmd = i2c_cmd_link_create()
  discard i2c_master_start(cmd)
  discard i2c_master_write_byte(cmd, (tc.address shl 1) or I2C_MASTER_WRITE, true)
  discard i2c_master_write_byte(cmd, uint8(reg shr 8), true)
  discard i2c_master_write_byte(cmd, uint8(reg and 0xFF), true)
  for b in data:
    discard i2c_master_write_byte(cmd, b, true)
  discard i2c_master_stop(cmd)
  let ret = i2c_master_cmd_begin(tc.i2cPort, cmd, pdMS_TO_TICKS(100))
  i2c_cmd_link_delete(cmd)
  result = ret == 0

proc i2cRead(tc: TouchController, reg: uint16, buf: var openarray[uint8]): bool =
  let len = buf.len
  if len == 0:
    return false

  # Write register address
  let cmd = i2c_cmd_link_create()
  discard i2c_master_start(cmd)
  discard i2c_master_write_byte(cmd, (tc.address shl 1) or I2C_MASTER_WRITE, true)
  discard i2c_master_write_byte(cmd, uint8(reg shr 8), true)
  discard i2c_master_write_byte(cmd, uint8(reg and 0xFF), true)

  # Repeated start + read
  discard i2c_master_start(cmd)
  discard i2c_master_write_byte(cmd, (tc.address shl 1) or I2C_MASTER_READ, true)
  if len > 1:
    discard i2c_master_read(cmd, addr buf[0], csize_t(len - 1), I2C_MASTER_ACK)
  discard i2c_master_read_byte(cmd, addr buf[len - 1], I2C_MASTER_NACK)
  discard i2c_master_stop(cmd)
  let ret = i2c_master_cmd_begin(tc.i2cPort, cmd, pdMS_TO_TICKS(100))
  i2c_cmd_link_delete(cmd)
  result = ret == 0

proc probeAddress(port: cint, address: uint8): bool =
  let cmd = i2c_cmd_link_create()
  discard i2c_master_start(cmd)
  discard i2c_master_write_byte(cmd, (address shl 1) or I2C_MASTER_WRITE, true)
  discard i2c_master_stop(cmd)
  let ret = i2c_master_cmd_begin(port, cmd, pdMS_TO_TICKS(100))
  i2c_cmd_link_delete(cmd)
  result = ret == 0

# --- Public API ---

proc newTouchController*(width, height: uint32): TouchController =
  # Drive INT pin (GPIO38) LOW to force GT911 address = 0x5D
  discard gpio_set_direction(38, GPIO_MODE_OUTPUT)
  discard gpio_set_level(38, 0)
  vTaskDelay(pdMS_TO_TICKS(50))

  # Release INT pin to input
  discard gpio_set_direction(38, GPIO_MODE_INPUT)
  vTaskDelay(pdMS_TO_TICKS(50))

  # Configure I2C master
  var conf: I2cConfig
  conf.mode = I2C_MODE_MASTER
  conf.sda_io_num = 19
  conf.scl_io_num = 20
  conf.sda_pullup_en = true
  conf.scl_pullup_en = true
  conf.master_clk_speed = 100_000

  discard i2c_param_config(I2C_NUM_0, addr conf)
  discard i2c_driver_install(I2C_NUM_0, I2C_MODE_MASTER, 0, 0, 0)

  # Probe for GT911
  var address = GT911_ADDR_PRIMARY
  for attempt in 0 ..< 3:
    if probeAddress(I2C_NUM_0, GT911_ADDR_PRIMARY):
      address = GT911_ADDR_PRIMARY
      break
    if probeAddress(I2C_NUM_0, GT911_ADDR_SECONDARY):
      address = GT911_ADDR_SECONDARY
      break
    vTaskDelay(pdMS_TO_TICKS(50))

  result = TouchController(
    i2cPort: I2C_NUM_0,
    address: address,
    lastTouch: false,
    lastX: 0,
    lastY: 0,
    width: width,
    height: height
  )

proc poll*(tc: var TouchController): Option[TouchEvent] =
  var status: array[1, uint8]
  if not tc.i2cRead(GT911_TOUCH_STATUS_REG, status):
    return none(TouchEvent)

  if (status[0] and 0x80) == 0:
    return none(TouchEvent)

  let numTouches = status[0] and 0x0F

  # Clear status register
  var zero: array[1, uint8] = [0'u8]
  discard tc.i2c_write(GT911_TOUCH_STATUS_REG, zero)

  if num_touches == 0:
    if tc.last_touch:
      tc.last_touch = false
      return some(TouchEvent(x: tc.last_x, y: tc.last_y, phase: Ended))
    return none(TouchEvent)

  # Read first touch point (8 bytes)
  var point_data: array[8, uint8]
  if not tc.i2c_read(GT911_POINT1_REG, point_data):
    return none(TouchEvent)

  var x = int32(point_data[1]) or (int32(point_data[2]) shl 8)
  var y = int32(point_data[3]) or (int32(point_data[4]) shl 8)

  # Clamp
  x = clamp(x, 0, int32(tc.width) - 1)
  y = clamp(y, 0, int32(tc.height) - 1)

  let phase = if tc.last_touch: Moved else: Started
  tc.last_touch = true
  tc.last_x = x
  tc.last_y = y

  return some(TouchEvent(x: x, y: y, phase: phase))
