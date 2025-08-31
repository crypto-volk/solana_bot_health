#######################################
#           CLIENT ENUMS              #
#######################################

CLIENT_FIREDANCER="firedancer"
CLIENT_AGAVE="agave"

#######################################
#      USER CONFIGURABLE SECTION      #
#######################################

# --- Select Client ---
CLIENT=$CLIENT_FIREDANCER  # Change this to CLIENT_AGAVE if you want to use Agave client

# --- Required Variables ---
TELEGRAM_TOKEN=""       # Set your Telegram token here, ask from @BotFather
BOT_ID=""               # Set your Telegram bot ID here, ask from @userinfobot
SERVICE="sol.service"
LEDGER_FOLDER="/mnt/ledger/"
USE_SUDO=true

# --- Optional Variables ---
# --- Directories ---
STATE_DIR="$PWD/state"
LOGS_DIR="$PWD/logs"

# --- Logs ---
INSTALL_LOG_FILE="${LOGS_DIR}/install.log"
LOG_BOT_FILE="${LOGS_DIR}/bot.log"
UPDATE_HISTORY_FILE="${LOGS_DIR}/history.log"

# --- Other Variables ---
GITHUB_TOKEN=""         # GitHub token for get versions
ID_FILE=${STATE_DIR}/last_update_id.txt
JOURNAL_COUNT=100000
INSTALL_FD_DIR="$PWD/firedancer"
MAX_ATTEMPTS_CHECK_SYNC=240 # ~240 sec
KEY_PAIR_PATH="$PWD/validator-keypair.json"
DUMMY_KEYPAIR_PATH="${STATE_DIR}/temp-identity.json"
CONFIG_PATH="~/config.toml"
RESTART_WINDOW_TIMEOUT_S=900 # 15min

# --- Icons ---
OK_ICON='🟢'
NOK_ICON='🔴'
WARNING_ICON='🟡'

#######################################
#   INTERNAL (DO NOT MODIFY BELOW)    #
#######################################

# --- Create sudo command ---
SUDO_CMD=""
if [ "${USE_SUDO}" = "true" ]; then
    SUDO_CMD="sudo"
fi

# --- Create folders ---
if [[ ! -d "$LOGS_DIR" ]]; then
    mkdir -p "$LOGS_DIR"
fi
if [[ ! -d "$STATE_DIR" ]]; then
    mkdir -p "$STATE_DIR"
fi

# --- Urls ---
TELEGRAM_SEND_URL="https://api.telegram.org/bot$TELEGRAM_TOKEN/sendMessage"
TELEGRAM_EDIT_URL="https://api.telegram.org/bot$TELEGRAM_TOKEN/editMessageText"
TELEGRAM_DELETE_URL="https://api.telegram.org/bot$TELEGRAM_TOKEN/deleteMessage"
