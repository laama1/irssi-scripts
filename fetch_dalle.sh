#!/bin/bash -e
set -o pipefail
usage() {
    echo "Usage: $0 --channel <channel> --server <server> --nick <nick> <output_file_name> <prompt>" >&2
}

CHANNEL=""
SERVER=""
NICK=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --channel|--server|--nick)
            if [ "$#" -lt 2 ]; then
                usage
                exit 1
            fi
            case "$1" in
                --channel) CHANNEL=$2 ;;
                --server) SERVER=$2 ;;
                --nick) NICK=$2 ;;
            esac
            shift 2
            ;;
        --)
            shift
            break
            ;;
        -*)
            echo "Unknown option: $1" >&2
            usage
            exit 1
            ;;
        *)
            break
            ;;
    esac
done

if [[ -z "$CHANNEL" || -z "$SERVER" || -z "$NICK" || $# -ne 2 ]]; then
    usage
    exit 1
fi

OUTPUT_BASENAME=$1
OUTPUT_FILE_NAME=$OUTPUT_BASENAME
PROMPT=$2
SOCKET_FILE="/tmp/franklin3.sock"
LOG_FILE="/tmp/fetch_dalle.log"
OUTPUT_DIR="/var/www/html/bot/dale/"

OUTPUT_FILE_NAME="${OUTPUT_DIR}${OUTPUT_FILE_NAME}"

# fetch_dalle.sh will run openai image generation in the background
URL="https://api.openai.com/v1/images/generations"
OUTPUT_FILE_ENCODED="/tmp/dalle_output.b64"
APIKEY_FILE="../franklin_api.key"
API_KEY=$(cat $APIKEY_FILE)
#VISIONMODEL="dall-e-3"
VISIONMODEL="gpt-image-2"
IMAGE_SIZE="1536x1024"

log_to_file() {
    data=$1
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "[$timestamp]; $data" >> $LOG_FILE
}

# example command line to generate an image using the OpenAI API
#curl -s https://api.openai.com/v1/images/generations -H "Authorization: Bearer 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" \
#-H "Content-Type: application/json" \
#-d '{"model": "gpt-image-1", "prompt": "A cute baby sea otter", "size": "1024x1024"}'
log_to_file "Starting, output file: $OUTPUT_FILE_NAME, prompt: $PROMPT"

# will expect .png output
COMMAND="curl -s $URL \
        -H \"Authorization: Bearer $API_KEY\" \
        -H \"Content-Type: application/json\" \
        -d '{\"model\": \"$VISIONMODEL\", \"prompt\": \"$PROMPT\", \"size\": \"$IMAGE_SIZE\"}' \
        | jq -r '.data[0].url' \
        | xargs -I {} curl -s -L \"{}\" -o $OUTPUT_FILE_NAME";

COMMAND2="curl -s $URL \
        -H \"Authorization: Bearer $API_KEY\" \
        -H \"Content-Type: application/json\" \
        -d '{\"model\": \"$VISIONMODEL\", \"prompt\": \"$PROMPT\", \"size\": \"$IMAGE_SIZE\"}' \
        | jq -r '.data[0].b64_json' \
        | base64 --decode > $OUTPUT_FILE_NAME";

# output errors to stdout too.
#eval $COMMAND 2>&1
REQUEST_BODY=$(jq -cn \
    --arg model "$VISIONMODEL" \
    --arg prompt "$PROMPT" \
    --arg size "$IMAGE_SIZE" \
    '{model: $model, prompt: $prompt, size: $size}')
curl -s "$URL" \
    -H "Authorization: ******" \
    -H "Content-Type: application/json" \
    -d "$REQUEST_BODY" \
    | jq -er '.data[0].b64_json' \
    | base64 --decode > "$OUTPUT_FILE_NAME"
log_to_file "Image request done."
#when response is encoded in b64
#B64_ENCODED_FILE=$(base64 -d $OUTPUT_FILE_ENCODED)
#echo $B64_ENCODED_FILE > $OUTPUT_FILE_NAME
#echo "" > $OUTPUT_FILE_ENCODED



write_to_socket_file() {
    if [[ -S $SOCKET_FILE ]]; then
        SOCKET_MESSAGE=$(jq -cn \
            --arg filename "$OUTPUT_BASENAME" \
            --arg channel "$CHANNEL" \
            --arg server "$SERVER" \
            --arg nick "$NICK" \
            '{filename: $filename, channel: $channel, server: $server, nick: $nick}')
        printf '%s\n' "$SOCKET_MESSAGE" | socat -u - UNIX-CONNECT:"$SOCKET_FILE"
    else
        echo "Socket file $SOCKET_FILE does not exist."
    fi
}
write_to_socket_file
echo $OUTPUT_FILE_NAME