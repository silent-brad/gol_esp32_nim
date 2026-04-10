import nesper/gpios

const
  DISPLAY_WIDTH* = 800'u32
  DISPLAY_HEIGHT* = 480'u32
  PIXEL_COUNT = (DISPLAY_WIDTH * DISPLAY_HEIGHT).int  # 384000
  FRAMEBUFFER_BYTES = PIXEL_COUNT * 2  # 768000

type
  Framebuffer* = object
    buffer*: ptr UncheckedArray[uint16]

proc new_framebuffer*(): Framebuffer =
  let buf = cast[ptr UncheckedArray[uint16]](alloc0(PIXEL_COUNT * sizeof(uint16)))
  result = Framebuffer(buffer: buf)

proc clear*(fb: var Framebuffer, color: uint16) =
  for i in 0 ..< PIXEL_COUNT:
    fb.buffer[i] = color

proc set_pixel*(fb: var Framebuffer, x, y: uint32, color: uint16) {.inline.} =
  if x < DISPLAY_WIDTH and y < DISPLAY_HEIGHT:
    fb.buffer[y.int * DISPLAY_WIDTH.int + x.int] = color

proc as_bytes*(fb: Framebuffer): pointer =
  cast[pointer](fb.buffer)

# --- ESP LCD C API bindings (not covered by Nesper) ---

type
  EspLcdPanelHandle = pointer

proc lcd_init_rgb_panel(out_panel: ptr pointer, out_fb: ptr pointer) {.
  importc, header: "lcd.h".}

proc esp_lcd_panel_del(panel: EspLcdPanelHandle): cint {.
  importc: "esp_lcd_panel_del", header: "esp_lcd_panel_ops.h".}

type
  Display* = object
    panel_handle: EspLcdPanelHandle
    fb_ptr: pointer

proc new_display*(): Display =
  # Setup backlight on GPIO2
  set_level(GPIO_NUM_2, 0'u32)
  configure({GPIO_NUM_2}, mode = GPIO_MODE_OUTPUT)
  set_level(GPIO_NUM_2, 1'u32)

  var panel_handle: pointer
  var fb_ptr: pointer
  lcd_init_rgb_panel(addr panel_handle, addr fb_ptr)

  result = Display(panel_handle: panel_handle, fb_ptr: fb_ptr)

proc flush*(display: var Display, fb: Framebuffer) =
  if display.fb_ptr != nil:
    copy_mem(display.fb_ptr, fb.as_bytes(), FRAMEBUFFER_BYTES)

proc destroy*(display: var Display) =
  if display.panel_handle != nil:
    discard esp_lcd_panel_del(display.panel_handle)
    display.panel_handle = nil
