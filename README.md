# 📡 Wireless Security Assessment Tools

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)
[![Platform](https://img.shields.io/badge/Platform-Linux-green.svg)](https://www.linux.org/)
[![Shell](https://img.shields.io/badge/Shell-Bash-yellow.svg)](https://www.gnu.org/software/bash/)

> **⚠️ FOR EDUCATIONAL AND AUTHORIZED TESTING ONLY**
> 
> These tools are designed for learning wireless security concepts and conducting authorized penetration testing. Unauthorized access to wireless networks is illegal.

## 📋 Table of Contents

- [Overview](#overview)
- [⚠️ Legal Disclaimer](#️-legal-disclaimer)
- [Features](#features)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Usage](#usage)
- [Educational Objectives](#educational-objectives)
- [Responsible Use Guidelines](#responsible-use-guidelines)
- [Contributing](#contributing)
- [License](#license)
- [Contact](#contact)

## Overview

A collection of educational bash scripts that automate functions of the aircrack-ng suite for authorized wireless network security assessments. These tools help security professionals and students understand wireless vulnerabilities and practice ethical hacking techniques.

## ⚠️ Legal Disclaimer

**🚨 CRITICAL: READ BEFORE USE**

- ✅ **Legal Use Only**: Use only on networks you own or have explicit written authorization to test
- ❌ **Illegal Use**: Unauthorized wireless network access is a criminal offense in most jurisdictions
- 📚 **Educational Purpose**: Designed for learning and authorized security research
- 🔒 **Responsible Disclosure**: Report vulnerabilities through proper channels
- ⚖️ **User Responsibility**: You assume full legal responsibility for use of these tools

By using these tools, you agree to comply with all applicable laws and use them only for authorized, ethical purposes.

## Features

### Script 1: Network Attack Automation
- 🎯 Automated BSSID discovery and channel detection
- 📡 WPA handshake capture via deauthentication
- 🔓 Dictionary-based PSK cracking
- 💾 Credential saving and handshake management
- 🛡️ Built-in error handling and cleanup

### Script 2: Access Point Setup & Testing
- 🏗️ Automated access point configuration
- 🌐 DHCP and DNS service setup
- 🔄 NAT and routing configuration
- 📊 Client connection monitoring
- 🧪 Evil twin attack simulation

## Prerequisites

### System Requirements
- **OS**: Linux (Debian/Ubuntu preferred)
- **Privileges**: Root access required
- **Hardware**: Wireless adapter with monitor mode support

### Dependencies
```bash
# Install required packages
sudo apt update
sudo apt install -y aircrack-ng hostapd dnsmasq iptables-persistent iw
```

### Hardware Compatibility
- Wireless adapters supporting monitor mode
- Multiple wireless interfaces (recommended for Script 2)

## Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/yourusername/wireless-security-tools.git
   cd wireless-security-tools
   ```

2. **Make scripts executable**
   ```bash
   chmod +x *.sh
   ```

3. **Verify dependencies**
   ```bash
   ./check-dependencies.sh
   ```

## Usage

### Basic Usage

```bash
# Run main attack script
sudo ./wireless-attack.sh

# Show saved handshakes
sudo ./wireless-attack.sh handshakes

# Use saved handshake
sudo ./wireless-attack.sh <handshake-filename>

# Access point setup
sudo ./ap-setup.sh
```

### Command Line Options

```bash
# Show help
sudo ./wireless-attack.sh --help

# List available interfaces
iwconfig
```

### Directory Structure
```
~/wifi_attack/
├── wordlists/              # Password dictionaries
├── captured_handshake/     # Temporary capture files
│   └── saved_handshake/    # Persistent handshake storage
└── saved_credentials/      # Cracked passwords
```

## Educational Objectives

- 🎓 **Learn Wireless Security**: Understand WPA/WPA2 vulnerabilities
- 🔍 **Penetration Testing**: Practice authorized network assessment
- 🛡️ **Defensive Security**: Improve your own network security
- 📖 **Security Research**: Contribute to wireless security knowledge

## Responsible Use Guidelines

### ✅ Authorized Use
- Your own networks
- Client networks with written permission
- Dedicated lab environments
- Educational institutions with proper oversight

### ❌ Unauthorized Use
- Public Wi-Fi networks
- Neighbor's networks
- Corporate networks without permission
- Any network you don't own or lack explicit authorization

### 🎯 Best Practices
1. **Get Written Permission**: Always obtain explicit authorization
2. **Document Everything**: Keep records of authorized testing
3. **Report Responsibly**: Use proper disclosure channels
4. **Respect Privacy**: Don't access or modify data
5. **Follow Laws**: Understand local cybersecurity regulations

## Contributing

We welcome contributions that improve educational value and security:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/improvement`)
3. Commit changes (`git commit -am 'Add educational feature'`)
4. Push to branch (`git push origin feature/improvement`)
5. Create a Pull Request

### Contribution Guidelines
- Maintain educational focus
- Include proper documentation
- Add safety checks and error handling
- Follow responsible disclosure principles

## License

This project is licensed under the **GNU Affero General Public License v3.0** - see the [LICENSE](LICENSE) file for details.

### License Summary
- ✅ Use for educational and authorized testing
- ✅ Modify and distribute with attribution
- ✅ Commercial use with AGPL compliance
- ❌ Remove copyright notices
- ❌ Use for unauthorized network access

**⚖️ Remember: With great power comes great responsibility. Use these tools ethically and legally.**

[![Made with ❤️ for Education](https://img.shields.io/badge/Made%20with-❤️%20for%20Education-red.svg)](https://github.com/yourusername/wireless-security-tools)
