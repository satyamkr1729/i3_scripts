#!/usr/bin/env bash
#

export POLYBAR_HOME=$(dirname $0)
function print_help() {
  cat <<EOF
$0 opcode
Valid opcodes:
  menu: spawn rofi with list of paired devices and upon selection connects to them
  check: check if any device is connected and displays their name
EOF
}

# some icons for known device types
declare -A icons=(
  [toggle-on]=''
  [toggle-off]=''
  [bluetooth-off]=''
  [bluetooth-on]=''
  [headset]=''
  [computer]=''
  [phone]=''
  [speaker]='󰦢'
  [keyboard]=''
  [generic]=''
  [battery_lt_5]=''
  [battery_lt_25]=' '
  [battery_lt_50]=' '
  [battery_lt_90]=' '
  [battery_lt_100]=' '
)

if ! which bluetoothctl &>/dev/null; then
  echo "Error: bluetoothctl not found"
  exit 1
fi

if [[ $# -eq 0 ]]; then
  echo "ERROR: no operator provided"
  print_help
  exit 1
fi

turn_off_bluetooth="Turn off Bluetooth"
turn_on_bluetooth="Turn on Bluetooth"

function get_dev_icon() {
  label=$1
  case $label in 
    audio-headset) echo ${icons[headset]};
      ;;
    computer) echo ${icons[computer]};
      ;;
    phone) echo ${icons[phone]};
      ;;
    audio-card) echo ${icons[speaker]};
      ;;
    input-keyboard) echo ${icons[keyboard]};
      ;;
    *) echo ${icons[generic]};
  esac
}

function get_battery() {
  mac=$1
  dev_name=dev_${mac//:/_}

  battery=$(dbus-send --print-reply=literal --system --dest=org.bluez \
    /org/bluez/hci0/${dev_name} org.freedesktop.DBus.Properties.Get \
    string:"org.bluez.Battery1" string:"Percentage")

  if [[ $? -ne 0 ]]; then
    echo -1
  else
    battery=$(echo $battery | tr -d '[:alpha:]'  | xargs)
    if [[ $battery -le 5 ]]; then
      echo "<span>   ${icons[battery_lt_5]} $battery%</span>"
    elif [[ $battery -le 25 ]]; then
      echo "<span>  ${icons[battery_lt_25]} $battery%</span>"
    elif [[ $battery -le 50 ]]; then
      echo "<span>   ${icons[battery_lt_50]} $battery%</span>"
    elif [[ $battery -le 90 ]]; then
      echo "<span>  ${icons[battery_lt_90]} $battery%</span>" 
    else
      echo "<span>   ${icons[battery_lt_100]} $battery%</span>"
    fi
  fi
}

function get_list() {
  # check if bluetooth is on
  isOn=$(bluetoothctl show | grep -i powered | cut -d' ' -f2)

  c=0
  if [[ $isOn == "yes" ]]; then
    # get connected device list and paired device list 
    devices_list=$(bluetoothctl devices Paired | tr -s '[:space:]' | cut -d' ' -f2-)
    connected_list=$(bluetoothctl devices Connected | tr -s '[:space:]' | cut -d' ' -f2-)
    IFS=$'\n'
    # display all connected devices first
    for device in $(echo "$connected_list"); do
      mac=$(echo $device | cut -d' ' -f1)
      device_name=$(echo $device | cut -d' ' -f2-)
      device_type=$(bluetoothctl info $mac | grep -i icon | cut -d' ' -f2 | xargs)
      icon=$(get_dev_icon $device_type)

      battery=$(get_battery $mac)
      #echo '<span color="lightgreen">'${icon}" <b>${device_name}</b></span>"
      if [[ $battery != "-1" ]]; then
        echo  "${device_name} ${battery}\0icon\x1f<span color='#88cc22'>${icon}</span>"
      else
        echo  "${device_name}\0icon\x1f<span color='#88cc22'>${icon}</span>"
      fi
      c=$(( c + 1 ))
    done

    # diplay all paired but disconnected devices
    for device in $(echo "$devices_list"); do
      mac=$(echo $device | cut -d' ' -f1)
      device_name=$(echo $device | cut -d' ' -f2-)
      device_type=$(bluetoothctl info $mac | grep -i icon | cut -d' ' -f2 | xargs)
      icon=$(get_dev_icon $device_type)
      if ! echo "$connected_list" | grep $device_name &>/dev/null; then
        #echo "${icon} <b>${device_name}</b>"
        echo "${device_name}\0icon\x1f<span color='white'>${icon}</span>"
      fi
    done 
    echo ""
    echo "${turn_off_bluetooth}\0icon\x1f<span color='#88cc22'>${icons['toggle-on']} </span>"
  else
    echo "${turn_on_bluetooth}\0icon\x1f<span>${icons['toggle-off']} </span>"
  fi
  echo "__count__=$c" # this value is for conveying number of rows to mark as active
}

# uses notify-send program to send notification. Insure dunst notification daemon is running
function notify() {
  status=$1
  op=$2
  device=$3

  notify_cmd="notify-send -i ${POLYBAR_HOME}/scripts/icons/bluetooth.png"
  notify_cmd_on_error="${notify_cmd} -h string:bgcolor:#2d2c2c -h string:fgcolor:#f70707"
  notify_cmd_on_success="${notify_cmd} -h string:bgcolor:#2d2c2c"
  
  case $op in
    poweroff|poweron) 
      if [[ $status -eq 0 ]]; then
        ${notify_cmd_on_success} "$op Success" "Bluetooth is now $op"
      else
        ${notify_cmd_on_error} "$op Failed" "Bluetooth failed to $op"
      fi
      ;;
    connect|disconnect)
      if [[ $status -eq 0 ]]; then
        ${notify_cmd_on_success} "${op^} Success" "$device ${op^}ed successfully"
      else
        ${notify_cmd_on_error} "${op^} Failed" "$device failed to ${op^}"
      fi
      ;;
  esac
}


# generates menu with list of all devices and turn on/off option
function menu() {
  data=$(get_list) 
  active_c=$(echo "$data" | grep '__count__' | cut -d'=' -f2)
  list=$(echo "$data" | grep -v '__count__')

  if [[ $active_c -ne 0 ]]; then
    active_flag="-a :$active_c"
  fi
  selected=$(echo -ne "$list" | rofi -dmenu -theme ${POLYBAR_HOME}/../rofi/bluetooth.rasi -p "   Bluetooth  " -markup-rows ${active_flag} -i)
  selected=$(echo $selected | sed 's#<span>.*</span>##g' | xargs)

  #selected=$(bluetoothctl devices Paired | tr -s '[:space:]' | cut -d' ' -f3- | rofi -dmenu)

  if [[ -n "$selected" ]]; then
    if [[ $selected == $turn_off_bluetooth ]]; then
      bluetoothctl power off
      notify $? poweroff
    elif [[ $selected == $turn_on_bluetooth ]]; then
      bluetoothctl power on
      notify $? poweron
    else
      mac=$(bluetoothctl devices | grep "$selected" | awk '{print $2}')
      if bluetoothctl devices Connected | grep "$mac" &>/dev/null; then
        bluetoothctl disconnect $mac
        notify $? disconnect "$selected"
      else
        bluetoothctl connect $mac
        notify $? connect "$selected"
      fi
    fi
  fi
}

# checks connected device and shows its name
function check() {
  isOn=$(bluetoothctl show | grep -i powered | cut -d' ' -f2)

  if [[ $isOn == "yes" ]]; then
    connections=$(bluetoothctl devices Connected | tr -s '[:space:]')
    if [[ -n $connections ]]; then
      output=$(echo "$connections" | head -1 | cut -d' ' -f3-)
      char_count=$(echo $output | wc -c)
      if [[ $char_count -gt 16 ]]; then
        output=${output:0:16}...
      fi
      echo "%{u#42A5F5}%{+u}%{F#42A5F5}${icons[bluetooth-on]} %{F-}${output}%{-u}%{u-}"
    else
      echo "%{u#6D8895}%{+u}${icons[bluetooth-on]} %{F#42A5F5}${icons[toggle-on]}%{F-}%{-u}%{u-}"
    fi
  else
    echo "%{u#FFFFFF}%{+u}${icons[bluetooth-off]} ${icons[toggle-off]}%{-u}%{u-}"
  fi
}

function disconnect() {
  selected=$(bluetoothctl devices Connected | tr -s '[:space:]' | cut -d' ' -f3- | rofi -dmenu)
  if [[ -n "$selected" ]]; then
    mac=$(bluetoothctl devices | grep "$selected" | awk '{print $2}')
    bluetoothctl disconnect $mac
  fi
}

case $1 in
  menu) menu; ;;
  check) check; ;;
  disconnect) disconnect; ;;
  *) print_help
esac
