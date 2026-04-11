import std/options
import nesper
import nesper/gpios
import nesper/i2cs

const
  GT911_ADDR_PRIMARY = 0x5_d'u16
  GT911_ADDR_SECONDARY = 0x14'u16
  GT911_TOUCH_STATUS_REG = 0x814_e'u16
  GT911_POINT1_REG = 0x814F'u16

type
  TouchPhase* = enum
    Started, Moved, Ended

  TouchEvent* = object
    x*: int32
    y*: int32
    phase*: TouchPhase

  TouchController* = object
    dev: I2cDevice
    last_touch: bool
    last_x: int32
    last_y: int32
    width: uint32
    height: uint32

# --- 16-bit register helpers for GT911 ---

proc read_reg16(dev: I2cDevice, reg: uint16, buf: var openarray[uint8]): bool =
  let w = [uint8(reg shr 8), uint8(reg and 0xFF)]
  try:
    dev.transmit_receive(w, buf)
    return true
  except I2cError:
    return false

proc write_reg16(dev: I2cDevice, reg: uint16, data: openarray[uint8]): bool =
  var tmp = new_seq[uint8](2 + data.len)
  tmp[0] = uint8(reg shr 8)
  tmp[1] = uint8(reg and 0xFF)
  if data.len > 0:
    copy_mem(addr tmp[2], unsafe_addr data[0], data.len)
  try:
    dev.transmit(tmp)
    return true
  except I2cError:
    return false

# --- Public API ---

proc new_touch_controller*(width, height: uint32): TouchController =
  # Drive INT pin (GPIO38) LOW to force GT911 address = 0x5D
  configure({GPIO_NUM_38}, mode = GPIO_MODE_OUTPUT)
  set_level(GPIO_NUM_38, 0'u32)
  v_task_delay(pd_ms_to_ticks(50))

  # Release INT pin to input
  configure({GPIO_NUM_38}, mode = GPIO_MODE_INPUT)
  v_task_delay(pd_ms_to_ticks(50))

  # Create I2C master bus
  let bus = new_i2c_master_bus(
    i2c_port = 0.cint,
    sda = GPIO_NUM_19,
    scl = GPIO_NUM_20,
    enable_internal_pullup = true
  )

  # Probe for GT911
  var address = GT911_ADDR_PRIMARY
  for attempt in 0 ..< 3:
    if bus.probe(GT911_ADDR_PRIMARY):
      address = GT911_ADDR_PRIMARY
      break
    if bus.probe(GT911_ADDR_SECONDARY):
      address = GT911_ADDR_SECONDARY
      break
    v_task_delay(pd_ms_to_ticks(50))

  let dev = bus.add_device(
    device_address = I2cAddr(address),
    scl_speed_hz = 100_000.Hertz
  )

  result = TouchController(
    dev: dev,
    last_touch: false,
    last_x: 0,
    last_y: 0,
    width: width,
    height: height
  )

proc poll*(tc: var TouchController): Option[TouchEvent] =
  var status: array[1, uint8]
  if not tc.dev.read_reg16(GT911_TOUCH_STATUS_REG, status):
    return none(TouchEvent)

  if (status[0] and 0x80) == 0:
    return none(TouchEvent)

  let num_touches = status[0] and 0x0F

  # Clear status register
  var zero: array[1, uint8] = [0'u8]
  discard tc.dev.write_reg16(GT911_TOUCH_STATUS_REG, zero)

  if num_touches == 0:
    if tc.last_touch:
      tc.last_touch = false
      return some(TouchEvent(x: tc.last_x, y: tc.last_y, phase: Ended))
    return none(TouchEvent)

  # Read first touch point (8 bytes)
  var point_data: array[8, uint8]
  if not tc.dev.read_reg16(GT911_POINT1_REG, point_data):
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
