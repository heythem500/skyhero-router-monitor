# skyhero-router-monitor
Shell-based v2.0 network-traffic &amp; device monitor for AsusWRT-Merlin firmware — runs as a separate web dashboard; archived for educational and research use, illustrating design patterns and scripting techniques.

<div align="center">
📸skyhero main dashboard
![Screenshot](https://github.com/heythem500/skyhero-router-monitor/blob/main/screenshots/Screenshot2-skyhero-v2.0.jpg)
![Screenshot](https://github.com/heythem500/skyhero-router-monitor/blob/main/screenshots/Screenshot1-skyhero-v2.0.jpg)
</div>

  
## 📋 Prerequisites

### ✅ Basic Requirements
- ASUS router (any model supporting Merlin)
- ASUS Merlin firmware installed

### 🔧 Required Packages
Run these commands on your router before using the script:

```bash
opkg update
opkg install jq
opkg install lighttpd 
opkg install lighttpd-mod-cgi

if any of these lines failed then first install :
Entware
by running "amtm" on your sh and install is using the code "ep" it's merlin related script

# to Install the 2.0 script Run manually
# ym = usb name
chmod +x /tmp/mnt/ym/skyhero-v2/install.sh
/tmp/mnt/ym/skyhero-v2/install.sh


License
Distributed under the MIT License.

⚠️ if you want something reliable to run on your rotuer use version v2.1 , this one only for reseach

⭐ Show Your Support
Give a ⭐ if this project helped you!
