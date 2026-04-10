import std/options
import nesper
import nesper/esp/esp_timer
import display, touch, simulation

proc now_ms(): uint64 =
  uint64(esp_timer_get_time() div 1000)

# --- Layout constants ---

const
  CELL_SIZE = 4'u32
  UI_BAR_H = 32'u32
  GRID_W = (DISPLAY_WIDTH div CELL_SIZE).int        # 200
  GRID_H = ((DISPLAY_HEIGHT - UI_BAR_H) div CELL_SIZE).int  # 112
  GRID_AREA_H = (GRID_H.uint32 * CELL_SIZE)         # 448
  FRAME_MS = 33'u64                                   # ~30 FPS
  STEP_INTERVAL_DEFAULT = 2'u32

# --- Colors (RGB565) ---

const
  COLOR_BG = 0x0000'u16
  COLOR_GRID = 0x18E3'u16
  COLOR_UI_BG = 0x2104'u16
  COLOR_UI_TEXT = 0xFFFF'u16
  COLOR_UI_ACCENT = 0x07_e0'u16

# --- Font (minimal 5x7 bitmask for A-Z, 0-9, +, -, :, space) ---

const FONT_W = 5
const FONT_H = 7

const FONT_DATA: array[128, array[7, uint8]] = block:
  var data: array[128, array[7, uint8]]

  # Space (32)
  data[32] = [0x00'u8, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]

  # + (43)
  data[43] = [0x00'u8, 0x04, 0x04, 0x1F, 0x04, 0x04, 0x00]

  # - (45)
  data[45] = [0x00'u8, 0x00, 0x00, 0x1_f, 0x00, 0x00, 0x00]

  # 0-9 (48-57)
  data[48] = [0x0_e'u8, 0x11, 0x13, 0x15, 0x19, 0x11, 0x0E]
  data[49] = [0x04'u8, 0x0_c, 0x04, 0x04, 0x04, 0x04, 0x0_e]
  data[50] = [0x0_e'u8, 0x11, 0x01, 0x06, 0x08, 0x10, 0x1F]
  data[51] = [0x0E'u8, 0x11, 0x01, 0x06, 0x01, 0x11, 0x0_e]
  data[52] = [0x02'u8, 0x06, 0x0A, 0x12, 0x1F, 0x02, 0x02]
  data[53] = [0x1F'u8, 0x10, 0x1_e, 0x01, 0x01, 0x11, 0x0_e]
  data[54] = [0x06'u8, 0x08, 0x10, 0x1E, 0x11, 0x11, 0x0E]
  data[55] = [0x1F'u8, 0x01, 0x02, 0x04, 0x08, 0x08, 0x08]
  data[56] = [0x0_e'u8, 0x11, 0x11, 0x0E, 0x11, 0x11, 0x0E]
  data[57] = [0x0E'u8, 0x11, 0x11, 0x0_f, 0x01, 0x02, 0x0_c]

  # : (58)
  data[58] = [0x00'u8, 0x04, 0x00, 0x00, 0x00, 0x04, 0x00]

  # A-Z (65-90)
  data[65] = [0x0E'u8, 0x11, 0x11, 0x1_f, 0x11, 0x11, 0x11]  # A
  data[66] = [0x1_e'u8, 0x11, 0x11, 0x1E, 0x11, 0x11, 0x1E]  # B
  data[67] = [0x0E'u8, 0x11, 0x10, 0x10, 0x10, 0x11, 0x0_e]  # C
  data[68] = [0x1_e'u8, 0x11, 0x11, 0x11, 0x11, 0x11, 0x1E]  # D
  data[69] = [0x1F'u8, 0x10, 0x10, 0x1_e, 0x10, 0x10, 0x1_f]  # E
  data[70] = [0x1_f'u8, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x10]  # F
  data[71] = [0x0E'u8, 0x11, 0x10, 0x17, 0x11, 0x11, 0x0_f]  # G
  data[72] = [0x11'u8, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11]  # H
  data[73] = [0x0E'u8, 0x04, 0x04, 0x04, 0x04, 0x04, 0x0_e]  # I
  data[74] = [0x07'u8, 0x02, 0x02, 0x02, 0x02, 0x12, 0x0C]  # J
  data[75] = [0x11'u8, 0x12, 0x14, 0x18, 0x14, 0x12, 0x11]  # K
  data[76] = [0x10'u8, 0x10, 0x10, 0x10, 0x10, 0x10, 0x1F]  # L
  data[77] = [0x11'u8, 0x1_b, 0x15, 0x15, 0x11, 0x11, 0x11]  # M
  data[78] = [0x11'u8, 0x11, 0x19, 0x15, 0x13, 0x11, 0x11]  # N
  data[79] = [0x0E'u8, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0_e]  # O
  data[80] = [0x1_e'u8, 0x11, 0x11, 0x1E, 0x10, 0x10, 0x10]  # P
  data[81] = [0x0E'u8, 0x11, 0x11, 0x11, 0x15, 0x12, 0x0_d]  # Q
  data[82] = [0x1_e'u8, 0x11, 0x11, 0x1E, 0x14, 0x12, 0x11]  # R
  data[83] = [0x0E'u8, 0x11, 0x10, 0x0_e, 0x01, 0x11, 0x0_e]  # S
  data[84] = [0x1_f'u8, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04]  # T
  data[85] = [0x11'u8, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0_e]  # U
  data[86] = [0x11'u8, 0x11, 0x11, 0x11, 0x0A, 0x0A, 0x04]  # V
  data[87] = [0x11'u8, 0x11, 0x11, 0x15, 0x15, 0x1_b, 0x11]  # W
  data[88] = [0x11'u8, 0x11, 0x0A, 0x04, 0x0A, 0x11, 0x11]  # X
  data[89] = [0x11'u8, 0x11, 0x0_a, 0x04, 0x04, 0x04, 0x04]  # Y
  data[90] = [0x1_f'u8, 0x01, 0x02, 0x04, 0x08, 0x10, 0x1F]  # Z

  data

proc draw_char(fb: var Framebuffer, cx, cy: uint32, ch: char, color: uint16) =
  let idx = ord(ch)
  if idx < 0 or idx >= 128:
    return
  for row in 0 ..< FONT_H:
    let bits = FONT_DATA[idx][row]
    for col in 0 ..< FONT_W:
      if (bits and (0x10'u8 shr col.uint8)) != 0:
        fb.set_pixel(cx + col.uint32, cy + row.uint32, color)

proc draw_text(fb: var Framebuffer, x, y: uint32, text: string, color: uint16) =
  var cx = x
  for ch in text:
    draw_char(fb, cx, y, ch, color)
    cx += (FONT_W + 1).uint32

# --- Button definitions ---

type
  Button = object
    x0, x1: uint32
    label: string
    color: uint16

let BUTTONS = [
  Button(x0: 4, x1: 84, label: "PLAY", color: COLOR_UI_ACCENT),
  Button(x0: 90, x1: 160, label: "STEP", color: COLOR_UI_TEXT),
  Button(x0: 166, x1: 240, label: "CLEAR", color: COLOR_UI_TEXT),
  Button(x0: 246, x1: 330, label: "RANDOM", color: COLOR_UI_TEXT),
  Button(x0: 336, x1: 396, label: "SPD-", color: COLOR_UI_TEXT),
  Button(x0: 402, x1: 462, label: "SPD+", color: COLOR_UI_TEXT),
]

# --- Color mapping ---

proc label_to_color(label: uint16): uint16 =
  var h = label * 0x9_e37'u16
  h = h xor (h shr 7)
  h = h * 0x5F35'u16
  let r = ((h shr 0) and 0x1_f) or 0x08
  let g = ((h shr 5) and 0x3_f) or 0x10
  let b = ((h shr 11) and 0x1_f) or 0x08
  (r shl 11) or (g shl 5) or b

# --- Rendering ---

proc render_grid(fb: var Framebuffer, sim: Simulation) =
  for gy in 0 ..< GRID_H:
    for gx in 0 ..< GRID_W:
      let lbl = sim.label(gx, gy)
      let px = gx.uint32 * CELL_SIZE
      let py = gy.uint32 * CELL_SIZE
      let fill = if lbl != 0: label_to_color(lbl) else: COLOR_BG
      for dy in 0'u32 ..< (CELL_SIZE - 1):
        for dx in 0'u32 ..< (CELL_SIZE - 1):
          fb.set_pixel(px + dx, py + dy, fill)
      for dx in 0'u32 ..< CELL_SIZE:
        fb.set_pixel(px + dx, py + CELL_SIZE - 1, COLOR_GRID)
      for dy in 0'u32 ..< CELL_SIZE:
        fb.set_pixel(px + CELL_SIZE - 1, py + dy, COLOR_GRID)

proc render_ui(fb: var Framebuffer, state: SimulationState, generation: uint64,
              step_interval: uint32) =
  let bar_y = DISPLAY_HEIGHT - UI_BAR_H
  let text_y = bar_y + (UI_BAR_H - FONT_H.uint32) div 2

  # Fill UI bar
  for y in bar_y ..< DISPLAY_HEIGHT:
    for x in 0'u32 ..< DISPLAY_WIDTH:
      fb.set_pixel(x, y, COLOR_UI_BG)

  # Draw buttons
  for btn in BUTTONS:
    var label = btn.label
    var color = btn.color
    if btn.label == "PLAY":
      if state == Running:
        label = "PAUSE"
      else:
        label = "PLAY"
        color = COLOR_UI_ACCENT

    let text_x = btn.x0 + ((btn.x1 - btn.x0) - label.len.uint32 * (FONT_W + 1).uint32) div 2
    draw_text(fb, text_x, text_y, label, color)

  # Generation counter + speed on right side
  draw_text(fb, 480, text_y, "GEN:" & $generation, COLOR_UI_TEXT)
  draw_text(fb, 680, text_y, "SPD:" & $step_interval, COLOR_UI_TEXT)

proc render(fb: var Framebuffer, sim: Simulation, state: SimulationState,
            step_interval: uint32) =
  renderGrid(fb, sim)
  renderUi(fb, state, sim.generation, step_interval)

# --- Touch handling ---

proc handleButton(x: int32, sim: var Simulation, state: var SimulationState,
                  step_interval: var uint32) =
  for i, btn in BUTTONS:
    if x.uint32 >= btn.x0 and x.uint32 < btn.x1:
      case i
      of 0:  # PLAY/PAUSE
        state = if state == Running: Paused else: Running
      of 1:  # STEP
        if state == Paused:
          sim.step()
      of 2:  # CLEAR
        sim.clear()
        state = Paused
      of 3:  # RANDOM
        sim.randomize()
      of 4:  # SPD-
        if step_interval < 30:
          step_interval += 1
      of 5:  # SPD+
        if step_interval > 1:
          step_interval -= 1
      break

proc handleTouch(event: TouchEvent, sim: var Simulation,
                 state: var SimulationState, step_interval: var uint32,
                 drawing: var bool, drawValue: var uint8) =
  case event.phase
  of Started:
    if event.y.uint32 >= GRID_AREA_H:
      handleButton(event.x, sim, state, step_interval)
    else:
      let gx = event.x div CELL_SIZE.int32
      let gy = event.y div CELL_SIZE.int32
      if gx >= 0 and gx < GRID_W.int32 and gy >= 0 and gy < GRID_H.int32:
        let alive = sim.get(gx.int, gy.int)
        drawValue = if alive != 0: 0'u8 else: 1'u8
        sim.set(gx.int, gy.int, drawValue)
        drawing = true
  of Moved:
    if drawing and event.y.uint32 < GRID_AREA_H:
      let gx = event.x div CELL_SIZE.int32
      let gy = event.y div CELL_SIZE.int32
      if gx >= 0 and gx < GRID_W.int32 and gy >= 0 and gy < GRID_H.int32:
        sim.set(gx.int, gy.int, drawValue)
  of Ended:
    drawing = false

# --- Main entry point ---

proc app_main() {.exportc.} =
  {.emit: "NimMain();".}

  const TAG: cstring = "GOL"
  logi(TAG, "Game of Life starting...")

  var display = newDisplay()
  var tc = newTouchController(DISPLAY_WIDTH, DISPLAY_HEIGHT)
  var fb = newFramebuffer()
  var sim = newSimulation(GRID_W, GRID_H)
  sim.randomize()

  var state = Running
  var step_interval = STEP_INTERVAL_DEFAULT
  var step_counter = 0'u32
  var frame_count = 0'u32
  var fps_timer = nowMs()
  var drawing = false
  var drawValue = 1'u8

  logi(TAG, "Entering main loop")

  while true:
    let frame_start = now_ms()

    # Handle touch input
    let touch_opt = tc.poll()
    if touch_opt.is_some:
      handle_touch(touch_opt.get(), sim, state, step_interval, drawing, draw_value)

    # Advance simulation
    if state == Running:
      step_counter += 1
      if step_counter >= step_interval:
        step_counter = 0
        sim.step()

    # Compute labels for coloring
    sim.compute_labels()

    # Render
    render(fb, sim, state, step_interval)

    # Flush to display
    display.flush(fb)

    # FPS logging
    frame_count += 1
    if frame_count >= 300:
      let elapsed = now_ms() - fps_timer
      if elapsed > 0:
        let fps = (frame_count.uint64 * 1000) div elapsed
        logi(TAG, "FPS: %llu", fps)
      frame_count = 0
      fps_timer = now_ms()

    # Frame timing
    let elapsed = now_ms() - frame_start
    if elapsed < FRAME_MS:
      v_task_delay(pd_ms_to_ticks(uint32(FRAME_MS - elapsed)))
