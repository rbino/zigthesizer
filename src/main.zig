const std = @import("std");

const micro = @import("microzig");
const regs = micro.chip.registers;
const RndGen = std.rand.DefaultPrng;

pub fn main() anyerror!void {
    systemInit();

    const green_led = micro.Gpio(micro.Pin("PD12"), .{ .mode = .output, .initial_state = .high });
    const orange_led = micro.Gpio(micro.Pin("PD13"), .{ .mode = .output, .initial_state = .high });
    const red_led = micro.Gpio(micro.Pin("PD14"), .{ .mode = .output, .initial_state = .high });
    const blue_led = micro.Gpio(micro.Pin("PD15"), .{ .mode = .output, .initial_state = .high });

    const i2c = try micro.i2c.I2CController(1, .{}).init(.{ .target_speed = 100_000 });
    const dsp_reset = micro.Gpio(micro.Pin("PD4"), .{ .mode = .output, .initial_state = .low });
    dsp_reset.init();
    std.time.sleep(600);
    dsp_reset.setToHigh();
    std.time.sleep(600);

    try i2c.device(0x4a).writeRegister(0x00, 0x99); //These five command are the "magic" initialization
    try i2c.device(0x4a).writeRegister(0x47, 0x80);
    try i2c.device(0x4a).writeRegister(0x32, 0xbb);
    try i2c.device(0x4a).writeRegister(0x32, 0x3b);
    try i2c.device(0x4a).writeRegister(0x00, 0x00);

    try i2c.device(0x4a).writeRegister(0x05, 0x20); //AUTO=0, SPEED=01, 32K=0, VIDEO=0, RATIO=0, MCLK=0
    try i2c.device(0x4a).writeRegister(0x04, 0xaf); //Headphone always ON, Speaker always OFF
    try i2c.device(0x4a).writeRegister(0x06, 0x04); //I2S Mode
    try i2c.device(0x4a).writeRegister(0x02, 0x9e); // Power on
    try i2c.device(0x4a).writeRegister(0x20, 0xd0); // Power on
    try i2c.device(0x4a).writeRegister(0x21, 0xd0); // Power on

    spiInit();

    var i: u16 = 0;
    var rnd = RndGen.init(0);
    var inc: u16 = 400;
    var x: u32 = 0;
    while (true) {
        if (x < 10_000) {
            regs.SPI3.DR.modify(i);
            while (regs.SPI3.SR.read().TXE == 0) {}
            regs.SPI3.DR.modify(i);
            while (regs.SPI3.SR.read().TXE == 0) {}
        } else if (x == 10_000) {
            green_led.setToLow();
            orange_led.setToLow();
            red_led.setToLow();
            blue_led.setToLow();
        } else if (x < 20_000) {
            regs.SPI3.DR.modify(0);
            while (regs.SPI3.SR.read().TXE == 0) {}
            regs.SPI3.DR.modify(0);
            while (regs.SPI3.SR.read().TXE == 0) {}
        } else if (x == 20_000) {
            green_led.setToHigh();
            orange_led.setToHigh();
            red_led.setToHigh();
            blue_led.setToHigh();
            x = 0;
            inc = 400 + @as(u16, rnd.random().int(u8));
        }

        i = i +% inc;
        x += 1;
    }
}

pub fn sleep(nanoseconds: u64) void {
    var i: usize = 0;
    while (i < nanoseconds) {
        asm volatile ("nop");
        i += 1;
    }
}

fn systemInit() void {
    // This init does these things:
    // - Enables the FPU coprocessor
    // - Sets the external oscillator to achieve a clock frequency of 168MHz
    // - Sets the correct PLL prescalers for that clock frequency
    // - Enables the flash data and instruction cache and sets the correct latency for 168MHz

    // Enable FPU coprocessor
    // WARN: currently not supported in qemu, comment if testing it there
    regs.FPU_CPACR.CPACR.modify(.{ .CP = 0b11 });

    // Enable HSI
    regs.RCC.CR.modify(.{ .HSION = 1 });

    // Wait for HSI ready
    while (regs.RCC.CR.read().HSIRDY != 1) {}

    // Select HSI as clock source
    regs.RCC.CFGR.modify(.{ .SW0 = 0, .SW1 = 0 });

    // Enable external high-speed oscillator (HSE)
    regs.RCC.CR.modify(.{ .HSEON = 1 });

    // Wait for HSE ready
    while (regs.RCC.CR.read().HSERDY != 1) {}

    // Set prescalers for 168 MHz: HPRE = 0, PPRE1 = DIV_2, PPRE2 = DIV_4
    regs.RCC.CFGR.modify(.{ .HPRE = 0, .PPRE1 = 0b101, .PPRE2 = 0b100 });

    // Disable PLL before changing its configuration
    regs.RCC.CR.modify(.{ .PLLON = 0 });

    // Set PLL prescalers and HSE clock source
    regs.RCC.PLLCFGR.modify(.{
        .PLLSRC = 1,
        // PLLM = 8 = 0b001000
        .PLLM0 = 0,
        .PLLM1 = 0,
        .PLLM2 = 0,
        .PLLM3 = 1,
        .PLLM4 = 0,
        .PLLM5 = 0,
        // PLLN = 336 = 0b101010000
        .PLLN0 = 0,
        .PLLN1 = 0,
        .PLLN2 = 0,
        .PLLN3 = 0,
        .PLLN4 = 1,
        .PLLN5 = 0,
        .PLLN6 = 1,
        .PLLN7 = 0,
        .PLLN8 = 1,
        // PLLP = 2 = 0b10
        .PLLP0 = 0,
        .PLLP1 = 1,
        // PLLQ = 7 = 0b111
        .PLLQ0 = 1,
        .PLLQ1 = 1,
        .PLLQ2 = 1,
    });

    // Enable PLL
    regs.RCC.CR.modify(.{ .PLLON = 1 });

    // Wait for PLL ready
    while (regs.RCC.CR.read().PLLRDY != 1) {}

    // Enable flash data and instruction cache and set flash latency to 5 wait states
    regs.FLASH.ACR.modify(.{ .DCEN = 1, .ICEN = 1, .LATENCY = 5 });

    // Select PLL as clock source
    regs.RCC.CFGR.modify(.{ .SW1 = 1, .SW0 = 0 });

    // Wait for PLL selected as clock source
    var cfgr = regs.RCC.CFGR.read();
    while (cfgr.SWS1 != 1 and cfgr.SWS0 != 0) : (cfgr = regs.RCC.CFGR.read()) {}

    // Disable HSI
    regs.RCC.CR.modify(.{ .HSION = 0 });
}

fn spiInit() void {
    regs.RCC.APB1ENR.modify(.{ .SPI3EN = 1 });

    const lrck = micro.Gpio(micro.Pin("PA4"), .{
        .mode = .alternate_function,
        .alternate_function = .af6,
    });
    const mclk = micro.Gpio(micro.Pin("PC7"), .{
        .mode = .alternate_function,
        .alternate_function = .af6,
    });
    const sclk = micro.Gpio(micro.Pin("PC10"), .{
        .mode = .alternate_function,
        .alternate_function = .af6,
    });
    const sdin = micro.Gpio(micro.Pin("PC12"), .{
        .mode = .alternate_function,
        .alternate_function = .af6,
    });

    lrck.init();
    mclk.init();
    sclk.init();
    sdin.init();

    // TODO: explain calculations here
    regs.RCC.PLLI2SCFGR.modify(.{
        .PLLI2SNx = 271,
        .PLLI2SRx = 2,
    });
    // Enable PLLI2S
    regs.RCC.CR.modify(.{ .PLLI2SON = 1 });

    while (regs.RCC.CR.read().PLLI2SRDY == 0) {}

    regs.SPI3.I2SPR.modify(.{
        .MCKOE = 1,
        .I2SDIV = 6,
    });

    regs.SPI3.I2SCFGR.modify(.{
        .I2SMOD = 1, // I2S mode selected
        .I2SE = 1, // I2S enabled
        .I2SCFG = 0b10, // Master transmit
    });
}
