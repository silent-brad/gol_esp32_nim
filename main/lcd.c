#include "lcd.h"
#include "esp_lcd_panel_rgb.h"
#include "esp_lcd_panel_ops.h"

void lcd_init_rgb_panel(void **out_panel_handle, void **out_fb)
{
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

    esp_lcd_panel_handle_t panel = NULL;
    esp_lcd_new_rgb_panel(&panel_config, &panel);
    esp_lcd_panel_reset(panel);
    esp_lcd_panel_init(panel);

    void *fb = NULL;
    esp_lcd_rgb_panel_get_frame_buffer(panel, 1, &fb);

    *out_panel_handle = panel;
    *out_fb = fb;
}
