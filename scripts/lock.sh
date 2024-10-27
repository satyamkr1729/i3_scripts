#!/usr/bin/bash 
# handles single screen mode
# handles two screen mode both in extended and mirror form 

export ROOT=$(dirname $0)
list=("geralt.png" "heimdall.png" "iron_man.png" "rick.png" "spider_man.png")

size=${#list[@]}
index=$(date '+%s' | rev)
index=${index:0:1}
index=$(( $index % $size ))

figure=${list[$index]}
final_lck_screen=$(mktemp /tmp/final_lck_screen_XXXXXX.png)

playAlarm=$1

function single_screen_lock() {
  file=$(mktemp /tmp/ss_XXXXXX.png)
  blur_lck_screen_img=$(mktemp /tmp/blur_lockscreen_XXXXXXX.png)
  if [[ $playAlarm == '-alarm' ]]; then
    import -window root $file
  else
    import -silent -window root $file
  fi

  convert $file -blur 0x5 $blur_lck_screen_img
  convert -composite $blur_lck_screen_img ${ROOT}/../images/${figure} -gravity South -geometry -20x1200 $final_lck_screen
}

function multi_screen_lock() {
  # logic:
  # 1. take individual SS, blur them and add images to each seperately
  # 2. merge the two images based on screen orientation
  
  screen_edp_file=$(mktemp /tmp/ss_edp_XXXXXX.png)
  screen_external_file=$(mktemp /tmp/ss_external_XXXXXX.png)

  screen_edp_blur_file=$(mktemp /tmp/blur_edp_lockscreen_XXXXXX.png)
  screen_external_blur_file=$(mktemp /tmp/blur_external_lockscreen_XXXXXX.png)

  screen_edp_fig_file=$(mktemp /tmp/fig_edp_lockscreen_XXXXXX.png)
  screen_external_fig_file=$(mktemp /tmp/fig_external_lockscreen_XXXXXX.png)

  screen_edp_res=$(xrandr --listactivemonitors | grep -i edp | awk '{print $3}' | sed 's/\/[0-9]*//g')
  screen_external_res=$(xrandr --listactivemonitors | grep -iv 'edp' | grep -iE 'hdmi|dp' | awk '{print $3}' | sed 's/\/[0-9]*//g')

  if [[ $playAlarm == '-alarm' ]]; then
    import -window root -crop $screen_edp_res $screen_edp_file  
  else
    import -silent -window root  -crop $screen_edp_res $screen_edp_file
  fi

  import -silent -window root -crop $screen_external_res $screen_external_file

  convert $screen_edp_file -blur 0x5 $screen_edp_blur_file
  convert $screen_external_file -blur 0x5 $screen_external_blur_file

  convert -composite $screen_edp_blur_file ${ROOT}/../images/${figure} -gravity South -geometry -20x1200 $screen_edp_fig_file
  convert -composite $screen_external_blur_file ${ROOT}/../images/${figure} -gravity South -geometry -20x1200 $screen_external_fig_file

  x_offset_edp=$(echo $screen_edp_res | cut -d'+' -f2)
  x_offset_external=$(echo $screen_external_res | cut -d'+' -f2)

  if [[ ${x_offset_edp} -eq 0 ]] && [[ ${x_offset_external} -eq 0 ]]; then
    orient=vertical
  else
    orient=horizontal
  fi
    
  if echo $screen_edp_res | grep '+0+0' &>/dev/null; then
    if [[ $orient == 'horizontal' ]]; then
      convert +append $screen_edp_fig_file $screen_external_fig_file $final_lck_screen
    else
      convert -append $screen_edp_fig_file $screen_external_fig_file $final_lck_screen
    fi
  else
    if [[ $orient == 'horizontal' ]]; then
      convert +append $screen_external_fig_file $screen_edp_fig_file $final_lck_screen
    else
      convert -append $screen_external_fig_file $screen_edp_fig_file $final_lck_screen
    fi
  fi
}

activeMon_count=$(xrandr --listactivemonitors | wc -l)

# check if additional screen connected
if [[ ${activeMon_count} -eq 2 ]]; then
  single_screen_lock
else
  # check if the screen is connected in mirror mode (xrandr --same-as)
  count=$(xrandr --listactivemonitors | grep '+0+0' | wc -l)
  if [[ ${count} -eq 2 ]]; then
    single_screen_lock # for screen mirror mode
  else
    multi_screen_lock # for screen extend mode
  fi
fi

i3lock -i $final_lck_screen --nofork

