# TriggerBox MATLAB interface for Linux

> **Disclaimer**: This project is an independent, community-developed effort and is **not affiliated with, endorsed by, or supported by Brain Products GmbH** in any way. The TriggerBox hardware and its official drivers are supported by Brain Products **exclusively on Windows**. Use of this library on Linux is entirely at your own risk. For official support, please refer to the [Brain Products website](https://www.brainproducts.com).

A MATLAB class to interface with the **Brain Products TriggerBox** on Linux using the FTDI D2XX library (`libftd2xx`). Supports both sending and reading triggers via GPIO bitbang mode.

---

## Requirements

- Ubuntu 24.04 (or compatible Linux distribution)
- MATLAB (R2019b or later recommended)
- FTDI D2XX driver (`libftd2xx`) — see installation below
- `gcc` / `g++` (required by MATLAB's `loadlibrary`)

---

## Installation

### 1. Install gcc (required by MATLAB)

```bash
sudo apt install gcc g++ make
```

### 2. Install the FTDI D2XX driver

Download the driver from the [FTDI website](https://ftdi.com/drivers) and follow their instructions. The following files should be present after installation:

```
/usr/local/lib/libftd2xx.so
/usr/local/lib/libftd2xx.so.1.4.34
/usr/local/include/ftd2xx.h
```

### 3. Prevent the kernel from claiming the device

The Linux kernel automatically loads the `ftdi_sio` driver when the TriggerBox is connected, which blocks `libftd2xx` from accessing the device. You need to unload it before use:

```bash
sudo rmmod ftdi_sio
sudo rmmod usbserial
```

To make this permanent, create a udev rule:

```bash
sudo nano /etc/udev/rules.d/99-triggerbox.rules
```

Add the following content:

```
SUBSYSTEM=="usb", ATTRS{idVendor}=="1103", ATTRS{idProduct}=="0021", MODE="0666", GROUP="dialout"
ACTION=="add", ATTRS{idVendor}=="1103", ATTRS{idProduct}=="0021", RUN+="/bin/sh -c 'rmmod ftdi_sio; rmmod usbserial'"
```

Reload udev rules:

```bash
sudo udevadm control --reload-rules && sudo udevadm trigger
```

### 4. Add your user to the `dialout` group

```bash
sudo usermod -a -G dialout $USER
```

Log out and back in for the change to take effect.

---

## Background: Why not use the serial port (VCP)?

The TriggerBox is based on an **FTDI FT2232H** chip with two interfaces:
- **Interface A** (`TriggerBox A`) — GPIO output, used to send triggers
- **Interface B** (`TriggerBox B`) — GPIO input, used to read incoming signals

The device operates in **asynchronous bitbang mode**, meaning data is written/read directly to/from GPIO pins — not as a serial UART stream. This is why using MATLAB's `serialport` always results in trigger value `1` regardless of what is sent: the UART start bit is always `1`.

The correct approach is to use `libftd2xx` directly with `FT_SetBitMode` and `FT_GetBitMode`.

---

## Usage

Place `TriggerBox.m` in your MATLAB path, then:

```matlab
% Initialize (once at the start of the experiment)
tb = TriggerBox();

% Send a trigger (auto-reset to 0 after 10ms)
tb.send(5);

% Send a trigger with custom duration (50ms)
tb.pulse(10, 0.05);

% Set a value without auto-reset
tb.set(3);
pause(0.1);
tb.reset();

% Read current state of input pins
value = tb.read();

% Wait for an input trigger (timeout: 5 seconds)
value = tb.readWait(5);
fprintf('Received trigger: %d\n', value);

% Read only if data is available (non-blocking)
value = tb.readAvailable();

% Close at the end of the experiment
delete(tb);
```

### Recommended pattern for experiments

```matlab
tb = TriggerBox();
try
    % Your experiment code here
    tb.send(1);           % start marker
    value = tb.readWait(10);  % wait for response (max 10s)
    tb.send(2);           % end marker
catch e
    warning('Error: %s', e.message);
end
delete(tb);  % always called, even after errors
```

---

## API Reference

| Method | Description |
|--------|-------------|
| `TriggerBox()` | Constructor — loads library, opens device, sets bitbang mode |
| `send(value)` | Sends trigger `value` (0–255), auto-resets to 0 after 10ms |
| `pulse(value, duration)` | Sends trigger `value` for `duration` seconds (default: 0.01s) |
| `set(value)` | Sets output pins to `value` without auto-reset |
| `reset()` | Resets output pins to 0 |
| `read()` | Returns current state of input pins (via `FT_GetBitMode`) |
| `readWait(timeout)` | Polls input until a non-zero value is received or timeout (seconds) |
| `readAvailable()` | Non-blocking read — returns -1 if no data available |
| `delete()` | Closes device and unloads library |

---

## Troubleshooting

**`FT_Open` returns status 3 (device not opened)**
→ The kernel `ftdi_sio` driver is loaded and blocking access. Run:
```bash
sudo rmmod ftdi_sio && sudo rmmod usbserial
```

**`FT_CreateDeviceInfoList` returns 0 devices**
→ `libftd2xx` does not recognize the Brain Products vendor ID by default. The constructor calls `FT_SetVIDPID(0x1103, 0x0021)` automatically to fix this. If the issue persists, ensure `ftdi_sio` is unloaded.

**`loadlibrary` fails with "Supported compiler not detected"**
→ Install gcc:
```bash
sudo apt install gcc g++ make
```

**Triggers always read as value 1**
→ You are likely using `serialport` instead of this library. The TriggerBox uses GPIO bitbang mode, not UART. Use this class instead.

---

## Device Identification

The TriggerBox is identified as:

| Property | Value |
|----------|-------|
| Vendor ID | `0x1103` (Brain Products) |
| Product ID | `0x0021` |
| Chip | FTDI FT2232H |
| Interface A | Output (send triggers) |
| Interface B | Input (read triggers) |

---

## License

MIT