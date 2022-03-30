#!/bin/bash

# This is a simple script for pomodoro timer.
# This is intended to be used with xfce4-genmon-plugin.

size=32                      # Icon size in pixels
pomodoro_time=45             # Time for the pomodoro cycle (in minutes)
short_break_time=10          # Time for the short break cycle (in minutes)
long_break_time=55           # Time for the long break cycle (in minutes)
cycles_between_long_breaks=3 # How many cycles should we do before long break
notify_time=10               # Time for notification to hang (in seconds)
custom_cmd="${HOME}/.pomodororc" # Default custom command handler

DIR="$( cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# default configuration values
notify_time=$(( notify_time * 1000 ))
summary="Pomodoro"
endmsg_shortbreak="Pomodoro ended, time to take short break"
endmsg_longbreak="Pomodoro ended, time to take long break"
killmsg="Pomodoro stopped, restart when you are ready"
pausedmsg="Timer paused"
unpausemsg="Timer unpaused"

function xnotify () {
  notify-send -t "${notify_time}" -i "${DIR}/icons/running.png" "$summary" "$1"
}

function run_custom_cmd() {
  if [[ -x "${custom_cmd}" ]]; then
    "${custom_cmd}" --command "$1" &>>/tmp/pomodororc.log
  fi
}

function custom_cmd_start() {
  local _mode="$1"
  run_custom_cmd "${_mode}_start"
}

function custom_cmd_end() {
  local _mode="$1"
  run_custom_cmd "${_mode}_end"
}

function terminate_pomodoro () {
  xnotify "${killmsg}"
  echo "" > "${savedtime}"
  echo "idle" > "${savedmode}"
  echo "" > "${savedcyclecount}"
}

function pause_timer () {
  current_time=$( date +%s )
  echo $current_time > "${savedpausetime}"
  mode=$( cat "${savedmode}" 2> /dev/null )
  echo "paused_${mode}" > "${savedmode}"
  xnotify "$pausedmsg"
}

function resume_timer () {
  current_time=$( date +%s )
  local pause_time=$( cat "${savedpausetime}" 2> /dev/null )
  local start_time=$( cat "${savedtime}" 2> /dev/null )
  echo $(( start_time + (current_time - pause_time) )) > "${savedtime}"
  mode=$( cat "${savedmode}" | cut -d _ -f 2 2> /dev/null )
  echo "${mode}" > "${savedmode}"
  xnotify "${unpausemsg}"
}

function render_status () {
  mode=$1
  remaining_time=$2
  saved_cycle_count=$3

  display_mode="Work"
  display_icon="running"
  if [ $mode == "shortbreak" ] ; then
    display_mode="Short break"
    display_icon="stopped"
  elif [ $mode == "longbreak" ] ; then
    display_mode="Long break"
    display_icon="stopped"
  fi

  # when pomodoro is off or break is active stop icon is displayed,
  # but user can intuitively and immidiatelly notice the difference,
  # because if it is break remaining time is displayed.
  local remaining_time_display=$(printf " %02d:%02d " $(( remaining_time / 60 )) $(( remaining_time % 60 )))
  echo "<txt> ${remaining_time_display} </txt>"
  echo "<img>${DIR}/icons/${display_icon}${size}.png</img>"
  echo "<tool>${display_mode}: You have ${remaining_time_display} min left [#${saved_cycle_count}]</tool>"
  gen_pomodoro_click_str
}


# parameter based configuration
sound="on"
storage="${DIR}"

function parse_args() {
  while [[ $# -gt 0 ]]; do
    local key="$1"

    case "${key}" in
      -n|--click)
        click="yes"
        ;;
      -t|--storage)
        storage="$2"
        shift # past value
        ;;
      -s|--sound)
        sound="$2"
        shift # past value
        ;;
      --pomodoro_time)
        pomodoro_time="$2"
        shift # past value
        ;;
      --short_break_time)
        short_break_time="$2"
        shift # past value
        ;;
      --long_break_time)
        long_break_time="$2"
        shift # past value
        ;;
      --cycles_between_long_breaks)
        cycles_between_long_breaks="$2"
        shift # past value
        ;;
      --custom_cmd)
        custom_cmd="$2"
        shift
        ;;
      *)    # unknown option
        # ignore unknown argument
        shift # past argument
        ;;
    esac
    shift # past argument
  done


  mkdir -p "${storage}"
  savedtime="${storage}/savedtime"
  savedmode="${storage}/savedmode"
  savedcyclecount="${storage}/savedcyclecount"
  lock="${storage}/lock"
  savedpausetime="${storage}/savedpausetime"
  startmsg="Pomodoro started, you have ${pomodoro_time} minutes left"

  pomodoro_cycle=$(( pomodoro_time * 60 ))
  short_break_cycle=$(( short_break_time * 60 ))
  long_break_cycle=$(( long_break_time * 60 ))
}

function gen_pomodoro_click_str() {
  cat<<EOF
<click>${DIR}/pomodoro.sh -n --storage "${storage}" --pomodoro_time "${pomodoro_time}" --custom_cmd "${custom_cmd}" --cycles_between_long_breaks "${cycles_between_long_breaks}"  --long_break_time "${long_break_time}" --short_break_time "${short_break_time}" --sound "${sound}"</click>
EOF
  cat<<EOF
<txtclick>${DIR}/pomodoro.sh -n --storage "${storage}" --pomodoro_time "${pomodoro_time}" --custom_cmd "${custom_cmd}" --cycles_between_long_breaks "${cycles_between_long_breaks}"  --long_break_time "${long_break_time}" --short_break_time "${short_break_time}" --sound "${sound}"</txtclick>
EOF
}

parse_args "$@"

( flock -x 200

  mode=$( cat "${savedmode}" 2> /dev/null )
  if [ -z "${mode}" ] ; then
    mode="idle"
  fi

  current_time=$( date +%s )
  if [ "${click}" == "yes" ] ; then
    if [ "${mode}" == "idle" ] ; then
      custom_cmd_end "${mode}"
      new_mode="pomodoro"
      xnotify "${startmsg}"
      echo "${current_time}" > "${savedtime}"
      echo "${new_mode}" > "${savedmode}"
      echo "0" > "${savedcyclecount}"
      custom_cmd_start "${new_mode}"
    elif [[ "${mode}" =~ ^paused_.* ]] ; then
      resume_timer
      run_custom_cmd resume
    else
      out=$(zenity --question --title="Pomodoro" \
        --text "Please select timer option." \
        --extra-button="Pause" --cancel-label="Do nothing" --ok-label="Stop")
      result=$?
      if [[ "${out}" == "Pause" ]] ; then
        run_custom_cmd pause
        pause_timer
      elif [[ "${result}" == 0 ]] ; then
        terminate_pomodoro
        run_custom_cmd pomodoro_end
      fi
    fi
  else
    # periodic check, and redrawing
    if [ "${mode}" == "idle" ] ; then
      echo "<img>${DIR}/icons/stopped${size}.png</img>"
      echo "<txt> Idle </txt>"
      echo "<tool>No Pomodoro Running</tool>"
      gen_pomodoro_click_str
    elif [[ "${mode}" =~ ^paused_.* ]] ; then
      echo "<img>${DIR}/icons/stopped${size}.png</img>"
      echo "<tool>Timer paused</tool>"
      echo "<txt> Paused </txt>"
      gen_pomodoro_click_str
    else
      # timer running

      cycle_start_time=$( cat "${savedtime}" 2> /dev/null )
      saved_cycle_count=$( cat "${savedcyclecount}" 2> /dev/null )

      if [ -z "${cycle_start_time}" ] ; then
        cycle_start_time=0
      fi

      if [ -z "${saved_cycle_count}" ] ; then
        saved_cycle_count=0
      fi

      cycle_time=0
      if [ "${mode}" == "pomodoro" ] ; then
        cycle_time=${pomodoro_cycle}
      elif [ "${mode}" == "shortbreak" ] ; then
        cycle_time=${short_break_cycle}
      elif [ "${mode}" == "longbreak" ]; then
        cycle_time=${long_break_cycle}
      fi

      remaining_time=$(( cycle_time + cycle_start_time - current_time))

      msg="${startmsg}"
      if [ ${remaining_time} -le 0 ] ; then
        # If remaining_time is is below zero for more that short break cycle,
        # that makes pomodoro invalid.
        # This, for example, can occurr when computer was turned off.
        # In such case terminate pomodoro and exit.
        invalid_pomodoro_time_margin=$((-short_break_cycle))
        if [ ${remaining_time} -lt ${invalid_pomodoro_time_margin} ] ; then
          terminate_pomodoro
          custom_cmd_end "pomodoro"
          exit 1
        fi

        if [ ${mode} == "pomodoro" ] ; then
          cycle_count=$((saved_cycle_count + 1))
          cycle_mod=$((cycle_count % cycles_between_long_breaks))
          new_remaining_time=${short_break_cycle}
          new_mode="shortbreak"
          msg="${endmsg_shortbreak}"
          if [ ${cycle_mod} -eq 0 ] ; then
            new_mode="longbreak"
            msg="${endmsg_longbreak}"
            new_remaining_time=${long_break_cycle}
          fi

          echo "${cycle_count}" > "${savedcyclecount}"
          render_status ${new_mode} ${new_remaining_time} ${cycle_count}
        else
          new_mode="pomodoro"
          msg="${startmsg}"
          render_status "pomodoro" ${pomodoro_cycle} ${saved_cycle_count}
        fi

        echo "${new_mode}" > "${savedmode}"

        if [ "${sound}" == "on" ] ; then
          aplay "${DIR}/cow.wav"
        fi

        custom_cmd_end "${mode}"
        xnotify "${msg}"
        zenity --info --text="${msg}"
        custom_cmd_start "${new_mode}"
        echo "${current_time}" > "${savedtime}"
      else
        render_status ${mode} ${remaining_time} ${saved_cycle_count}
      fi
    fi
  fi

) 200> "${lock}"
