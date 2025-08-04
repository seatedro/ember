const std = @import("std");
const ember = @import("../ember.zig");
const sdl = ember.sdl;
const ctx = ember.Context;
const types = ember.types;

const log = std.log.scoped(.io);

pub const MouseButton = enum(u3) {
    left = sdl.c.SDL_BUTTON_LEFT,
    middle = sdl.c.SDL_BUTTON_MIDDLE,
    right = sdl.c.SDL_BUTTON_RIGHT,
    mb4 = sdl.c.SDL_BUTTON_X1,
    mb5 = sdl.c.SDL_BUTTON_X2,
};

pub const MouseButtonEvent = struct {
    pub const ButtonState = enum(u16) {
        up = sdl.c.SDL_EVENT_MOUSE_BUTTON_UP,
        down = sdl.c.SDL_EVENT_MOUSE_BUTTON_DOWN,
    };
    timestamp: u64,
    window_id: u32, // window if any
    mouse_instance_id: u32,
    button: MouseButton,
    clicks: u8,
    x: f32,
    y: f32,

    pub fn convert(e: sdl.c.SDL_MouseButtonEvent) MouseButtonEvent {
        return .{
            .timestamp = e.timestamp,
            .window_id = e.windowID,
            .mouse_instance_id = e.which,
            .button = @enumFromInt(e.button),
            .clicks = e.clicks,
            .x = e.x,
            .y = e.y,
        };
    }
};

pub const MouseButtonState = struct {
    const Self = @This();
    flags: u5, // least storage needed

    pub fn convert(b: sdl.c.SDL_MouseButtonFlags) Self {
        return .{
            .flags = @intCast(b),
        };
    }

    fn mask(b: MouseButton) u5 {
        return @intCast(
            @as(u32, 1) << (@intFromEnum(b) - 1),
        );
    }

    pub fn isPressed(self: MouseButtonState, b: MouseButton) bool {
        return (self.flags & mask(b) != 0);
    }
};

pub const MouseMotionEvent = struct {
    timestamp: u64,
    window_id: u32, // window if any
    mouse_instance_id: u32,
    state: MouseButtonState,
    x: f32,
    y: f32,
    delta_x: f32,
    delta_y: f32,

    pub fn convert(e: sdl.c.SDL_MouseMotionEvent) MouseMotionEvent {
        return .{
            .timestamp = e.timestamp,
            .window_id = e.windowID,
            .mouse_instance_id = e.which,
            .state = MouseButtonState.convert(e.state),
            .x = e.x,
            .y = e.y,
            .delta_x = e.xrel,
            .delta_y = e.yrel,
        };
    }
};

pub const MouseWheelEvent = struct {
    pub const WheelDirection = enum(u1) {
        normal = sdl.c.SDL_MOUSEWHEEL_NORMAL,
        flipped = sdl.c.SDL_MOUSEWHEEL_FLIPPED,
    };

    timestamp: u64,
    window_id: u32, // window if any
    mouse_instance_id: u32,
    delta_x: f32,
    delta_y: f32,
    direction: WheelDirection,

    pub fn convert(e: sdl.c.SDL_MouseWheelEvent) MouseWheelEvent {
        return .{
            .timestamp = e.timestamp,
            .window_id = e.windowID,
            .mouse_instance_id = e.which,
            .delta_x = e.x,
            .delta_y = e.y,
            .direction = @enumFromInt(@as(u1, @intCast(e.direction))),
        };
    }
};

// u16 because it's a bitflag
pub const ModifierKey = enum(u16) {
    none = sdl.c.SDL_KMOD_NONE,
    lshift = sdl.c.SDL_KMOD_LSHIFT,
    rshift = sdl.c.SDL_KMOD_RSHIFT,
    l5shift = sdl.c.SDL_KMOD_LEVEL5,
    lctrl = sdl.c.SDL_KMOD_LCTRL,
    rctrl = sdl.c.SDL_KMOD_RCTRL,
    lalt = sdl.c.SDL_KMOD_LALT,
    ralt = sdl.c.SDL_KMOD_RALT,
    lgui = sdl.c.SDL_KMOD_LGUI,
    rgui = sdl.c.SDL_KMOD_RGUI,
    numlock = sdl.c.SDL_KMOD_NUM,
    capslock = sdl.c.SDL_KMOD_CAPS,
    altgr = sdl.c.SDL_KMOD_MODE,
    scroll = sdl.c.SDL_KMOD_SCROLL,
    ctrl = (sdl.c.SDL_KMOD_LCTRL | sdl.c.SDL_KMOD_RCTRL),
    shift = (sdl.c.SDL_KMOD_LSHIFT | sdl.c.SDL_KMOD_RSHIFT),
    alt = (sdl.c.SDL_KMOD_LALT | sdl.c.SDL_KMOD_RALT),
    gui = (sdl.c.SDL_KMOD_LGUI | sdl.c.SDL_KMOD_RGUI),
};

pub const Modifiers = struct {
    const Self = @This();
    state: u16,

    pub fn convert(mod: sdl.c.SDL_Keymod) Self {
        return .{ .state = mod };
    }

    pub fn get(self: Self, mod: ModifierKey) bool {
        return (self.state & @intFromEnum(mod)) != 0;
    }

    pub fn set(self: *Self, mod: ModifierKey) void {
        self.state |= @intFromEnum(mod);
    }

    pub fn clear(self: *Self, mod: ModifierKey) void {
        self.state &= ~@intFromEnum(mod);
    }
};

pub const KeyboardEvent = struct {
    const Self = @This();

    const KeyState = enum(u16) {
        down = sdl.c.SDL_EVENT_KEY_DOWN,
        up = sdl.c.SDL_EVENT_KEY_UP,
    };

    timestamp: u64,
    window_id: u32, // window if any
    mouse_instance_id: u32,
    repeat: bool,
    state: KeyState,
    scancode: Scancode,
    keycode: Keycode,
    modifiers: Modifiers,

    pub fn convert(e: sdl.c.SDL_KeyboardEvent) Self {
        return .{
            .timestamp = e.timestamp,
            .mouse_instance_id = e.which,
            .window_id = e.windowID,
            .state = @enumFromInt(e.type),
            .repeat = e.repeat,
            .scancode = @enumFromInt(e.scancode),
            .keycode = @enumFromInt(e.key),
            .modifiers = Modifiers.convert(e.mod),
        };
    }
};

pub const Scancode = enum(sdl.c.SDL_Scancode) {
    unknown = sdl.c.SDL_SCANCODE_UNKNOWN,
    a = sdl.c.SDL_SCANCODE_A,
    b = sdl.c.SDL_SCANCODE_B,
    c = sdl.c.SDL_SCANCODE_C,
    d = sdl.c.SDL_SCANCODE_D,
    e = sdl.c.SDL_SCANCODE_E,
    f = sdl.c.SDL_SCANCODE_F,
    g = sdl.c.SDL_SCANCODE_G,
    h = sdl.c.SDL_SCANCODE_H,
    i = sdl.c.SDL_SCANCODE_I,
    j = sdl.c.SDL_SCANCODE_J,
    k = sdl.c.SDL_SCANCODE_K,
    l = sdl.c.SDL_SCANCODE_L,
    m = sdl.c.SDL_SCANCODE_M,
    n = sdl.c.SDL_SCANCODE_N,
    o = sdl.c.SDL_SCANCODE_O,
    p = sdl.c.SDL_SCANCODE_P,
    q = sdl.c.SDL_SCANCODE_Q,
    r = sdl.c.SDL_SCANCODE_R,
    s = sdl.c.SDL_SCANCODE_S,
    t = sdl.c.SDL_SCANCODE_T,
    u = sdl.c.SDL_SCANCODE_U,
    v = sdl.c.SDL_SCANCODE_V,
    w = sdl.c.SDL_SCANCODE_W,
    x = sdl.c.SDL_SCANCODE_X,
    y = sdl.c.SDL_SCANCODE_Y,
    z = sdl.c.SDL_SCANCODE_Z,
    @"1" = sdl.c.SDL_SCANCODE_1,
    @"2" = sdl.c.SDL_SCANCODE_2,
    @"3" = sdl.c.SDL_SCANCODE_3,
    @"4" = sdl.c.SDL_SCANCODE_4,
    @"5" = sdl.c.SDL_SCANCODE_5,
    @"6" = sdl.c.SDL_SCANCODE_6,
    @"7" = sdl.c.SDL_SCANCODE_7,
    @"8" = sdl.c.SDL_SCANCODE_8,
    @"9" = sdl.c.SDL_SCANCODE_9,
    @"0" = sdl.c.SDL_SCANCODE_0,
    @"return" = sdl.c.SDL_SCANCODE_RETURN,
    escape = sdl.c.SDL_SCANCODE_ESCAPE,
    backspace = sdl.c.SDL_SCANCODE_BACKSPACE,
    tab = sdl.c.SDL_SCANCODE_TAB,
    space = sdl.c.SDL_SCANCODE_SPACE,
    minus = sdl.c.SDL_SCANCODE_MINUS,
    equals = sdl.c.SDL_SCANCODE_EQUALS,
    left_bracket = sdl.c.SDL_SCANCODE_LEFTBRACKET,
    right_bracket = sdl.c.SDL_SCANCODE_RIGHTBRACKET,
    backslash = sdl.c.SDL_SCANCODE_BACKSLASH,
    non_us_hash = sdl.c.SDL_SCANCODE_NONUSHASH,
    semicolon = sdl.c.SDL_SCANCODE_SEMICOLON,
    apostrophe = sdl.c.SDL_SCANCODE_APOSTROPHE,
    grave = sdl.c.SDL_SCANCODE_GRAVE,
    comma = sdl.c.SDL_SCANCODE_COMMA,
    period = sdl.c.SDL_SCANCODE_PERIOD,
    slash = sdl.c.SDL_SCANCODE_SLASH,
    capslock = sdl.c.SDL_SCANCODE_CAPSLOCK,
    f1 = sdl.c.SDL_SCANCODE_F1,
    f2 = sdl.c.SDL_SCANCODE_F2,
    f3 = sdl.c.SDL_SCANCODE_F3,
    f4 = sdl.c.SDL_SCANCODE_F4,
    f5 = sdl.c.SDL_SCANCODE_F5,
    f6 = sdl.c.SDL_SCANCODE_F6,
    f7 = sdl.c.SDL_SCANCODE_F7,
    f8 = sdl.c.SDL_SCANCODE_F8,
    f9 = sdl.c.SDL_SCANCODE_F9,
    f10 = sdl.c.SDL_SCANCODE_F10,
    f11 = sdl.c.SDL_SCANCODE_F11,
    f12 = sdl.c.SDL_SCANCODE_F12,
    print_screen = sdl.c.SDL_SCANCODE_PRINTSCREEN,
    scrollock = sdl.c.SDL_SCANCODE_SCROLLLOCK,
    pause = sdl.c.SDL_SCANCODE_PAUSE,
    insert = sdl.c.SDL_SCANCODE_INSERT,
    home = sdl.c.SDL_SCANCODE_HOME,
    page_up = sdl.c.SDL_SCANCODE_PAGEUP,
    delete = sdl.c.SDL_SCANCODE_DELETE,
    end = sdl.c.SDL_SCANCODE_END,
    page_down = sdl.c.SDL_SCANCODE_PAGEDOWN,
    right = sdl.c.SDL_SCANCODE_RIGHT,
    left = sdl.c.SDL_SCANCODE_LEFT,
    down = sdl.c.SDL_SCANCODE_DOWN,
    up = sdl.c.SDL_SCANCODE_UP,
    numlock_clear = sdl.c.SDL_SCANCODE_NUMLOCKCLEAR,
    kp_divide = sdl.c.SDL_SCANCODE_KP_DIVIDE,
    kp_multiply = sdl.c.SDL_SCANCODE_KP_MULTIPLY,
    kp_minus = sdl.c.SDL_SCANCODE_KP_MINUS,
    kp_plus = sdl.c.SDL_SCANCODE_KP_PLUS,
    kp_enter = sdl.c.SDL_SCANCODE_KP_ENTER,
    kp_1 = sdl.c.SDL_SCANCODE_KP_1,
    kp_2 = sdl.c.SDL_SCANCODE_KP_2,
    kp_3 = sdl.c.SDL_SCANCODE_KP_3,
    kp_4 = sdl.c.SDL_SCANCODE_KP_4,
    kp_5 = sdl.c.SDL_SCANCODE_KP_5,
    kp_6 = sdl.c.SDL_SCANCODE_KP_6,
    kp_7 = sdl.c.SDL_SCANCODE_KP_7,
    kp_8 = sdl.c.SDL_SCANCODE_KP_8,
    kp_9 = sdl.c.SDL_SCANCODE_KP_9,
    kp_0 = sdl.c.SDL_SCANCODE_KP_0,
    kp_period = sdl.c.SDL_SCANCODE_KP_PERIOD,
    kp_equals = sdl.c.SDL_SCANCODE_KP_EQUALS,
    kp_comma = sdl.c.SDL_SCANCODE_KP_COMMA,
    kp_equals_as_400 = sdl.c.SDL_SCANCODE_KP_EQUALSAS400,
    kp_00 = sdl.c.SDL_SCANCODE_KP_00,
    kp_000 = sdl.c.SDL_SCANCODE_KP_000,
    kp_left_parenthesis = sdl.c.SDL_SCANCODE_KP_LEFTPAREN,
    kp_right_parenthesis = sdl.c.SDL_SCANCODE_KP_RIGHTPAREN,
    kp_left_brace = sdl.c.SDL_SCANCODE_KP_LEFTBRACE,
    kp_right_brace = sdl.c.SDL_SCANCODE_KP_RIGHTBRACE,
    kp_tab = sdl.c.SDL_SCANCODE_KP_TAB,
    kp_backspace = sdl.c.SDL_SCANCODE_KP_BACKSPACE,
    kp_a = sdl.c.SDL_SCANCODE_KP_A,
    kp_b = sdl.c.SDL_SCANCODE_KP_B,
    kp_c = sdl.c.SDL_SCANCODE_KP_C,
    kp_d = sdl.c.SDL_SCANCODE_KP_D,
    kp_e = sdl.c.SDL_SCANCODE_KP_E,
    kp_f = sdl.c.SDL_SCANCODE_KP_F,
    kp_xor = sdl.c.SDL_SCANCODE_KP_XOR,
    kp_power = sdl.c.SDL_SCANCODE_KP_POWER,
    kp_percent = sdl.c.SDL_SCANCODE_KP_PERCENT,
    kp_less = sdl.c.SDL_SCANCODE_KP_LESS,
    kp_greater = sdl.c.SDL_SCANCODE_KP_GREATER,
    kp_ampersand = sdl.c.SDL_SCANCODE_KP_AMPERSAND,
    kp_double_ampersand = sdl.c.SDL_SCANCODE_KP_DBLAMPERSAND,
    kp_vertical_bar = sdl.c.SDL_SCANCODE_KP_VERTICALBAR,
    kp_double_vertical_bar = sdl.c.SDL_SCANCODE_KP_DBLVERTICALBAR,
    kp_colon = sdl.c.SDL_SCANCODE_KP_COLON,
    kp_hash = sdl.c.SDL_SCANCODE_KP_HASH,
    kp_space = sdl.c.SDL_SCANCODE_KP_SPACE,
    kp_at_sign = sdl.c.SDL_SCANCODE_KP_AT,
    kp_exclamation_mark = sdl.c.SDL_SCANCODE_KP_EXCLAM,
    kp_memory_store = sdl.c.SDL_SCANCODE_KP_MEMSTORE,
    kp_memory_recall = sdl.c.SDL_SCANCODE_KP_MEMRECALL,
    kp_memory_clear = sdl.c.SDL_SCANCODE_KP_MEMCLEAR,
    kp_memory_add = sdl.c.SDL_SCANCODE_KP_MEMADD,
    kp_memory_subtract = sdl.c.SDL_SCANCODE_KP_MEMSUBTRACT,
    kp_memory_multiply = sdl.c.SDL_SCANCODE_KP_MEMMULTIPLY,
    kp_memory_divide = sdl.c.SDL_SCANCODE_KP_MEMDIVIDE,
    kp_plus_minus = sdl.c.SDL_SCANCODE_KP_PLUSMINUS,
    kp_clear = sdl.c.SDL_SCANCODE_KP_CLEAR,
    kp_clear_entry = sdl.c.SDL_SCANCODE_KP_CLEARENTRY,
    kp_binary = sdl.c.SDL_SCANCODE_KP_BINARY,
    kp_octal = sdl.c.SDL_SCANCODE_KP_OCTAL,
    kp_decimal = sdl.c.SDL_SCANCODE_KP_DECIMAL,
    kp_hexadecimal = sdl.c.SDL_SCANCODE_KP_HEXADECIMAL,
    non_us_backslash = sdl.c.SDL_SCANCODE_NONUSBACKSLASH,
    application = sdl.c.SDL_SCANCODE_APPLICATION,
    power = sdl.c.SDL_SCANCODE_POWER,
    f13 = sdl.c.SDL_SCANCODE_F13,
    f14 = sdl.c.SDL_SCANCODE_F14,
    f15 = sdl.c.SDL_SCANCODE_F15,
    f16 = sdl.c.SDL_SCANCODE_F16,
    f17 = sdl.c.SDL_SCANCODE_F17,
    f18 = sdl.c.SDL_SCANCODE_F18,
    f19 = sdl.c.SDL_SCANCODE_F19,
    f20 = sdl.c.SDL_SCANCODE_F20,
    f21 = sdl.c.SDL_SCANCODE_F21,
    f22 = sdl.c.SDL_SCANCODE_F22,
    f23 = sdl.c.SDL_SCANCODE_F23,
    f24 = sdl.c.SDL_SCANCODE_F24,
    execute = sdl.c.SDL_SCANCODE_EXECUTE,
    help = sdl.c.SDL_SCANCODE_HELP,
    menu = sdl.c.SDL_SCANCODE_MENU,
    select = sdl.c.SDL_SCANCODE_SELECT,
    stop = sdl.c.SDL_SCANCODE_STOP,
    again = sdl.c.SDL_SCANCODE_AGAIN,
    undo = sdl.c.SDL_SCANCODE_UNDO,
    cut = sdl.c.SDL_SCANCODE_CUT,
    copy = sdl.c.SDL_SCANCODE_COPY,
    paste = sdl.c.SDL_SCANCODE_PASTE,
    find = sdl.c.SDL_SCANCODE_FIND,
    volume_up = sdl.c.SDL_SCANCODE_VOLUMEUP,
    volume_down = sdl.c.SDL_SCANCODE_VOLUMEDOWN,
    international_1 = sdl.c.SDL_SCANCODE_INTERNATIONAL1,
    international_2 = sdl.c.SDL_SCANCODE_INTERNATIONAL2,
    international_3 = sdl.c.SDL_SCANCODE_INTERNATIONAL3,
    international_4 = sdl.c.SDL_SCANCODE_INTERNATIONAL4,
    international_5 = sdl.c.SDL_SCANCODE_INTERNATIONAL5,
    international_6 = sdl.c.SDL_SCANCODE_INTERNATIONAL6,
    international_7 = sdl.c.SDL_SCANCODE_INTERNATIONAL7,
    international_8 = sdl.c.SDL_SCANCODE_INTERNATIONAL8,
    international_9 = sdl.c.SDL_SCANCODE_INTERNATIONAL9,
    language_1 = sdl.c.SDL_SCANCODE_LANG1,
    language_2 = sdl.c.SDL_SCANCODE_LANG2,
    language_3 = sdl.c.SDL_SCANCODE_LANG3,
    language_4 = sdl.c.SDL_SCANCODE_LANG4,
    language_5 = sdl.c.SDL_SCANCODE_LANG5,
    language_6 = sdl.c.SDL_SCANCODE_LANG6,
    language_7 = sdl.c.SDL_SCANCODE_LANG7,
    language_8 = sdl.c.SDL_SCANCODE_LANG8,
    language_9 = sdl.c.SDL_SCANCODE_LANG9,
    alternate_erase = sdl.c.SDL_SCANCODE_ALTERASE,
    system_request = sdl.c.SDL_SCANCODE_SYSREQ,
    cancel = sdl.c.SDL_SCANCODE_CANCEL,
    clear = sdl.c.SDL_SCANCODE_CLEAR,
    prior = sdl.c.SDL_SCANCODE_PRIOR,
    return_2 = sdl.c.SDL_SCANCODE_RETURN2,
    separator = sdl.c.SDL_SCANCODE_SEPARATOR,
    out = sdl.c.SDL_SCANCODE_OUT,
    oper = sdl.c.SDL_SCANCODE_OPER,
    clear_again = sdl.c.SDL_SCANCODE_CLEARAGAIN,
    cursor_selection = sdl.c.SDL_SCANCODE_CRSEL,
    extend_selection = sdl.c.SDL_SCANCODE_EXSEL,
    thousands_separator = sdl.c.SDL_SCANCODE_THOUSANDSSEPARATOR,
    decimal_separator = sdl.c.SDL_SCANCODE_DECIMALSEPARATOR,
    currency_unit = sdl.c.SDL_SCANCODE_CURRENCYUNIT,
    currency_subunit = sdl.c.SDL_SCANCODE_CURRENCYSUBUNIT,
    left_ctrl = sdl.c.SDL_SCANCODE_LCTRL,
    left_shift = sdl.c.SDL_SCANCODE_LSHIFT,
    left_alt = sdl.c.SDL_SCANCODE_LALT,
    left_gui = sdl.c.SDL_SCANCODE_LGUI,
    right_ctrl = sdl.c.SDL_SCANCODE_RCTRL,
    right_shift = sdl.c.SDL_SCANCODE_RSHIFT,
    right_alt = sdl.c.SDL_SCANCODE_RALT,
    right_gui = sdl.c.SDL_SCANCODE_RGUI,
    mode = sdl.c.SDL_SCANCODE_MODE,
    media_next_track = sdl.c.SDL_SCANCODE_MEDIA_NEXT_TRACK,
    media_prev_track = sdl.c.SDL_SCANCODE_MEDIA_PREVIOUS_TRACK,
    media_stop = sdl.c.SDL_SCANCODE_MEDIA_STOP,
    media_play = sdl.c.SDL_SCANCODE_MEDIA_PLAY,
    media_eject = sdl.c.SDL_SCANCODE_MEDIA_EJECT,
    media_select = sdl.c.SDL_SCANCODE_MEDIA_SELECT,
    media_rewind = sdl.c.SDL_SCANCODE_MEDIA_REWIND,
    media_fast_forward = sdl.c.SDL_SCANCODE_MEDIA_FAST_FORWARD,
    mute = sdl.c.SDL_SCANCODE_MUTE,
    application_control_search = sdl.c.SDL_SCANCODE_AC_SEARCH,
    application_control_home = sdl.c.SDL_SCANCODE_AC_HOME,
    application_control_back = sdl.c.SDL_SCANCODE_AC_BACK,
    application_control_forward = sdl.c.SDL_SCANCODE_AC_FORWARD,
    application_control_stop = sdl.c.SDL_SCANCODE_AC_STOP,
    application_control_refresh = sdl.c.SDL_SCANCODE_AC_REFRESH,
    application_control_bookmarks = sdl.c.SDL_SCANCODE_AC_BOOKMARKS,
    sleep = sdl.c.SDL_SCANCODE_SLEEP,
    _,
};

pub const KeyboardState = struct {
    states: []const u8,

    pub fn isPressed(ks: KeyboardState, scancode: Scancode) bool {
        return ks.states[@intCast(@intFromEnum(scancode))] != 0;
    }
};

pub fn getKeyboardState() KeyboardState {
    var len: c_int = undefined;
    const slice = sdl.c.SDL_GetKeyboardState(&len);
    return KeyboardState{
        .states = slice[0..@intCast(len)],
    };
}

pub fn getKeyboardModifierState() Modifiers {
    return Modifiers.convert(@intCast(sdl.c.SDL_GetModState()));
}

pub const Keycode = enum(sdl.c.SDL_Keycode) {
    unknown = sdl.c.SDLK_UNKNOWN,
    a = sdl.c.SDLK_A,
    b = sdl.c.SDLK_B,
    c = sdl.c.SDLK_C,
    d = sdl.c.SDLK_D,
    e = sdl.c.SDLK_E,
    f = sdl.c.SDLK_F,
    g = sdl.c.SDLK_G,
    h = sdl.c.SDLK_H,
    i = sdl.c.SDLK_I,
    j = sdl.c.SDLK_J,
    k = sdl.c.SDLK_K,
    l = sdl.c.SDLK_L,
    m = sdl.c.SDLK_M,
    n = sdl.c.SDLK_N,
    o = sdl.c.SDLK_O,
    p = sdl.c.SDLK_P,
    q = sdl.c.SDLK_Q,
    r = sdl.c.SDLK_R,
    s = sdl.c.SDLK_S,
    t = sdl.c.SDLK_T,
    u = sdl.c.SDLK_U,
    v = sdl.c.SDLK_V,
    w = sdl.c.SDLK_W,
    x = sdl.c.SDLK_X,
    y = sdl.c.SDLK_Y,
    z = sdl.c.SDLK_Z,
    @"1" = sdl.c.SDLK_1,
    @"2" = sdl.c.SDLK_2,
    @"3" = sdl.c.SDLK_3,
    @"4" = sdl.c.SDLK_4,
    @"5" = sdl.c.SDLK_5,
    @"6" = sdl.c.SDLK_6,
    @"7" = sdl.c.SDLK_7,
    @"8" = sdl.c.SDLK_8,
    @"9" = sdl.c.SDLK_9,
    @"0" = sdl.c.SDLK_0,
    @"return" = sdl.c.SDLK_RETURN,
    escape = sdl.c.SDLK_ESCAPE,
    backspace = sdl.c.SDLK_BACKSPACE,
    tab = sdl.c.SDLK_TAB,
    space = sdl.c.SDLK_SPACE,
    minus = sdl.c.SDLK_MINUS,
    equals = sdl.c.SDLK_EQUALS,
    left_bracket = sdl.c.SDLK_LEFTBRACKET,
    right_bracket = sdl.c.SDLK_RIGHTBRACKET,
    backslash = sdl.c.SDLK_BACKSLASH,
    semicolon = sdl.c.SDLK_SEMICOLON,
    apostrophe = sdl.c.SDLK_APOSTROPHE,
    grave = sdl.c.SDLK_GRAVE,
    comma = sdl.c.SDLK_COMMA,
    period = sdl.c.SDLK_PERIOD,
    slash = sdl.c.SDLK_SLASH,
    capslock = sdl.c.SDLK_CAPSLOCK,
    f1 = sdl.c.SDLK_F1,
    f2 = sdl.c.SDLK_F2,
    f3 = sdl.c.SDLK_F3,
    f4 = sdl.c.SDLK_F4,
    f5 = sdl.c.SDLK_F5,
    f6 = sdl.c.SDLK_F6,
    f7 = sdl.c.SDLK_F7,
    f8 = sdl.c.SDLK_F8,
    f9 = sdl.c.SDLK_F9,
    f10 = sdl.c.SDLK_F10,
    f11 = sdl.c.SDLK_F11,
    f12 = sdl.c.SDLK_F12,
    print_screen = sdl.c.SDLK_PRINTSCREEN,
    scrollock = sdl.c.SDLK_SCROLLLOCK,
    pause = sdl.c.SDLK_PAUSE,
    insert = sdl.c.SDLK_INSERT,
    home = sdl.c.SDLK_HOME,
    page_up = sdl.c.SDLK_PAGEUP,
    delete = sdl.c.SDLK_DELETE,
    end = sdl.c.SDLK_END,
    page_down = sdl.c.SDLK_PAGEDOWN,
    right = sdl.c.SDLK_RIGHT,
    left = sdl.c.SDLK_LEFT,
    down = sdl.c.SDLK_DOWN,
    up = sdl.c.SDLK_UP,
    numlock_clear = sdl.c.SDLK_NUMLOCKCLEAR,
    kp_divide = sdl.c.SDLK_KP_DIVIDE,
    kp_multiply = sdl.c.SDLK_KP_MULTIPLY,
    kp_minus = sdl.c.SDLK_KP_MINUS,
    kp_plus = sdl.c.SDLK_KP_PLUS,
    kp_enter = sdl.c.SDLK_KP_ENTER,
    kp_1 = sdl.c.SDLK_KP_1,
    kp_2 = sdl.c.SDLK_KP_2,
    kp_3 = sdl.c.SDLK_KP_3,
    kp_4 = sdl.c.SDLK_KP_4,
    kp_5 = sdl.c.SDLK_KP_5,
    kp_6 = sdl.c.SDLK_KP_6,
    kp_7 = sdl.c.SDLK_KP_7,
    kp_8 = sdl.c.SDLK_KP_8,
    kp_9 = sdl.c.SDLK_KP_9,
    kp_0 = sdl.c.SDLK_KP_0,
    kp_period = sdl.c.SDLK_KP_PERIOD,
    kp_equals = sdl.c.SDLK_KP_EQUALS,
    kp_comma = sdl.c.SDLK_KP_COMMA,
    kp_equals_as_400 = sdl.c.SDLK_KP_EQUALSAS400,
    kp_00 = sdl.c.SDLK_KP_00,
    kp_000 = sdl.c.SDLK_KP_000,
    kp_left_parenthesis = sdl.c.SDLK_KP_LEFTPAREN,
    kp_right_parenthesis = sdl.c.SDLK_KP_RIGHTPAREN,
    kp_left_brace = sdl.c.SDLK_KP_LEFTBRACE,
    kp_right_brace = sdl.c.SDLK_KP_RIGHTBRACE,
    kp_tab = sdl.c.SDLK_KP_TAB,
    kp_backspace = sdl.c.SDLK_KP_BACKSPACE,
    kp_a = sdl.c.SDLK_KP_A,
    kp_b = sdl.c.SDLK_KP_B,
    kp_c = sdl.c.SDLK_KP_C,
    kp_d = sdl.c.SDLK_KP_D,
    kp_e = sdl.c.SDLK_KP_E,
    kp_f = sdl.c.SDLK_KP_F,
    kp_xor = sdl.c.SDLK_KP_XOR,
    kp_power = sdl.c.SDLK_KP_POWER,
    kp_percent = sdl.c.SDLK_KP_PERCENT,
    kp_less = sdl.c.SDLK_KP_LESS,
    kp_greater = sdl.c.SDLK_KP_GREATER,
    kp_ampersand = sdl.c.SDLK_KP_AMPERSAND,
    kp_double_ampersand = sdl.c.SDLK_KP_DBLAMPERSAND,
    kp_vertical_bar = sdl.c.SDLK_KP_VERTICALBAR,
    kp_double_vertical_bar = sdl.c.SDLK_KP_DBLVERTICALBAR,
    kp_colon = sdl.c.SDLK_KP_COLON,
    kp_hash = sdl.c.SDLK_KP_HASH,
    kp_space = sdl.c.SDLK_KP_SPACE,
    kp_at_sign = sdl.c.SDLK_KP_AT,
    kp_exclamation_mark = sdl.c.SDLK_KP_EXCLAM,
    kp_memory_store = sdl.c.SDLK_KP_MEMSTORE,
    kp_memory_recall = sdl.c.SDLK_KP_MEMRECALL,
    kp_memory_clear = sdl.c.SDLK_KP_MEMCLEAR,
    kp_memory_add = sdl.c.SDLK_KP_MEMADD,
    kp_memory_subtract = sdl.c.SDLK_KP_MEMSUBTRACT,
    kp_memory_multiply = sdl.c.SDLK_KP_MEMMULTIPLY,
    kp_memory_divide = sdl.c.SDLK_KP_MEMDIVIDE,
    kp_plus_minus = sdl.c.SDLK_KP_PLUSMINUS,
    kp_clear = sdl.c.SDLK_KP_CLEAR,
    kp_clear_entry = sdl.c.SDLK_KP_CLEARENTRY,
    kp_binary = sdl.c.SDLK_KP_BINARY,
    kp_octal = sdl.c.SDLK_KP_OCTAL,
    kp_decimal = sdl.c.SDLK_KP_DECIMAL,
    kp_hexadecimal = sdl.c.SDLK_KP_HEXADECIMAL,
    application = sdl.c.SDLK_APPLICATION,
    power = sdl.c.SDLK_POWER,
    f13 = sdl.c.SDLK_F13,
    f14 = sdl.c.SDLK_F14,
    f15 = sdl.c.SDLK_F15,
    f16 = sdl.c.SDLK_F16,
    f17 = sdl.c.SDLK_F17,
    f18 = sdl.c.SDLK_F18,
    f19 = sdl.c.SDLK_F19,
    f20 = sdl.c.SDLK_F20,
    f21 = sdl.c.SDLK_F21,
    f22 = sdl.c.SDLK_F22,
    f23 = sdl.c.SDLK_F23,
    f24 = sdl.c.SDLK_F24,
    execute = sdl.c.SDLK_EXECUTE,
    help = sdl.c.SDLK_HELP,
    menu = sdl.c.SDLK_MENU,
    select = sdl.c.SDLK_SELECT,
    stop = sdl.c.SDLK_STOP,
    again = sdl.c.SDLK_AGAIN,
    undo = sdl.c.SDLK_UNDO,
    cut = sdl.c.SDLK_CUT,
    copy = sdl.c.SDLK_COPY,
    paste = sdl.c.SDLK_PASTE,
    find = sdl.c.SDLK_FIND,
    volume_up = sdl.c.SDLK_VOLUMEUP,
    volume_down = sdl.c.SDLK_VOLUMEDOWN,
    alternate_erase = sdl.c.SDLK_ALTERASE,
    system_request = sdl.c.SDLK_SYSREQ,
    cancel = sdl.c.SDLK_CANCEL,
    clear = sdl.c.SDLK_CLEAR,
    prior = sdl.c.SDLK_PRIOR,
    return_2 = sdl.c.SDLK_RETURN2,
    separator = sdl.c.SDLK_SEPARATOR,
    out = sdl.c.SDLK_OUT,
    oper = sdl.c.SDLK_OPER,
    clear_again = sdl.c.SDLK_CLEARAGAIN,
    cursor_selection = sdl.c.SDLK_CRSEL,
    extend_selection = sdl.c.SDLK_EXSEL,
    thousands_separator = sdl.c.SDLK_THOUSANDSSEPARATOR,
    decimal_separator = sdl.c.SDLK_DECIMALSEPARATOR,
    currency_unit = sdl.c.SDLK_CURRENCYUNIT,
    currency_subunit = sdl.c.SDLK_CURRENCYSUBUNIT,
    left_ctrl = sdl.c.SDLK_LCTRL,
    left_shift = sdl.c.SDLK_LSHIFT,
    left_alt = sdl.c.SDLK_LALT,
    left_gui = sdl.c.SDLK_LGUI,
    right_ctrl = sdl.c.SDLK_RCTRL,
    right_shift = sdl.c.SDLK_RSHIFT,
    right_alt = sdl.c.SDLK_RALT,
    right_gui = sdl.c.SDLK_RGUI,
    mode = sdl.c.SDLK_MODE,
    media_next_track = sdl.c.SDLK_MEDIA_NEXT_TRACK,
    media_prev_track = sdl.c.SDLK_MEDIA_PREVIOUS_TRACK,
    media_stop = sdl.c.SDLK_MEDIA_STOP,
    media_play = sdl.c.SDLK_MEDIA_PLAY,
    media_eject = sdl.c.SDLK_MEDIA_EJECT,
    media_select = sdl.c.SDLK_MEDIA_SELECT,
    media_rewind = sdl.c.SDLK_MEDIA_REWIND,
    media_fast_forward = sdl.c.SDLK_MEDIA_FAST_FORWARD,
    mute = sdl.c.SDLK_MUTE,
    application_control_search = sdl.c.SDLK_AC_SEARCH,
    application_control_home = sdl.c.SDLK_AC_HOME,
    application_control_back = sdl.c.SDLK_AC_BACK,
    application_control_forward = sdl.c.SDLK_AC_FORWARD,
    application_control_stop = sdl.c.SDLK_AC_STOP,
    application_control_refresh = sdl.c.SDLK_AC_REFRESH,
    application_control_bookmarks = sdl.c.SDLK_AC_BOOKMARKS,
    sleep = sdl.c.SDLK_SLEEP,
    _,
};

pub const WindowEvent = struct {
    const Type = enum(u16) {
        none = sdl.c.SDL_EVENT_FIRST,
        shown = sdl.c.SDL_EVENT_WINDOW_SHOWN,
        hidden = sdl.c.SDL_EVENT_WINDOW_HIDDEN,
        exposed = sdl.c.SDL_EVENT_WINDOW_EXPOSED,
        moved = sdl.c.SDL_EVENT_WINDOW_MOVED,
        resized = sdl.c.SDL_EVENT_WINDOW_RESIZED,
        minimized = sdl.c.SDL_EVENT_WINDOW_MINIMIZED,
        maximized = sdl.c.SDL_EVENT_WINDOW_MAXIMIZED,
        restored = sdl.c.SDL_EVENT_WINDOW_RESTORED,
        enter = sdl.c.SDL_EVENT_WINDOW_MOUSE_ENTER,
        leave = sdl.c.SDL_EVENT_WINDOW_MOUSE_LEAVE,
        focused = sdl.c.SDL_EVENT_WINDOW_FOCUS_GAINED,
        unfocused = sdl.c.SDL_EVENT_WINDOW_FOCUS_LOST,
        close = sdl.c.SDL_EVENT_WINDOW_CLOSE_REQUESTED,
        _,
    };

    const Data = union(Type) {
        none: void,
        shown: void,
        hidden: void,
        exposed: void,
        moved: types.Point,
        resized: types.Size,
        minimized: void,
        maximized: void,
        restored: void,
        enter: void,
        leave: void,
        focused: void,
        unfocused: void,
        close: void,
    };

    timestamp: u64,
    window_id: u32,
    type: Data,

    fn convert(e: sdl.c.SDL_WindowEvent) WindowEvent {
        return WindowEvent{
            .timestamp = e.timestamp,
            .window_id = e.windowID,
            .type = switch (@as(Type, @enumFromInt(e.type))) {
                .shown => Data{ .shown = {} },
                .hidden => Data{ .hidden = {} },
                .exposed => Data{ .exposed = {} },
                .moved => Data{
                    .moved = types.Point{
                        .x = @floatFromInt(e.data1),
                        .y = @floatFromInt(e.data2),
                    },
                },
                .resized => Data{
                    .resized = types.Size{
                        .width = @intCast(e.data1),
                        .height = @intCast(e.data2),
                    },
                },
                .minimized => Data{ .minimized = {} },
                .maximized => Data{ .maximized = {} },
                .restored => Data{ .restored = {} },
                .enter => Data{ .enter = {} },
                .leave => Data{ .leave = {} },
                .focused => Data{ .focused = {} },
                .unfocused => Data{ .unfocused = {} },
                .close => Data{ .close = {} },
                else => Data{ .none = {} },
            },
        };
    }
};

pub const Event = union(enum) {
    pub const CommonEvent = sdl.c.SDL_CommonEvent;
    pub const QuitEvent = sdl.c.SDL_QuitEvent;
    window: WindowEvent,
    key_down: KeyboardEvent,
    key_up: KeyboardEvent,
    key_map_changed: CommonEvent,
    mouse_motion: MouseMotionEvent,
    mouse_button_down: MouseButtonEvent,
    mouse_button_up: MouseButtonEvent,
    mouse_wheel: MouseWheelEvent,
    quit: QuitEvent,
    clipboard_update: CommonEvent,

    pub fn from(e: sdl.c.SDL_Event) Event {
        return switch (e.type) {
            sdl.c.SDL_EVENT_QUIT => .{ .quit = e.quit },
            sdl.c.SDL_EVENT_KEY_DOWN => .{ .key_down = KeyboardEvent.convert(e.key) },
            sdl.c.SDL_EVENT_KEY_UP => .{ .key_up = KeyboardEvent.convert(e.key) },
            sdl.c.SDL_EVENT_MOUSE_MOTION => .{ .mouse_motion = MouseMotionEvent.convert(e.motion) },
            sdl.c.SDL_EVENT_MOUSE_BUTTON_DOWN => .{ .mouse_button_down = MouseButtonEvent.convert(e.button) },
            sdl.c.SDL_EVENT_MOUSE_BUTTON_UP => .{ .mouse_button_up = MouseButtonEvent.convert(e.button) },
            sdl.c.SDL_EVENT_MOUSE_WHEEL => .{ .mouse_wheel = MouseWheelEvent.convert(e.wheel) },
            sdl.c.SDL_EVENT_KEYMAP_CHANGED => .{ .key_map_changed = e.common },
            sdl.c.SDL_EVENT_CLIPBOARD_UPDATE => .{ .clipboard_update = e.common },
            else => {
                if (e.type >= sdl.c.SDL_EVENT_WINDOW_FIRST and
                    e.type <= sdl.c.SDL_EVENT_WINDOW_LAST)
                {
                    return .{ .window = WindowEvent.convert(e.window) };
                }

                log.err("I should add this event type: {any}", .{e.type});
                @panic("I should add this event type");
            },
        };
    }
};

pub fn pollEvent() ?Event {
    var e: sdl.c.SDL_Event = undefined;
    if (sdl.c.SDL_PollEvent(&e) != false)
        return Event.from(e);
    return null;
}

pub fn pollSdlEvent() ?sdl.c.SDL_Event {
    var e: sdl.c.SDL_Event = undefined;
    if (sdl.c.SDL_PollEvent(&e) == true)
        return e;
    return null;
}

// inline fn mapMousePosToCanvas(ctx: *Context, pos: types.Point) types.Point {
//     //TODO: backend implementation specific
// }
