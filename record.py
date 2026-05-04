import serial
import wave
import numpy as np
from serial.tools import list_ports
from datetime import datetime
import argparse
import signal

# =========================
# CONFIG
# =========================
VID = 0x0403   # <-- CHANGE THIS
PID = 0x6010   # <-- CHANGE THIS

BAUD = 2000000
TIMEOUT = 0.5

SAMPLE_RATE = 44100
OUTPUT_LENGTH = 16
EXPONENT_LENGTH = 4

# =========================
# FIND SERIAL PORT
# =========================
def find_serial_by_vid_pid(vid, pid):
    for port in list_ports.comports():
        if port.vid == vid and port.pid == pid:
            return port.device
    return None

if __name__=="__main__":
    port = find_serial_by_vid_pid(VID, PID)

    if port is None:
        print("Available ports:")
        for p in list_ports.comports():
            print(p.device, p.vid, p.pid, p.description)
        raise RuntimeError("Device not found")

    print(f"Using port: {port}")

    # =========================
    # DECOMPRESSION
    # =========================
    def decompress_float(value, output_length=16, exponent_length=4):
        mantissa_length = output_length - exponent_length - 1

        sign = (value >> (output_length - 1)) & 0x1
        exponent = (value >> mantissa_length) & ((1 << exponent_length) - 1)
        mantissa = value & ((1 << mantissa_length) - 1)

        if exponent == 0:
            result = mantissa
        else:
            result = ((1 << mantissa_length) | mantissa) << (exponent - 1)

        if sign:
            result = -result

        return result
    
    # =========================
    # ARGUMENT PARSING
    # =========================
    parser = argparse.ArgumentParser(description="Serial audio recorder")
    parser.add_argument(
        "-t", "--time",
        type=int,
        default=10,
        help="Recording duration in seconds (default: 10, max: 3600)"
    )

    args = parser.parse_args()
    record_seconds = args.time
    if(record_seconds>3600):
        print("Max record time is 3600 seconds")
        exit(1)

    # =========================
    # SERIAL SETUP
    # =========================
    ser = serial.Serial(port, BAUD, timeout=TIMEOUT)
    tmp=ser.read(1024)
    if(tmp!=b''):
        tmp=ser.read(1024)
        if(tmp!=b''):
            print("Board already recording, exiting...")
            exit(1)

    # Send start command
    minutes = record_seconds//60
    seconds = record_seconds%60
    ser.write(bytearray([0x69, minutes, seconds, 0x42]))
    
    def handler(signum, frame):
        print('Ctrl+Z pressed, stopping...')
        ser.write(bytearray([0x69, 0, 0, 0x42]))
        

    signal.signal(signal.SIGTSTP, handler)

    print(f"Recording {record_seconds} seconds (press ctrl+Z to stop)...")

    # =========================
    # READ UNTIL TIMEOUT
    # =========================
    audio = []
    buffer = bytearray()

    while True:
        chunk = ser.read(1024)

        if len(chunk) == 0:
            print("Stream ended (timeout)")
            break

        buffer.extend(chunk)

        # Process full stereo frames (4 bytes)
        while len(buffer) >= 4:
            frame = buffer[:4]
            buffer = buffer[4:]

            # Try 'big' first — change to 'little' if needed
            left_raw  = int.from_bytes(frame[0:2], byteorder='little', signed=False)
            right_raw = int.from_bytes(frame[2:4], byteorder='little', signed=False)

            left  = decompress_float(left_raw, OUTPUT_LENGTH, EXPONENT_LENGTH)
            right = decompress_float(right_raw, OUTPUT_LENGTH, EXPONENT_LENGTH)

            # Clip to int32
            left  = max(min(left, (2**23)-1), -2**23)
            right = max(min(right, (2**23)-1), -2**23)

            audio.append([left, right])

    ser.close()

    print(f"Captured {len(audio)} samples")

    # =========================
    # SAVE WAV
    # =========================
    audio_np = np.array(audio, dtype=np.int32)
    audio_np*=256

    timestamp = datetime.now().strftime("%d-%m-%y_%H-%M-%S")
    filename = f"recorded_{timestamp}.wav"

    with wave.open(filename, "w") as f:
        f.setnchannels(2)
        f.setsampwidth(4)
        f.setframerate(SAMPLE_RATE)
        f.writeframes(audio_np.tobytes())

    print("Saved recorded.wav")
