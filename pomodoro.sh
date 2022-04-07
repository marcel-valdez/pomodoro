#!/usr/bin/env bash

# This is a simple script for pomodoro timer.
# This is intended to be used with xfce4-genmon-plugin.

ICON_SIZE=32                 # Icon size in pixels
POMODORO_TIME=45             # Time for the pomodoro cycle (in minutes)
SHORT_BREAK_TIME=10          # Time for the short break cycle (in minutes)
LONG_BREAK_TIME=55           # Time for the long break cycle (in minutes)
CYCLES_BETWEEN_LONG_BREAKS=3 # How many cycles should we do before long break
NOTIFY_TIME=10               # Time for notification to hang (in seconds)
CUSTOM_CMD="${HOME}/.pomodororc" # Default custom command handler

DIR="$( cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# default configuration values
NOTIFY_TIME=$(( NOTIFY_TIME * 1000 ))
SUMMARY="Pomodoro"
END_MSG_SHORTBREAK="Pomodoro ended, time to take short break"
END_MSG_LONGBREAK="Pomodoro ended, time to take long break"
KILL_MSG="Pomodoro stopped, restart when you are ready"
PAUSED_MSG="Timer paused"
UNPAUSE_MSG="Timer unpaused"


# parameter based configuration
SOUND="on"
STORAGE="${DIR}"

function parse_args() {
  while [[ $# -gt 0 ]]; do
    local key="$1"

    case "${key}" in
      -n|--click)
        CLICKED="yes"
        ;;
      -t|--storage)
        STORAGE="$2"
        shift # past value
        ;;
      -s|--sound)
        SOUND="$2"
        shift # past value
        ;;
      --pomodoro_time)
        POMODORO_TIME="$2"
        shift # past value
        ;;
      --short_break_time)
        SHORT_BREAK_TIME="$2"
        shift # past value
        ;;
      --long_break_time)
        LONG_BREAK_TIME="$2"
        shift # past value
        ;;
      --cycles_between_long_breaks)
        CYCLES_BETWEEN_LONG_BREAKS="$2"
        shift # past value
        ;;
      --custom_cmd)
        CUSTOM_CMD="$2"
        shift
        ;;
      *)    # unknown option
        # ignore unknown argument
        shift # past argument
        ;;
    esac
    shift # past argument
  done


  mkdir -p "${STORAGE}"
  SAVED_TIME_FILE="${STORAGE}/saved_time"
  SAVED_MODE_FILE="${STORAGE}/saved_mode"
  SAVED_CYCLE_COUNT_FILE="${STORAGE}/saved_cycle_count"
  LOCK="${STORAGE}/lock"
  SAVED_PAUSE_TIME_FILE="${STORAGE}/saved_pause_time"
  START_POMODORO_MSG="Pomodoro started, you have ${POMODORO_TIME} minutes left"

  POMODORO_CYCLE=$(( POMODORO_TIME * 60 ))
  SHORT_BREAK_CYCLE=$(( SHORT_BREAK_TIME * 60 ))
  LONG_BREAK_CYCLE=$(( LONG_BREAK_TIME * 60 ))
}

function debug() {
  if [[ "${DEBUG}" ]]; then
    echo "$(date "+%H:%M:%S") $@" >>/tmp/${USER}.pomodoro.log
  fi
}

function xnotify () {
  notify-send -t "${NOTIFY_TIME}" -i "${DIR}/icons/running.png" "$SUMMARY" "$1"
}

function run_custom_cmd() {
  if [[ -x "${CUSTOM_CMD}" ]]; then
    "${CUSTOM_CMD}" --command "$1" "${mode}" &>>/tmp/${USER}.pomodoro.log
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
  xnotify "${KILL_MSG}"
  echo "" > "${SAVED_TIME_FILE}"
  echo "idle" > "${SAVED_MODE_FILE}"
  echo "" > "${SAVED_CYCLE_COUNT_FILE}"
}

function pause_timer () {
  local _current_time=$( date +%s )
  echo ${_current_time} > "${SAVED_PAUSE_TIME_FILE}"
  mode=$( cat "${SAVED_MODE_FILE}" 2> /dev/null )
  echo "paused_${mode}" > "${SAVED_MODE_FILE}"
  xnotify "${PAUSED_MSG}"
}

function resume_timer () {
  local _current_time=$( date +%s )
  local _pause_time=$( cat "${SAVED_PAUSE_TIME_FILE}" 2> /dev/null )
  local _start_time=$( cat "${SAVED_TIME_FILE}" 2> /dev/null )
  echo $(( _start_time + (_current_time - _pause_time) )) > "${SAVED_TIME_FILE}"
  mode=$( cat "${SAVED_MODE_FILE}" | cut -d _ -f 2 2> /dev/null )
  echo "${mode}" > "${SAVED_MODE_FILE}"
  xnotify "${UNPAUSE_MSG}"
}

function gen_click_tag_by_type() {
  local click_type="$1"
    cat<<EOF
<${click_type}>${DIR}/pomodoro.sh -n --storage "${STORAGE}" --POMODORO_TIME "${POMODORO_TIME}" --CUSTOM_CMD "${CUSTOM_CMD}" --CYCLES_BETWEEN_LONG_BREAKS "${CYCLES_BETWEEN_LONG_BREAKS}"  --LONG_BREAK_TIME "${LONG_BREAK_TIME}" --SHORT_BREAK_TIME "${SHORT_BREAK_TIME}" --sound "${SOUND}"</${click_type}>
EOF
}

function gen_click_tag() {
  gen_click_tag_by_type "click"
  gen_click_tag_by_type "txtclick"
}

function render_status () {
  local _mode="$1"
  local _remaining_time="$2"
  local _saved_cycle_count="$3"

  local _display_mode="Work"
  local _display_icon="running"
  if [ "${_mode}" == "shortbreak" ] ; then
    _display_mode="Short break"
    _display_icon="stopped"
  elif [ "${_mode}" == "longbreak" ] ; then
    _display_mode="Long break"
    _display_icon="stopped"
  fi

  # when pomodoro is off or break is active stop icon is displayed,
  # but user can intuitively and immidiatelly notice the difference,
  # because if it is break remaining time is displayed.
  local _remaining_time_display=$(printf " %02d:%02d " $(( _remaining_time / 60 )) $(( _remaining_time % 60 )))
  echo "<txt><span font='8'>▋▋</span> ${_remaining_time_display} </txt>"
  echo "<img>${DIR}/icons/${_display_icon}${ICON_SIZE}.png</img>"
  echo "<tool>${_display_mode}: You have ${_remaining_time_display} min left [#${_saved_cycle_count}]</tool>"
  gen_click_tag
}

function display_info_dialog_yad() {
  local msg="<span size='13pt' allow_breaks='true'>\n${1}</span>"
  local timeout="$2"
  if [[ "${timeout}" ]]; then
    timeout=$((timeout*60))
  else
    timeout=30
  fi
  local args=(
    --form
    --text="${msg}"
    --width=200
    --title="Pomodoro"
    --window-icon "${DIR}/icons/running${ICON_SIZE}.png"
    --image="${DIR}/icons/running${ICON_SIZE}.png"
    --button="OK!!:1"
    --undecorated
    --align=center
    --buttons-layout=center
    --borders=10
    --timeout="${timeout}"
    --timeout-indicator=top
    --skip-taskbar
    --close-on-unfocus
    --sticky
    --on-top
    --center
  )

  yad "${args[@]}"
}

function display_info_dialog_zenity() {
  local msg="$1"
  local timeout="$2"
  if [[ "${timeout}" ]]; then
    timeout=$((timeout*60))
  else
    timeout=30
  fi
  zenity --info --text="${msg}" --timeout "$((timeout*60))"
}

function display_info_dialog() {
  local msg="$1"
  local timeout="$2"

  # TODO: Should we pause the timer while the dialog is shown?
  if type yad &>/dev/null; then
    display_info_dialog_yad "${msg}" "${timeout}"
  elif type zenity &>/dev/null; then
    display_info_dialog_zenity "${msg}" "${timeout}"
  else
    xnotify "Pomodoro" "${msg}"
  fi
}

function display_pause_menu_yad() {
  local args=(
    --form
    --title="Pomodoro"
    --window-icon "${DIR}/icons/running${ICON_SIZE}.png"
    --button="▋▋!!Pause the current pomodoro:2"
    --button="■!!Stop and cancel the current pomodoro:0"
    --borders=0
    --timeout=10
    --on-top
    --undecorated
    --skip-taskbar
    --close-on-unfocus
  )
  if type xdotool &>/dev/null; then
    eval "$(xdotool getmouselocation --shell --prefix "__")"
    args+=(--posx="$((__X-40))" --posy="$((__Y+10))")
  else
    args+=(--mouse)
  fi
  yad "${args[@]}"
}

function display_pause_menu_zenity() {
  zenity --question --title="Pomodoro" \
    --window-icon "${DIR}/icons/running${ICON_SIZE}.png" \
    --extra-button="Pause" --ok-label="Stop" --cancel-label "Do nothing"
}

function display_pause_menu() {
  if type yad &>/dev/null; then
    display_pause_menu_yad
    return $?
  elif type zenity &>/dev/null; then
    display_pause_menu_zenity
    return $?
  else
    xnotify "Pomodoro" "Please install zenity or yad to interact with the plugin."
    return 1
  fi
}

function handle_timer_click() {
  local result=
  local btn_id_choice=
  result=$(display_pause_menu)
  btn_id_choice=$?
  if [[ "${result}" == "Pause" ]] || [[ "${btn_id_choice}" == 2 ]]; then
    run_custom_cmd pause
    pause_timer
  elif [[ "${btn_id_choice}" == 0 ]] ; then
    terminate_pomodoro
    run_custom_cmd pomodoro_end
  fi
}


function maybe_play_sound() {
  if [ "${SOUND}" == "on" ] ; then
    aplay "${DIR}/cow.wav"
  fi
}

function load_timers_state() {
  current_time=$( date +%s )
  # periodic check, and redrawing
  cycle_start_time=$( cat "${SAVED_TIME_FILE}" 2> /dev/null )
  paused_time=$(cat "${SAVED_PAUSE_TIME_FILE}" 2> /dev/null )
  saved_cycle_count=$( cat "${SAVED_CYCLE_COUNT_FILE}" 2> /dev/null )

  if [ -z "${cycle_start_time}" ] ; then
    cycle_start_time=0
  fi

  # timer running
  if [ -z "${saved_cycle_count}" ] ; then
    saved_cycle_count=0
  fi
}

function handle_idle_mode() {
  if [[ "${mode}" != "idle" ]]; then
    echo "Invalid mode (${mode}) for handle_idle_mode"
    return 1
  fi

  if [[ "${CLICKED}" == "yes" ]]; then
    run_custom_cmd idle_end
    xnotify "${START_POMODORO_MSG}"
    local _current_time=$( date +%s )
    echo "${_current_time}" > "${SAVED_TIME_FILE}"
    echo "pomodoro" > "${SAVED_MODE_FILE}"
    echo "0" > "${SAVED_CYCLE_COUNT_FILE}"
    custom_cmd_start "pomodoro"
    return 0
  fi

  echo "<img>${DIR}/icons/stopped${ICON_SIZE}.png</img>"
  echo "<txt> Idle </txt>"
  echo "<tool>No Pomodoro Running</tool>"
  gen_click_tag
}

function handle_paused_mode() {
  if ! [[ "${mode}" =~ "paused" ]]; then
    echo "Invalid mode (${mode}) for handle_paused_mode"
    return 1
  fi

  if [ "${CLICKED}" == "yes" ] ; then
      resume_timer
      run_custom_cmd resume
      return 0
  fi

  load_timers_state
  local _cycle_time=${POMODORO_CYCLE}
  if [[ "${mode}" == "paused_shortbreak" ]]; then
    _cycle_time=${SHORT_BREAK_CYCLE}
  elif [[ "${mode}" == "paused_longbreak" ]]; then
    _cycle_time=${LONG_BREAK_CYCLE}
  fi

  echo "<img>${DIR}/icons/stopped${ICON_SIZE}.png</img>"
  echo "<tool>Timer paused. Click to resume.</tool>"
  local _remaining_time=$(( _cycle_time - (paused_time - cycle_start_time) ))
  local _paused_time_display=$(printf " %02d:%02d " $(( _remaining_time / 60 )) $(( _remaining_time % 60 )))
  echo "<txt>▶ ${_paused_time_display} </txt>"
  gen_click_tag
}

function handle_pomodoro_mode() {
  if [[ "${mode}" != "pomodoro" ]]; then
    echo "Invalid mode (${mode}) for handle_pomodoro_mode"
    return 1
  fi

  if [ "${CLICKED}" == "yes" ] ; then
    handle_timer_click
    return 0
  fi

  load_timers_state
  local _remaining_time=$(( POMODORO_CYCLE + cycle_start_time - current_time))
  if [ ${_remaining_time} -gt 0 ] ; then
    render_status ${mode} ${_remaining_time} ${saved_cycle_count}
    return 0
  fi

  # If _remaining_time is is below zero for more that short break cycle,
  # that makes pomodoro invalid.
  # This, for example, can occurr when computer was turned off.
  # In such case terminate pomodoro and exit.
  local _invalid_pomodoro_time_margin=$((-SHORT_BREAK_CYCLE))
  if [ ${_remaining_time} -lt ${_invalid_pomodoro_time_margin} ] ; then
    terminate_pomodoro
    custom_cmd_end "${mode}"
    return 1
  fi

  local cycle_count=$((saved_cycle_count + 1))
  local cycle_mod=$((cycle_count % CYCLES_BETWEEN_LONG_BREAKS))
  local new_remaining_time=${SHORT_BREAK_CYCLE}
  local new_mode="shortbreak"
  local _msg="${END_MSG_SHORTBREAK}"
  if [ ${cycle_mod} -eq 0 ] ; then
    new_mode="longbreak"
    _msg="${END_MSG_LONGBREAK}"
    new_remaining_time=${LONG_BREAK_CYCLE}
  fi

  echo "${cycle_count}" > "${SAVED_CYCLE_COUNT_FILE}"
  echo "${new_mode}" > "${SAVED_MODE_FILE}"
  echo "${current_time}" > "${SAVED_TIME_FILE}"
  render_status ${new_mode} ${new_remaining_time} ${cycle_count}
  maybe_play_sound
  custom_cmd_end "${mode}"
  xnotify "${_msg}"
  display_info_dialog "${_msg}" "${new_remaining_time}"
  custom_cmd_start "${new_mode}"
}

function handle_break_mode() {
  if ! [[ "${mode}" =~ "break" ]]; then
    echo "Invalid mode (${mode}) for handle_break_mode"
    return 1
  fi

  if [ "${CLICKED}" == "yes" ] ; then
    handle_timer_click
    return 0
  fi

  load_timers_state
  local _cycle_time=${SHORT_BREAK_CYCLE}
  if [ "${mode}" == "longbreak" ]; then
    _cycle_time=${LONG_BREAK_CYCLE}
  fi

  local _remaining_time=$(( _cycle_time + cycle_start_time - current_time))
  if [ ${_remaining_time} -gt 0 ] ; then
    render_status ${mode} ${_remaining_time} ${saved_cycle_count}
    return 0
  fi

  # If _remaining_time is below zero for more than short break cycle,
  # that makes the pomodoro invalid.
  # This, for example, can occurr when computer was turned off.
  # In such case terminate pomodoro and exit.
  local invalid_pomodoro_time_margin=$((-SHORT_BREAK_CYCLE))
  if [ ${_remaining_time} -lt ${invalid_pomodoro_time_margin} ] ; then
    terminate_pomodoro
    custom_cmd_end "pomodoro"
    return 1
  fi

  render_status "pomodoro" ${POMODORO_CYCLE} ${saved_cycle_count}
  maybe_play_sound
  custom_cmd_end "${mode}"
  xnotify "${START_POMODORO_MSG}"
  display_info_dialog "${START_POMODORO_MSG}" "${POMODORO_CYCLE}"
  custom_cmd_start "pomodoro"
  echo "pomodoro" > "${SAVED_MODE_FILE}"
  echo "${current_time}" > "${SAVED_TIME_FILE}"
}

function handle_mode() {
  case "${mode}" in
    idle)
      handle_idle_mode
      ;;
    paused*)
      handle_paused_mode
      ;;
    pomodoro)
      handle_pomodoro_mode
      ;;
    *break)
      handle_break_mode
      ;;
    *)
      echo "Invalid mode: ${mode}"
      return 1
      ;;
  esac
}

function main() {
  mode=$( cat "${SAVED_MODE_FILE}" 2> /dev/null )
  if [ -z "${mode}" ] ; then
    mode="idle"
  fi

  handle_mode "${mode}"
  exit 0
}

if ! (return 0 2>/dev/null); then
  parse_args "$@"
  exec 8>"${LOCK}"
  flock -x 8
  main
fi
