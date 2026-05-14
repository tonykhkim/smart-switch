# smart-switch

An IoT project that controls a light switch through a smartphone app using Bluetooth Low Energy (BLE).

# System Architecture

Smartphone App → BLE (MLT-BT05) → Arduino Nano → Servo Motor → Light Switch

# Components Used
- Arduino Nano (ATmega328P)
- BLE Module (MLT-BT05 / CC2541)
- SG90 Servo Motors × 2
- Smartphone App (Flutter)

# Folder Structure
- arduino/ : Arduino control code
- flutter/ : Flutter smartphone app
- web/ : HTML web app (for testing)
- docs/ : Circuit diagrams and documentation
