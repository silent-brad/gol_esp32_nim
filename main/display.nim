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

# --- ESP LCD C API bindings ---

type
  EspLcdPanelHandle = pointer

proc esp_lcd_panel_del(panel: EspLcdPanelHandle): cint {.
  importc: "esp_lcd_panel_del", header: "esp_lcd_panel_ops.h".}

proc gpio_set_direction(gpio_num: cint, mode: cint): cint {.
  importc: "gpio_set_direction", header: "driver/gpio.h".}

proc gpio_set_level(gpio_num: cint, level: uint32): cint {.
  importc: "gpio_set_level", header: "driver/gpio.h".}

const GPIO_MODE_OUTPUT = 2

type
  Display* = object
    panel_handle: EspLcdPanelHandle
    fb_ptr: pointer  # raw pointer to PSRAM framebuffer managed by LCD driver

proc new_display*(): Display =
  var panel_handle: EspLcdPanelHandle
  var fb_ptr: pointer

  # Setup backlight on GPIO2
  discard gpio_set_direction(2, GPIO_MODE_OUTPUT)
  discard gpio_set_level(2, 1)

  # Use emit to create and configure the RGB panel through C code
  # This is the cleanest way to handle the complex nested struct with anonymous unions/bitfields
  {.emit: """
    #include "esp_lcd_panel_rgb.h"
    #include "esp_lcd_panel_ops.h"

    esp_lcd_rgb_panel_config_t panel_config = {
        .clk_src = LCD_CLK_SRC_DEFAULT,
        .timings = {
            .pclk_hz = 16000000,
            .h_res = 800,
            .v_res = 480,
            .hsync_pulse_width = 1,
            .hsync_back_porch = 40,
            .hsync_front_porch = 40,
            .vsync_pulse_width = 1,
            .vsync_back_porch = 8,
            .vsync_front_porch = 4,
            .flags = {
                .pclk_active_neg = 1,
            },
        },
        .data_width = 16,
        .bits_per_pixel = 16,
        .num_fbs = 1,
        .bounce_buffer_size_px = 8000,
        .hsync_gpio_num = 39,
        .vsync_gpio_num = 41,
        .de_gpio_num = 40,
        .pclk_gpio_num = 0,
        .disp_gpio_num = -1,
        .data_gpio_nums = {8, 3, 46, 9, 1, 5, 6, 7, 15, 16, 4, 45, 48, 47, 21, 14},
        .flags = {
            .fb_in_psram = 1,
            .bb_invalidate_cache = 1,
        },
        .psram_trans_align = 64,
        .sram_trans_align = 4,
    };

    esp_lcd_panel_handle_t _panel_handle = NULL;
    esp_lcd_new_rgb_panel(&panel_config, &_panel_handle);
    esp_lcd_panel_reset(_panel_handle);
    esp_lcd_panel_init(_panel_handle);

    void *_fb_ptr = NULL;
    esp_lcd_rgb_panel_get_frame_buffer(_panel_handle, 1, &_fb_ptr);

    `panelHandle` = (void*)_panel_handle;
    `fbPtr` = _fb_ptr;
  """.}

  result = Display(panel_handle: panel_handle, fb_ptr: fb_ptr)

proc flush*(display: var Display, fb: Framebuffer) =
  if display.fb_ptr != nil:
    copy_mem(display.fb_ptr, fb.as_bytes(), FRAMEBUFFER_BYTES)

proc destroy*(display: var Display) =
  if display.panel_handle != nil:
    discard esp_lcd_panel_del(display.panel_handle)
    display.panel_handle = nil
