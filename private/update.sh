#!/bin/bash

source ./config.sh

send_message_curl() {
    local message=$1
    local remove_keyboard=${2:-false}

    local payload="chat_id=$BOT_ID&text=$message"
    if [[ "$remove_keyboard" == "true" ]]; then
        payload="$payload&reply_markup=$(jq -nc '{remove_keyboard: true}')"
    fi

    echo $(curl -s -X POST $TELEGRAM_SEND_URL -d "$payload")
}

edit_message_curl() {
    local message=$1
    local message_id=$2
    echo $(curl -s -X POST $TELEGRAM_EDIT_URL -d chat_id=$BOT_ID -d "message_id=$message_id" -d text="$message")
}

delete_message() {
    local message_id=$1
    response=$(curl -s -X POST $TELEGRAM_DELETE_URL -d chat_id=$BOT_ID -d message_id=$message_id)

    if [[ $(echo "$response" | jq -r '.ok') != "true" ]]; then
        echo "Ошибка при удалении сообщения $message_id"
    fi
}

animate() {
    local message=$1
    local message_id=$2
    local frames=("◢" "◣" "◤" "◥")

    while true; do
        for frame in "${frames[@]}"; do
            edit_message_curl "${message} $frame" "$message_id" > /dev/null
            sleep 2
        done
    done
}

run_with_animation() {
    local command=$1
    local message=$2

    message_id=$(send_message_curl "$message" | jq '.result.message_id')

    animate "$message" "$message_id" &
    animation_pid=$!

    $command
    local exit_code=$?

    kill $animation_pid
    delete_message $message_id

    return $exit_code
}

output_message() {
    local message=$1
    local remove_keyboard=${2:-false}
    if [ "$TELEGRAM" == "1" ]; then
        response=$(send_message_curl "$message" "$remove_keyboard")
        if [[ $(echo "$response" | jq -r '.ok') != "true" ]]; then
            echo "Ошибка отправки сообщения: $message"
            return 1
        fi
    else
        echo "$message"
    fi
}

if [ -z "$1" ]; then
    VERSION_EXAMPLE=""
    if [[ $CLIENT == $CLIENT_FIREDANCER ]]; then
        VERSION_EXAMPLE="0.403.20113"
    elif [[ $CLIENT == $CLIENT_AGAVE ]]; then
        VERSION_EXAMPLE="2.0.13"
    fi
    output_message "Укажите версию для обновления, например ${VERSION_EXAMPLE}"
    exit 1
fi

VERSION="v${1}"
MAX_DELINQUENT_STAKE=${2:-5}

format_duration() {
    local duration=$1
    local hours=$((duration / 3600))
    local minutes=$(((duration % 3600) / 60))
    local seconds=$((duration % 60))
    echo "${hours}ч:${minutes}м:${seconds}с"
}

wait_for_restart_and_restart() {
    if [ "$MAX_DELINQUENT_STAKE" = "0" ]; then
        echo "MAX_DELINQUENT_STAKE=0 — выполняем немедленный рестарт"
        ${SUDO_CMD} systemctl restart ${SERVICE}
        return
    fi

    timeout -k 2 ${RESTART_WINDOW_TIMEOUT_S} ${SUDO_CMD} agave-validator --ledger ${LEDGER_FOLDER} \
        wait-for-restart-window --max-delinquent-stake $MAX_DELINQUENT_STAKE > /dev/null 2>&1

    if [ $? -eq 0 ]; then
        ${SUDO_CMD} systemctl restart ${SERVICE}
    else
        return 1
    fi
}

install_firedancer_deps() {
    ./deps.sh fetch >> "$INSTALL_LOG_FILE" 2>&1
    ./deps.sh check >> "$INSTALL_LOG_FILE" 2>&1
    ./deps.sh install >> "$INSTALL_LOG_FILE" 2>&1
}

make_firedancer(){
    make -j fdctl solana >> "$INSTALL_LOG_FILE" 2>&1
    return $?
}

install_firedancer() {
    local repo_url="https://github.com/firedancer-io/firedancer"
    local clean_version=${VERSION#v}

    if [[ -x "$FIREDANCER_BIN" ]]; then
        local current_version=$("$FIREDANCER_BIN" version 2>/dev/null | awk '{print $1}')

        if [[ "$current_version" == "$clean_version" ]]; then
            output_message "Версии совпадают, установка не требуется" | tee -a "$INSTALL_LOG_FILE"
            return 0
        fi
    fi

    rm -rf $INSTALL_LOG_FILE
    if [[ ! -d "$INSTALL_FD_DIR/.git" ]]; then
        output_message "Клонируем репозиторий в $INSTALL_FD_DIR" | tee -a "$INSTALL_LOG_FILE"
        git clone  --recurse-submodules "$repo_url" "$INSTALL_FD_DIR" >> "$INSTALL_LOG_FILE" 2>&1
        if [[ $? -ne 0 ]]; then
            output_message "Ошибка: не удалось клонировать репозиторий" | tee -a "$INSTALL_LOG_FILE"
            return 1
        fi
    fi

    cd "$INSTALL_FD_DIR" || return 1

    git submodule sync
    git submodule update --init --recursive >> "$INSTALL_LOG_FILE" 2>&1
    if [[ $? -ne 0 ]]; then
        output_message "Ошибка при обновлении подмодулей. Попробуем пересинхронизировать agave..." | tee -a "$INSTALL_LOG_FILE"

        git submodule deinit -f agave >> "$INSTALL_LOG_FILE" 2>&1
        rm -rf .git/modules/agave agave
        git submodule update --init --recursive >> "$INSTALL_LOG_FILE" 2>&1

        if [[ $? -ne 0 ]]; then
            output_message "Ошибка: не удалось восстановить подмодуль agave." | tee -a "$INSTALL_LOG_FILE"
            return 1
        fi
    fi
    git fetch origin >> "$INSTALL_LOG_FILE" 2>&1
    git checkout "$VERSION" >> "$INSTALL_LOG_FILE" 2>&1
    if [[ $? -ne 0 ]]; then
        output_message "Ошибка: не удалось переключиться на версию $VERSION" | tee -a "$INSTALL_LOG_FILE"
        return 1
    fi

    if [ "$TELEGRAM" == "1" ]; then
        run_with_animation install_firedancer_deps "Установка зависимостей" || return 1
        run_with_animation make_firedancer "Идет сборка" || return 1
    else
        output_message "Установка зависимостей" | tee -a "$INSTALL_LOG_FILE"
        install_firedancer_deps

        output_message "Идет сборка" | tee -a "$INSTALL_LOG_FILE"
        make_firedancer
    fi

    if [[ $? -ne 0 ]]; then
        output_message "Ошибка: сборка не удалась" | tee -a "$INSTALL_LOG_FILE"
        return 1
    fi

    cd -

    local fdctl_version=$("${FIREDANCER_BIN}" version 2>/dev/null | awk '{print $1}')

    if [[ "$fdctl_version" != "$clean_version" ]]; then
        output_message "Ошибка: версии не совпадают: текущая=$fdctl_version, ожидается=$clean_version" | tee -a "$INSTALL_LOG_FILE"
        tail -n 10 "$INSTALL_LOG_FILE"
        return 1
    fi

    return 0
}

install_agave() {
    sh -c "$(curl -sSfL https://release.anza.xyz/$VERSION/install)"
}

save_history() {
    echo "{\"date\": \"$(date)\", \"version\": \"${VERSION}\", \"client\": \"$CLIENT\", \"total_duration\": \"$(format_duration $TOTAL_DURATION)\", \"max-delinquent-stake\": \"$MAX_DELINQUENT_STAKE\"}" >> ${UPDATE_HISTORY_FILE}
}

check_agave_monitor_status() {
    local attempt=0
    local frames=("◢" "◣" "◤" "◥")
    local frame_index=0
    local initial_text="⏳ Проверка статуса ноды"
    local message_id=$(send_message_curl "$initial_text" | jq '.result.message_id')

    while (( attempt < MAX_ATTEMPTS_CHECK_SYNC )); do
        local frame=${frames[$frame_index]}
        frame_index=$(( (frame_index + 1) % ${#frames[@]} ))

        output=$(${SUDO_CMD} timeout 1 agave-validator --ledger "${LEDGER_FOLDER}" monitor 2>&1)
        if ! echo "$output" | grep -q "Processed Slot"; then
            edit_message_curl "⏳ Нода запускается: $output $frame" "$message_id"
            continue
        fi

        health=$(echo "$output" | grep -oP '\| \K([0-9]+ slots behind|unhealthy|ok)' | head -n1)

        case "$health" in
            ok|"")
                trimmed=$(echo "$output" | grep "Processed Slot" | tail -n 1)
                edit_message_curl "${OK_ICON} healthy: $trimmed" "$message_id"
                return 0
                ;;
            unhealthy)
                edit_message_curl "${WARNING_ICON} unhealthy $frame" "$message_id"
                ;;
            *"slots behind")
                delay=$(echo "$health" | grep -oP '^\d+')
                if [[ -n "$delay" ]]; then
                    edit_message_curl "${WARNING_ICON} Нода отстаёт на $delay слотов $frame" "$message_id"
                else
                    edit_message_curl "${WARNING_ICON} Нода отстаёт (не удалось определить задержку) $frame" "$message_id"
                fi
                ;;
            *)
                edit_message_curl "${initial_text} $frame" "$message_id"
                ;;
        esac

        ((attempt++))
    done

    edit_message_curl "${NOK_ICON} Нода не перешла в healthy за $MAX_ATTEMPTS_CHECK_SYNC попыток, возможно нужен ребут" "$message_id"
    return 1
}

install_client() {
    if [[ $CLIENT == $CLIENT_FIREDANCER ]]; then
        if ! install_firedancer; then
            output_message "Ошибка: установка Firedancer не удалась."
            return 1
        fi
    elif [[ $CLIENT == $CLIENT_AGAVE ]]; then
        install_agave
    else
        output_message "Задан неправльный клиент"
        return 1
    fi
}

main() {
    output_message "Установка ${CLIENT} версии: ${VERSION}" true

    local start_time=$(date +%s)

    if ! install_client; then
        return 1
    fi

    output_message "Установка $CLIENT $VERSION завершена за $(format_duration $(( $(date +%s) - $start_time )))."

    local mins=$(( (RESTART_WINDOW_TIMEOUT_S + 59) / 60 ))

    if [ "$TELEGRAM" == "1" ]; then
        run_with_animation wait_for_restart_and_restart "Ожидание окна перезапуска валидатора($MAX_DELINQUENT_STAKE) макс ${mins} минут"
    else
        output_message "Ожидание окна перезапуска валидатора (max-delinquent-stake: $MAX_DELINQUENT_STAKE) макс ${mins} минут"
        wait_for_restart_and_restart
    fi || {
        output_message "⛔ Окно перезапуска валидатора не найдено за ${mins} минут"
        return 1
    }

    output_message "Валидатор перзапущен за $(format_duration $(( $(date +%s) - $start_time ))), ожидание синхронизации."
    if [ "$TELEGRAM" == "1" ]; then
        if check_agave_monitor_status; then
            output_message "#update: $CLIENT обновлен до версии ${VERSION}, дата: $(date). общее время: $(format_duration $(( $(date +%s) - $start_time )))."
            save_history
        fi
    fi
}

main "$@"
