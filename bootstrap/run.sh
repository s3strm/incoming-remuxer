#!/usr/bin/env bash
export PATH="/usr/local/bin:${PATH}"
AZ=$(curl 169.254.169.254/latest/meta-data/placement/availability-zone/)
export AWS_DEFAULT_REGION=${AZ::-1}
export INSTANCE_ID

MOVIES_BUCKET=$(
  aws cloudformation list-exports \
    --query 'Exports[?Name==`s3strm-movies-bucket`].Value' \
    --output text
)
export MOVIES_BUCKET

AUTO_SCALING_GROUP=$(
  aws cloudformation describe-stacks \
    --stack-name s3strm-incoming-remuxer \
    --query 'Stacks[].Outputs[?OutputKey==`AutoScalingGroup`].OutputValue' \
    --output text
)

function find_video() {
  # Should use a queue for this because then dead-letters can be handled
  aws s3 ls "s3://${MOVIES_BUCKET}/incoming/" 2> /dev/null \
    | grep -m1 -e "\.mp4$" -e "\.mkv$" -e "\.avi$" \
    | grep -E -o "[^\ ]+$"
  return $?
}

function download() {
  echo "downloading s3://${MOVIES_BUCKET}/incoming/$1"
  aws s3 cp "s3://${MOVIES_BUCKET}/incoming/$1" "/dev/shm/$1" > /dev/null
}

function upload() {
  local imdb_id
  imdb_id="$(basename "$1" .mp4)"
  echo "uploading s3://${MOVIES_BUCKET}/${imdb_id}/video.mp4"
  aws s3 cp "/dev/shm/$1" "s3://${MOVIES_BUCKET}/${imdb_id}/video.mp4" > /dev/null
  return $?
}

function remux() {
  $(dirname "$0")/remuxer "/dev/shm/$1"
}

function cleanup() {
  echo "Scaling down because there are no more videos to process"
  aws autoscaling update-auto-scaling-group \
    --auto-scaling-group-name "${AUTO_SCALING_GROUP}" \
    --desired-capacity 0
}

trap '{ cleanup; }' EXIT

which ffmpeg || $(dirname "$0")/download_ffmpeg
which ffmpeg || sleep 1200

while true; do
  video="$(find_video)"
  [[ -z ${video} ]] && exit 0

  video_extension=$(echo "${video}" | grep -E -o "\.[^\.]+$")
  imdb_id="$(basename "${video}" "${video_extension}")"
  download "${video}"
  remux "${video}"
  if [[ $? -eq 0 ]]; then
    original_video=${video}
    video="${imdb_id}.mp4"
    upload "${video}" \
      && aws s3 rm "s3://${MOVIES_BUCKET}/incoming/${original_video}"
  else
    echo "failed to remux ${video}" >&2
    aws s3 cp /dev/shm/${video} "s3://${MOVIES_BUCKET}/incoming/dead_letters/${video}"
    aws s3 rm "s3://${MOVIES_BUCKET}/incoming/${video}"
  fi

  find /dev/shm -iname "${imdb_id}.*" -delete
  unset video imdb_id
done
