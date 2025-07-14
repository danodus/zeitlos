import sys
import serial
import time
import os

PACKET_DATA_MAX = 250

def send(ser, bytes):
    for b in bytes:
        ser.write(b.to_bytes(1, 'little'))
        time.sleep(0.0005)


def crc32b(a):
    crc = 0xffffffff
    for x in a:
        crc ^= x
        for k in range(8):
            mask = -(crc & 1)
            crc = (crc >> 1) ^ (0xedb88320 & mask)
    crc = ~crc
    crc &= 0xffffffff
    return crc


def send_packet(ser, cmd, data):
    packet = bytearray()
    packet.extend(ord(cmd).to_bytes(1, 'little'))
    packet.extend(len(data).to_bytes(1, 'little'))
    packet.extend(data)
    crc = crc32b(packet)
    packet.extend(crc.to_bytes(4, 'little'))
    send(ser, packet)


def cmd_load(ser, data):
    send_packet(ser, 'L', data)


def get_ack(ser):
    print("Waiting for ACK or NACK...")
    while True:
        c = ser.read(1)
        if c == b'A':
            print("ACK received")
            return True
        elif c == b'N':
            print("NACK received")
            return False


def main(argv):
    if (len(argv) < 2):
        print("Usage: sendbin.py <serial device> <bin file>")
        exit(0)
    else:
        try:
            ser = serial.Serial(argv[0], baudrate=1000000)
        except serial.serialutil.SerialException:
            print("Unable to open the serial device {0}".format(argv[0]))
            exit(1)
        
        file = open(argv[1], 'rb')
        file_size = os.path.getsize(argv[1])

        packet = 0
        total_bytes = 0
        while True:
            buf = file.read(PACKET_DATA_MAX)
            bytes_read = len(buf)
            if bytes_read != 0:
                while True:
                    cmd_load(ser, buf)
                    if get_ack(ser):
                        total_bytes = total_bytes + bytes_read
                        break
                    else:
                        print("failed")
                        send(ser, ord('D').to_bytes(1))
                        exit(1)
                print("Progress: {0} / {1} bytes".format(total_bytes, file_size))
            else:
                break

        send(ser, ord('D').to_bytes(1))
        
        ser.close()
    exit(0)


if __name__ == "__main__":
    main(sys.argv[1:])
